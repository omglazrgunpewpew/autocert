package main

import (
	"context"
	"flag"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/yourusername/autocert/internal/config"
	"github.com/yourusername/autocert/pkg/certificate"
	"github.com/yourusername/autocert/pkg/monitoring"
	"github.com/yourusername/autocert/pkg/storage"
)

var (
	configFile = flag.String("config", "", "Path to configuration file")
	domains    = flag.String("domains", "", "Comma-separated list of domains")
	email      = flag.String("email", "", "Email address for ACME registration")
	cacheDir   = flag.String("cache-dir", "/var/lib/autocert/cache", "Directory to cache certificates")
)

func main() {
	flag.Parse()

	// Load configuration from file or flags
	var cfg *config.Config
	var err error

	if *configFile != "" {
		cfg, err = config.Load(*configFile)
		if err != nil {
			log.Fatalf("Failed to load configuration: %v", err)
		}
	} else {
		// Create configuration from flags
		if *domains == "" || *email == "" {
			log.Fatalf("Domains and email are required")
		}

		cfg = &config.Config{
			Domains:     parseCommaSeparated(*domains),
			Email:       *email,
			CacheDir:    *cacheDir,
			RenewBefore: 30 * 24 * time.Hour, // 30 days
			Storage: storage.StoreConfig{
				Type: "file",
				Path: *cacheDir,
			},
		}
	}

	// Create logger
	logger := monitoring.NewLogger(cfg.Logging)

	// Create storage backend
	store, err := storage.NewStore(cfg.Storage)
	if err != nil {
		logger.Error("Failed to create storage", "error", err)
		os.Exit(1)
	}

	// Create metrics collector
	metrics := monitoring.NewMetricsCollector()

	// Create certificate manager
	manager, err := certificate.NewManager(certificate.Config{
		Domains:     cfg.Domains,
		Email:       cfg.Email,
		CacheDir:    cfg.CacheDir,
		RenewBefore: cfg.RenewBefore,
		Store:       store,
		AcmeConfig:  cfg.ACME,
		Logger:      logger,
		Metrics:     metrics,
	})
	if err != nil {
		logger.Error("Failed to create certificate manager", "error", err)
		os.Exit(1)
	}

	// Create your application server
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain")
		w.Write([]byte("Hello, TLS!"))
	})

	// Start HTTP server for ACME challenges
	go func() {
		logger.Info("Starting HTTP server for ACME challenges", "address", ":80")
		if err := http.ListenAndServe(":80", manager.HTTPHandler()); err != nil {
			logger.Error("HTTP server error", "error", err)
		}
	}()

	// Create HTTPS server with automatic certificate management
	server := &http.Server{
		Addr: ":443",
		TLSConfig: &tls.Config{
			GetCertificate: manager.GetCertificate,
		},
		Handler: mux,
	}

	// Start HTTPS server
	go func() {
		logger.Info("Starting HTTPS server", "address", ":443")
		if err := server.ListenAndServeTLS("", ""); err != nil && err != http.ErrServerClosed {
			logger.Error("HTTPS server error", "error", err)
			os.Exit(1)
		}
	}()

	// Wait for signals
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)
	<-sigCh

	// Graceful shutdown
	logger.Info("Shutting down servers...")

	// Create shutdown context with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Shutdown HTTPS server
	if err := server.Shutdown(ctx); err != nil {
		logger.Error("Server shutdown error", "error", err)
	}

	logger.Info("Shutdown complete")
}

// parseCommaSeparated parses a comma-separated list of values
func parseCommaSeparated(s string) []string {
	if s == "" {
		return nil
	}
	var result []string
	for _, part := range strings.Split(s, ",") {
		if trimmed := strings.TrimSpace(part); trimmed != "" {
			result = append(result, trimmed)
		}
	}
	return result
}