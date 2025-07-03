package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/yourusername/autocert/internal/config"
	"github.com/yourusername/autocert/pkg/certificate"
	"github.com/yourusername/autocert/pkg/monitoring"
	"github.com/yourusername/autocert/pkg/storage"
)

// Config contains API server configuration
type Config struct {
	// Address to bind the API server to
	Address string
	
	// TLS configuration
	TLS config.APITLSConfig
	
	// Certificate manager
	Manager *certificate.Manager
	
	// Storage backend
	Store storage.Store
	
	// Logger
	Logger monitoring.Logger
	
	// Metrics
	Metrics *monitoring.MetricsCollector
}

// Server is the API server
type Server struct {
	config Config
	server *http.Server
}

// NewServer creates a new API server
func NewServer(config Config) *Server {
	return &Server{
		config: config,
	}
}

// Start starts the API server
func (s *Server) Start() error {
	mux := http.NewServeMux()
	
	// Register API routes
	mux.HandleFunc("/api/v1/certificates", s.handleCertificates)
	mux.HandleFunc("/api/v1/certificates/", s.handleCertificate)
	mux.HandleFunc("/api/v1/renew", s.handleRenew)
	mux.HandleFunc("/api/v1/health", s.handleHealth)
	mux.HandleFunc("/api/v1/metrics", s.handleMetrics)
	
	s.server = &http.Server{
		Addr:         s.config.Address,
		Handler:      s.loggingMiddleware(mux),
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  120 * time.Second,
	}
	
	s.config.Logger.Info("Starting API server", "address", s.config.Address)
	
	if s.config.TLS.Enabled {
		s.config.Logger.Info("TLS enabled for API server")
		return s.server.ListenAndServeTLS(s.config.TLS.CertFile, s.config.TLS.KeyFile)
	}
	
	return s.server.ListenAndServe()
}

// Stop stops the API server
func (s *Server) Stop() error {
	if s.server != nil {
		return s.server.Close()
	}
	return nil
}

// handleCertificates handles the /api/v1/certificates endpoint
func (s *Server) handleCertificates(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		// List all certificates
		certs, err := s.config.Manager.ListCertificates()
		if err != nil {
			s.jsonError(w, err.Error(), http.StatusInternalServerError)
			return
		}
		s.jsonResponse(w, certs)
	
	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}

// handleCertificate handles the /api/v1/certificates/{domain} endpoint
func (s *Server) handleCertificate(w http.ResponseWriter, r *http.Request) {
	// Extract domain from URL path
	domain := extractDomain(r.URL.Path, "/api/v1/certificates/")
	if domain == "" {
		http.NotFound(w, r)
		return
	}
	
	switch r.Method {
	case http.MethodGet:
		// Get certificate details
		certs, err := s.config.Manager.ListCertificates()
		if err != nil {
			s.jsonError(w, err.Error(), http.StatusInternalServerError)
			return
		}
		
		for _, cert := range certs {
			if cert.Domain == domain {
				s.jsonResponse(w, cert)
				return
			}
		}
		
		http.NotFound(w, r)
	
	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}

// handleRenew handles the /api/v1/renew endpoint
func (s *Server) handleRenew(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	
	type RenewRequest struct {
		Domain string `json:"domain,omitempty"`
		All    bool   `json:"all,omitempty"`
	}
	
	var req RenewRequest
	err := json.NewDecoder(r.Body).Decode(&req)
	if err != nil {
		s.jsonError(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	
	if !req.All && req.Domain == "" {
		s.jsonError(w, "Either domain or all must be specified", http.StatusBadRequest)
		return
	}
	
	// Trigger renewal
	if req.All {
		err = s.config.Manager.RenewCertificates(r.Context())
		if err != nil {
			s.jsonError(w, err.Error(), http.StatusInternalServerError)
			return
		}
		s.jsonResponse(w, map[string]string{"status": "renewal triggered for all certificates"})
		return
	}
	
	// Renew a specific domain
	// Implementation depends on adding a domain-specific renewal to the Manager
	s.jsonError(w, "Not implemented yet", http.StatusNotImplemented)
}

// handleHealth handles the /api/v1/health endpoint
func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	
	s.jsonResponse(w, map[string]string{
		"status": "healthy",
	})
}

// handleMetrics handles the /api/v1/metrics endpoint
func (s *Server) handleMetrics(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	
	metrics := s.config.Metrics.GetMetrics()
	s.jsonResponse(w, metrics)
}

// jsonResponse sends a JSON response
func (s *Server) jsonResponse(w http.ResponseWriter, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	
	if err := json.NewEncoder(w).Encode(data); err != nil {
		s.config.Logger.Error("Failed to encode JSON response", "error", err)
		http.Error(w, "Failed to encode response", http.StatusInternalServerError)
		return
	}
}

// jsonError sends a JSON error response
func (s *Server) jsonError(w http.ResponseWriter, message string, status int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	
	errResponse := map[string]string{
		"error": message,
	}
	
	if err := json.NewEncoder(w).Encode(errResponse); err != nil {
		s.config.Logger.Error("Failed to encode error response", "error", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}
}

// loggingMiddleware logs API requests
func (s *Server) loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		
		// Create a custom response writer to capture status code
		rw := newResponseWriter(w)
		
		// Call the next handler
		next.ServeHTTP(rw, r)
		
		duration := time.Since(start)
		
		s.config.Logger.Info("API request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", rw.status,
			"duration", duration,
			"remote_addr", r.RemoteAddr,
			"user_agent", r.UserAgent(),
		)
		
		// Record metrics
		s.config.Metrics.APIRequest(r.Method, r.URL.Path, rw.status, duration)
	})
}

// responseWriter is a wrapper for http.ResponseWriter that captures the status code
type responseWriter struct {
	http.ResponseWriter
	status int
}

// newResponseWriter creates a new responseWriter
func newResponseWriter(w http.ResponseWriter) *responseWriter {
	return &responseWriter{
		ResponseWriter: w,
		status:         http.StatusOK,
	}
}

// WriteHeader captures the status code
func (rw *responseWriter) WriteHeader(status int) {
	rw.status = status
	rw.ResponseWriter.WriteHeader(status)
}

// extractDomain extracts the domain from the URL path
func extractDomain(path, prefix string) string {
	if len(path) <= len(prefix) {
		return ""
	}
	return path[len(prefix):]
}