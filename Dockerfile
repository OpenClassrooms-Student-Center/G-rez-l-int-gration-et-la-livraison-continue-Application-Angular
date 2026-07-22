# ============================================================
# STAGE 1: "build" — compile the Angular application
# We use a full Node image, but it will NOT be part of the final
# image (multi-stage build): it only produces the static output
# (HTML/CSS/JS).
# ============================================================
FROM node:20-alpine AS build
WORKDIR /app

# Copy only the dependency manifests first.
# As long as package.json / package-lock.json don't change,
# Docker reuses the cached "npm ci" layer instead of reinstalling
# everything on every build (speeds up rebuilds a lot).
COPY package.json package-lock.json ./
RUN npm ci --cache .npm --prefer-offline

# Copy the rest of the source code (src/, angular.json, etc.)
# after dependencies are installed, so source changes don't
# invalidate the dependency cache layer above.
COPY . .

# "npm run build" = "ng build" (see package.json).
# Angular (builder @angular/build:application) outputs the static
# files to dist/olympic-games-starter/browser/
RUN npm run build

# ============================================================
# STAGE 2: "serve" — final image, actually run in production
# Starting fresh from a minimal nginx image: the Node SDK and
# node_modules from the previous stage are dropped here, only the
# build output is carried over. Result: a lightweight final image.
# ============================================================
FROM nginx:1.27-alpine

# Replace the default nginx config with the project's own
# (nginx/nginx.conf), which serves files from /app and handles
# SPA routing (try_files ... /index.html) plus HTTP caching.
COPY nginx/nginx.conf /etc/nginx/nginx.conf

# "--from=build": fetch the compiled files from the previous stage
# (not from the host machine) and place them in /app, the folder
# expected by nginx.conf.
COPY --from=build /app/dist/olympic-games-starter/browser /app

# By default the nginx image runs as root (SonarQube rule S6471).
# Ports below 1024 (like 80) normally require root privileges to
# bind, which is the usual reason people leave the container as
# root. Instead, grant the nginx binary itself the specific Linux
# capability it needs (CAP_NET_BIND_SERVICE) via setcap, so it can
# bind port 80 even when started as a non-root user. "libcap" is
# only needed to run "setcap" at build time, so it's removed right
# after to keep the final image small.
RUN apk add --no-cache libcap \
    && setcap 'cap_net_bind_service=+ep' /usr/sbin/nginx \
    && apk del libcap

# Run the container as the unprivileged "nginx" user (already
# created by the base image) instead of root.
USER nginx

# Documents the port the container listens on (doesn't publish
# anything by itself: docker-compose.yml / "docker run -p" is what
# actually exposes the port to the host).
EXPOSE 80

# Run nginx in the foreground ("daemon off"): required so the
# container stays alive (otherwise nginx would daemonize into the
# background and the container would exit immediately, having no
# foreground process left).
CMD ["nginx", "-g", "daemon off;"]
