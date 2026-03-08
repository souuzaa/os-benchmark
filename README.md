# os-benchmark

HTTP server for benchmarking OS-level performance differences between Linux and FreeBSD. Each endpoint isolates a specific kernel/runtime subsystem so results are directly comparable across operating systems.

## Architecture

Three machines (e.g., AWS c6i instances):

- **Linux server** — runs the Go API on Ubuntu 24.04 LTS
- **FreeBSD server** — runs the Go API on FreeBSD 14.1
- **Load generator** — runs wrk2 against both servers

## Quick start

### 1. Provision machines

```bash
# On the Linux server
sudo ./scripts/setup-linux.sh

# On the FreeBSD server
sudo ./scripts/setup-freebsd.sh

# On the load generator
sudo ./scripts/setup-loadgen.sh
```

### 2. Start the API server (on both Linux and FreeBSD)

```bash
go build -o api main.go
GOMAXPROCS=4 ./api
```

Server starts on `:3000`.

### 3. Run benchmarks (from load generator or locally)

```bash
# Benchmark Linux
./scripts/bench.sh <linux-ip> linux

# Benchmark FreeBSD
./scripts/bench.sh <freebsd-ip> freebsd

# Compare results
./scripts/compare.sh
```

The bench script handles wrk2 installation, warmup, and runs all endpoints across three concurrency profiles (low/mid/high). Results are saved to `results/<os>/`.

## Endpoints

| Endpoint | What it tests | OS subsystem |
|-----------|--------------|--------------|
| `/` | API info and endpoint listing | — |
| `/health` | Health check | — |
| `/compute` | Tight loop (sum 0..9999) | CPU scheduler |
| `/cached` | Pre-marshalled JSON response | Network stack, allocator hot path |
| `/db` | Simulated query (2ms sleep) | Timer resolution, netpoller (epoll/kqueue) |
| `/fileio` | Write/read/delete 4KB temp file | VFS, page cache, disk I/O syscalls |
| `/concurrent` | Spawn 500 goroutines with syscalls | Scheduler, thread management, wake-ups |
| `/mem` | Allocate 100x 1MiB slices + GC | mmap/brk, memory reclamation |
| `/syscall` | 1000x getpid + getwd calls | Raw syscall transition overhead |

## Concurrency profiles

