#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# OS Benchmark — Compare results between Linux and FreeBSD
# Usage: ./compare.sh [results-dir]
# Example: ./compare.sh results
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RESULTS_DIR="${1:-${PROJECT_DIR}/results}"
OS_A="linux"
OS_B="freebsd"
DIR_A="${RESULTS_DIR}/${OS_A}"
DIR_B="${RESULTS_DIR}/${OS_B}"

if [[ ! -d "${DIR_A}" ]]; then
  echo "[!] Missing results for ${OS_A} in ${DIR_A}"
  exit 1
fi
if [[ ! -d "${DIR_B}" ]]; then
  echo "[!] Missing results for ${OS_B} in ${DIR_B}"
  exit 1
fi

ENDPOINTS=(compute cached db fileio concurrent mem syscall)
PROFILES=(low mid high)

# --- Helpers -----------------------------------------------------------------

parse_avg_latency() {
  # Extract avg latency from "Thread Stats" line, convert to microseconds
  local file="$1"
  local raw
  raw=$(grep -A1 "Thread Stats" "$file" | tail -1 | awk '{print $2}')
  to_us "$raw"
}

parse_p50() {
  local file="$1"
  grep "^ 50.000%" "$file" | awk '{print $2}' | head -1
}

parse_p99() {
  local file="$1"
  grep "^ 99.000%" "$file" | awk '{print $2}' | head -1
}

parse_max_latency() {
  local file="$1"
  grep -A1 "Thread Stats" "$file" | tail -1 | awk '{print $4}'
}

parse_rps() {
  local file="$1"
  grep "^Requests/sec:" "$file" | awk '{print $2}'
}

parse_total_requests() {
  local file="$1"
  grep "requests in" "$file" | awk '{print $1}'
}

to_us() {
  # Convert latency string (e.g., 0.85ms, 790.17us, 1.20s, 0.93m) to microseconds
  local val="$1"
  if [[ "$val" == *ms ]]; then
    echo "$val" | sed 's/ms//' | awk '{printf "%.2f", $1 * 1000}'
  elif [[ "$val" == *us ]]; then
    echo "$val" | sed 's/us//' | awk '{printf "%.2f", $1}'
  elif [[ "$val" == *m ]]; then
    echo "$val" | sed 's/m//' | awk '{printf "%.2f", $1 * 60 * 1000000}'
  elif [[ "$val" == *s ]]; then
    echo "$val" | sed 's/s//' | awk '{printf "%.2f", $1 * 1000000}'
  else
    echo "$val"
  fi
}

format_latency() {
  # Format microseconds into human-readable form
  local us="$1"
  awk "BEGIN {
    v = $us
    if (v >= 60000000) printf \"%.2fm\", v / 60000000
    else if (v >= 1000000) printf \"%.2fs\", v / 1000000
    else if (v >= 1000) printf \"%.2fms\", v / 1000
    else printf \"%.2fus\", v
  }"
}

pct_diff() {
  # Calculate percentage difference: positive = B is worse (higher latency)
  # For latency: positive means FreeBSD is slower
  # For throughput: positive means FreeBSD is faster
  local a="$1" b="$2"
  awk "BEGIN {
    if ($a == 0) { printf \"N/A\"; exit }
    diff = (($b - $a) / $a) * 100
    printf \"%+.1f%%\", diff
  }"
}

color_latency_diff() {
  # Green if FreeBSD is lower (negative diff), red if higher
  local diff="$1"
  if [[ "$diff" == "N/A" ]]; then
    echo "$diff"
    return
  fi
  local num
  num=$(echo "$diff" | sed 's/[%+]//g')
  if awk "BEGIN { exit !($num < -1) }"; then
    echo -e "\033[32m${diff}\033[0m"  # green = FreeBSD faster
  elif awk "BEGIN { exit !($num > 1) }"; then
    echo -e "\033[31m${diff}\033[0m"  # red = FreeBSD slower
  else
    echo -e "\033[33m${diff}\033[0m"  # yellow = roughly equal
  fi
}

color_rps_diff() {
  # Green if FreeBSD is higher (positive diff), red if lower
  local diff="$1"
  if [[ "$diff" == "N/A" ]]; then
    echo "$diff"
    return
  fi
  local num
  num=$(echo "$diff" | sed 's/[%+]//g')
  if awk "BEGIN { exit !($num > 1) }"; then
    echo -e "\033[32m${diff}\033[0m"  # green = FreeBSD faster
  elif awk "BEGIN { exit !($num < -1) }"; then
    echo -e "\033[31m${diff}\033[0m"  # red = FreeBSD slower
  else
    echo -e "\033[33m${diff}\033[0m"  # yellow = roughly equal
  fi
}

# --- Header ------------------------------------------------------------------

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════════════════════════════╗"
echo "║                              OS BENCHMARK COMPARISON: Linux vs FreeBSD                             ║"
echo "╚══════════════════════════════════════════════════════════════════════════════════════════════════════╝"
echo ""

# --- Per-profile comparison --------------------------------------------------

