#!/usr/bin/env bash

set -euo pipefail
set +x

readonly API_ROOT="https://androidpublisher.googleapis.com/androidpublisher/v3"
readonly UPLOAD_ROOT="https://androidpublisher.googleapis.com/upload/androidpublisher/v3"
readonly PACKAGE_NAME="com.kindjeff.anycast"
readonly TARGET_TRACK="internal"

required_variables=(
  GOOGLE_PLAY_ACCESS_TOKEN
  AAB_PATH
  RELEASE_NAME
)

for variable_name in "${required_variables[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    echo "Required environment variable is empty: ${variable_name}" >&2
    exit 1
  fi
done

if [[ ! -f "${AAB_PATH}" || -L "${AAB_PATH}" ]]; then
  echo "Signed AAB is missing or is a symbolic link: ${AAB_PATH}" >&2
  exit 1
fi

authorization_header="Authorization: Bearer ${GOOGLE_PLAY_ACCESS_TOKEN}"
readonly authorization_header

edit_response="$(
  curl --fail-with-body --silent --show-error \
    --request POST \
    --header "${authorization_header}" \
    --header 'Content-Type: application/json' \
    --data '{}' \
    "${API_ROOT}/applications/${PACKAGE_NAME}/edits"
)"
edit_id="$(jq -er '.id' <<<"${edit_response}")"
unset edit_response

if [[ ! "${edit_id}" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Google Play returned an invalid edit ID" >&2
  exit 1
fi

committed=false
cleanup_edit() {
  if [[ "${committed}" != "true" ]]; then
    curl --silent --show-error \
      --request DELETE \
      --header "${authorization_header}" \
      "${API_ROOT}/applications/${PACKAGE_NAME}/edits/${edit_id}" \
      >/dev/null || true
  fi
}
trap cleanup_edit EXIT INT TERM

tracks_response="$(
  curl --fail-with-body --silent --show-error \
    --request GET \
    --header "${authorization_header}" \
    "${API_ROOT}/applications/${PACKAGE_NAME}/edits/${edit_id}/tracks"
)"

if ! jq -e '.tracks | type == "array"' \
  <<<"${tracks_response}" >/dev/null; then
  echo "Google Play returned an invalid track list" >&2
  exit 1
fi

if ! jq -e \
  --arg track "${TARGET_TRACK}" \
  'any(.tracks[]?; .track == $track)' \
  <<<"${tracks_response}" >/dev/null; then
  available_tracks="$(
    jq -r \
      '[
        .tracks[]?.track
        | select(type == "string" and length > 0)
      ]
      | unique
      | sort
      | if length == 0 then "(none)" else join(", ") end' \
      <<<"${tracks_response}"
  )"
  echo \
    "Required Google Play track ${TARGET_TRACK} is unavailable. Available tracks: ${available_tracks}" \
    >&2
  exit 1
fi
unset tracks_response

bundle_response="$(
  curl --fail-with-body --silent --show-error \
    --request POST \
    --header "${authorization_header}" \
    --header 'Content-Type: application/octet-stream' \
    --data-binary "@${AAB_PATH}" \
    "${UPLOAD_ROOT}/applications/${PACKAGE_NAME}/edits/${edit_id}/bundles?uploadType=media"
)"
version_code="$(jq -er '.versionCode | tostring' <<<"${bundle_response}")"
unset bundle_response

if [[ ! "${version_code}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Google Play returned an invalid version code" >&2
  exit 1
fi

track_payload="$(
  jq -cn \
    --arg track "${TARGET_TRACK}" \
    --arg release_name "${RELEASE_NAME}" \
    --arg version_code "${version_code}" \
    '{
      track: $track,
      releases: [{
        name: $release_name,
        versionCodes: [$version_code],
        status: "completed"
      }]
    }'
)"

curl --fail-with-body --silent --show-error \
  --request PUT \
  --header "${authorization_header}" \
  --header 'Content-Type: application/json' \
  --data "${track_payload}" \
  "${API_ROOT}/applications/${PACKAGE_NAME}/edits/${edit_id}/tracks/${TARGET_TRACK}" \
  >/dev/null
unset track_payload

curl --fail-with-body --silent --show-error \
  --request POST \
  --header "${authorization_header}" \
  "${API_ROOT}/applications/${PACKAGE_NAME}/edits/${edit_id}:commit" \
  >/dev/null

committed=true
echo "Uploaded Android version code ${version_code} to Play track ${TARGET_TRACK}."
