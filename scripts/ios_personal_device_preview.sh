#!/usr/bin/env bash

set -euo pipefail
set +x

umask 077

readonly EXPECTED_FLUTTER_VERSION="3.38.3"
readonly PROJECT_OWNER_TEAM_ID="5TQ9AN87D8"
readonly CANONICAL_BUNDLE_ID="com.kindjeff.anycast"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly PROJECT_ROOT
readonly CHECKSUM_FILE="${PROJECT_ROOT}/config/infisical-config.sha256"

device_id=""
certificate_id=""
preview_bundle_id=""
flutter_bin="${FLUTTER_BIN:-}"
allow_provisioning_updates=false
open_mirroring=false
dry_run=false

usage() {
  cat <<'EOF'
Build, install, and launch an isolated Anycast Profile preview on a personal iPhone.

Usage:
  scripts/ios_personal_device_preview.sh \
    --device <UDID> \
    --certificate-id <certificate-label-suffix> \
    [--bundle-id <personal-preview-bundle-id>] \
    [--flutter-bin <path>] \
    [--allow-provisioning-updates] \
    [--open-mirroring] \
    [--dry-run]

Required:
  --device
      Physical iPhone UDID reported by `xcrun xcdevice list`.

  --certificate-id
      Identifier shown at the end of an Apple Development identity label,
      for example the value inside parentheses. This is not DEVELOPMENT_TEAM.

Options:
  --bundle-id
      Personal preview bundle ID. Defaults to:
      com.<lowercase-derived-team-id>.anycast.preview

  --flutter-bin
      Flutter executable. The project requires Flutter 3.38.3.

  --allow-provisioning-updates
      Allow Xcode to contact Apple and create or refresh personal development
      provisioning. Omit this when a matching profile already exists.

  --open-mirroring
      Open the macOS iPhone Mirroring app after launch. A human must enter any
      Mac login password requested by the system.

  --dry-run
      Validate the device, certificate, team, configuration, and profile
      without copying, building, signing, installing, or launching.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --device)
      device_id="${2:-}"
      shift 2
      ;;
    --certificate-id)
      certificate_id="${2:-}"
      shift 2
      ;;
    --bundle-id)
      preview_bundle_id="${2:-}"
      shift 2
      ;;
    --flutter-bin)
      flutter_bin="${2:-}"
      shift 2
      ;;
    --allow-provisioning-updates)
      allow_provisioning_updates=true
      shift
      ;;
    --open-mirroring)
      open_mirroring=true
      shift
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${device_id}" || -z "${certificate_id}" ]]; then
  echo "--device and --certificate-id are required" >&2
  usage >&2
  exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "A physical iOS preview requires macOS" >&2
  exit 1
fi

required_commands=(
  codesign
  find
  git
  openssl
  perl
  plutil
  pod
  rsync
  ruby
  security
  shasum
  unlink
  xcodebuild
  xcrun
)

for required_command in "${required_commands[@]}"; do
  if ! command -v "${required_command}" >/dev/null 2>&1; then
    echo "Required command is missing: ${required_command}" >&2
    exit 1
  fi
done

if [[ -z "${flutter_bin}" ]]; then
  flutter_bin="$(command -v flutter || true)"
fi
if [[ -z "${flutter_bin}" || ! -x "${flutter_bin}" ]]; then
  echo "Flutter was not found. Pass --flutter-bin with Flutter 3.38.3." >&2
  exit 1
fi
flutter_bin="$(cd "$(dirname "${flutter_bin}")" && pwd)/$(basename "${flutter_bin}")"
readonly flutter_bin

flutter_version="$(
  "${flutter_bin}" --version --machine |
    ruby -rjson -e 'puts JSON.parse($stdin.read).fetch("frameworkVersion")'
)"
if [[ "${flutter_version}" != "${EXPECTED_FLUTTER_VERSION}" ]]; then
  echo "Expected Flutter ${EXPECTED_FLUTTER_VERSION}, found ${flutter_version}" >&2
  exit 1
