#!/bin/bash

LOGFILE="system_watchdog.log"
MAXSIZE=10485760  # 10 MiB
TMPLOG="system_watchdog.tmp"
PREV_COUNT=0

# ANSI color codes
RESET="\033[0m"
BLUE="\033[1;34m"
RED="\033[0;31m"
BOLD_RED="\033[1;31m"
YELLOW="\033[0;33m"

# Rotate log file if needed
rotate_log() {
  if [[ -f "$LOGFILE" && $(stat -c%s "$LOGFILE") -ge $MAXSIZE ]]; then
    mv "$LOGFILE" "$LOGFILE.$(date '+%Y%m%d_%H%M%S')"
    echo "[Log rotated]" > "$LOGFILE"
    echo "[Log rotated]"
  fi
}

# Determine severity
get_severity() {
  local line="$1"
  if echo "$line" | grep -iq "critical"; then
    echo "CRITICAL"
  elif echo "$line" | grep -iqE "fail|error|panic"; then
    echo "ERROR"
  elif echo "$line" | grep -iq "warn"; then
    echo "WARNING"
  else
    echo "INFO"
  fi
}

# Color severity
colorize_severity() {
  case "$1" in
    CRITICAL) echo -e "${BOLD_RED}$1${RESET}" ;;
    ERROR) echo -e "${RED}$1${RESET}" ;;
    WARNING) echo -e "${YELLOW}$1${RESET}" ;;
    *) echo "$1" ;;
  esac
}

# Print headers
print_headers() {
  echo -e "${BLUE}Severity   | Timestamp           | Source     | Message${RESET}"
  echo -e "-----------|---------------------|------------|--------"
}

# Cleanup function
cleanup() {
  echo -e "\n[!] Caught interrupt signal. Cleaning up..."
  kill "$JOURNAL_PID" "$DMESG_PID" 2>/dev/null
  sort_messages >> "$LOGFILE"
  rm -f "$TMPLOG"
  echo "[✓] Log saved to $LOGFILE"
  exit 0
}

# Collect and buffer messages
log_with_timestamp() {
  local source="$1"
  while IFS= read -r line; do
    severity=$(get_severity "$line")
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf "%s|%s|%s|%s\n" "$severity" "$timestamp" "$source" "$line" >> "$TMPLOG"
    rotate_log
  done
}

# Sort and print buffered messages
sort_messages() {
  sort -t'|' -k1,1 -k2,2 "$TMPLOG" | while IFS='|' read -r severity timestamp source message; do
    severity_color=$(colorize_severity "$severity")
    printf "%-10s| %-20s | %-10s | %s\n" "$severity_color" "$timestamp" "$source" "$message"
  done
}

# Watch for file growth and redraw if needed
watch_log_changes() {
  while true; do
    COUNT=$(wc -l < "$TMPLOG")
    if [[ "$COUNT" -ne "$PREV_COUNT" ]]; then
      clear
      echo
      echo "=== System Watchdog Started ==="
      echo "Watching for system warnings and errors..."
      echo "Outputting to both terminal and: $LOGFILE"
      echo
      echo "Press Ctrl+C to stop."
      echo
      echo "-----------------------------------------------"
      print_headers
      sort_messages
      PREV_COUNT=$COUNT
    fi
    sleep 1
  done
}

# Setup
trap cleanup SIGINT
rm -f "$TMPLOG"
touch "$TMPLOG"

echo
echo "=== System Watchdog Started ==="
echo "Watching for system warnings and errors..."
echo "Outputting to both terminal and: $LOGFILE"
echo
echo "Press Ctrl+C to stop."
echo
echo "-----------------------------------------------"
sleep 5

# Start log readers
journalctl -f -p warning | log_with_timestamp "JOURNALCTL" &
JOURNAL_PID=$!

dmesg --follow | grep --line-buffered -Ei 'warn|error|fail|critical|panic' | log_with_timestamp "DMESG" &
DMESG_PID=$!

# Start monitoring for changes
watch_log_changes
