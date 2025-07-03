package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/yourusername/autocert/internal/api"
	"github.com/yourusername/autocert/internal/config"
	"github.com/yourusername/autocert/pkg/certificate"
	"github.com/yourusername/autocert/pkg/monitoring"
	"github.com/yourusername/autocert/pkg/storage"
)

var (
	configFile = flag.String("config", "", "Path to configuration file")
	version    = "dev"
)

func main() {
	flag.Parse()

	fmt.Printf("Autocert %s starting...\n", version)

	// Load configuration
	cfg, err := config.Load(*configFile)
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// Setup logging
	logger := monitoring.NewLogger(cfg.Logging)
	logger.Info("Autocert started", "version", version)

	// Initialize storage
	store, err := storage.NewStore(cfg.Storage)
	if err != nil {
		logger.Error("Failed to initialize storage", "error", err)
		os.Exit(1)
	}

	// Initialize metrics collector
	metrics := monitoring.NewMetricsCollector()

	// Initialize certificate manager
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
		logger.Error("Failed to initialize certificate manager", "error", err)
		os.Exit(1)
	}

	// Start HTTP server for ACME challenges
	go func() {
		logger.Info("Starting HTTP server for ACME challenges", "address", ":80")
		if err := http.ListenAndServe(":80", manager.HTTPHandler()); err != nil {
			logger.Error("HTTP server error", "error", err)
		}
	}()

	// Start metrics server
	go func() {
		metricsAddr := cfg.Monitoring.MetricsAddress
		if metricsAddr == "" {
			metricsAddr = ":9091"
		}
		logger.Info("Starting metrics server", "address", metricsAddr)
		http.Handle("/metrics", metrics.Handler())
		if err := http.ListenAndServe(metricsAddr, nil); err != nil {
			logger.Error("Metrics server error", "error", err)
		}
	}()

	// Set up API server if enabled
	if cfg.API.Enabled {
		apiServer := api.NewServer(api.Config{
			Address:  cfg.API.Address,
			TLS:      cfg.API.TLS,
			Manager:  manager,
			Store:    store,
			Logger:   logger,
			Metrics:  metrics,
		})
		go apiServer.Start()
	}

	// Schedule certificate renewal check
	ticker := time.NewTicker(24 * time.Hour)
	go func() {
		for {
			select {
			case <-ticker.C:
				ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
				if err := manager.RenewCertificates(ctx); err != nil {
					logger.Error("Certificate renewal failed", "error", err)
				}
				cancel()
			}
		}
	}()

	// Wait for signals
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)

	sig := <-sigCh
	logger.Info("Received signal, shutting down", "signal", sig)

	// Trigger certificate renewal for certificates nearing expiration
	shutdownCtx, shutdownCancel := context.WithTimeout(ctx, 30*time.Second)
	defer shutdownCancel()

	if err := manager.RenewCertificates(shutdownCtx); err != nil {
		logger.Error("Error during final certificate renewal", "error", err)
	}

	logger.Info("Shutdown complete")
}