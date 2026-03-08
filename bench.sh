#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# OS Benchmark — wrk2 test runner
# Usage: ./bench.sh <server-ip> <os-name>
# Example: ./bench.sh 192.168.1.10 linux
#          ./bench.sh 192.168.1.20 freebsd
# =============================================================================

SERVER_IP="${1:?Usage: ./bench.sh <server-ip> <os-name>}"
OS_NAME="${2:?Usage: ./bench.sh <server-ip> <os-name>}"
BASE_URL="http://${SERVER_IP}:3000"
WRK2="./wrk2/wrk"
RESULTS_DIR="results/${OS_NAME}"
DURATION="60s"
WARMUP_DURATION="30s"

ENDPOINTS=(compute cached db fileio concurrent mem syscall)

# Concurrency profiles: name threads connections target-rate
PROFILES=(
  "low:4:50:2000"
  "mid:8:200:5000"
  "high:8:500:10000"
)

# --- Setup -------------------------------------------------------------------

mkdir -p "${RESULTS_DIR}"

if [[ ! -x "${WRK2}" ]]; then
  echo "[*] Building wrk2..."
  if command -v apt-get &>/dev/null; then
    sudo apt-get install -y gcc make git libssl-dev zlib1g-dev
  elif command -v yum &>/dev/null; then
    sudo yum install -y gcc make git openssl-devel
  elif command -v pkg &>/dev/null; then
    sudo pkg install -y gcc gmake git openssl
  fi
  rm -rf wrk2-src
  git clone https://github.com/giltene/wrk2.git wrk2-src && cd wrk2-src
  if command -v gmake &>/dev/null; then gmake; else make; fi
  cd ..
  mkdir -p wrk2 && cp wrk2-src/wrk "${WRK2}"
  echo "[*] wrk2 built successfully"
fi

# --- Health check ------------------------------------------------------------

echo "[*] Checking server at ${BASE_URL}/health ..."
if ! curl -sf "${BASE_URL}/health" > /dev/null 2>&1; then
  echo "[!] Server not reachable at ${BASE_URL}. Start the Go service first."
  exit 1
fi
echo "[*] Server is healthy"

# --- Warmup ------------------------------------------------------------------

echo ""
echo "============================================"
echo "  WARMUP (${WARMUP_DURATION}) — ${OS_NAME}"
echo "============================================"

for ep in "${ENDPOINTS[@]}"; do
  echo "[*] Warming up /${ep} ..."
  ${WRK2} -t4 -c100 -d"${WARMUP_DURATION}" -R1000 "${BASE_URL}/${ep}" > /dev/null 2>&1
done

echo "[*] Warmup complete. Cooling down 5s..."
sleep 5

# --- Benchmark runs ----------------------------------------------------------

echo ""
echo "============================================"
echo "  BENCHMARK — ${OS_NAME}"
echo "============================================"

for profile in "${PROFILES[@]}"; do
  IFS=':' read -r label threads conns rate <<< "${profile}"

  echo ""
  echo "--- Profile: ${label} (threads=${threads}, conns=${conns}, rate=${rate} req/s) ---"

  for ep in "${ENDPOINTS[@]}"; do
    outfile="${RESULTS_DIR}/${ep}_${label}.txt"
    echo "[*] Testing /${ep} @ ${label} -> ${outfile}"

    ${WRK2} \
      -t"${threads}" \
      -c"${conns}" \
      -d"${DURATION}" \
      -R"${rate}" \
      --latency \
      "${BASE_URL}/${ep}" > "${outfile}" 2>&1

    # Print summary line (requests/sec and avg latency)
    tail -5 "${outfile}" | head -2

    # Brief cooldown between tests to avoid interference
    sleep 2
  done
done

# --- Summary -----------------------------------------------------------------

echo ""
echo "============================================"
echo "  DONE — results in ${RESULTS_DIR}/"
echo "============================================"
ls -la "${RESULTS_DIR}/"
