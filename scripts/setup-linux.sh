#!/bin/bash
# =============================================================================
# setup-linux.sh — Linux API Server (c6i.xlarge / Ubuntu 24.04 LTS)
# Usage: chmod +x setup-linux.sh && sudo ./setup-linux.sh
# =============================================================================

set -euo pipefail

REPO_URL="https://github.com/souuzaa/os-benchmark"
GO_VERSION="1.22.3"
GO_TARBALL="go${GO_VERSION}.linux-amd64.tar.gz"
GO_URL="https://go.dev/dl/${GO_TARBALL}"
INSTALL_DIR="/home/ubuntu"

echo "============================================="
echo " OS Benchmark — Linux API Server Setup"
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
apt-get install -y -qq git wget curl gcc make tar linux-tools-common linux-tools-$(uname -r) 2>/dev/null || \
  apt-get install -y -qq git wget curl gcc make tar linux-tools-common

# -----------------------------------------------------------------------------
# 3. Go installation
# -----------------------------------------------------------------------------
echo "[3/6] Installing Go ${GO_VERSION}..."
wget -q "${GO_URL}" -O "/tmp/${GO_TARBALL}"
rm -rf /usr/local/go
tar -C /usr/local -xzf "/tmp/${GO_TARBALL}"
rm "/tmp/${GO_TARBALL}"

# Add Go to PATH system-wide
cat > /etc/profile.d/go.sh << 'EOF'
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
EOF

export PATH=$PATH:/usr/local/go/bin
echo "Go version: $(go version)"

# -----------------------------------------------------------------------------
# 4. Kernel tuning
# -----------------------------------------------------------------------------
echo "[4/6] Tuning kernel parameters..."
cat > /etc/sysctl.d/99-benchmark.conf << 'EOF'
net.core.somaxconn=65535
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=15
net.core.netdev_max_backlog=65535
net.ipv4.tcp_max_syn_backlog=65535
vm.swappiness=1
EOF
sysctl --system --quiet

# CPU performance mode
cpupower frequency-set -g performance 2>/dev/null || echo "Warning: cpupower not available, skipping"

# Increase open file limits
cat >> /etc/security/limits.conf << 'EOF'
ubuntu soft nofile 100000
ubuntu hard nofile 100000
EOF

# -----------------------------------------------------------------------------
# 5. Clone repository
# -----------------------------------------------------------------------------
echo "[5/6] Cloning repository..."
sudo -u ubuntu bash << EOF
cd ${INSTALL_DIR}
git clone ${REPO_URL} os-benchmark
cd os-benchmark
export PATH=\$PATH:/usr/local/go/bin
go mod tidy 2>/dev/null || true
go build -o api main.go
echo "Repo cloned and API binary built."
EOF

# -----------------------------------------------------------------------------
# 6. Verify io_uring support
# -----------------------------------------------------------------------------
echo "[6/6] Verifying io_uring support..."
if grep -qs "CONFIG_IO_URING=y" /boot/config-$(uname -r) 2>/dev/null; then
  echo "io_uring: ENABLED"
elif zcat /proc/config.gz 2>/dev/null | grep -q "CONFIG_IO_URING=y"; then
  echo "io_uring: ENABLED"
else
  uname -r | grep -qE '^(5\.[1-9]|6\.)' && echo "io_uring: likely available (kernel $(uname -r))" || echo "io_uring: not confirmed — kernel $(uname -r)"
fi

echo ""
echo "============================================="
echo " Setup complete!"
echo " Repo:     ${INSTALL_DIR}/os-benchmark"
echo " Go:       $(go version)"
echo " Kernel:   $(uname -r)"
echo "============================================="
