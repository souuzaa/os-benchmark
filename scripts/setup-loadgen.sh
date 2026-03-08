#!/bin/bash
# =============================================================================
# setup-loadgen.sh — Load Generator (c6i.2xlarge / Ubuntu 24.04 LTS)
# Usage: chmod +x setup-loadgen.sh && sudo ./setup-loadgen.sh
# =============================================================================

set -euo pipefail

REPO_URL="https://github.com/souuzaa/os-benchmark"
GO_VERSION="1.22.3"
GO_TARBALL="go${GO_VERSION}.linux-amd64.tar.gz"
GO_URL="https://go.dev/dl/${GO_TARBALL}"
INSTALL_DIR="/home/ubuntu"

echo "============================================="
echo " OS Benchmark — Load Generator Setup"
echo "============================================="

# -----------------------------------------------------------------------------
# 1. System update
# -----------------------------------------------------------------------------
echo "[1/6] Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq

# -----------------------------------------------------------------------------
# 2. Base dependencies
# -----------------------------------------------------------------------------
echo "[2/6] Installing base dependencies..."
apt-get install -y -qq git wget curl gcc make libssl-dev zlib1g-dev luarocks

# -----------------------------------------------------------------------------
# 3. Go installation (for running any Go benchmark helpers)
# -----------------------------------------------------------------------------
echo "[3/6] Installing Go ${GO_VERSION}..."
wget -q "${GO_URL}" -O "/tmp/${GO_TARBALL}"
rm -rf /usr/local/go
tar -C /usr/local -xzf "/tmp/${GO_TARBALL}"
rm "/tmp/${GO_TARBALL}"

cat > /etc/profile.d/go.sh << 'EOF'
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
EOF

export PATH=$PATH:/usr/local/go/bin
echo "Go version: $(go version)"

# -----------------------------------------------------------------------------
# 4. wrk2 installation
# -----------------------------------------------------------------------------
echo "[4/6] Building wrk2..."
cd /tmp
git clone https://github.com/giltene/wrk2.git
cd wrk2
make -j$(nproc)
cp wrk /usr/local/bin/wrk2
chmod +x /usr/local/bin/wrk2
wrk2 --version 2>&1 | head -1 || echo "wrk2 installed at $(which wrk2)"
cd / && rm -rf /tmp/wrk2

# -----------------------------------------------------------------------------
# 5. Load generator tuning
# -----------------------------------------------------------------------------
echo "[5/6] Tuning system for load generation..."

# Higher connection limits — load gen needs lots of outbound sockets
cat > /etc/sysctl.d/99-loadgen.conf << 'EOF'
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=10
net.core.netdev_max_backlog=65535
net.ipv4.tcp_max_syn_backlog=65535
net.core.somaxconn=65535
EOF
sysctl --system --quiet

# Open file limits for ubuntu
cat >> /etc/security/limits.conf << 'EOF'
ubuntu soft nofile 100000
ubuntu hard nofile 100000
EOF

# -----------------------------------------------------------------------------
# 6. Clone repository + create run scripts
# -----------------------------------------------------------------------------
echo "[6/6] Cloning repository and creating run scripts..."
sudo -u ubuntu bash << EOF
cd ${INSTALL_DIR}
git clone ${REPO_URL} os-benchmark
cd os-benchmark
export PATH=\$PATH:/usr/local/go/bin
go mod tidy 2>/dev/null || true
echo "Repo cloned."
EOF

# Create the benchmark runner script
cat > ${INSTALL_DIR}/run-benchmark.sh << 'RUNNER'
#!/bin/bash
# =============================================================================
# run-benchmark.sh — Execute full benchmark against Linux and FreeBSD targets
# Usage: ./run-benchmark.sh <linux-ip> <freebsd-ip>
# =============================================================================

set -euo pipefail

LINUX_IP="${1:?Usage: ./run-benchmark.sh <linux-ip> <freebsd-ip>}"
FREEBSD_IP="${2:?Usage: ./run-benchmark.sh <linux-ip> <freebsd-ip>}"
PORT="3000"
RESULTS_DIR="$HOME/results/$(date +%Y%m%d_%H%M%S)"
THREADS=8
DURATION="60s"

mkdir -p "${RESULTS_DIR}"

