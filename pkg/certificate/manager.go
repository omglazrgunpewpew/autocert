package certificate

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"net/http"
	"path"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/acme"
	"golang.org/x/crypto/acme/autocert"

	"github.com/yourusername/autocert/pkg/monitoring"
	"github.com/yourusername/autocert/pkg/storage"
)

// Config holds the configuration for the certificate manager
type Config struct {
	// Domains is a list of domains to obtain certificates for
	Domains []string

	// Email is the email address to use for ACME registration
	Email string

	// CacheDir is the directory to cache certificates
	CacheDir string

	// RenewBefore is the duration before expiry to renew certificates
	RenewBefore time.Duration

	// Store is the storage backend for certificates
	Store storage.Store

	// AcmeConfig contains ACME-specific configuration
	AcmeConfig AcmeConfig

	// Logger for logging operations
	Logger monitoring.Logger

	// Metrics collector
	Metrics *monitoring.MetricsCollector
}

// AcmeConfig holds the configuration for ACME
type AcmeConfig struct {
	// Server is the ACME directory URL
	Server string

	// EABKeyID is the External Account Binding Key ID
	EABKeyID string

	// EABHMACKey is the External Account Binding HMAC Key
	EABHMACKey string
}

// Manager handles certificate acquisition and renewal
type Manager struct {
	config     Config
	acmeClient *acme.Client
	cache      autocert.Cache
	certCache  map[string]*tls.Certificate
	mu         sync.RWMutex
	httpToken  map[string]string
	tokenMu    sync.RWMutex
	validator  *Validator
	logger     monitoring.Logger
	metrics    *monitoring.MetricsCollector
}

// NewManager creates a new certificate manager
func NewManager(config Config) (*Manager, error) {
	if len(config.Domains) == 0 {
		return nil, errors.New("at least one domain must be specified")
	}

	if config.Email == "" {
		return nil, errors.New("email must be specified")
	}

	// Use default ACME server if not specified
	if config.AcmeConfig.Server == "" {
		config.AcmeConfig.Server = acme.LetsEncryptURL
	}

	// Set default renewal period if not specified
	if config.RenewBefore == 0 {
		config.RenewBefore = 30 * 24 * time.Hour // 30 days
	}

	// Set default logger if not provided
	if config.Logger == nil {
		config.Logger = monitoring.NewNopLogger()
	}

	// Set default metrics collector if not provided
	if config.Metrics == nil {
		config.Metrics = monitoring.NewMetricsCollector()
	}

	// Initialize storage if not provided
	if config.Store == nil {
		if config.CacheDir == "" {
			return nil, errors.New("either store or cache directory must be specified")
		}
		fileStore, err := storage.NewFileStore(config.CacheDir)
		if err != nil {
			return nil, fmt.Errorf("failed to create file store: %w", err)
		}
		config.Store = fileStore
	}

	// Create the ACME client
	acmeClient := &acme.Client{
		DirectoryURL: config.AcmeConfig.Server,
	}

	// Create certificate validator
	validator := NewValidator(config.RenewBefore)

	return &Manager{
		config:     config,
		acmeClient: acmeClient,
		cache:      &cacheAdapter{store: config.Store},
		certCache:  make(map[string]*tls.Certificate),
		httpToken:  make(map[string]string),
		validator:  validator,
		logger:     config.Logger,
		metrics:    config.Metrics,
	}, nil
}