fi
unset flutter_version

TEMP_PARENT="${TMPDIR:-/tmp}"
TEMP_PARENT="${TEMP_PARENT%/}"
readonly TEMP_PARENT
PREFLIGHT_DIR="$(mktemp -d "${TEMP_PARENT}/anycast-ios-preview.XXXXXX")"
readonly PREFLIGHT_DIR
chmod 700 "${PREFLIGHT_DIR}"

readonly PREVIEW_ROOT="${PROJECT_ROOT}/build/ios/personal-device-preview"
readonly WORKSPACE_ROOT="${PREVIEW_ROOT}/workspace"
readonly LOCK_DIR="${PREVIEW_ROOT}/lock"
workspace_created=false
lock_created=false

remove_preview_workspace() {
  if [[ -L "${WORKSPACE_ROOT}" ]]; then
    echo "Refusing to remove symbolic-link preview workspace: ${WORKSPACE_ROOT}" >&2
    return 1
  fi

  case "${WORKSPACE_ROOT}" in
    "${PROJECT_ROOT}"/build/ios/personal-device-preview/workspace)
      rm -rf -- "${WORKSPACE_ROOT}"
      ;;
    *)
      echo "Refusing to remove unexpected preview workspace: ${WORKSPACE_ROOT}" >&2
      return 1
      ;;
  esac
}

remove_preview_lock() {
  if [[ -L "${LOCK_DIR}" ]]; then
    echo "Refusing to remove symbolic-link preview lock: ${LOCK_DIR}" >&2
    return 1
  fi

  case "${LOCK_DIR}" in
    "${PROJECT_ROOT}"/build/ios/personal-device-preview/lock)
      if [[ -f "${LOCK_DIR}/pid" ]]; then
        unlink "${LOCK_DIR}/pid"
      fi
      rmdir "${LOCK_DIR}"
      ;;
    *)
      echo "Refusing to remove unexpected preview lock: ${LOCK_DIR}" >&2
      return 1
      ;;
  esac
}

cleanup() {
  local status="$?"

  if [[ "${workspace_created}" == "true" && -e "${WORKSPACE_ROOT}" ]]; then
    remove_preview_workspace || true
  fi

  if [[ "${lock_created}" == "true" && -d "${LOCK_DIR}" ]]; then
    remove_preview_lock >/dev/null 2>&1 || true
  fi

  case "${PREFLIGHT_DIR}" in
    "${TEMP_PARENT}"/anycast-ios-preview.*)
      rm -rf -- "${PREFLIGHT_DIR}"
      ;;
  esac

  return "${status}"
}
trap cleanup EXIT INT TERM

device_list_path="${PREFLIGHT_DIR}/devices.json"
xcrun xcdevice list --timeout 10 >"${device_list_path}"
if ! ruby -rjson -e '
  devices = JSON.parse(File.read(ARGV.fetch(0)))
  wanted = ARGV.fetch(1)
  device = devices.find { |item| item["identifier"] == wanted }
  exit 1 unless device
  exit 2 unless device["simulator"] == false
  exit 3 unless device["available"] == true
  exit 0
' "${device_list_path}" "${device_id}"; then
  echo "The requested UDID is not an available physical device: ${device_id}" >&2
  exit 1
fi

identity_matches="$(
  security find-identity -v -p codesigning |
    grep -F "(${certificate_id})" |
    grep '"Apple Development:' || true
)"
identity_count="$(grep -c . <<<"${identity_matches}" || true)"
if [[ "${identity_count}" != "1" ]]; then
  echo "Expected one Apple Development identity ending in (${certificate_id}); found ${identity_count}" >&2
  exit 1
fi

