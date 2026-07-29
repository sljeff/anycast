#!/usr/bin/env bash

set -euo pipefail
set +x

umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly PROJECT_ROOT

if [[ -z "${RUNNER_TEMP:-}" ]]; then
  echo "RUNNER_TEMP is required" >&2
  exit 1
fi

required_secrets=(
  ANDROID_UPLOAD_KEYSTORE_B64
  ANDROID_KEY_ALIAS
  ANDROID_KEY_PASSWORD
  ANDROID_STORE_PASSWORD
)

for secret_name in "${required_secrets[@]}"; do
  if [[ -z "${!secret_name:-}" ]]; then
    echo "Required environment variable is empty: ${secret_name}" >&2
    exit 1
  fi
done

for single_line_value in \
  "${ANDROID_KEY_ALIAS}" \
  "${ANDROID_KEY_PASSWORD}" \
  "${ANDROID_STORE_PASSWORD}"; do
  if [[ "${single_line_value}" == *$'\n'* ||
        "${single_line_value}" == *$'\r'* ]]; then
    echo "Android signing fields must be single-line values" >&2
    exit 1
  fi
done
unset single_line_value

readonly SIGNING_DIR="${RUNNER_TEMP%/}/anycast-android-signing"
readonly KEYSTORE_PATH="${SIGNING_DIR}/upload-keystore.jks"
readonly KEY_PROPERTIES_PATH="${PROJECT_ROOT}/android/key.properties"

if [[ -e "${SIGNING_DIR}" || -e "${KEY_PROPERTIES_PATH}" ||
      -L "${KEY_PROPERTIES_PATH}" ]]; then
  echo "Refusing to overwrite an existing Android signing path" >&2
  exit 1
fi

mkdir -p "${SIGNING_DIR}"
chmod 700 "${SIGNING_DIR}"

if base64 --help 2>&1 | grep -q -- '--decode'; then
  printf '%s' "${ANDROID_UPLOAD_KEYSTORE_B64}" |
    base64 --decode >"${KEYSTORE_PATH}"
else
  printf '%s' "${ANDROID_UPLOAD_KEYSTORE_B64}" |
    base64 -D >"${KEYSTORE_PATH}"
fi
chmod 600 "${KEYSTORE_PATH}"

keytool -list \
  -keystore "${KEYSTORE_PATH}" \
  -storepass "${ANDROID_STORE_PASSWORD}" \
  -alias "${ANDROID_KEY_ALIAS}" >/dev/null

{
  printf 'storePassword=%s\n' "${ANDROID_STORE_PASSWORD}"
  printf 'keyPassword=%s\n' "${ANDROID_KEY_PASSWORD}"
  printf 'keyAlias=%s\n' "${ANDROID_KEY_ALIAS}"
  printf 'storeFile=%s\n' "${KEYSTORE_PATH}"
} >"${KEY_PROPERTIES_PATH}"
chmod 600 "${KEY_PROPERTIES_PATH}"

echo "Prepared temporary Android upload signing."
