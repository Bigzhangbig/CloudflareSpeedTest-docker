# Stage 1: Builder
FROM --platform=$BUILDPLATFORM golang:alpine3.20 AS builder

# Set necessary environment variables
ENV CGO_ENABLED=0
ENV GOPROXY=https://goproxy.cn,direct

ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

# Install git for go modules
RUN apk add --no-cache git

WORKDIR /app

# Copy go.mod and go.sum first to leverage Docker cache
COPY go.mod go.sum ./

# Download Go modules
RUN go mod download

# Copy only required application source code
COPY main.go ./
COPY task ./task
COPY utils ./utils

# Build the application
# Use -ldflags to embed version information and strip debug info for smaller binary
ARG VERSION=v0.0.0
RUN GOARM=""; \
	if [ "$TARGETARCH" = "arm" ]; then GOARM="${TARGETVARIANT#v}"; fi; \
	GOOS=${TARGETOS} GOARCH=${TARGETARCH} GOARM=${GOARM} \
	go build -trimpath -buildvcs=false -ldflags "-s -w -X main.version=${VERSION}" -o cfst .

# Stage 2: Runner
FROM alpine:3.20

LABEL org.opencontainers.image.title="CloudflareSpeedTest Docker" \
	org.opencontainers.image.description="CloudflareSpeedTest CLI container for Cloudflare IP latency and download testing. Quick start: docker run --rm ghcr.io/bigzhangbig/cloudflarespeedtest-docker:latest -n 500. Common options: -dn 20 -sl 5 -tl 200 -tp 443 -f ip.txt -o result.csv. Use --help for full flags." \
	org.opencontainers.image.source="https://github.com/Bigzhangbig/CloudflareSpeedTest-docker" \
	org.opencontainers.image.url="https://github.com/Bigzhangbig/CloudflareSpeedTest-docker" \
	org.opencontainers.image.documentation="https://github.com/Bigzhangbig/CloudflareSpeedTest-docker#readme" \
	org.opencontainers.image.licenses="GPL-3.0"

WORKDIR /app

RUN apk add --no-cache ca-certificates tini tzdata

# Copy the compiled binary from the builder stage
COPY --from=builder /app/cfst .
COPY docker-entrypoint.sh .
RUN chmod +x /app/docker-entrypoint.sh

# Copy IP files
COPY ip.txt .
COPY ipv6.txt .

# Expose the default port if applicable (e.g., for HTTPing or internal server)
# CloudflareSpeedTest typically runs as a CLI tool, so exposing a port might not be necessary
# unless it starts an internal HTTP server for heartbeat or web UI.
# For now, let's assume it runs as a CLI, so no EXPOSE needed unless specified later for heartbeat.

# Define entrypoint to run the application
STOPSIGNAL SIGTERM

ENTRYPOINT ["/sbin/tini", "-g", "--", "/app/docker-entrypoint.sh"]

# Default command (can be overridden)
CMD []