echo "============================================="
echo " wrk2 Benchmark Runner"
echo " Linux:   ${LINUX_IP}:${PORT}"
echo " FreeBSD: ${FREEBSD_IP}:${PORT}"
echo " Results: ${RESULTS_DIR}"
echo "============================================="

run_test() {
  local label="$1"
  local url="$2"
  local conns="$3"
  local rate="$4"
  local outfile="${RESULTS_DIR}/${label}.txt"

  echo "  Running: ${label} (conns=${conns}, rate=${rate} req/s)..."
  wrk2 -t${THREADS} -c${conns} -d${DURATION} -R${rate} --latency "${url}" > "${outfile}" 2>&1
  echo "  Done. Output: ${outfile}"
}

# -- Warmup (not recorded) ----------------------------------------------------
echo ""
echo "[Warmup] Warming up both servers (30s each)..."
wrk2 -t4 -c50 -d30s -R500 --latency "http://${LINUX_IP}:${PORT}/compute"   > /dev/null 2>&1
wrk2 -t4 -c50 -d30s -R500 --latency "http://${FREEBSD_IP}:${PORT}/compute" > /dev/null 2>&1
echo "[Warmup] Done."

# -- Low concurrency (c=50, R=2000) -------------------------------------------
echo ""
echo "[Low Concurrency] conns=50, rate=2000 req/s"
run_test "linux_compute_low"   "http://${LINUX_IP}:${PORT}/compute"   50  2000
run_test "linux_cached_low"    "http://${LINUX_IP}:${PORT}/cached"    50  2000
run_test "linux_db_low"        "http://${LINUX_IP}:${PORT}/db"        50  2000
run_test "freebsd_compute_low" "http://${FREEBSD_IP}:${PORT}/compute" 50  2000
run_test "freebsd_cached_low"  "http://${FREEBSD_IP}:${PORT}/cached"  50  2000
run_test "freebsd_db_low"      "http://${FREEBSD_IP}:${PORT}/db"      50  2000

# -- High concurrency (c=500, R=10000) ----------------------------------------
echo ""
echo "[High Concurrency] conns=500, rate=10000 req/s"
run_test "linux_compute_high"   "http://${LINUX_IP}:${PORT}/compute"   500 10000
run_test "linux_cached_high"    "http://${LINUX_IP}:${PORT}/cached"    500 10000
run_test "linux_db_high"        "http://${LINUX_IP}:${PORT}/db"        500 10000
run_test "freebsd_compute_high" "http://${FREEBSD_IP}:${PORT}/compute" 500 10000
run_test "freebsd_cached_high"  "http://${FREEBSD_IP}:${PORT}/cached"  500 10000
run_test "freebsd_db_high"      "http://${FREEBSD_IP}:${PORT}/db"      500 10000

# -- Summary ------------------------------------------------------------------
echo ""
echo "============================================="
echo " All tests complete. Extracting p99 latencies..."
echo "============================================="
echo ""
printf "%-30s %10s %10s %10s %10s\n" "Test" "p50" "p90" "p99" "p999"
printf "%-30s %10s %10s %10s %10s\n" "----" "---" "---" "---" "----"

for f in "${RESULTS_DIR}"/*.txt; do
  label=$(basename "$f" .txt)
  p50=$(grep "50.000%" "$f"  | awk '{print $2}' || echo "N/A")
  p90=$(grep "90.000%" "$f"  | awk '{print $2}' || echo "N/A")
  p99=$(grep "99.000%" "$f"  | awk '{print $2}' || echo "N/A")
  p999=$(grep "99.900%" "$f" | awk '{print $2}' || echo "N/A")
  printf "%-30s %10s %10s %10s %10s\n" "$label" "$p50" "$p90" "$p99" "$p999"
done

echo ""
echo "Raw results saved to: ${RESULTS_DIR}"
RUNNER

chmod +x ${INSTALL_DIR}/run-benchmark.sh
chown ubuntu:ubuntu ${INSTALL_DIR}/run-benchmark.sh

echo ""
echo "============================================="
echo " Setup complete!"
echo " Repo:     ${INSTALL_DIR}/os-benchmark"
echo " wrk2:     $(which wrk2)"
echo " Go:       $(go version)"
echo ""
echo " To run the benchmark:"
echo "   ./run-benchmark.sh <linux-ip> <freebsd-ip>"
echo "============================================="