identity_hash="$(awk '{print $2}' <<<"${identity_matches}")"
identity_label="$(
  sed -E 's/^[^"]*"([^"]+)".*$/\1/' <<<"${identity_matches}"
)"
if [[ ! "${identity_hash}" =~ ^[0-9A-Fa-f]{40}$ ||
      "${identity_label}" == *$'\n'* ||
      "${identity_label}" == *'"'* ]]; then
  echo "The selected Apple Development identity could not be parsed safely" >&2
  exit 1
fi
readonly identity_hash
readonly identity_label
unset identity_matches identity_count

certificate_subject="$(
  security find-certificate -c "${identity_label}" -p |
    openssl x509 -noout -subject -nameopt RFC2253
)"
development_team="$(
  sed -E 's/^.*OU=([^,]+).*$/\1/' <<<"${certificate_subject}"
)"
if [[ ! "${development_team}" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "Could not derive DEVELOPMENT_TEAM from the certificate OU" >&2
  exit 1
fi
if [[ "${development_team}" == "${PROJECT_OWNER_TEAM_ID}" ]]; then
  echo "Refusing project-owner team ${PROJECT_OWNER_TEAM_ID}; use a personal Apple Development identity" >&2
  exit 1
fi
readonly development_team
unset certificate_subject

team_identity_count=0
while IFS= read -r candidate_line; do
  candidate_label="$(
    sed -E 's/^[^"]*"([^"]+)".*$/\1/' <<<"${candidate_line}"
  )"
  candidate_subject="$(
    security find-certificate -c "${candidate_label}" -p 2>/dev/null |
      openssl x509 -noout -subject -nameopt RFC2253 2>/dev/null || true
  )"
  candidate_team="$(
    sed -E 's/^.*OU=([^,]+).*$/\1/' <<<"${candidate_subject}"
  )"
  if [[ "${candidate_team}" == "${development_team}" ]]; then
    (( team_identity_count += 1 ))
  fi
done < <(
  security find-identity -v -p codesigning |
    grep '"Apple Development:' || true
)

if [[ "${team_identity_count}" != "1" ]]; then
  echo "Expected one valid Apple Development identity for team ${development_team}; found ${team_identity_count}" >&2
  echo "Automatic signing would be ambiguous, so the preview stopped before building." >&2
  exit 1
fi
unset team_identity_count candidate_line candidate_label candidate_subject candidate_team

if [[ -z "${preview_bundle_id}" ]]; then
  preview_bundle_id="com.$(
    tr '[:upper:]' '[:lower:]' <<<"${development_team}"
  ).anycast.preview"
fi
if [[ ! "${preview_bundle_id}" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; then
  echo "Invalid preview bundle ID: ${preview_bundle_id}" >&2
  exit 1
fi
if [[ "${preview_bundle_id}" == "${CANONICAL_BUNDLE_ID}" ]]; then
  echo "The personal preview must not use the canonical owner bundle ID" >&2
  exit 1
fi
readonly preview_bundle_id

if [[ ! -f "${CHECKSUM_FILE}" ]]; then
  echo "Missing reviewed configuration checksums: ${CHECKSUM_FILE}" >&2
  exit 1
fi

normalized_digest() {
  perl -0777 -pe 's/\n*\z/\n/' "$1" |
    shasum -a 256 |
    awk '{print $1}'
}

verify_reviewed_config() {
  local repository_path="$1"
  local file_path="${PROJECT_ROOT}/${repository_path}"
  local expected_digest
  local actual_digest

  if [[ ! -f "${file_path}" ]]; then
    echo "Missing local app configuration: ${repository_path}" >&2
    echo "This preview script never runs scripts/bootstrap.sh automatically." >&2
    exit 1
  fi

  expected_digest="$(
    awk -v repository_path="${repository_path}" \
      '$2 == repository_path { print $1; exit }' \
      "${CHECKSUM_FILE}"
  )"
  actual_digest="$(normalized_digest "${file_path}")"

  if [[ ! "${expected_digest}" =~ ^[0-9a-f]{64}$ ||
        "${actual_digest}" != "${expected_digest}" ]]; then
    echo "Local app configuration is not the reviewed version: ${repository_path}" >&2
    exit 1
  fi
}

verify_reviewed_config ".env"
verify_reviewed_config "ios/Runner/GoogleService-Info.plist"
verify_reviewed_config "lib/firebase_options.dart"

configured_bundle_id="$(
  plutil -extract BUNDLE_ID raw -o - \
    "${PROJECT_ROOT}/ios/Runner/GoogleService-Info.plist"
)"
if [[ "${configured_bundle_id}" != "${CANONICAL_BUNDLE_ID}" ]]; then
  echo "Unexpected Firebase iOS bundle ID in reviewed configuration" >&2
  exit 1
