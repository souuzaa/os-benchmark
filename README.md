# os-benchmark

HTTP server for benchmarking OS-level performance differences between Linux and FreeBSD. Each endpoint isolates a specific kernel/runtime subsystem so results are directly comparable across operating systems.

## Architecture

Three machines (e.g., AWS c6i instances):

- **Linux server** — runs the Go API on Amazon Linux 2023
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
| `scripts/setup-linux.sh` | Installs Go, PostgreSQL, kernel tuning on Amazon Linux 2023 |
| `scripts/setup-freebsd.sh` | Installs Go, PostgreSQL, sysctl tuning on FreeBSD 14.1 |
| `scripts/setup-loadgen.sh` | Installs wrk2, kernel tuning for high connection counts |
| `scripts/bench.sh` | Runs wrk2 benchmarks across all endpoints and profiles |
| `scripts/compare.sh` | Side-by-side comparison of Linux vs FreeBSD results |

## Project structure

```
main.go                    — benchmark server (all endpoints)
scripts/
  setup-linux.sh           — Linux API server setup (Amazon Linux 2023)
  setup-freebsd.sh         — FreeBSD API server setup (FreeBSD 14.1)
  setup-loadgen.sh         — load generator machine setup
  bench.sh                 — wrk2 test runner script
  compare.sh               — compare Linux vs FreeBSD results
results/                   — benchmark output (created by bench.sh)
```
