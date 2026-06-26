# Stage 1: Build stage
FROM node:20-alpine AS build

USER root

# Skip downloading Chrome for Puppeteer (saves build time)
ENV PUPPETEER_SKIP_DOWNLOAD=true

# Install build dependencies needed for native modules
RUN apk add --no-cache python3 py3-setuptools make g++ build-base

# Install latest Flowise globally (specific version can be set: flowise@1.0.0)
RUN npm install -g flowise

# Upgrade @langchain/aws und AWS SDK für Prompt Caching Support
RUN cd /usr/local/lib/node_modules/flowise && npm install @langchain/aws@1.3.9 @aws-sdk/client-bedrock-runtime@3.1006.0

# Stage 2: Runtime stage
FROM node:20-alpine

# Install runtime dependencies
RUN apk add --no-cache chromium git python3 py3-pip make g++ build-base cairo-dev pango-dev curl

# Set the environment variable for Puppeteer to find Chromium
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

# Copy Flowise from the build stage
COPY --from=build /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=build /usr/local/bin /usr/local/bin

# Set environment variables
ENV PORT=80

# Expose the specified port
EXPOSE ${PORT}

ENTRYPOINT ["flowise", "start"]