fi
unset configured_bundle_id

profile_found=false
profile_name=""
profile_expiration=""
profile_install_dir="${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles"
if [[ -d "${profile_install_dir}" ]]; then
  while IFS= read -r -d '' profile_path; do
    decoded_profile="${PREFLIGHT_DIR}/profile.plist"
    if ! security cms -D -i "${profile_path}" \
      >"${decoded_profile}" 2>/dev/null; then
      continue
    fi

    profile_team="$(
      plutil -extract TeamIdentifier.0 raw -o - \
        "${decoded_profile}" 2>/dev/null || true
    )"
    profile_app_id="$(
      plutil -extract Entitlements.application-identifier raw -o - \
        "${decoded_profile}" 2>/dev/null || true
    )"
    profile_debug="$(
      plutil -extract Entitlements.get-task-allow raw -o - \
        "${decoded_profile}" 2>/dev/null || true
    )"
    candidate_expiration="$(
      plutil -extract ExpirationDate raw -o - \
        "${decoded_profile}" 2>/dev/null || true
    )"
    candidate_devices="$(
      plutil -extract ProvisionedDevices json -o - \
        "${decoded_profile}" 2>/dev/null || true
    )"
    candidate_platforms="$(
      plutil -extract Platform json -o - \
        "${decoded_profile}" 2>/dev/null || true
    )"

    if [[ "${profile_team}" == "${development_team}" &&
          "${profile_app_id}" == "${development_team}.${preview_bundle_id}" &&
          "${profile_debug}" == "true" ]] &&
       ruby -rjson -e \
         'begin
            exit JSON.parse(ARGV.fetch(0)).include?(ARGV.fetch(1)) ? 0 : 1
          rescue JSON::ParserError
            exit 1
          end' \
         "${candidate_devices}" "${device_id}" &&
       ruby -rjson -e \
         'begin
            exit JSON.parse(ARGV.fetch(0)).include?("iOS") ? 0 : 1
          rescue JSON::ParserError
            exit 1
          end' \
         "${candidate_platforms}" &&
       ruby -rtime -e \
         'exit Time.parse(ARGV.fetch(0)) > Time.now ? 0 : 1' \
         "${candidate_expiration}"; then
      profile_name="$(
        plutil -extract Name raw -o - "${decoded_profile}" 2>/dev/null || true
      )"
      profile_expiration="${candidate_expiration}"
      profile_found=true
      break
    fi
  done < <(find "${profile_install_dir}" -type f -print0)
fi

if [[ "${profile_found}" != "true" &&
      "${allow_provisioning_updates}" != "true" ]]; then
  echo "No personal development profile matches ${preview_bundle_id}." >&2
  echo "Create it in Xcode first, or rerun with --allow-provisioning-updates after explicit approval." >&2
  exit 1
fi

echo "Personal iOS preview preflight passed:"
echo "  Device UDID: ${device_id}"
echo "  Certificate: ${identity_label}"
echo "  DEVELOPMENT_TEAM: ${development_team}"
echo "  Preview bundle ID: ${preview_bundle_id}"
if [[ "${profile_found}" == "true" ]]; then
  echo "  Provisioning profile: ${profile_name}"
  echo "  Profile expires: ${profile_expiration}"
  if ruby -rtime -e \
    'exit Time.parse(ARGV.fetch(0)) - Time.now < 7 * 86_400 ? 0 : 1' \
    "${profile_expiration}"; then
    echo "  WARNING: provisioning profile expires in less than seven days"
  fi
