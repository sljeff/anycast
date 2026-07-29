#!/usr/bin/env bash

set -euo pipefail
set +x

umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly PROJECT_ROOT
readonly PLATFORM="${1:-}"
readonly CHECKSUM_FILE="${PROJECT_ROOT}/config/infisical-config.sha256"
readonly ANDROID_PACKAGE="com.kindjeff.anycast"
readonly IOS_BUNDLE_ID="com.kindjeff.anycast"

if [[ "${PLATFORM}" != "android" && "${PLATFORM}" != "ios" ]]; then
  echo "Usage: $0 <android|ios>" >&2
  exit 2
fi

for required_command in install perl; do
  if ! command -v "${required_command}" >/dev/null 2>&1; then
    echo "Required command is missing: ${required_command}" >&2
    exit 1
  fi
done

if [[ "${PLATFORM}" == "android" ]] &&
   ! command -v jq >/dev/null 2>&1; then
  echo "Required command is missing: jq" >&2
  exit 1
fi

if [[ "${PLATFORM}" == "ios" ]] &&
   ! command -v plutil >/dev/null 2>&1; then
  echo "Required command is missing: plutil" >&2
  exit 1
fi

if [[ ! -f "${CHECKSUM_FILE}" ]]; then
  echo "Missing reviewed configuration checksums: ${CHECKSUM_FILE}" >&2
  exit 1
fi

required_secrets=(
  PURCHASES_IOS_API_KEY
  PURCHASES_ANDROID_API_KEY
  FIREBASE_OPTIONS_DART
)

if [[ "${PLATFORM}" == "android" ]]; then
  required_secrets+=(ANDROID_GOOGLE_SERVICES_JSON)
else
  required_secrets+=(IOS_GOOGLE_SERVICE_INFO_PLIST)
fi

for secret_name in "${required_secrets[@]}"; do
  if [[ -z "${!secret_name:-}" ]]; then
    echo "Required environment variable is empty: ${secret_name}" >&2
    exit 1
  fi
done

if [[ "${PURCHASES_IOS_API_KEY}" == *$'\n'* ||
      "${PURCHASES_IOS_API_KEY}" == *$'\r'* ||
      "${PURCHASES_ANDROID_API_KEY}" == *$'\n'* ||
      "${PURCHASES_ANDROID_API_KEY}" == *$'\r'* ]]; then
  echo "RevenueCat SDK keys must each be a single line" >&2
  exit 1
fi

if [[ "${PURCHASES_IOS_API_KEY}" != appl_* ||
      "${PURCHASES_ANDROID_API_KEY}" != goog_* ]]; then
  echo "Expected RevenueCat public iOS and Android SDK keys" >&2
  exit 1
fi

TEMP_PARENT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
TEMP_PARENT="${TEMP_PARENT%/}"
readonly TEMP_PARENT
TEMP_DIR="$(mktemp -d "${TEMP_PARENT}/anycast-app-config.XXXXXX")"
if [[ -z "${TEMP_DIR}" || ! -d "${TEMP_DIR}" ]]; then
  echo "Failed to create a temporary configuration directory" >&2
  exit 1
fi
readonly TEMP_DIR
chmod 700 "${TEMP_DIR}"

cleanup() {
  case "${TEMP_DIR:-}" in
    "${TEMP_PARENT}"/anycast-app-config.*)
      rm -rf -- "${TEMP_DIR}"
      ;;
    *)
      echo "Refusing to remove unexpected temporary path" >&2
      ;;
  esac
}
trap cleanup EXIT INT TERM

normalized_digest() {
  local file_path="$1"

  if command -v shasum >/dev/null 2>&1; then
    perl -0777 -pe 's/\n*\z/\n/' "${file_path}" |
      shasum -a 256 |
      awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    perl -0777 -pe 's/\n*\z/\n/' "${file_path}" |
      sha256sum |
      awk '{print $1}'
  else
    echo "Neither shasum nor sha256sum is available" >&2
    return 1
  fi
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

{
  printf 'PURCHASES_IOS_API_KEY=%s\n' "${PURCHASES_IOS_API_KEY}"
  printf 'PURCHASES_ANDROID_API_KEY=%s\n' "${PURCHASES_ANDROID_API_KEY}"
} >"${TEMP_DIR}/dotenv"

printf '%s' "${FIREBASE_OPTIONS_DART}" \
  >"${TEMP_DIR}/firebase_options.dart"

if ! grep -q 'class DefaultFirebaseOptions' \
  "${TEMP_DIR}/firebase_options.dart"; then
  echo "Infisical firebase_options.dart did not pass validation" >&2
  exit 1
fi

verify_reviewed_digest \
  lib/firebase_options.dart \
  "${TEMP_DIR}/firebase_options.dart"
verify_reviewed_digest \
  .env \
  "${TEMP_DIR}/dotenv"

if [[ "${PLATFORM}" == "android" ]]; then
  printf '%s' "${ANDROID_GOOGLE_SERVICES_JSON}" \
    >"${TEMP_DIR}/google-services.json"

  jq -e \
    --arg package_name "${ANDROID_PACKAGE}" \
    '
      (.project_info.project_id | type == "string" and length > 0) and
      any(.client[]?; .client_info.android_client_info.package_name == $package_name)
    ' \
    "${TEMP_DIR}/google-services.json" >/dev/null

  verify_reviewed_digest \
    android/app/google-services.json \
    "${TEMP_DIR}/google-services.json"

  install_staged_file \
    "${TEMP_DIR}/google-services.json" \
    "${PROJECT_ROOT}/android/app/google-services.json"
else
  printf '%s' "${IOS_GOOGLE_SERVICE_INFO_PLIST}" \
    >"${TEMP_DIR}/GoogleService-Info.plist"

  plutil -lint "${TEMP_DIR}/GoogleService-Info.plist" >/dev/null
  plist_bundle_id="$(
    plutil -extract BUNDLE_ID raw -o - \
      "${TEMP_DIR}/GoogleService-Info.plist"
  )"
  if [[ "${plist_bundle_id}" != "${IOS_BUNDLE_ID}" ]]; then
    echo "Unexpected iOS Firebase bundle ID" >&2
    exit 1
  fi
  unset plist_bundle_id

  verify_reviewed_digest \
    ios/Runner/GoogleService-Info.plist \
    "${TEMP_DIR}/GoogleService-Info.plist"

  install_staged_file \
    "${TEMP_DIR}/GoogleService-Info.plist" \
    "${PROJECT_ROOT}/ios/Runner/GoogleService-Info.plist"
fi

install_staged_file \
  "${TEMP_DIR}/dotenv" \
  "${PROJECT_ROOT}/.env"
install_staged_file \
  "${TEMP_DIR}/firebase_options.dart" \
  "${PROJECT_ROOT}/lib/firebase_options.dart"

echo "Materialized reviewed ${PLATFORM} app configuration."
