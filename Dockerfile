# Multi-stage build for production - optimized for smaller image size
# Build image for Postiz - uses system fonts instead of remote Google Fonts
# to allow offline/networkless builds.

# Stage 1: Builder
FROM node:22-alpine AS builder

ARG NEXT_PUBLIC_VERSION
ENV NEXT_PUBLIC_VERSION=$NEXT_PUBLIC_VERSION

# Install build dependencies
RUN apk add --no-cache g++ make py3-pip bash

WORKDIR /app

# Install pnpm
RUN npm --no-update-notifier --no-fund --global install pnpm@10.6.1

# Copy all files (leverage Docker cache for dependencies)
COPY . .

# Install dependencies
RUN pnpm install --frozen-lockfile

# Build the application
RUN NODE_OPTIONS="--max-old-space-size=4096" pnpm run build

# Prune dev dependencies
RUN pnpm prune --prod

# Remove unnecessary files
RUN rm -rf apps/*/src apps/*/.next/cache apps/frontend/.next/cache \
    libraries/*/src .git .github apps/extension apps/commands

# Stage 2: Production Runtime
FROM node:22-alpine AS runtime

ARG NEXT_PUBLIC_VERSION
ENV NEXT_PUBLIC_VERSION=$NEXT_PUBLIC_VERSION
ENV NODE_ENV=production

# Install only runtime dependencies
RUN apk add --no-cache bash nginx

# Create www user
RUN adduser -D -g 'www' www && \
    mkdir /www && \
    chown -R www:www /var/lib/nginx && \
    chown -R www:www /www

# Install pnpm and pm2 globally
RUN npm --no-update-notifier --no-fund --global install pnpm@10.6.1 pm2

WORKDIR /app

# Copy only production files from builder
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/apps ./apps
COPY --from=builder /app/libraries ./libraries
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/pnpm-workspace.yaml ./pnpm-workspace.yaml

# Copy nginx config
COPY var/docker/nginx.conf /etc/nginx/nginx.conf

# Expose port
EXPOSE 5000

CMD ["sh", "-c", "nginx && pnpm run pm2"]