else
  echo "  Provisioning profile: Xcode may create or refresh it"
fi
echo "  Flutter: ${EXPECTED_FLUTTER_VERSION}"

if [[ "${dry_run}" == "true" ]]; then
  echo "Dry run complete. No build, signing, installation, or launch was performed."
  exit 0
fi

initial_git_status_digest="$(
  git -C "${PROJECT_ROOT}" status \
    --porcelain=v1 \
    -z \
    --untracked-files=all |
    shasum -a 256 |
    awk '{print $1}'
)"
readonly initial_git_status_digest

mkdir -p "${PREVIEW_ROOT}"
chmod 700 "${PREVIEW_ROOT}"
if [[ -d "${LOCK_DIR}" ]]; then
  existing_pid=""
  if [[ -f "${LOCK_DIR}/pid" ]]; then
    existing_pid="$(<"${LOCK_DIR}/pid")"
  fi
  if [[ "${existing_pid}" =~ ^[0-9]+$ ]] &&
     kill -0 "${existing_pid}" >/dev/null 2>&1; then
    echo "Another personal-device preview is running with PID ${existing_pid}" >&2
    exit 1
  fi
  echo "Removing a stale personal-device preview lock..."
  remove_preview_lock
fi
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  echo "Another personal-device preview may be running: ${LOCK_DIR}" >&2
  exit 1
fi
lock_created=true
printf '%s\n' "$$" >"${LOCK_DIR}/pid"

if [[ -e "${WORKSPACE_ROOT}" ]]; then
  remove_preview_workspace
fi
mkdir -p "${WORKSPACE_ROOT}"
chmod 700 "${WORKSPACE_ROOT}"
workspace_created=true

bundle_cache_key="$(
  printf '%s' "${preview_bundle_id}" |
    shasum -a 256 |
    awk '{print substr($1, 1, 12)}'
)"
readonly DERIVED_DATA_PATH="${PREVIEW_ROOT}/DerivedData-${development_team}-${device_id}-${bundle_cache_key}"
readonly LOG_DIR="${PREVIEW_ROOT}/logs"
mkdir -p "${DERIVED_DATA_PATH}" "${LOG_DIR}"
chmod 700 "${DERIVED_DATA_PATH}" "${LOG_DIR}"

echo "Preparing isolated preview workspace..."
rsync -a \
  --exclude '/.git/' \
  --exclude '/.infisical.json' \
  --exclude '/.dart_tool/' \
  --exclude '/build/' \
  --exclude '/ios/Flutter/Generated.xcconfig' \
  --exclude '/ios/Flutter/flutter_export_environment.sh' \
  --exclude '/ios/Pods/' \
  "${PROJECT_ROOT}/" \
  "${WORKSPACE_ROOT}/"

dependency_log="${LOG_DIR}/flutter-pub-get.log"
if ! (
  cd "${WORKSPACE_ROOT}"
  "${flutter_bin}" pub get --enforce-lockfile
) >"${dependency_log}" 2>&1; then
  echo "Flutter dependency resolution failed. Last log lines:" >&2
  tail -80 "${dependency_log}" >&2
  exit 1
fi

echo "Generating path-correct iOS configuration and CocoaPods..."
ios_config_log="${LOG_DIR}/flutter-ios-config.log"
if ! (
  cd "${WORKSPACE_ROOT}"
  "${flutter_bin}" build ios \
    --config-only \
    --profile \
    --no-codesign
) >"${ios_config_log}" 2>&1; then
  echo "Flutter iOS configuration failed. Last log lines:" >&2
  tail -80 "${ios_config_log}" >&2
  exit 1