for profile in "${PROFILES[@]}"; do
  echo "┌──────────────────────────────────────────────────────────────────────────────────────────────────────┐"
  printf "│  Profile: %-89s│\n" "${profile}"
  echo "├──────────────┬────────────────────────┬────────────────────────┬────────────────────────────────────┤"
  printf "│ %-12s │ %-22s │ %-22s │ %-34s │\n" "Endpoint" "Linux" "FreeBSD" "Diff (FreeBSD vs Linux)"
  echo "├──────────────┼────────────────────────┼────────────────────────┼────────────────────────────────────┤"

  for ep in "${ENDPOINTS[@]}"; do
    file_a="${DIR_A}/${ep}_${profile}.txt"
    file_b="${DIR_B}/${ep}_${profile}.txt"

    if [[ ! -f "$file_a" || ! -f "$file_b" ]]; then
      printf "│ %-12s │ %-22s │ %-22s │ %-34s │\n" "$ep" "MISSING" "MISSING" "-"
      continue
    fi

    # Avg latency
    lat_a=$(parse_avg_latency "$file_a")
    lat_b=$(parse_avg_latency "$file_b")
    lat_diff=$(pct_diff "$lat_a" "$lat_b")
    lat_diff_colored=$(color_latency_diff "$lat_diff")

    # P50
    p50_a_raw=$(parse_p50 "$file_a")
    p50_b_raw=$(parse_p50 "$file_b")
    p50_a=$(to_us "$p50_a_raw")
    p50_b=$(to_us "$p50_b_raw")

    # P99
    p99_a_raw=$(parse_p99 "$file_a")
    p99_b_raw=$(parse_p99 "$file_b")
    p99_a=$(to_us "$p99_a_raw")
    p99_b=$(to_us "$p99_b_raw")
    p99_diff=$(pct_diff "$p99_a" "$p99_b")
    p99_diff_colored=$(color_latency_diff "$p99_diff")

    # RPS
    rps_a=$(parse_rps "$file_a")
    rps_b=$(parse_rps "$file_b")
    rps_diff=$(pct_diff "$rps_a" "$rps_b")
    rps_diff_colored=$(color_rps_diff "$rps_diff")

    # Format for display
    lat_a_fmt=$(format_latency "$lat_a")
    lat_b_fmt=$(format_latency "$lat_b")
    p50_a_fmt=$(format_latency "$p50_a")
    p50_b_fmt=$(format_latency "$p50_b")
    p99_a_fmt=$(format_latency "$p99_a")
    p99_b_fmt=$(format_latency "$p99_b")

    # Print rows
    printf "│ %-12s │                        │                        │                                    │\n" "$ep"
    printf "│   Avg Lat    │ %22s │ %22s │   %s\n" "$lat_a_fmt" "$lat_b_fmt" "$lat_diff_colored"
    printf "│   P50        │ %22s │ %22s │\n" "$p50_a_fmt" "$p50_b_fmt"
    printf "│   P99        │ %22s │ %22s │   %s\n" "$p99_a_fmt" "$p99_b_fmt" "$p99_diff_colored"
    printf "│   Req/sec    │ %22s │ %22s │   %s\n" "$rps_a" "$rps_b" "$rps_diff_colored"
  done

  echo "└──────────────┴────────────────────────┴────────────────────────┴────────────────────────────────────┘"
  echo ""
done

# --- Summary table -----------------------------------------------------------

echo "╔══════════════════════════════════════════════════════════════════════════════════════════════════════╗"
echo "║                                          SUMMARY                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════════════════════════════════════════╝"
echo ""

linux_wins=0
freebsd_wins=0
ties=0

for profile in "${PROFILES[@]}"; do
  for ep in "${ENDPOINTS[@]}"; do
    file_a="${DIR_A}/${ep}_${profile}.txt"
    file_b="${DIR_B}/${ep}_${profile}.txt"
    [[ ! -f "$file_a" || ! -f "$file_b" ]] && continue

    lat_a=$(parse_avg_latency "$file_a")
    lat_b=$(parse_avg_latency "$file_b")

    result=$(awk "BEGIN {
      diff = (($lat_b - $lat_a) / $lat_a) * 100
      if (diff < -1) print \"freebsd\"
      else if (diff > 1) print \"linux\"
      else print \"tie\"
    }")

    case "$result" in
      linux)   linux_wins=$((linux_wins + 1)) ;;
      freebsd) freebsd_wins=$((freebsd_wins + 1)) ;;
      tie)     ties=$((ties + 1)) ;;
    esac
  done
done

total=$((linux_wins + freebsd_wins + ties))

echo "  Based on average latency across all ${total} test combinations:"
echo ""
printf "    Linux wins:   %d/%d\n" "$linux_wins" "$total"
printf "    FreeBSD wins: %d/%d\n" "$freebsd_wins" "$total"
printf "    Ties (<1%%):   %d/%d\n" "$ties" "$total"
echo ""

if ((linux_wins > freebsd_wins)); then
  echo -e "  \033[32mLinux\033[0m has lower latency in the majority of tests."
elif ((freebsd_wins > linux_wins)); then
  echo -e "  \033[32mFreeBSD\033[0m has lower latency in the majority of tests."
else
  echo "  Results are evenly split between Linux and FreeBSD."
fi
echo ""
