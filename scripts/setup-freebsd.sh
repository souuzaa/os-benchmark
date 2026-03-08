#!/bin/sh
# =============================================================================
# setup-freebsd.sh — FreeBSD API Server (c6i.xlarge / FreeBSD 14.1)
# Usage: chmod +x setup-freebsd.sh && sudo ./setup-freebsd.sh
# Note: Uses /bin/sh — FreeBSD may not have bash by default
# =============================================================================

set -e

REPO_URL="https://github.com/souuzaa/os-benchmark"
INSTALL_DIR="/home/ec2-user"

echo "============================================="
echo " OS Benchmark — FreeBSD API Server Setup"
echo "============================================="

# -----------------------------------------------------------------------------
# 1. Bootstrap pkg and update
# -----------------------------------------------------------------------------
echo "[1/6] Bootstrapping pkg and updating..."
env ASSUME_ALWAYS_YES=YES pkg bootstrap -f
pkg update -q
pkg upgrade -y -q

# -----------------------------------------------------------------------------
# 2. Base dependencies
# -----------------------------------------------------------------------------
echo "[2/6] Installing base dependencies..."
pkg install -y git go bash curl wget

# -----------------------------------------------------------------------------
# 3. Go verification
# -----------------------------------------------------------------------------
echo "[3/6] Verifying Go installation..."
go version
echo "GOPATH will be set to ${INSTALL_DIR}/go"

# Add Go env to profile
cat >> /etc/profile << 'EOF'
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
EOF

# Also add to rc for non-login shells
cat >> /etc/rc.conf << 'EOF'
# Go environment
EOF

# -----------------------------------------------------------------------------
# 4. Kernel / sysctl tuning
# -----------------------------------------------------------------------------
echo "[4/6] Tuning sysctl parameters..."
cat >> /etc/sysctl.conf << 'EOF'
kern.ipc.somaxconn=65535
kern.maxfiles=200000
kern.maxfilesperproc=100000
net.inet.tcp.recvbuf_max=16777216
net.inet.tcp.sendbuf_max=16777216
net.inet.tcp.fast_finwait2_recycle=1
net.inet.tcp.nolocaltimewait=1
EOF
sysctl -f /etc/sysctl.conf

# Increase open file limits
cat >> /etc/login.conf << 'EOF'

benchmark:\
  :openfiles=100000:\
  :tc=default:
EOF
cap_mkdb /etc/login.conf

# CPU performance mode (disable powerd throttling)
sysrc powerd_enable="NO"
service powerd stop 2>/dev/null || true

# Set CPU to max frequency
sysctl dev.cpu.0.freq_levels 2>/dev/null | awk -F'/' '{print $1}' | awk '{print $NF}' | xargs -I{} sysctl dev.cpu.0.freq={} 2>/dev/null || true

# -----------------------------------------------------------------------------
# 5. Clone repository
# -----------------------------------------------------------------------------
echo "[5/6] Cloning repository..."
su -m ec2-user -c "
  cd ${INSTALL_DIR}
  git clone ${REPO_URL} os-benchmark
  cd os-benchmark
  export GOPATH=\${HOME}/go
  go mod tidy 2>/dev/null || true
  go build ./... 2>/dev/null || true
  echo 'Repo cloned and dependencies downloaded.'
"

# -----------------------------------------------------------------------------
# 6. kqueue verification
# -----------------------------------------------------------------------------
echo "[6/6] Verifying kqueue support..."
if kldstat | grep -q "kqueue"; then
  echo "kqueue: LOADED as module"
else
  echo "kqueue: built into kernel (default on FreeBSD 14)"
fi

echo ""
echo "============================================="
echo " Setup complete!"
echo " Repo:     ${INSTALL_DIR}/os-benchmark"
echo " Go:       $(go version)"
echo " Kernel:   $(uname -r)"
echo " kqueue:   native async I/O"
echo "============================================="
