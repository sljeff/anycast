#!/usr/bin/env bash

set -euo pipefail
set +x

umask 077

readonly TEAM_ID="5TQ9AN87D8"
readonly RUNNER_BUNDLE_ID="com.kindjeff.anycast"
readonly SHARE_BUNDLE_ID="com.kindjeff.anycast.Share-Extension"
readonly DISTRIBUTION_CERT_SERIAL="514320B4F20FC518B5E8AE2F5FF05CAE"
readonly RUNNER_PROFILE_NAME="Anycast GitHub App Store"
readonly RUNNER_PROFILE_UUID="8556542b-9ee1-4053-87f9-7a8a939124e5"
readonly SHARE_PROFILE_NAME="Anycast Share Extension GitHub App Store"
readonly SHARE_PROFILE_UUID="64282043-b776-4bbb-9f70-7b4bbc5a3a39"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "iOS signing preparation requires macOS" >&2
  exit 1
fi

if [[ -z "${RUNNER_TEMP:-}" || -z "${GITHUB_ENV:-}" ]]; then
  echo "RUNNER_TEMP and GITHUB_ENV are required" >&2
  exit 1
fi

required_secrets=(
  IOS_DISTRIBUTION_P12_B64
  IOS_DISTRIBUTION_P12_PASSWORD
  IOS_RUNNER_PROFILE_B64
  IOS_SHARE_EXTENSION_PROFILE_B64
  APP_STORE_CONNECT_ISSUER_ID
  APP_STORE_CONNECT_KEY_ID
  APP_STORE_CONNECT_PRIVATE_KEY_B64
)

for secret_name in "${required_secrets[@]}"; do
  if [[ -z "${!secret_name:-}" ]]; then
    echo "Required environment variable is empty: ${secret_name}" >&2
    exit 1
  fi
done

if [[ ! "${APP_STORE_CONNECT_KEY_ID}" =~ ^[A-Z0-9]{10}$ ||
      ! "${APP_STORE_CONNECT_ISSUER_ID}" =~ ^[0-9a-fA-F-]{36}$ ]]; then
  echo "Invalid App Store Connect API identifiers" >&2
  exit 1
fi

readonly SIGNING_DIR="${RUNNER_TEMP%/}/anycast-ios-signing"
readonly P12_PATH="${SIGNING_DIR}/distribution.p12"
readonly RUNNER_PROFILE_SOURCE="${SIGNING_DIR}/runner.mobileprovision"
readonly SHARE_PROFILE_SOURCE="${SIGNING_DIR}/share.mobileprovision"
readonly KEYCHAIN_PATH="${SIGNING_DIR}/signing.keychain-db"
readonly PRIVATE_KEYS_DIR="${SIGNING_DIR}/private_keys"

if [[ -e "${SIGNING_DIR}" ]]; then
  echo "Refusing to overwrite an existing iOS signing directory" >&2
  exit 1
fi

mkdir -p "${SIGNING_DIR}" "${PRIVATE_KEYS_DIR}"
chmod 700 "${SIGNING_DIR}" "${PRIVATE_KEYS_DIR}"

runner_profile_path=""
share_profile_path=""
prepared=false
original_keychains=()

: >"${SIGNING_DIR}/original-keychains.txt"
while IFS= read -r keychain_path; do
  keychain_path="$(
    sed -e 's/^[[:space:]]*"//' -e 's/"$//' <<<"${keychain_path}"
  )"
  if [[ -n "${keychain_path}" ]]; then
    original_keychains+=("${keychain_path}")
    printf '%s\n' "${keychain_path}" \
      >>"${SIGNING_DIR}/original-keychains.txt"
  fi
done < <(security list-keychains -d user)
chmod 600 "${SIGNING_DIR}/original-keychains.txt"