fi

generated_config="${WORKSPACE_ROOT}/ios/Flutter/Generated.xcconfig"
if [[ ! -f "${generated_config}" ]] ||
   ! grep -Fqx "FLUTTER_APPLICATION_PATH=${WORKSPACE_ROOT}" "${generated_config}"; then
  echo "Flutter generated an iOS configuration outside the isolated workspace" >&2
  exit 1
fi
unset generated_config

project_file="${WORKSPACE_ROOT}/ios/Runner.xcodeproj/project.pbxproj"
ruby - \
  "${project_file}" \
  "${development_team}" \
  "${preview_bundle_id}" <<'RUBY'
path, team, bundle_id = ARGV
text = File.binread(path)

def replace_once(text, old_value, new_value, label)
  count = text.scan(old_value).length
  abort("Expected one #{label}; found #{count}") unless count == 1
  text.sub(old_value, new_value)
end

text = replace_once(
  text,
  "\t\t\t\t2EAEC0832C4C104700F151D9 /* StoreKit.framework in Frameworks */,\n",
  "",
  "Runner StoreKit framework entry"
)
text = replace_once(
  text,
  "\t\t\t\t2E26E3072C54D10B00211493 /* Embed Foundation Extensions */,\n",
  "",
  "Runner Share Extension embed phase"
)
text = replace_once(
  text,
  "\t\t\t\t2E26E3052C54D10B00211493 /* PBXTargetDependency */,\n",
  "",
  "Runner Share Extension target dependency"
)

profile_marker = "\t\t249021D4217E4FDB00AE95B9 /* Profile */ = {\n"
profile_start = text.index(profile_marker)
abort("Runner Profile configuration was not found") unless profile_start
profile_end = text.index("\n\t\t};", profile_start)
abort("Runner Profile configuration end was not found") unless profile_end
profile_end += "\n\t\t};".length
profile = text[profile_start...profile_end]

group_id = "group.#{team.downcase}.anycast.preview"

profile = replace_once(
  profile,
  "\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;\n",
  "\t\t\t\tCODE_SIGN_ENTITLEMENTS = \"\";\n" \
  "\t\t\t\tCODE_SIGN_IDENTITY = \"Apple Development\";\n" \
  "\t\t\t\t\"CODE_SIGN_IDENTITY[sdk=iphoneos*]\" = \"Apple Development\";\n" \
  "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n",
  "Runner Profile signing settings"
)
profile = replace_once(
  profile,
  "\t\t\t\tCUSTOM_GROUP_ID = group.com.kindjeff.ShareExtention;\n",
  "\t\t\t\tCUSTOM_GROUP_ID = #{group_id};\n",
  "Runner Profile app-group setting"
)
profile = replace_once(
  profile,
  "\t\t\t\tDEVELOPMENT_TEAM = 5TQ9AN87D8;\n",
  "\t\t\t\tDEVELOPMENT_TEAM = #{team};\n",
  "Runner Profile development team"
)
profile = replace_once(
  profile,
  "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.kindjeff.anycast;\n",
  "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = #{bundle_id};\n",
  "Runner Profile bundle ID"
)
profile = profile.gsub(
  /^\s*PROVISIONING_PROFILE_SPECIFIER = .*;\n/,
  ""
)

text[profile_start...profile_end] = profile
File.binwrite(path, text)
RUBY

build_log="${LOG_DIR}/xcodebuild-profile.log"
build_command=(
  xcodebuild
  -workspace "${WORKSPACE_ROOT}/ios/Runner.xcworkspace"
  -scheme Runner
  -configuration Profile
  -destination "id=${device_id}"
  -derivedDataPath "${DERIVED_DATA_PATH}"
  COMPILER_INDEX_STORE_ENABLE=NO
)
if [[ "${allow_provisioning_updates}" == "true" ]]; then
  build_command+=(-allowProvisioningUpdates)
