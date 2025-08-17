# Build stage for the Twilio MCP server
FROM node:20-slim AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./
COPY packages/mcp/package*.json ./packages/mcp/
COPY packages/openapi-mcp-server/package*.json ./packages/openapi-mcp-server/

# Install dependencies
RUN npm ci

# Copy source code
COPY . .

# Build the MCP server
RUN npm run build

# Runtime stage with Supergateway
FROM supercorp/supergateway:latest

# Install Node.js in the Supergateway image
RUN apt-get update && apt-get install -y \
    curl \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy built server from builder stage
COPY --from=builder /app/packages/mcp/build ./server
COPY --from=builder /app/packages/mcp/twilio-oai ./twilio-oai
COPY --from=builder /app/packages/mcp/node_modules ./node_modules
COPY --from=builder /app/packages/openapi-mcp-server/build ./openapi-server
COPY --from=builder /app/node_modules ./root-node_modules

# Expose the HTTP port
EXPOSE 8000

# Run Supergateway wrapping the stdio MCP server
CMD ["--stdio", "node /app/server/index.js", "--port", "8000", "--host", "0.0.0.0"]