cleanup_on_failure() {
  local status="$?"

  if [[ "${status}" -ne 0 && "${prepared}" != "true" ]]; then
    if [[ -n "${runner_profile_path}" && -f "${runner_profile_path}" ]]; then
      rm -f -- "${runner_profile_path}"
    fi
    if [[ -n "${share_profile_path}" && -f "${share_profile_path}" ]]; then
      rm -f -- "${share_profile_path}"
    fi
    if [[ -f "${KEYCHAIN_PATH}" ]]; then
      security delete-keychain "${KEYCHAIN_PATH}" >/dev/null 2>&1 || true
    fi
    if (( ${#original_keychains[@]} > 0 )); then
      security list-keychains -d user -s \
        "${original_keychains[@]}" >/dev/null 2>&1 || true
    fi
    case "${SIGNING_DIR}" in
      "${RUNNER_TEMP%/}"/anycast-ios-signing)
        rm -rf -- "${SIGNING_DIR}"
        ;;
    esac
  fi

  return "${status}"
}
trap cleanup_on_failure EXIT

decode_base64() {
  local destination="$1"

  if base64 --help 2>&1 | grep -q -- '--decode'; then
    base64 --decode >"${destination}"
  else
    base64 -D >"${destination}"
  fi
  chmod 600 "${destination}"
}

printf '%s' "${IOS_DISTRIBUTION_P12_B64}" |
  decode_base64 "${P12_PATH}"
printf '%s' "${IOS_RUNNER_PROFILE_B64}" |
  decode_base64 "${RUNNER_PROFILE_SOURCE}"
printf '%s' "${IOS_SHARE_EXTENSION_PROFILE_B64}" |
  decode_base64 "${SHARE_PROFILE_SOURCE}"

readonly ASC_KEY_PATH="${PRIVATE_KEYS_DIR}/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
printf '%s' "${APP_STORE_CONNECT_PRIVATE_KEY_B64}" |
  decode_base64 "${ASC_KEY_PATH}"

if ! grep -q '^-----BEGIN PRIVATE KEY-----' "${ASC_KEY_PATH}"; then
  echo "Invalid App Store Connect private key" >&2
  exit 1
fi

keychain_password="$(openssl rand -hex 32)"
security create-keychain -p "${keychain_password}" "${KEYCHAIN_PATH}"
security set-keychain-settings -lut 21600 "${KEYCHAIN_PATH}"
security unlock-keychain -p "${keychain_password}" "${KEYCHAIN_PATH}"
security import "${P12_PATH}" \
  -k "${KEYCHAIN_PATH}" \
  -P "${IOS_DISTRIBUTION_P12_PASSWORD}" \
  -T /usr/bin/codesign \
  -t cert \
  -f pkcs12 >/dev/null
security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "${keychain_password}" \
  "${KEYCHAIN_PATH}" >/dev/null
security list-keychains -d user -s "${KEYCHAIN_PATH}"
unset keychain_password

if ! security find-identity -v -p codesigning "${KEYCHAIN_PATH}" |
  grep -q 'Apple Distribution'; then
  echo "The P12 does not contain an Apple Distribution signing identity" >&2
  exit 1
fi

distribution_cert_serial="$(
  security find-certificate \
    -c 'Apple Distribution' \
    -p \
    "${KEYCHAIN_PATH}" |
    openssl x509 -noout -serial |
    sed 's/^serial=//' |
    tr '[:lower:]' '[:upper:]'
)"
if [[ "${distribution_cert_serial}" != "${DISTRIBUTION_CERT_SERIAL}" ]]; then
  echo "Unexpected Apple Distribution certificate serial" >&2
  exit 1
fi
unset distribution_cert_serial

readonly PROFILE_INSTALL_DIR="${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "${PROFILE_INSTALL_DIR}"

install_profile() {
  local source_path="$1"
  local expected_bundle_id="$2"
  local expected_name="$3"
  local expected_uuid="$4"
  local label="$5"
  local decoded_path="${SIGNING_DIR}/${label}.plist"
  local certificate_b64_path="${SIGNING_DIR}/${label}-certificate.b64"
  local certificate_path="${SIGNING_DIR}/${label}.cer"
  local certificate_serial
  local profile_uuid
  local profile_name
  local normalized_profile_uuid
  local profile_team_id
  local profile_app_identifier
  local profile_expiration
  local profile_get_task_allow
  local expiration_epoch
  local now_epoch
  local installed_path

  security cms -D -i "${source_path}" >"${decoded_path}"
  profile_uuid="$(plutil -extract UUID raw -o - "${decoded_path}")"
  normalized_profile_uuid="$(
    tr '[:upper:]' '[:lower:]' <<<"${profile_uuid}"
  )"
  profile_name="$(plutil -extract Name raw -o - "${decoded_path}")"
  profile_team_id="$(
    plutil -extract TeamIdentifier.0 raw -o - "${decoded_path}"
  )"
  profile_app_identifier="$(
    plutil -extract Entitlements.application-identifier raw -o - \
      "${decoded_path}"
  )"
  profile_expiration="$(
    plutil -extract ExpirationDate raw -o - "${decoded_path}"
  )"
  profile_get_task_allow="$(
    plutil -extract Entitlements.get-task-allow raw -o - "${decoded_path}"
  )"

  if [[ "${normalized_profile_uuid}" != "${expected_uuid}" ||
        "${profile_name}" != "${expected_name}" ||
        "${profile_team_id}" != "${TEAM_ID}" ||
        "${profile_app_identifier}" != "${TEAM_ID}.${expected_bundle_id}" ||
        "${profile_get_task_allow}" != "false" ]]; then
    echo "Unexpected ${label} provisioning profile" >&2
    exit 1
  fi

  plutil -extract DeveloperCertificates.0 raw \
    -o "${certificate_b64_path}" \
    "${decoded_path}"
  decode_base64 "${certificate_path}" <"${certificate_b64_path}"
  certificate_serial="$(
    openssl x509 \
      -inform DER \
      -in "${certificate_path}" \
      -noout \
      -serial |
      sed 's/^serial=//' |
      tr '[:lower:]' '[:upper:]'
  )"
  if [[ "${certificate_serial}" != "${DISTRIBUTION_CERT_SERIAL}" ]]; then
    echo "${label} profile does not match the distribution certificate" >&2
    exit 1
  fi

  expiration_epoch="$(
    date -j -f '%Y-%m-%dT%H:%M:%SZ' "${profile_expiration}" '+%s'
  )"
  now_epoch="$(date '+%s')"
  if (( expiration_epoch <= now_epoch + 604800 )); then
    echo "${label} provisioning profile expires within seven days" >&2
    exit 1
  fi

  installed_path="${PROFILE_INSTALL_DIR}/${profile_uuid}.mobileprovision"
  if [[ -e "${installed_path}" || -L "${installed_path}" ]]; then
    echo "Refusing to overwrite an installed ${label} profile" >&2
    exit 1
  fi
  install -m 600 "${source_path}" "${installed_path}"
  printf '%s' "${installed_path}"
}

runner_profile_path="$(
  install_profile \
    "${RUNNER_PROFILE_SOURCE}" \
    "${RUNNER_BUNDLE_ID}" \
    "${RUNNER_PROFILE_NAME}" \
    "${RUNNER_PROFILE_UUID}" \
    runner
)"
share_profile_path="$(
  install_profile \
    "${SHARE_PROFILE_SOURCE}" \
    "${SHARE_BUNDLE_ID}" \
    "${SHARE_PROFILE_NAME}" \
    "${SHARE_PROFILE_UUID}" \
    share
)"

{
  printf 'API_PRIVATE_KEYS_DIR=%s\n' "${PRIVATE_KEYS_DIR}"
  printf 'IOS_KEYCHAIN_PATH=%s\n' "${KEYCHAIN_PATH}"
  printf 'IOS_RUNNER_PROFILE_PATH=%s\n' "${runner_profile_path}"
  printf 'IOS_SHARE_PROFILE_PATH=%s\n' "${share_profile_path}"
  printf 'IOS_SIGNING_DIR=%s\n' "${SIGNING_DIR}"
} >>"${GITHUB_ENV}"

prepared=true
echo "Prepared temporary iOS distribution signing."
