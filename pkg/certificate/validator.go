package certificate

import (
	"crypto/x509"
	"errors"
	"fmt"
	"time"
)

// ValidationError represents an error that occurred during certificate validation
type ValidationError struct {
	Domain string
	Reason string
}

func (e *ValidationError) Error() string {
	return fmt.Sprintf("certificate validation failed for %s: %s", e.Domain, e.Reason)
}

// Validator performs certificate validation operations
type Validator struct {
	// MinValidity is the minimum validity period for a certificate to be considered valid
	MinValidity time.Duration
}

// NewValidator creates a new certificate validator
func NewValidator(minValidity time.Duration) *Validator {
	if minValidity == 0 {
		minValidity = 7 * 24 * time.Hour // Default to 7 days
	}
	return &Validator{
		MinValidity: minValidity,
	}
}

// ValidateCertificate checks if a certificate is valid for the given domain
func (v *Validator) ValidateCertificate(cert *x509.Certificate, domain string) error {
	if cert == nil {
		return &ValidationError{Domain: domain, Reason: "certificate is nil"}
	}

	// Check if the certificate is expired
	now := time.Now()
	if now.After(cert.NotAfter) {
		return &ValidationError{
			Domain: domain,
			Reason: fmt.Sprintf("certificate expired on %s", cert.NotAfter),
		}
	}

	// Check if the certificate is not yet valid
	if now.Before(cert.NotBefore) {
		return &ValidationError{
			Domain: domain,
			Reason: fmt.Sprintf("certificate not valid until %s", cert.NotBefore),
		}
	}

	// Check if the certificate is about to expire
	if now.Add(v.MinValidity).After(cert.NotAfter) {
		return &ValidationError{
			Domain: domain,
			Reason: fmt.Sprintf("certificate expires soon on %s", cert.NotAfter),
		}
	}

	// Verify the certificate is valid for the domain
	if err := v.verifyDomain(cert, domain); err != nil {
		return &ValidationError{
			Domain: domain,
			Reason: err.Error(),
		}
	}

	return nil
}

// verifyDomain checks if a certificate is valid for the specified domain
func (v *Validator) verifyDomain(cert *x509.Certificate, domain string) error {
	// Check the Common Name
	if cert.Subject.CommonName == domain {
		return nil
	}

	// Check the Subject Alternative Names
	for _, san := range cert.DNSNames {
		if san == domain {
			return nil
		}
	}

	return fmt.Errorf("certificate not valid for domain %s", domain)
}

// IsExpiringSoon checks if a certificate will expire within the specified duration
func (v *Validator) IsExpiringSoon(cert *x509.Certificate) bool {
	if cert == nil {
		return false
	}

	return time.Now().Add(v.MinValidity).After(cert.NotAfter)
}

// GetExpiryInfo returns information about certificate expiration
func (v *Validator) GetExpiryInfo(cert *x509.Certificate) (time.Duration, error) {
	if cert == nil {
		return 0, errors.New("certificate is nil")
	}

	return cert.NotAfter.Sub(time.Now()), nil
}