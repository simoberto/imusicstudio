# websocket/Dockerfile (Based on Dockerfile.prod from the document)

# Stage 1: Builder stage (if there were build steps or many dev dependencies)
# For a simple Node.js app without transpilation, a builder stage might be less critical,
# but it's good practice if you want to prune devDependencies strictly.

FROM node:18-alpine AS builder

WORKDIR /app

# Copy package.json and package-lock.json (or yarn.lock)
COPY package*.json ./

# Install all dependencies (including devDependencies if needed for any build/pruning step)
# If no build step and devDependencies are not huge, can skip pruning for simplicity.
# The original Dockerfile.prod had `npm ci` in builder, then `npm prune --production`.
RUN npm ci

# Copy the rest of the application source code
COPY . .

# Prune development dependencies if they were installed for some build step.
# If server.js and health-check.js are simple and don't need a build step,
# one could install only production dependencies directly in the final stage.
RUN npm prune --production


# Stage 2: Production stage
FROM node:18-alpine AS production

# Install runtime system dependencies
# - dumb-init: A lightweight init system for containers, handles signals properly.
# - curl: Useful for health checks or other internal HTTP requests if needed.
# - htop: (Optional) For debugging resource usage within the container. Can be removed for smaller image.
RUN apk update && apk upgrade --no-cache && apk add --no-cache \
  dumb-init \
  curl \
  htop

WORKDIR /app

# Copy necessary files from the builder stage:
# - node_modules (production dependencies only)
# - server.js (main application)
# - health-check.js (for Docker health check)
# - package.json (needed by npm/node for context, e.g. `npm start`)
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/server.js ./server.js
COPY --from=builder /app/health-check.js ./health-check.js
COPY --from=builder /app/package.json ./package.json


# Create a non-root user and group for running the application.
RUN addgroup -g 1001 -S nodejs && \
    adduser -S websocket-user -u 1001 -G nodejs
    # Renamed user to websocket-user for clarity

# Create directories that might be needed by the application (e.g., for logs if not stdout)
# and set permissions. The server.js currently logs to console.
# RUN mkdir -p /app/logs && \
#     chown -R websocket-user:nodejs /app/logs

# Ensure the entire /app directory is owned by the new user.
RUN chown -R websocket-user:nodejs /app

# Switch to the non-root user.
USER websocket-user

# Expose the port the WebSocket server will listen on (defined in server.js, default 8080).
EXPOSE 8080

# Health check using the health-check.js script.
# This script should try to connect to the WebSocket server and exit with 0 if healthy, 1 otherwise.
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
  CMD node health-check.js

# Labels for metadata and monitoring.
LABEL maintainer="AI Music Studio Team"
LABEL version="2.0.0" # Should match package.json version
LABEL description="AI Music Studio WebSocket Server - Production"

# Start the WebSocket server using dumb-init to handle signals correctly.
# This uses the "start" script from package.json (which is `node server.js`).
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["npm", "start"]
