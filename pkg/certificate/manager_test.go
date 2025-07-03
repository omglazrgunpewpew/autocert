package certificate

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/yourusername/autocert/pkg/monitoring"
	"github.com/yourusername/autocert/pkg/storage"
)

func TestNewManager(t *testing.T) {
	tests := []struct {
		name        string
		config      Config
		expectError bool
	}{
		{
			name: "Valid configuration",
			config: Config{
				Domains: []string{"example.com"},
				Email:   "admin@example.com",
				CacheDir: "/tmp/autocert-test",
			},
			expectError: false,
		},
		{
			name: "No domains",
			config: Config{
				Email:   "admin@example.com",
				CacheDir: "/tmp/autocert-test",
			},
			expectError: true,
		},
		{
			name: "No email",
			config: Config{
				Domains: []string{"example.com"},
				CacheDir: "/tmp/autocert-test",
			},
			expectError: true,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, err := NewManager(test.config)
			if test.expectError && err == nil {
				t.Errorf("Expected error but got nil")
			}
			if !test.expectError && err != nil {
				t.Errorf("Expected no error but got: %v", err)
			}
		})
	}
}

func TestHTTPHandler(t *testing.T) {
	// Create test manager
	store := storage.NewMemoryStore()
	manager, err := NewManager(Config{
		Domains:  []string{"example.com"},
		Email:    "admin@example.com",
		Store:    store,
		Logger:   monitoring.NewNopLogger(),
		Metrics:  monitoring.NewMetricsCollector(),
	})
	if err != nil {
		t.Fatalf("Failed to create manager: %v", err)
	}

	// Add a test token
	manager.tokenMu.Lock()
	manager.httpToken["test-token"] = "test-key-authorization"
	manager.tokenMu.Unlock()

	// Test valid challenge
	req := httptest.NewRequest("GET", "/.well-known/acme-challenge/test-token", nil)
	w := httptest.NewRecorder()
	
	handler := manager.HTTPHandler()
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status code %d but got %d", http.StatusOK, w.Code)
	}
	if w.Body.String() != "test-key-authorization" {
		t.Errorf("Expected response body %q but got %q", "test-key-authorization", w.Body.String())
	}

	// Test invalid challenge
	req = httptest.NewRequest("GET", "/.well-known/acme-challenge/nonexistent-token", nil)
	w = httptest.NewRecorder()
	
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("Expected status code %d but got %d", http.StatusNotFound, w.Code)
	}

	// Test non-challenge URL
	req = httptest.NewRequest("GET", "/index.html", nil)
	w = httptest.NewRecorder()
	
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("Expected status code %d but got %d", http.StatusNotFound, w.Code)
	}
}

// Mock certificate for testing
func createMockCertificate(domain string, validFor time.Duration) (*tls.Certificate, error) {
	// In a real test, you'd generate an actual certificate
	// This is a simplified mock
	now := time.Now()
	template := &x509.Certificate{
		SerialNumber: nil, // Would be a real serial number
		Subject: pkix.Name{
			CommonName: domain,
		},
		NotBefore: now,
		NotAfter:  now.Add(validFor),
		DNSNames:  []string{domain},
	}
	
	// This would actually create a certificate
	cert := &tls.Certificate{
		Leaf: template,
	}
	
	return cert, nil
}

// Additional tests would include:
// - TestGetCertificate
// - TestCertificateRenewal
// - TestListCertificates
// etc.