| Profile | Threads | Connections | Target rate |
|---------|---------|-------------|-------------|
| low | 4 | 50 | 2,000 req/s |
| mid | 8 | 200 | 5,000 req/s |
| high | 8 | 500 | 10,000 req/s |

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/setup-linux.sh` | Installs Go, kernel tuning on Ubuntu 24.04 LTS |
| `scripts/setup-freebsd.sh` | Installs Go, sysctl tuning on FreeBSD 14.1 |
| `scripts/setup-loadgen.sh` | Installs wrk2, kernel tuning for high connection counts |
| `scripts/bench.sh` | Runs wrk2 benchmarks across all endpoints and profiles |
| `scripts/compare.sh` | Side-by-side comparison of Linux vs FreeBSD results |

## Results (AWS c6i.xlarge)

Tested on AWS c6i.xlarge instances (4 vCPU, 8 GiB RAM). All values from wrk2 with fixed target rates.

### Low concurrency (4 threads, 50 connections, 2,000 req/s)

| Endpoint | Metric | Linux | FreeBSD | Diff |
|----------|--------|------:|--------:|-----:|
| compute | Avg Lat | 870.00us | 930.00us | +6.9% |
| | P99 | 1.92ms | 1.85ms | -3.6% |
| | Req/sec | 1999.44 | 1999.42 | -0.0% |
| cached | Avg Lat | 846.78us | 930.00us | +9.8% |
| | P99 | 1.92ms | 1.92ms | +0.0% |
| | Req/sec | 1999.42 | 1999.44 | +0.0% |
| db | Avg Lat | 2.93ms | 3.00ms | +2.4% |
| | P99 | 3.99ms | 4.02ms | +0.8% |
| | Req/sec | 1999.32 | 1999.35 | +0.0% |
| fileio | Avg Lat | 880.00us | 1.00ms | +13.6% |
| | P99 | 1.70ms | 1.98ms | +16.5% |
| | Req/sec | 1999.41 | 1999.42 | +0.0% |
| concurrent | Avg Lat | 1.05ms | 1.20ms | +14.3% |
| | P99 | 2.16ms | 2.36ms | +9.3% |
| | Req/sec | 1999.42 | 1999.42 | +0.0% |
| mem | Avg Lat | 33.11s | 31.63s | -4.5% |
| | P99 | 55.80s | 54.60s | -2.2% |
| | Req/sec | 114.84 | 170.34 | +48.3% |
| syscall | Avg Lat | 16.29s | 8.01s | -50.8% |
| | P99 | 28.33s | 14.25s | -49.7% |
| | Req/sec | 1068.20 | 1542.03 | +44.4% |

### Mid concurrency (8 threads, 200 connections, 5,000 req/s)

| Endpoint | Metric | Linux | FreeBSD | Diff |
|----------|--------|------:|--------:|-----:|
| compute | Avg Lat | 794.74us | 870.00us | +9.5% |
| | P99 | 1.84ms | 1.88ms | +2.2% |
| | Req/sec | 4986.53 | 4996.43 | +0.2% |
| cached | Avg Lat | 766.99us | 827.07us | +7.8% |
| | P99 | 1.80ms | 1.83ms | +1.7% |
| | Req/sec | 4986.58 | 4996.59 | +0.2% |
| db | Avg Lat | 3.10ms | 3.00ms | -3.2% |
| | P99 | 4.15ms | 3.98ms | -4.1% |
| | Req/sec | 4996.29 | 4996.31 | +0.0% |
| fileio | Avg Lat | 870.00us | 1.06ms | +21.8% |
| | P99 | 1.88ms | 2.46ms | +30.9% |
| | Req/sec | 4996.45 | 4986.39 | -0.2% |
| concurrent | Avg Lat | 1.85ms | 2.24ms | +21.1% |
| | P99 | 5.01ms | 5.11ms | +2.0% |
| | Req/sec | 4996.21 | 4996.14 | -0.0% |
| mem | Avg Lat | 34.06s | 33.65s | -1.2% |
| | P99 | 58.20s | 57.00s | -2.1% |
| | Req/sec | 99.67 | 192.32 | +93.0% |
| syscall | Avg Lat | 27.00s | 22.63s | -16.2% |
| | P99 | 46.10s | 38.86s | -15.7% |
| | Req/sec | 1140.78 | 1753.41 | +53.7% |

### High concurrency (8 threads, 500 connections, 10,000 req/s)

| Endpoint | Metric | Linux | FreeBSD | Diff |
|----------|--------|------:|--------:|-----:|
| compute | Avg Lat | 930.00us | 930.00us | +0.0% |
| | P99 | 2.02ms | 1.89ms | -6.4% |
| | Req/sec | 9939.30 | 9978.46 | +0.4% |
| cached | Avg Lat | 860.00us | 1.00ms | +16.3% |
| | P99 | 1.84ms | 2.18ms | +18.5% |
| | Req/sec | 9956.84 | 9939.28 | -0.2% |
| db | Avg Lat | 3.20ms | 3.01ms | -5.9% |
| | P99 | 4.17ms | 4.03ms | -3.4% |
| | Req/sec | 9977.74 | 9978.18 | +0.0% |
| fileio | Avg Lat | 960.00us | 6.14ms | +539.6% |
| | P99 | 2.01ms | 69.69ms | +3367.2% |
| | Req/sec | 9978.23 | 9952.00 | -0.3% |
| concurrent | Avg Lat | 12.21s | 12.19s | -0.2% |
| | P99 | 21.66s | 20.41s | -5.8% |
| | Req/sec | 6491.05 | 6536.20 | +0.7% |
| mem | Avg Lat | 34.44s | 34.38s | -0.2% |
| | P99 | 58.20s | 58.20s | +0.0% |
| | Req/sec | 141.64 | 172.30 | +21.6% |
| syscall | Avg Lat | 30.95s | 28.68s | -7.3% |
| | P99 | 52.80s | 49.02s | -7.2% |
| | Req/sec | 1124.15 | 1739.40 | +54.7% |

### Summary

Based on average latency across all 21 test combinations:

- **Linux wins:** 11/21
- **FreeBSD wins:** 7/21
- **Ties (<1%):** 3/21

Linux has lower latency in the majority of tests. FreeBSD excels at raw syscall throughput (+44–55% higher req/sec) and memory allocation throughput (+22–93% higher req/sec). Linux dominates file I/O and concurrent workloads, especially under high connection counts.

## Project structure

```
main.go                    — benchmark server (all endpoints)
scripts/
  setup-linux.sh           — Linux API server setup (Ubuntu 24.04 LTS)
  setup-freebsd.sh         — FreeBSD API server setup (FreeBSD 14.1)
  setup-loadgen.sh         — load generator machine setup
  bench.sh                 — wrk2 test runner script
  compare.sh               — compare Linux vs FreeBSD results
results/                   — benchmark output (created by bench.sh)
```
