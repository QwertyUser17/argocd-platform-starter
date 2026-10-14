// demo-api is the example workload for the apps layer: JSON logs for Fluent Bit,
// /metrics for the Prometheus pod annotations, /healthz and /readyz for the probes.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"
)

// Set at build time: -ldflags "-X main.version=v1.2.3".
var version = "dev"

var (
	requests atomic.Uint64
	ready    atomic.Bool
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	mux := http.NewServeMux()
	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		logger.Info("request", "method", r.Method, "path", r.URL.Path, "remote", r.RemoteAddr)
		fmt.Fprintf(w, "demo-api %s\n", version)
	})
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, r *http.Request) {
		if !ready.Load() {
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("GET /metrics", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		fmt.Fprintf(w, "# HELP demo_api_requests_total Requests served by the root handler.\n")
		fmt.Fprintf(w, "# TYPE demo_api_requests_total counter\n")
		fmt.Fprintf(w, "demo_api_requests_total %d\n", requests.Load())
		fmt.Fprintf(w, "# HELP demo_api_build_info Build version.\n")
		fmt.Fprintf(w, "# TYPE demo_api_build_info gauge\n")
		fmt.Fprintf(w, "demo_api_build_info{version=%q} 1\n", version)
	})

	srv := &http.Server{
		Addr:              ":8080",
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
	defer stop()

	go func() {
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("server failed", "error", err)
			os.Exit(1)
		}
	}()
	ready.Store(true)
	logger.Info("listening", "addr", srv.Addr, "version", version)

	<-ctx.Done()
	// Fail readiness and keep serving briefly, so the Service stops routing here
	// before open connections are closed.
	ready.Store(false)
	time.Sleep(5 * time.Second)

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Error("shutdown failed", "error", err)
	}
	logger.Info("stopped")
}
