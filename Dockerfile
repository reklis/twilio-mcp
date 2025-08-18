# Build stage for the Twilio MCP server
FROM node:20-slim AS builder

# Install git for npm dependencies
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy package files
COPY package*.json ./
COPY packages/mcp/package*.json ./packages/mcp/
COPY packages/openapi-mcp-server/package*.json ./packages/openapi-mcp-server/

# Install dependencies (skip prepare scripts until source is copied)
RUN npm ci --ignore-scripts

# Copy source code
COPY . .

# Run prepare scripts now that source is available
RUN npm rebuild && npm run prepare

# Build the MCP server
RUN npm run build

# Runtime stage with Supergateway
FROM supercorp/supergateway:latest

# Install Node.js in the Supergateway image (Alpine-based)
RUN apk add --no-cache nodejs npm

WORKDIR /app

# Copy built server from builder stage
COPY --from=builder /app/packages/mcp/build ./server
COPY --from=builder /app/packages/mcp/twilio-oai ./twilio-oai
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/packages/openapi-mcp-server/build ./node_modules/@twilio-alpha/openapi-mcp-server
COPY --from=builder /app/packages/openapi-mcp-server/package.json ./node_modules/@twilio-alpha/openapi-mcp-server/package.json

# Expose the HTTP port
EXPOSE 8000

# Set environment variable for credentials (can be overridden at runtime)
ENV TWILIO_CREDENTIALS=""

# Create an entrypoint script to handle credentials
RUN echo '#!/bin/sh' > /entrypoint.sh && \
    echo 'if [ -z "$TWILIO_CREDENTIALS" ]; then' >> /entrypoint.sh && \
    echo '  echo "Error: TWILIO_CREDENTIALS environment variable is required"' >> /entrypoint.sh && \
    echo '  echo "Format: ACCOUNT_SID/API_KEY:API_SECRET"' >> /entrypoint.sh && \
    echo '  exit 1' >> /entrypoint.sh && \
    echo 'fi' >> /entrypoint.sh && \
    echo 'exec supergateway --stdio "node /app/server/index.js $TWILIO_CREDENTIALS $@" --port 8000 --host 0.0.0.0' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]