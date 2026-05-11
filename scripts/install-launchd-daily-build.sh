#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLIST_LABEL="com.agent-docker.daily-build"
PLIST_PATH="${HOME}/Library/LaunchAgents/${PLIST_LABEL}.plist"
BUILD_SCRIPT="${REPO_DIR}/scripts/daily-build.sh"

mkdir -p "${HOME}/Library/LaunchAgents" "${REPO_DIR}/logs"
chmod +x "${BUILD_SCRIPT}"

cat >"${PLIST_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${PLIST_LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>${BUILD_SCRIPT}</string>
  </array>

  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>6</integer>
    <key>Minute</key>
    <integer>30</integer>
  </dict>

  <key>RunAtLoad</key>
  <false/>

  <key>StandardOutPath</key>
  <string>${REPO_DIR}/logs/daily-build.launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>${REPO_DIR}/logs/daily-build.launchd.err.log</string>
</dict>
</plist>
EOF

if launchctl print "gui/$(id -u)/${PLIST_LABEL}" >/dev/null 2>&1; then
  launchctl bootout "gui/$(id -u)" "${PLIST_PATH}"
fi

launchctl bootstrap "gui/$(id -u)" "${PLIST_PATH}"
launchctl enable "gui/$(id -u)/${PLIST_LABEL}"

echo "installed ${PLIST_PATH}"
echo "daily build time: 06:30 local time"
echo "build log: ${REPO_DIR}/logs/daily-build.log"
