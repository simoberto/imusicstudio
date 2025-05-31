# frontend/Dockerfile (Based on Dockerfile.prod from the document)

# Stage 1: Builder stage
# Use a Node.js version that matches your development environment or project requirements.
# Alpine Linux is used for a smaller image size.
FROM node:18-alpine AS builder

WORKDIR /app

# Copy package.json and package-lock.json (or yarn.lock)
# This leverages Docker's layer caching. These layers are only rebuilt if these files change.
COPY package*.json ./

# Install dependencies
# Using npm ci for cleaner installs, assuming package-lock.json is present and up-to-date.
# --only=production might be too aggressive if build scripts are in devDependencies.
# For building, you usually need all dependencies, then prune for the runtime stage.
# The original script had --only=production --ignore-scripts for the builder, which is unusual.
# Typically, you install all deps to build, then copy only prod deps or prune.
# Let's assume all dependencies are needed for the build process.
RUN npm ci

# Copy the rest of the application source code
COPY . .

# Build arguments that can be passed from docker-compose.yml or docker build command
ARG REACT_APP_API_URL
ARG REACT_APP_WS_URL
ARG REACT_APP_VERSION
ARG GENERATE_SOURCEMAP=false

# Set build-time environment variables from ARGs
ENV REACT_APP_API_URL=${REACT_APP_API_URL}
ENV REACT_APP_WS_URL=${REACT_APP_WS_URL}
ENV REACT_APP_VERSION=${REACT_APP_VERSION}
ENV GENERATE_SOURCEMAP=${GENERATE_SOURCEMAP}

# Build the React application for production
# The original script had `npm run build:prod` which was `GENERATE_SOURCEMAP=false react-scripts build`
# We can directly use that or rely on the ENV var.
RUN echo "Building with GENERATE_SOURCEMAP=${GENERATE_SOURCEMAP}" &&     npm run build # This will use react-scripts build, which respects GENERATE_SOURCEMAP env var.

# Stage 2: Production stage
# Use Nginx on Alpine Linux for a lightweight production web server.
FROM nginx:1.25-alpine AS production # Pinned to 1.25-alpine from docker-compose

# Install security updates for nginx image and add curl for healthcheck
RUN apk update && apk upgrade --no-cache && apk add --no-cache curl

# Copy the built static files from the builder stage to Nginx's web server directory.
COPY --from=builder /app/build /usr/share/nginx/html

# Copy a custom Nginx configuration file.
# This nginx.conf should be tailored to serve the React app correctly,
# handling routing for single-page applications (SPA) and possibly proxying API requests.
# The document provided a main nginx.conf; this one would be simpler, just for serving static files.
# If this container is directly exposed, it needs its own nginx.conf.
# If it's behind the main nginx reverse proxy, it might not even need nginx, just serve.
# For now, assuming it needs to serve itself.
COPY nginx.conf /etc/nginx/nginx.conf
# A simple nginx.conf for serving SPA (to be placed in frontend/nginx.conf if not using main nginx):
# server {
#   listen 3000;
#   root /usr/share/nginx/html;
#   index index.html;
#   location / {
#     try_files $uri /index.html;
#   }
#   # Add other configurations like gzip, cache headers, etc.
# }


# Create a non-root user and group for running Nginx for better security.
RUN addgroup -g 1001 -S nginx-app && \
    adduser -S nginx-app -u 1001 -G nginx-app

# Set correct permissions for Nginx files and directories.
RUN chown -R nginx-app:nginx-app /usr/share/nginx/html && \
    chown -R nginx-app:nginx-app /var/cache/nginx && \
    chown -R nginx-app:nginx-app /var/log/nginx && \
    chown -R nginx-app:nginx-app /etc/nginx/conf.d
RUN touch /var/run/nginx.pid && \
    chown -R nginx-app:nginx-app /var/run/nginx.pid

# Switch to the non-root user.
USER nginx-app

# Expose the port Nginx will listen on (usually 80 for HTTP, 3000 was in original docker-compose for this service).
EXPOSE 3000

# Health check for the Nginx server.
# This assumes the Nginx server (configured by nginx.conf) is running on port 3000.
# The original docker-compose used http://localhost:3000/health; this needs an endpoint in nginx.conf or app.
# For a simple static server, checking the main page is often enough.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:3000/ || exit 1
  # To use /health, nginx.conf would need: location /health { return 200 "healthy"; }

# Labels for metadata and monitoring.
LABEL maintainer="AI Music Studio Team"
LABEL version="2.0.0" # This should ideally come from ARG REACT_APP_VERSION
LABEL description="AI Music Studio Frontend - Production Build"

# Default command to start Nginx in the foreground.
CMD ["nginx", "-g", "daemon off;"]
