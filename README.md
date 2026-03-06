# os-benchmark

HTTP server for benchmarking OS-level performance differences between Linux and FreeBSD. Each endpoint isolates a specific kernel/runtime subsystem so results are directly comparable across operating systems.

## Build & Run

```bash
go build -o api main.go
GOMAXPROCS=4 ./api
```

Server starts on `:3000`.

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

## Benchmarking with wrk2

```bash
# On the Linux machine
./bench.sh 192.168.1.10 linux

# On the FreeBSD machine
./bench.sh 192.168.1.20 freebsd
```

The script handles wrk2 installation, warmup, and runs all endpoints across three concurrency profiles (low/mid/high). Results are saved to `results/<os>/`.

### Manual wrk2 commands

If you prefer running wrk2 manually instead of using the script:

```bash
# Install wrk2
git clone https://github.com/giltene/wrk2.git && cd wrk2 && make
# On FreeBSD, use: pkg install gcc gmake git openssl && gmake

# Warmup (run before measurements)
./wrk2-t4 -c100 -d30s -R1000 http://<server-ip>:3000/compute

# Low concurrency
./wrk2-t4 -c50  -d60s -R2000  --latency http://<server-ip>:3000/compute
./wrk2-t4 -c50  -d60s -R2000  --latency http://<server-ip>:3000/cached
./wrk2-t4 -c50  -d60s -R2000  --latency http://<server-ip>:3000/db
./wrk2-t4 -c50  -d60s -R2000  --latency http://<server-ip>:3000/fileio
./wrk2-t4 -c50  -d60s -R2000  --latency http://<server-ip>:3000/concurrent
./wrk2-t4 -c50  -d60s -R2000  --latency http://<server-ip>:3000/mem
./wrk2-t4 -c50  -d60s -R2000  --latency http://<server-ip>:3000/syscall

# Mid concurrency
./wrk2-t8 -c200 -d60s -R5000  --latency http://<server-ip>:3000/compute
./wrk2-t8 -c200 -d60s -R5000  --latency http://<server-ip>:3000/cached
./wrk2-t8 -c200 -d60s -R5000  --latency http://<server-ip>:3000/db
./wrk2-t8 -c200 -d60s -R5000  --latency http://<server-ip>:3000/fileio
./wrk2-t8 -c200 -d60s -R5000  --latency http://<server-ip>:3000/concurrent
./wrk2-t8 -c200 -d60s -R5000  --latency http://<server-ip>:3000/mem
./wrk2-t8 -c200 -d60s -R5000  --latency http://<server-ip>:3000/syscall

# High concurrency
./wrk2-t8 -c500 -d60s -R10000 --latency http://<server-ip>:3000/compute
./wrk2-t8 -c500 -d60s -R10000 --latency http://<server-ip>:3000/cached
./wrk2-t8 -c500 -d60s -R10000 --latency http://<server-ip>:3000/db
./wrk2-t8 -c500 -d60s -R10000 --latency http://<server-ip>:3000/fileio
./wrk2-t8 -c500 -d60s -R10000 --latency http://<server-ip>:3000/concurrent
./wrk2-t8 -c500 -d60s -R10000 --latency http://<server-ip>:3000/mem
./wrk2-t8 -c500 -d60s -R10000 --latency http://<server-ip>:3000/syscall
```

### Concurrency profiles

| Profile | Threads | Connections | Target rate |
|---------|---------|-------------|-------------|
| low | 4 | 50 | 2,000 req/s |
| mid | 8 | 200 | 5,000 req/s |
| high | 8 | 500 | 10,000 req/s |

## Project structure

```
main.go     — benchmark server (all endpoints)
bench.sh    — wrk2 test runner script
results/    — benchmark output (created by bench.sh)
```
