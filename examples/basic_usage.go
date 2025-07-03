package main

import (
	"crypto/tls"
	"log"
	"net/http"
	"time"

	"github.com/yourusername/autocert/pkg/certificate"
	"github.com/yourusername/autocert/pkg/storage"
)

func main() {
	// Create a memory storage backend (use file storage for production)
	store := storage.NewMemoryStore()

	// Create certificate manager
	manager, err := certificate.NewManager(certificate.Config{
		Domains:     []string{"example.com", "www.example.com"},
		Email:       "admin@example.com",
		RenewBefore: 30 * 24 * time.Hour, // 30 days
		Store:       store,
	})
	if err != nil {
		log.Fatalf("Failed to create certificate manager: %v", err)
	}

	// Create HTTP server for ACME challenges
	go func() {
		log.Printf("Starting HTTP server for ACME challenges on :80")
		if err := http.ListenAndServe(":80", manager.HTTPHandler()); err != nil {
			log.Printf("HTTP server error: %v", err)
		}
	}()

	// Create HTTPS server with automatic certificate management
	server := &http.Server{
		Addr: ":443",
		TLSConfig: &tls.Config{
			GetCertificate: manager.GetCertificate,
		},
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "text/plain")
			w.Write([]byte("Hello, TLS!"))
		}),
	}

	// Start HTTPS server
	log.Printf("Starting HTTPS server on :443")
	if err := server.ListenAndServeTLS("", ""); err != nil {
		log.Fatalf("HTTPS server error: %v", err)
	}
}