fi
build_command+=(build)

echo "Building the Profile/AOT preview..."
if ! "${build_command[@]}" >"${build_log}" 2>&1; then
  echo "Profile build failed. Last log lines:" >&2
  tail -120 "${build_log}" >&2
  exit 1
fi

readonly APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Profile-iphoneos/Runner.app"
if [[ ! -d "${APP_PATH}" ]]; then
  echo "Profile build succeeded without producing Runner.app" >&2
  exit 1
fi

actual_bundle_id="$(
  plutil -extract CFBundleIdentifier raw -o - "${APP_PATH}/Info.plist"
)"
if [[ "${actual_bundle_id}" != "${preview_bundle_id}" ]]; then
  echo "Built bundle ID does not match the requested preview bundle ID" >&2
  exit 1
fi
unset actual_bundle_id

resigned_framework=false
while IFS= read -r -d '' framework_path; do
  if ! codesign --verify --strict "${framework_path}" >/dev/null 2>&1; then
    echo "Signing nested framework: $(basename "${framework_path}")"
    codesign \
      --force \
      --sign "${identity_hash}" \
      --preserve-metadata=identifier,entitlements \
      "${framework_path}"
    resigned_framework=true
  fi
done < <(
  find "${APP_PATH}/Frameworks" \
    -maxdepth 1 \
    -type d \
    -name '*.framework' \
    -print0
)

if [[ "${resigned_framework}" == "true" ]]; then
  codesign \
    --force \
    --sign "${identity_hash}" \
    --preserve-metadata=identifier,entitlements \
    "${APP_PATH}"
fi

codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
signature_details="$(codesign -dvvv "${APP_PATH}" 2>&1)"
if ! grep -Fqx "Authority=${identity_label}" <<<"${signature_details}"; then
  echo "The built app was not signed by the selected Apple Development identity" >&2
  exit 1
fi
if ! grep -Fqx "TeamIdentifier=${development_team}" <<<"${signature_details}"; then
  echo "The built app was not signed by the derived personal team" >&2
  exit 1
fi
unset signature_details

embedded_profile_path="${APP_PATH}/embedded.mobileprovision"
embedded_profile_plist="${PREFLIGHT_DIR}/embedded-profile.plist"
if [[ ! -f "${embedded_profile_path}" ]] ||
   ! security cms -D -i "${embedded_profile_path}" \
     >"${embedded_profile_plist}" 2>/dev/null; then
  echo "The built app does not contain a readable provisioning profile" >&2
  exit 1
fi

embedded_profile_team="$(
  plutil -extract TeamIdentifier.0 raw -o - \
    "${embedded_profile_plist}" 2>/dev/null || true
)"
embedded_profile_app_id="$(
  plutil -extract Entitlements.application-identifier raw -o - \
    "${embedded_profile_plist}" 2>/dev/null || true
)"
embedded_profile_debug="$(
  plutil -extract Entitlements.get-task-allow raw -o - \
    "${embedded_profile_plist}" 2>/dev/null || true
)"
embedded_profile_expiration="$(
  plutil -extract ExpirationDate raw -o - \
    "${embedded_profile_plist}" 2>/dev/null || true
)"
embedded_profile_devices="$(
  plutil -extract ProvisionedDevices json -o - \
    "${embedded_profile_plist}" 2>/dev/null || true
)"
embedded_profile_platforms="$(
  plutil -extract Platform json -o - \
    "${embedded_profile_plist}" 2>/dev/null || true
)"

