package main

import (
	"crypto/rand"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"sync/atomic"
	"time"
)

var cachedPayload []byte

func main() {
	cachedPayload, _ = json.Marshal(map[string]string{"status": "ok", "source": "cache"})

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"name":    "os-benchmark",
			"message": "HTTP server for benchmarking OS-level performance: CPU scheduling, memory allocation, and I/O paths.",
			"endpoints": "/compute, /cached, /db, /fileio, /concurrent, /mem, /syscall, /health",
		})
	})

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
	})

	http.HandleFunc("/compute", func(w http.ResponseWriter, r *http.Request) {
		// Pure compute — isolates scheduler behavior
		n := 0
		for i := 0; i < 10000; i++ {
			n += i
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]int{"result": n})
	})

	http.HandleFunc("/cached", func(w http.ResponseWriter, r *http.Request) {
		// Pre-allocated response — tests allocator + hot path
		w.Header().Set("Content-Type", "application/json")
		w.Write(cachedPayload)
	})

	http.HandleFunc("/db", func(w http.ResponseWriter, r *http.Request) {
		// Simulated DB query — tests I/O path via sleep (epoll/kqueue + Go netpoller)
		time.Sleep(2 * time.Millisecond)
		results := []map[string]interface{}{
			{"id": 1, "name": "alice"},
			{"id": 2, "name": "bob"},
			{"id": 3, "name": "charlie"},
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(results)
	})

	http.HandleFunc("/fileio", func(w http.ResponseWriter, r *http.Request) {
		// File I/O — tests VFS, page cache, and disk write/read/delete syscalls
		tmpDir := os.TempDir()
		path := filepath.Join(tmpDir, fmt.Sprintf("bench_%d.tmp", time.Now().UnixNano()))

		data := make([]byte, 4096)
		rand.Read(data)

		if err := os.WriteFile(path, data, 0644); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}

		readBack, err := os.ReadFile(path)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		os.Remove(path)

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"wrote": len(data),
			"read":  len(readBack),
		})
	})

	http.HandleFunc("/concurrent", func(w http.ResponseWriter, r *http.Request) {
		// High concurrency — spawns goroutines that each do a small syscall (time.Now)
		// Stresses the scheduler and OS thread management (epoll/kqueue wake-ups)
		const numGoroutines = 500
		var wg sync.WaitGroup
		var ops atomic.Int64

		wg.Add(numGoroutines)
		for i := 0; i < numGoroutines; i++ {
			go func() {
				defer wg.Done()
				time.Now()
				ops.Add(1)
			}()
		}
		wg.Wait()

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"goroutines": numGoroutines,
			"completed":  ops.Load(),
		})
	})

	http.HandleFunc("/mem", func(w http.ResponseWriter, r *http.Request) {
		// Memory pressure — allocate and release slices to stress mmap/brk and GC
		const rounds = 100
		const size = 1 << 20 // 1 MiB per round
		total := 0

		for i := 0; i < rounds; i++ {
			buf := make([]byte, size)
			buf[0] = byte(i)
			buf[size-1] = byte(i)
			total += len(buf)
		}
		runtime.GC()

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"rounds":     rounds,
			"bytes_each": size,
			"total":      total,
		})
	})

	http.HandleFunc("/syscall", func(w http.ResponseWriter, r *http.Request) {
		// Syscall-heavy — rapid getpid-equivalent calls via os.Getpid + cwd lookups
		const iterations = 1000
		for i := 0; i < iterations; i++ {
			os.Getpid()
			os.Getwd()
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"iterations":     iterations,
			"syscalls_aprox": iterations * 2,
		})
	})

	log.Println("Starting os-benchmark server on :3000")
	log.Fatal(http.ListenAndServe(":3000", nil))
}
