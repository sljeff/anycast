#!/usr/bin/env bash

set -euo pipefail
set +x

umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly PROJECT_ROOT
readonly INFISICAL_ENV="${1:-dev}"
readonly SECRET_PATH="/app-config"
readonly CHECKSUM_FILE="${PROJECT_ROOT}/config/infisical-config.sha256"
readonly ANDROID_PACKAGE="com.kindjeff.anycast"
readonly IOS_BUNDLE_ID="com.kindjeff.anycast"

if [[ "${INFISICAL_ENV}" != "dev" && "${INFISICAL_ENV}" != "release" ]]; then
  echo "Usage: $0 [dev|release]" >&2
  exit 2
fi

for required_command in infisical install jq perl plutil shasum; do
  if ! command -v "${required_command}" >/dev/null 2>&1; then
    echo "Required command is missing: ${required_command}" >&2
    exit 1
  fi
done

if [[ ! -f "${PROJECT_ROOT}/.infisical.json" ]]; then
  echo "Missing ${PROJECT_ROOT}/.infisical.json" >&2
  exit 1
fi

if [[ ! -f "${CHECKSUM_FILE}" ]]; then
  echo "Missing reviewed configuration checksums: ${CHECKSUM_FILE}" >&2
  exit 1
fi

TEMP_PARENT="${TMPDIR:-/tmp}"
TEMP_PARENT="${TEMP_PARENT%/}"
readonly TEMP_PARENT
TEMP_DIR="$(mktemp -d "${TEMP_PARENT}/anycast-bootstrap.XXXXXX")"
if [[ -z "${TEMP_DIR}" || ! -d "${TEMP_DIR}" ]]; then
  echo "Failed to create a temporary configuration directory" >&2
  exit 1
fi
readonly TEMP_DIR
chmod 700 "${TEMP_DIR}"

cleanup() {
  case "${TEMP_DIR:-}" in
    "${TEMP_PARENT}"/anycast-bootstrap.*)
      rm -rf -- "${TEMP_DIR}"
      ;;
    *)
      echo "Refusing to remove unexpected temporary path" >&2
      ;;
  esac
}
trap cleanup EXIT INT TERM

fetch_to_stage() {
  local secret_name="$1"
  local stage_name="$2"
  local stage_file="${TEMP_DIR}/${stage_name}"

  (
    cd "${PROJECT_ROOT}"
    infisical secrets get "${secret_name}" \
      --env="${INFISICAL_ENV}" \
      --path="${SECRET_PATH}" \
      --expand=false \
      --plain \
      --silent
  ) >"${stage_file}"

  if [[ ! -s "${stage_file}" ]]; then
    echo "Infisical secret ${secret_name} is empty" >&2
    exit 1
  fi
}

read_secret() {
  local secret_name="$1"

  (
    cd "${PROJECT_ROOT}"
    infisical secrets get "${secret_name}" \
      --env="${INFISICAL_ENV}" \
      --path="${SECRET_PATH}" \
      --expand=false \
      --plain \
      --silent
  )
}

normalized_digest() {
  perl -0777 -pe 's/\n*\z/\n/' "$1" | shasum -a 256 | awk '{print $1}'
}

verify_reviewed_digest() {
  local repository_path="$1"
  local stage_file="$2"
  local expected_digest
  local actual_digest

  expected_digest="$(
    awk -v repository_path="${repository_path}" \
      '$2 == repository_path { print $1; exit }' \
      "${CHECKSUM_FILE}"
  )"
  actual_digest="$(normalized_digest "${stage_file}")"

  if [[ ! "${expected_digest}" =~ ^[0-9a-f]{64}$ ]]; then
    echo "No reviewed checksum for ${repository_path}" >&2
    exit 1
  fi

  if [[ "${actual_digest}" != "${expected_digest}" ]]; then
    echo "Infisical configuration changed without Git review: ${repository_path}" >&2
    exit 1
  fi
}

