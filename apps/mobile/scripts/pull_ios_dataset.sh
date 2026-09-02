#!/usr/bin/env bash

set -euo pipefail

BUNDLE_ID="${BUNDLE_ID:-io.rootlens.app}"
LOCAL_ROOT="${LOCAL_ROOT:-./logs/ios_sessions}"

usage() {
  cat <<EOF
Usage:
  scripts/pull_ios_dataset.sh [--latest] [--all]

Options:
  --latest       Pull only the latest session folder (default)
  --all          Pull all session_* folders
  --help, -h     Show this help

Environment overrides:
  BUNDLE_ID=io.rootlens.app
  LOCAL_ROOT=./logs/ios_sessions

Prerequisites:
  Xcode 15+ with xcrun devicectl (ships with Xcode, no extra install needed)

Uses xcrun devicectl to access the iOS app's data container and copy
session data (session_data.mcap, metadata.json, thumbnail.jpg).

Examples:
  scripts/pull_ios_dataset.sh
  scripts/pull_ios_dataset.sh --all
EOF
}

MODE="latest"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      MODE="all"
      shift
      ;;
    --latest)
      MODE="latest"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

# --- Dependency check ---

if ! xcrun devicectl --version >/dev/null 2>&1; then
  echo "xcrun devicectl not found. Install Xcode 15+ and retry."
  exit 1
fi

# --- Temp directory for JSON outputs ---

TMPDIR_DC="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_DC"' EXIT

# --- Detect connected device ---

echo "Detecting connected iOS device..."
xcrun devicectl list devices --json-output "$TMPDIR_DC/devices.json" 2>/dev/null

UDID="$(python3 -c "
import json, sys
with open('$TMPDIR_DC/devices.json') as f:
    data = json.load(f)
devices = data.get('result', {}).get('devices', [])
connected = [d for d in devices if d.get('connectionProperties', {}).get('transportType') is not None]
if not connected:
    sys.exit(0)
print(connected[0]['identifier'], end='')
")"

if [[ -z "$UDID" ]]; then
  echo "No connected iOS device found. Connect your device and trust this computer."
  exit 1
fi

echo "Found device: $UDID"

# --- Helpers ---

file_size() {
  du -sh "$1" 2>/dev/null | cut -f1
}

verify_session() {
  local session_dir="$1"
  local all_ok=true

  echo "  Verifying session contents:"

  # Check for session_data_*.mcap
  local mcap_files
  mcap_files=("$session_dir"/session_data_*.mcap)
  if [[ -f "${mcap_files[0]}" && -s "${mcap_files[0]}" ]]; then
    echo "    ✓ $(basename "${mcap_files[0]}") ($(file_size "${mcap_files[0]}"))"
  else
    echo "    ✗ session_data_*.mcap — missing or empty"
    all_ok=false
  fi

  for f in metadata.json thumbnail.jpg; do
    local fpath="$session_dir/$f"
    if [[ -f "$fpath" && -s "$fpath" ]]; then
      echo "    ✓ $f ($(file_size "$fpath"))"
    else
      echo "    ✗ $f — missing or empty"
      all_ok=false
    fi
  done

  if [[ "$all_ok" == false ]]; then
    echo "  WARNING: session appears incomplete"
    return 1
  fi
}

# --- List sessions on device ---

echo "Listing sessions on device..."
xcrun devicectl device info files \
  --device "$UDID" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --subdirectory Documents/ar_sessions \
  --json-output "$TMPDIR_DC/files.json" 2>/dev/null

sessions=()
while IFS= read -r line; do
  [[ -n "$line" ]] && sessions+=("$line")
done < <(python3 -c "
import json
with open('$TMPDIR_DC/files.json') as f:
    data = json.load(f)
files = data.get('result', {}).get('files', [])
names = sorted([
    f['name'] for f in files
    if f.get('name', '').startswith('session_')
    and '/' not in f.get('name', '')
    and f.get('resources', {}).get('isDirectory', False)
])
for n in names:
    print(n)
")

if [[ ${#sessions[@]} -eq 0 ]]; then
  echo "No session folders found under ar_sessions/ in app container."
  exit 1
fi

echo "Found ${#sessions[@]} session(s) on device."

# --- Select sessions ---

if [[ "$MODE" == "latest" ]]; then
  sessions=("${sessions[${#sessions[@]}-1]}")
fi

# --- Pull sessions ---

mkdir -p "$LOCAL_ROOT"

for session_name in "${sessions[@]}"; do
  local_path="$LOCAL_ROOT/$session_name"
  echo "Pulling $session_name -> $local_path"

  xcrun devicectl device copy from \
    --device "$UDID" \
    --source "Documents/ar_sessions/$session_name" \
    --destination "$local_path" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" 2>/dev/null

  verify_session "$local_path" || true
  echo ""
done

if [[ "$MODE" == "all" ]]; then
  echo "Pulled ${#sessions[@]} sessions into $LOCAL_ROOT"
else
  echo "Done: $LOCAL_ROOT/${sessions[0]}"
fi
