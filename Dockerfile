FROM golang:1.18-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache git make

# Copy Go module files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build
RUN CGO_ENABLED=0 go build -o /autocert ./cmd/autocert

# Create final minimal image
FROM alpine:3.15

# Add CA certificates
RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

# Copy binary from builder stage
COPY --from=builder /autocert /app/autocert

# Create directory for certificates
RUN mkdir -p /var/lib/autocert/cache && \
    chmod 700 /var/lib/autocert/cache

# Expose HTTP port for ACME challenges
EXPOSE 80

# Expose HTTPS port for API (if enabled)
EXPOSE 443

# Set up environment variables
ENV AUTOCERT_CACHE_DIR=/var/lib/autocert/cache

# Run the application
ENTRYPOINT ["/app/autocert"]