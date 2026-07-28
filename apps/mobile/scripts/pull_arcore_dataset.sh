#!/usr/bin/env bash

set -euo pipefail

APP_ID="${APP_ID:-open.fpvlabs.stera}"
EXTERNAL_ROOT="${EXTERNAL_ROOT:-/storage/emulated/0/Android/data/${APP_ID}/files/ar_sessions}"
LOCAL_ROOT="${LOCAL_ROOT:-./logs/arcore_sessions}"

usage() {
  cat <<EOF
Usage:
  scripts/pull_arcore_dataset.sh [--latest] [--all]

Options:
  --latest       Pull only the latest session folder (default)
  --all          Pull all session_* folders

Environment overrides:
  APP_ID=open.fpvlabs.stera
  EXTERNAL_ROOT=/storage/emulated/0/Android/data/<APP_ID>/files/ar_sessions
  LOCAL_ROOT=./logs/arcore_sessions

Pulls session_data.mcap, metadata.json, and thumbnail.jpg from the device.

Examples:
  scripts/pull_arcore_dataset.sh
  scripts/pull_arcore_dataset.sh --all
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

if ! command -v adb >/dev/null 2>&1; then
  echo "adb not found. Install Android platform-tools and retry."
  exit 1
fi

if [[ -z "$(adb devices | awk 'NR>1 && $2=="device" {print $1}')" ]]; then
  echo "No connected Android device found. Connect phone and enable USB debugging."
  exit 1
fi

mkdir -p "$LOCAL_ROOT"

# Print size of a file in human-readable form
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

pull_session() {
  local session_path="$1"
  local session_name
  session_name="$(basename "$session_path")"
  local local_path="$LOCAL_ROOT/$session_name"

  echo "Pulling $session_name -> $local_path"

  adb pull "$EXTERNAL_ROOT/$session_name" "$LOCAL_ROOT"

  verify_session "$local_path" || true
}

if [[ "$MODE" == "all" ]]; then
  mapfile -t sessions < <(adb shell "ls -d ${EXTERNAL_ROOT}/session_* 2>/dev/null" | tr -d '\r')
  if [[ ${#sessions[@]} -eq 0 ]]; then
    echo "No session folders found under ${EXTERNAL_ROOT} (app external storage)"
    exit 1
  fi

  for remote_path in "${sessions[@]}"; do
    pull_session "$remote_path"
    echo ""
  done
  echo "Pulled ${#sessions[@]} sessions into $LOCAL_ROOT"
else
  latest="$(adb shell "ls -td ${EXTERNAL_ROOT}/session_* 2>/dev/null | head -n 1" | tr -d '\r')"
  if [[ -z "$latest" ]]; then
    echo "No session folders found under ${EXTERNAL_ROOT} (app external storage)"
    exit 1
  fi

  pull_session "$latest"
  echo ""
  echo "Done: ${LOCAL_ROOT}/$(basename "$latest")"
fi