if [[ "${embedded_profile_team}" != "${development_team}" ||
      "${embedded_profile_app_id}" != "${development_team}.${preview_bundle_id}" ||
      "${embedded_profile_debug}" != "true" ]] ||
   ! ruby -rjson -e '
       begin
         exit JSON.parse(ARGV.fetch(0)).include?(ARGV.fetch(1)) ? 0 : 1
       rescue JSON::ParserError
         exit 1
       end
     ' "${embedded_profile_devices}" "${device_id}" ||
   ! ruby -rjson -e '
       begin
         exit JSON.parse(ARGV.fetch(0)).include?("iOS") ? 0 : 1
       rescue JSON::ParserError
         exit 1
       end
     ' "${embedded_profile_platforms}" ||
   ! ruby -rtime -e \
     'exit Time.parse(ARGV.fetch(0)) > Time.now ? 0 : 1' \
     "${embedded_profile_expiration}"; then
  echo "The app's embedded provisioning profile does not match the verified personal preview" >&2
  exit 1
fi
unset \
  embedded_profile_team \
  embedded_profile_app_id \
  embedded_profile_debug \
  embedded_profile_expiration \
  embedded_profile_devices \
  embedded_profile_platforms

install_log="${LOG_DIR}/devicectl-install.log"
echo "Installing the preview on the physical iPhone..."
if ! xcrun devicectl device install app \
  --device "${device_id}" \
  "${APP_PATH}" >"${install_log}" 2>&1; then
  echo "Device installation failed. Last log lines:" >&2
  tail -80 "${install_log}" >&2
  exit 1
fi

launch_log="${LOG_DIR}/devicectl-launch.log"
echo "Launching the standalone Profile preview..."
if ! xcrun devicectl device process launch \
  --device "${device_id}" \
  --terminate-existing \
  "${preview_bundle_id}" >"${launch_log}" 2>&1; then
  echo "Device launch failed. Last log lines:" >&2
  tail -80 "${launch_log}" >&2
  exit 1
fi

apps_json="${PREFLIGHT_DIR}/apps.json"
xcrun devicectl device info apps \
  --device "${device_id}" \
  --json-output "${apps_json}" >/dev/null
if ! installed_executable="$(
  ruby -rjson -e '
      apps = JSON.parse(File.read(ARGV.fetch(0))).dig("result", "apps") || []
      app = apps.find { |item| item["bundleIdentifier"] == ARGV.fetch(1) }
      exit 1 unless app
      print "#{app.fetch("url")}Runner"
    ' "${apps_json}" "${preview_bundle_id}"
)"; then
  echo "The installed preview app could not be resolved by bundle ID" >&2
  exit 1
fi
readonly installed_executable

process_json="${PREFLIGHT_DIR}/processes.json"
process_running=false
for _ in {1..15}; do
  xcrun devicectl device info processes \
    --device "${device_id}" \
    --json-output "${process_json}" >/dev/null
  if ruby -rjson -e '
    data = JSON.parse(File.read(ARGV.fetch(0)))
    processes = data.dig("result", "runningProcesses") || []
    exit(
      processes.any? { |item|
        item.fetch("executable", "") == ARGV.fetch(1)
      } ? 0 : 1
    )
  ' "${process_json}" "${installed_executable}"; then
    process_running=true
    break
  fi
  sleep 2
done

if [[ "${process_running}" != "true" ]]; then
  echo "Runner did not remain active after launch" >&2
  exit 1
fi

final_git_status_digest="$(
  git -C "${PROJECT_ROOT}" status \
    --porcelain=v1 \
    -z \
    --untracked-files=all |
    shasum -a 256 |
    awk '{print $1}'
)"
if [[ "${final_git_status_digest}" != "${initial_git_status_digest}" ]]; then
  echo "The repository worktree status changed during the preview run" >&2
  echo "Inspect git status before treating the preview as verified." >&2
  exit 1
fi
unset final_git_status_digest

if [[ "${open_mirroring}" == "true" ]]; then
  open -b com.apple.ScreenContinuity
fi

echo "Anycast is installed and running as a standalone Profile preview."
echo "Confirm the actual first frame on the iPhone or in iPhone Mirroring."
echo "A running PID alone does not prove that the UI is not white."
echo "Build log: ${build_log}"
