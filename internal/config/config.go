package config

import (
	"errors"
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/yourusername/autocert/pkg/storage"
	"gopkg.in/yaml.v3"
)

// Config holds the application configuration
type Config struct {
	// Domains is a list of domains to obtain certificates for
	Domains []string `json:"domains" yaml:"domains"`

	// Email is the email address to use for ACME registration
	Email string `json:"email" yaml:"email"`

	// CacheDir is the directory to cache certificates
	CacheDir string `json:"cache_dir" yaml:"cache_dir"`

	// RenewBefore is the duration before expiry to renew certificates
	RenewBefore time.Duration `json:"renew_before" yaml:"renew_before"`

	// Storage configuration
	Storage storage.StoreConfig `json:"storage" yaml:"storage"`

	// ACME contains ACME-specific configuration
	ACME AcmeConfig `json:"acme" yaml:"acme"`

	// API contains API server configuration
	API APIConfig `json:"api" yaml:"api"`
}

// AcmeConfig holds the configuration for ACME
type AcmeConfig struct {
	// Server is the ACME directory URL
	Server string `json:"server" yaml:"server"`

	// EAB contains External Account Binding configuration
	EAB EABConfig `json:"eab" yaml:"eab"`
}

// EABConfig contains External Account Binding configuration
type EABConfig struct {
	// KID is the External Account Binding Key ID
	KID string `json:"kid" yaml:"kid"`

	// HMACKey is the External Account Binding HMAC Key
	HMACKey string `json:"hmac_key" yaml:"hmac_key"`
}

// APIConfig holds configuration for the API server
type APIConfig struct {
	// Enabled indicates if the API server should be started
	Enabled bool `json:"enabled" yaml:"enabled"`

	// Address is the address to bind the API server to
	Address string `json:"address" yaml:"address"`

	// TLS configuration for the API server
	TLS APITLSConfig `json:"tls" yaml:"tls"`
}

// APITLSConfig holds TLS configuration for the API server
type APITLSConfig struct {
	// Enabled indicates if TLS should be enabled for the API
	Enabled bool `json:"enabled" yaml:"enabled"`

	// CertFile is the path to the certificate file
	CertFile string `json:"cert_file" yaml:"cert_file"`

	// KeyFile is the path to the key file
	KeyFile string `json:"key_file" yaml:"key_file"`
}

// Load loads the configuration from a file and environment variables
func Load(configFile string) (*Config, error) {
	config := &Config{
		ACME: AcmeConfig{
			Server: "https://acme-v02.api.letsencrypt.org/directory",
		},
		API: APIConfig{
			Address: ":8443",
		},
		RenewBefore: 30 * 24 * time.Hour, // 30 days
	}

	// Load from file if specified
	if configFile != "" {
		if err := loadFromFile(configFile, config); err != nil {
			return nil, err
		}
	}

	// Override with environment variables
	if err := loadFromEnv(config); err != nil {
		return nil, err
	}

	// Validate the configuration
	if err := validateConfig(config); err != nil {
		return nil, err
	}

	return config, nil
}

// loadFromFile loads configuration from a YAML file
func loadFromFile(file string, config *Config) error {
	data, err := ioutil.ReadFile(file)
	if err != nil {
		return fmt.Errorf("failed to read config file: %w", err)
	}

	if err := yaml.Unmarshal(data, config); err != nil {
		return fmt.Errorf("failed to parse config file: %w", err)
	}

	return nil
}

// loadFromEnv loads configuration from environment variables
func loadFromEnv(config *Config) error {
	// Example environment variable processing
	if domains := os.Getenv("AUTOCERT_DOMAINS"); domains != "" {
		config.Domains = strings.Split(domains, ",")
	}

	if email := os.Getenv("AUTOCERT_EMAIL"); email != "" {
		config.Email = email
	}

	if cacheDir := os.Getenv("AUTOCERT_CACHE_DIR"); cacheDir != "" {
		config.CacheDir = cacheDir
	}

	if server := os.Getenv("AUTOCERT_ACME_SERVER"); server != "" {
		config.ACME.Server = server
	}

	// Additional environment variable processing
	// ...

	return nil
}

// validateConfig validates the configuration
func validateConfig(config *Config) error {
	if len(config.Domains) == 0 {
		return errors.New("at least one domain must be specified")
	}

	if config.Email == "" {
		return errors.New("email must be specified")
	}

	// Check if cache directory is specified and create if needed
	if config.CacheDir == "" && (config.Storage.Type == "" || config.Storage.Type == "file") {
		return errors.New("cache_dir must be specified when using file storage")
	}

	if config.CacheDir != "" {
		absPath, err := filepath.Abs(config.CacheDir)
		if err != nil {
			return fmt.Errorf("failed to resolve cache directory path: %w", err)
		}
		config.CacheDir = absPath

		if err := os.MkdirAll(config.CacheDir, 0700); err != nil {
			return fmt.Errorf("failed to create cache directory: %w", err)
		}
	}

	return nil
}