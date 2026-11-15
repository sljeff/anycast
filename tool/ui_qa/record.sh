#!/usr/bin/env bash
# UI walkthrough recorder: record the simulator while a driver runs, then
# split the video into review frames.
#
# Usage:
#   tool/ui_qa/record.sh <run-name> <udid> <driver-command...>
#
# Example:
#   tool/ui_qa/record.sh smoke-walkthrough AFD8A99E-5B4B-43DB-B9E4-86BCC022B2F3 \
#     xcodebuild -project native/Anycast.xcodeproj -scheme Anycast \
#       -derivedDataPath native/build/dd -destination 'platform=iOS Simulator,id=AFD8A99E-5B4B-43DB-B9E4-86BCC022B2F3' \
#       -only-testing:AnycastUITests/SmokeFlowsUITests test-without-building
#
# Artifacts (all disposable, under native/build/runs/<run-name>/):
#   video.mp4      the raw screen recording (h264)
#   frames/*.png   1 fps review frames (override with FRAME_FPS)
#   driver.log     the driver's full output
set -euo pipefail

RUN_NAME=${1:?run name required}
UDID=${2:?simulator udid required}
shift 2

RUN_DIR="native/build/runs/${RUN_NAME}"
mkdir -p "${RUN_DIR}/frames"
VIDEO="${RUN_DIR}/video.mp4"
FRAME_FPS=${FRAME_FPS:-1}

echo "[record] video → ${VIDEO}"
xcrun simctl io "${UDID}" recordVideo --codec h264 --force "${VIDEO}" &
REC_PID=$!
sleep 1   # let the encoder attach before the driver starts moving

set +e
"$@" > "${RUN_DIR}/driver.log" 2>&1
DRIVER_STATUS=$?
set -e

# SIGINT makes recordVideo finalize the file cleanly; a hard kill truncates it.
kill -INT "${REC_PID}" 2>/dev/null || true
wait "${REC_PID}" 2>/dev/null || true

echo "[record] driver exit ${DRIVER_STATUS}; splitting frames at ${FRAME_FPS} fps"
ffmpeg -hide_banner -loglevel error -i "${VIDEO}" -vf "fps=${FRAME_FPS}" "${RUN_DIR}/frames/f_%04d.png"
echo "[record] done: ${RUN_DIR} ($(ls "${RUN_DIR}/frames" | wc -l | tr -d ' ') frames)"
exit "${DRIVER_STATUS}"