// GetCertificate implements the tls.Config.GetCertificate function
func (m *Manager) GetCertificate(hello *tls.ClientHelloInfo) (*tls.Certificate, error) {
	if hello.ServerName == "" {
		return nil, errors.New("missing server name")
	}

	m.logger.Debug("GetCertificate requested", "domain", hello.ServerName)

	// Check the in-memory cache first
	m.mu.RLock()
	cert, ok := m.certCache[hello.ServerName]
	m.mu.RUnlock()

	if ok {
		// Check if the certificate is still valid
		if cert.Leaf != nil && time.Now().Add(m.config.RenewBefore).Before(cert.Leaf.NotAfter) {
			m.logger.Debug("Using cached certificate", "domain", hello.ServerName,
				"expires", cert.Leaf.NotAfter)
			m.metrics.CertificateHit(hello.ServerName)
			return cert, nil
		}
		// Certificate needs renewal
		m.logger.Info("Certificate needs renewal", "domain", hello.ServerName)
	}

	m.metrics.CertificateMiss(hello.ServerName)

	// Get or renew the certificate
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	start := time.Now()
	newCert, err := m.getCertificate(ctx, hello.ServerName)
	if err != nil {
		m.logger.Error("Failed to get certificate", "domain", hello.ServerName, "error", err)
		m.metrics.CertificateError(hello.ServerName, err)
		return nil, err
	}
	m.metrics.CertificateObtained(hello.ServerName, time.Since(start))

	// Cache the certificate
	m.mu.Lock()
	m.certCache[hello.ServerName] = newCert
	m.mu.Unlock()

	// Update expiration metric
	if newCert.Leaf != nil {
		m.metrics.CertificateExpiry(hello.ServerName, newCert.Leaf.NotAfter)
	}

	return newCert, nil
}

// getCertificate fetches or generates a certificate for the given domain
func (m *Manager) getCertificate(ctx context.Context, domain string) (*tls.Certificate, error) {
	// Try to load from storage first
	certData, err := m.cache.Get(ctx, domain)
	if err == nil {
		cert, err := tls.X509KeyPair(certData, certData)
		if err == nil {
			leaf, err := x509.ParseCertificate(cert.Certificate[0])
			if err == nil {
				cert.Leaf = leaf
				// Check if the certificate is valid
				validationErr := m.validator.ValidateCertificate(leaf, domain)
				if validationErr == nil {
					m.logger.Debug("Loaded valid certificate from storage", "domain", domain)
					return &cert, nil
				}
				m.logger.Info("Certificate from storage is invalid", "domain", domain, "reason", validationErr)
			}
		}
	}

	m.logger.Info("Requesting new certificate", "domain", domain)

	// Create a new autocert.Manager for this specific domain
	certManager := &autocert.Manager{
		Cache:      m.cache,
		Prompt:     autocert.AcceptTOS,
		HostPolicy: autocert.HostWhitelist(domain),
		Email:      m.config.Email,
		Client:     m.acmeClient,
	}

	// Request a new certificate
	cert, err := certManager.GetCertificate(&tls.ClientHelloInfo{
		ServerName: domain,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get certificate: %w", err)
	}

	return cert, nil
}

// HTTPHandler returns an http.Handler that handles ACME HTTP challenges
func (m *Manager) HTTPHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasPrefix(r.URL.Path, "/.well-known/acme-challenge/") {
			http.NotFound(w, r)
			return
		}

		token := path.Base(r.URL.Path)
		m.logger.Debug("Received ACME challenge", "token", token, "remote_addr", r.RemoteAddr)

		m.tokenMu.RLock()
		keyAuth, ok := m.httpToken[token]
		m.tokenMu.RUnlock()

		if !ok {
			http.NotFound(w, r)
			return
		}

		w.Write([]byte(keyAuth))
		m.logger.Debug("Served ACME challenge", "token", token)
	})
}