install_staged_file() {
  local stage_file="$1"
  local destination="$2"

  if [[ -L "${destination}" ]]; then
    echo "Refusing to overwrite symbolic link: ${destination}" >&2
    exit 1
  fi

  mkdir -p "$(dirname "${destination}")"
  install -m 600 "${stage_file}" "${destination}"
}

purchase_ios_api_key="$(read_secret PURCHASES_IOS_API_KEY)"
purchase_android_api_key="$(read_secret PURCHASES_ANDROID_API_KEY)"

if [[ -z "${purchase_ios_api_key}" || -z "${purchase_android_api_key}" ]]; then
  echo "A RevenueCat SDK key is empty" >&2
  exit 1
fi

if [[ "${purchase_ios_api_key}" == *$'\n'* ||
      "${purchase_ios_api_key}" == *$'\r'* ||
      "${purchase_android_api_key}" == *$'\n'* ||
      "${purchase_android_api_key}" == *$'\r'* ]]; then
  echo "RevenueCat SDK keys must each be a single line" >&2
  exit 1
fi

if [[ "${purchase_ios_api_key}" != appl_* ||
      "${purchase_android_api_key}" != goog_* ]]; then
  echo "Expected RevenueCat public iOS and Android SDK keys" >&2
  exit 1
fi

{
  printf 'PURCHASES_IOS_API_KEY=%s\n' "${purchase_ios_api_key}"
  printf 'PURCHASES_ANDROID_API_KEY=%s\n' "${purchase_android_api_key}"
} >"${TEMP_DIR}/dotenv"

unset purchase_ios_api_key purchase_android_api_key

fetch_to_stage \
  ANDROID_GOOGLE_SERVICES_JSON \
  google-services.json
fetch_to_stage \
  IOS_GOOGLE_SERVICE_INFO_PLIST \
  GoogleService-Info.plist
fetch_to_stage \
  FIREBASE_OPTIONS_DART \
  firebase_options.dart

jq -e \
  --arg package_name "${ANDROID_PACKAGE}" \
  '
    (.project_info.project_id | type == "string" and length > 0) and
    any(.client[]?; .client_info.android_client_info.package_name == $package_name)
  ' \
  "${TEMP_DIR}/google-services.json" >/dev/null

plutil -lint "${TEMP_DIR}/GoogleService-Info.plist" >/dev/null
plist_bundle_id="$(
  plutil -extract BUNDLE_ID raw -o - "${TEMP_DIR}/GoogleService-Info.plist"
)"
if [[ "${plist_bundle_id}" != "${IOS_BUNDLE_ID}" ]]; then
  echo "Unexpected iOS Firebase bundle ID" >&2
  exit 1
fi
unset plist_bundle_id

if ! grep -q 'class DefaultFirebaseOptions' "${TEMP_DIR}/firebase_options.dart"; then
  echo "Infisical firebase_options.dart did not pass validation" >&2
  exit 1
fi

verify_reviewed_digest \
  android/app/google-services.json \
  "${TEMP_DIR}/google-services.json"
verify_reviewed_digest \
  ios/Runner/GoogleService-Info.plist \
  "${TEMP_DIR}/GoogleService-Info.plist"
verify_reviewed_digest \
  lib/firebase_options.dart \
  "${TEMP_DIR}/firebase_options.dart"
verify_reviewed_digest \
  .env \
  "${TEMP_DIR}/dotenv"

install_staged_file "${TEMP_DIR}/dotenv" "${PROJECT_ROOT}/.env"
install_staged_file \
  "${TEMP_DIR}/google-services.json" \
  "${PROJECT_ROOT}/android/app/google-services.json"
install_staged_file \
  "${TEMP_DIR}/GoogleService-Info.plist" \
  "${PROJECT_ROOT}/ios/Runner/GoogleService-Info.plist"
install_staged_file \
  "${TEMP_DIR}/firebase_options.dart" \
  "${PROJECT_ROOT}/lib/firebase_options.dart"

echo "Generated Anycast ${INFISICAL_ENV} configuration successfully."
