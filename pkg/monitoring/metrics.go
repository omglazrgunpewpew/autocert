package monitoring

import (
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// MetricsCollector collects and exposes metrics
type MetricsCollector struct {
	registry             *prometheus.Registry
	certificateRequests  *prometheus.CounterVec
	certificateHits      *prometheus.CounterVec
	certificateMisses    *prometheus.CounterVec
	certificateErrors    *prometheus.CounterVec
	certificateRenewals  *prometheus.CounterVec
	certificateLatency   *prometheus.HistogramVec
	certificateExpiry    *prometheus.GaugeVec
	apiRequestsTotal     *prometheus.CounterVec
	apiRequestDuration   *prometheus.HistogramVec
}

// NewMetricsCollector creates a new metrics collector
func NewMetricsCollector() *MetricsCollector {
	registry := prometheus.NewRegistry()
	
	certificateRequests := prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "autocert_certificate_requests_total",
			Help: "Total number of certificate requests",
		},
		[]string{"domain"},
	)
	
	certificateHits := prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "autocert_certificate_cache_hits_total",
			Help: "Total number of certificate cache hits",
		},
		[]string{"domain"},
	)
	
	certificateMisses := prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "autocert_certificate_cache_misses_total",
			Help: "Total number of certificate cache misses",
		},
		[]string{"domain"},
	)
	
	certificateErrors := prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "autocert_certificate_errors_total",
			Help: "Total number of certificate errors",
		},
		[]string{"domain", "error_type"},
	)
	
	certificateRenewals := prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "autocert_certificate_renewals_total",
			Help: "Total number of certificate renewals",
		},
		[]string{"domain"},
	)
	
	certificateLatency := prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "autocert_certificate_request_duration_seconds",
			Help:    "Histogram of certificate request latencies",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"domain", "operation"},
	)
	
	certificateExpiry := prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "autocert_certificate_expiry_timestamp",
			Help: "Timestamp of when certificates expire",
		},
		[]string{"domain"},
	)
	
	apiRequestsTotal := prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "autocert_api_requests_total",
			Help: "Total number of API requests",
		},
		[]string{"method", "path", "status"},
	)
	
	apiRequestDuration := prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "autocert_api_request_duration_seconds",
			Help:    "Histogram of API request latencies",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"method", "path"},
	)
	
	// Register all metrics
	registry.MustRegister(
		certificateRequests,
		certificateHits,
		certificateMisses,
		certificateErrors,
		certificateRenewals,
		certificateLatency,
		certificateExpiry,
		apiRequestsTotal,
		apiRequestDuration,
	)
	
	return &MetricsCollector{
		registry:             registry,
		certificateRequests:  certificateRequests,
		certificateHits:      certificateHits,
		certificateMisses:    certificateMisses,
		certificateErrors:    certificateErrors,
		certificateRenewals:  certificateRenewals,
		certificateLatency:   certificateLatency,
		certificateExpiry:    certificateExpiry,
		apiRequestsTotal:     apiRequestsTotal,
		apiRequestDuration:   apiRequestDuration,
	}
}

// CertificateHit records a certificate cache hit
func (m *MetricsCollector) CertificateHit(domain string) {
	m.certificateRequests.WithLabelValues(domain).Inc()
	m.certificateHits.WithLabelValues(domain).Inc()
}

// CertificateMiss records a certificate cache miss
func (m *MetricsCollector) CertificateMiss(domain string) {
	m.certificateRequests.WithLabelValues(domain).Inc()
	m.certificateMisses.WithLabelValues(domain).Inc()
}

// CertificateError records a certificate error
func (m *MetricsCollector) CertificateError(domain string, err error) {
	errorType := "unknown"
	if err != nil {
		// Classify error types
		if _, ok := err.(x509.UnknownAuthorityError); ok {
			errorType = "unknown_authority"
		} else if _, ok := err.(x509.HostnameError); ok {
			errorType = "hostname_mismatch"
		} else {
			errorType = "other"
		}
	}
	
	m.certificateErrors.WithLabelValues(domain, errorType).Inc()
}

// CertificateObtained records a certificate being obtained
func (m *MetricsCollector) CertificateObtained(domain string, duration time.Duration) {
	m.certificateLatency.WithLabelValues(domain, "obtain").Observe(duration.Seconds())
}

// CertificateRenewed records a certificate being renewed
func (m *MetricsCollector) CertificateRenewed(domain string, duration time.Duration) {
	m.certificateRenewals.WithLabelValues(domain).Inc()
	m.certificateLatency.WithLabelValues(domain, "renew").Observe(duration.Seconds())
}

// CertificateRenewalError records a certificate renewal error
func (m *MetricsCollector) CertificateRenewalError(domain string, err error) {
	errorType := "unknown"
	if err != nil {
		errorType = "renewal_failed"
	}
	
	m.certificateErrors.WithLabelValues(domain, errorType).Inc()
}

// CertificateExpiry records when a certificate expires
func (m *MetricsCollector) CertificateExpiry(domain string, expiryTime time.Time) {
	m.certificateExpiry.WithLabelValues(domain).Set(float64(expiryTime.Unix()))
}

// APIRequest records an API request
func (m *MetricsCollector) APIRequest(method, path string, status int, duration time.Duration) {
	statusStr := fmt.Sprintf("%d", status)
	m.apiRequestsTotal.WithLabelValues(method, path, statusStr).Inc()
	m.apiRequestDuration.WithLabelValues(method, path).Observe(duration.Seconds())
}

// Handler returns an HTTP handler for exposing metrics
func (m *MetricsCollector) Handler() http.Handler {
	return promhttp.HandlerFor(m.registry, promhttp.HandlerOpts{})
}

// GetMetrics returns a map of metrics for the API
func (m *MetricsCollector) GetMetrics() map[string]interface{} {
	// This is a simplified version
	// In a real implementation, we'd gather all metrics from Prometheus
	// and convert them to a format suitable for JSON
	return map[string]interface{}{
		"certificate_requests": "Available at /metrics endpoint",
		"certificate_renewals": "Available at /metrics endpoint",
		"api_requests":         "Available at /metrics endpoint",
	}
}