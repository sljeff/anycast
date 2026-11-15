#!/usr/bin/env bash

set -euo pipefail
set +x

umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly PROJECT_ROOT
readonly RESOURCES_DIR="${PROJECT_ROOT}/native/Anycast/Resources"
readonly INFISICAL_ENV="${1:-dev}"
readonly SECRET_PATH="/app-config"
readonly CHECKSUM_FILE="${PROJECT_ROOT}/config/infisical-config.sha256"
readonly IOS_BUNDLE_ID="com.kindjeff.anycast"

if [[ "${INFISICAL_ENV}" != "dev" && "${INFISICAL_ENV}" != "release" ]]; then
  echo "Usage: $0 [dev|release]" >&2
  exit 2
fi

for required_command in infisical install plutil perl shasum; do
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

if [[ -e "${RESOURCES_DIR}/GoogleService-Info.plist" ||
      -e "${RESOURCES_DIR}/Secrets.plist" ||
      -e "${PROJECT_ROOT}/native/.env" ]]; then
  echo "Refusing to overwrite an existing local app configuration" >&2
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

if [[ -z "${purchase_ios_api_key}" ]]; then
  echo "The RevenueCat SDK key is empty" >&2
  exit 1
fi

if [[ "${purchase_ios_api_key}" == *$'\n'* ||
      "${purchase_ios_api_key}" == *$'\r'* ]]; then
  echo "The RevenueCat SDK key must be a single line" >&2
  exit 1
fi

if [[ "${purchase_ios_api_key}" != appl_* ]]; then
  echo "Expected a RevenueCat public iOS SDK key" >&2
  exit 1
fi

printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n\t<key>PURCHASES_IOS_API_KEY</key>\n\t<string>%s</string>\n</dict>\n</plist>\n' \
  "${purchase_ios_api_key}" >"${TEMP_DIR}/Secrets.plist"

unset purchase_ios_api_key

plutil -lint "${TEMP_DIR}/Secrets.plist" >/dev/null

figma_v2_url="$(read_secret FIGMA_ANYCAST_V2_URL)"

if [[ -z "${figma_v2_url}" ]]; then
  echo "The Figma v2 design link is empty" >&2
  exit 1
fi

if [[ "${figma_v2_url}" == *$'\n'* ||
      "${figma_v2_url}" == *$'\r'* ||
      "${figma_v2_url}" == *" "* ]]; then
  echo "The Figma v2 design link must be a single line without spaces" >&2
  exit 1
fi

if [[ "${figma_v2_url}" != https://www.figma.com/* ]]; then
  echo "Expected an https://www.figma.com/ design link" >&2
  exit 1
fi

printf 'FIGMA_ANYCAST_V2_URL=%s\n' "${figma_v2_url}" >"${TEMP_DIR}/figma_v2_dotenv"

unset figma_v2_url

fetch_to_stage \
  IOS_GOOGLE_SERVICE_INFO_PLIST \
  GoogleService-Info.plist

plutil -lint "${TEMP_DIR}/GoogleService-Info.plist" >/dev/null
plist_bundle_id="$(
  plutil -extract BUNDLE_ID raw -o - "${TEMP_DIR}/GoogleService-Info.plist"
)"
if [[ "${plist_bundle_id}" != "${IOS_BUNDLE_ID}" ]]; then
  echo "Unexpected iOS Firebase bundle ID" >&2
  exit 1
fi
unset plist_bundle_id

verify_reviewed_digest \
  native/Anycast/Resources/GoogleService-Info.plist \
  "${TEMP_DIR}/GoogleService-Info.plist"
verify_reviewed_digest \
  native/Anycast/Resources/Secrets.plist \
  "${TEMP_DIR}/Secrets.plist"
verify_reviewed_digest \
  native/.env \
  "${TEMP_DIR}/figma_v2_dotenv"

install_staged_file \
  "${TEMP_DIR}/GoogleService-Info.plist" \
  "${RESOURCES_DIR}/GoogleService-Info.plist"
install_staged_file \
  "${TEMP_DIR}/Secrets.plist" \
  "${RESOURCES_DIR}/Secrets.plist"
install_staged_file \
  "${TEMP_DIR}/figma_v2_dotenv" \
  "${PROJECT_ROOT}/native/.env"

echo "Generated Anycast ${INFISICAL_ENV} configuration successfully."