// RenewCertificates checks and renews certificates that are near expiration
func (m *Manager) RenewCertificates(ctx context.Context) error {
	m.logger.Info("Starting certificate renewal check")

	// Get all domains to check
	domains := m.config.Domains

	// Add domains from certificates in storage
	keys, err := m.config.Store.List()
	if err != nil {
		m.logger.Error("Failed to list certificates in storage", "error", err)
		return fmt.Errorf("failed to list certificates: %w", err)
	}

	renewCount := 0
	errorCount := 0

	for _, domain := range domains {
		m.logger.Debug("Checking certificate", "domain", domain)

		// Check if the certificate needs renewal
		needsRenewal, err := m.checkRenewal(ctx, domain)
		if err != nil {
			m.logger.Error("Failed to check renewal", "domain", domain, "error", err)
			errorCount++
			continue
		}

		if !needsRenewal {
			m.logger.Debug("Certificate does not need renewal", "domain", domain)
			continue
		}

		m.logger.Info("Renewing certificate", "domain", domain)

		// Force renewal by removing from cache
		m.mu.Lock()
		delete(m.certCache, domain)
		m.mu.Unlock()

		// Request a new certificate
		start := time.Now()
		_, err = m.getCertificate(ctx, domain)
		if err != nil {
			m.logger.Error("Failed to renew certificate", "domain", domain, "error", err)
			m.metrics.CertificateRenewalError(domain, err)
			errorCount++
			continue
		}

		m.metrics.CertificateRenewed(domain, time.Since(start))
		renewCount++
		m.logger.Info("Certificate renewed successfully", "domain", domain)
	}

	m.logger.Info("Certificate renewal complete",
		"checked", len(domains),
		"renewed", renewCount,
		"errors", errorCount)

	return nil
}

// checkRenewal checks if a certificate needs renewal
func (m *Manager) checkRenewal(ctx context.Context, domain string) (bool, error) {
	// Check the in-memory cache first
	m.mu.RLock()
	cert, ok := m.certCache[domain]
	m.mu.RUnlock()

	if ok && cert.Leaf != nil {
		return m.validator.IsExpiringSoon(cert.Leaf), nil
	}

	// Try to load from storage
	certData, err := m.cache.Get(ctx, domain)
	if err != nil {
		// Certificate not found, so it needs to be obtained
		return true, nil
	}

	cert, err = tls.X509KeyPair(certData, certData)
	if err != nil {
		// Invalid certificate, so it needs to be renewed
		return true, nil
	}

	leaf, err := x509.ParseCertificate(cert.Certificate[0])
	if err != nil {
		return true, nil
	}

	return m.validator.IsExpiringSoon(leaf), nil
}

// ListCertificates returns information about all managed certificates
func (m *Manager) ListCertificates() ([]CertificateInfo, error) {
	keys, err := m.config.Store.List()
	if err != nil {
		return nil, fmt.Errorf("failed to list certificates: %w", err)
	}

	result := make([]CertificateInfo, 0, len(keys))

	for _, key := range keys {
		ctx := context.Background()
		certData, err := m.cache.Get(ctx, key)
		if err != nil {
			continue
		}

		cert, err := tls.X509KeyPair(certData, certData)
		if err != nil {
			continue
		}

		leaf, err := x509.ParseCertificate(cert.Certificate[0])
		if err != nil {
			continue
		}

		expiryDuration, _ := m.validator.GetExpiryInfo(leaf)

		info := CertificateInfo{
			Domain:         key,
			Issuer:         leaf.Issuer.CommonName,
			NotBefore:      leaf.NotBefore,
			NotAfter:       leaf.NotAfter,
			ExpiresIn:      expiryDuration,
			IsExpiringSoon: m.validator.IsExpiringSoon(leaf),
		}

		result = append(result, info)
	}

	return result, nil
}

// CertificateInfo contains information about a certificate
type CertificateInfo struct {
	Domain         string
	Issuer         string
	NotBefore      time.Time
	NotAfter       time.Time
	ExpiresIn      time.Duration
	IsExpiringSoon bool
}

// cacheAdapter adapts storage.Store to autocert.Cache interface
type cacheAdapter struct {
	store storage.Store
}

// Get implements autocert.Cache.Get
func (c *cacheAdapter) Get(ctx context.Context, key string) ([]byte, error) {
	return c.store.Get(key)
}

// Put implements autocert.Cache.Put
func (c *cacheAdapter) Put(ctx context.Context, key string, data []byte) error {
	return c.store.Put(key, data)
}

// Delete implements autocert.Cache.Delete
func (c *cacheAdapter) Delete(ctx context.Context, key string) error {
	return c.store.Delete(key)
}