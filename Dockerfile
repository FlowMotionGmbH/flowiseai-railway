# Stage 1: Build stage
FROM node:20-alpine AS build
USER root
# Skip downloading Chrome for Puppeteer (saves build time)
ENV PUPPETEER_SKIP_DOWNLOAD=true
# Install build dependencies needed for native modules
RUN apk add --no-cache python3 py3-setuptools make g++ build-base
# Install latest Flowise globally (specific version can be set: flowise@1.0.0)
RUN npm install -g flowise
# Upgrade @langchain/aws und AWS SDK für Prompt Caching Support (inkl. aller verschachtelten Kopien)
RUN cd /usr/local/lib/node_modules/flowise && npm install @langchain/aws@1.3.9 @aws-sdk/client-bedrock-runtime@3.1006.0 ws && \
    UPGRADED=/usr/local/lib/node_modules/flowise/node_modules/@langchain/aws && \
    for dir in $(find /usr/local/lib/node_modules/flowise -type d -name aws); do \
        PARENT=$(dirname "$dir"); \
        PARENTNAME=$(basename "$PARENT"); \
        if [ "$PARENTNAME" = "@langchain" ] && [ "$dir" != "$UPGRADED" ]; then \
            rm -rf "$dir" && cp -r "$UPGRADED" "$dir"; \
        fi; \
    done
# Patch Flowise Bedrock Node to enable Prompt Caching (cache_control)
RUN sed -i \
    -e "s/    setMultiModalOption(multiModalOption) {/    async _generate(messages, options, runManager) {\n        options.cache_control = { type: 'default' };\n        try { console.log('CACHE_PATCH_DEBUG @langchain\/aws version:', require('@langchain\/aws\/package.json').version); } catch(e) { console.log('CACHE_PATCH_DEBUG version check failed:', e.message); }\n        return await super._generate(messages, options, runManager);\n    }\n    async *_streamResponseChunks(messages, options, runManager) {\n        options.cache_control = { type: 'default' };\n        try { console.log('CACHE_PATCH_DEBUG @langchain\/aws version:', require('@langchain\/aws\/package.json').version); } catch(e) { console.log('CACHE_PATCH_DEBUG version check failed:', e.message); }\n        yield* super._streamResponseChunks(messages, options, runManager);\n    }\n    setMultiModalOption(multiModalOption) {/" \
    /usr/local/lib/node_modules/flowise/node_modules/flowise-components/dist/nodes/chatmodels/AWSBedrock/FlowiseAWSChatBedrock.js
# Verify the patch actually applied — fail the build loudly if not
RUN grep -q "options.cache_control = { type: 'default' };" /usr/local/lib/node_modules/flowise/node_modules/flowise-components/dist/nodes/chatmodels/AWSBedrock/FlowiseAWSChatBedrock.js \
    && echo "✅ CACHE PATCH APPLIED SUCCESSFULLY" \
    || (echo "❌ CACHE PATCH FAILED — PATTERN NOT FOUND IN SOURCE FILE" && exit 1)
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
RUN echo "const WebSocket = require('/usr/local/lib/node_modules/flowise/node_modules/ws'); globalThis.WebSocket = WebSocket;" > /usr/local/lib/ws-polyfill.js
ENV NODE_OPTIONS="--require /usr/local/lib/ws-polyfill.js"
ENV PORT=80
# Expose the specified port
EXPOSE ${PORT}
ENTRYPOINT ["flowise", "start"]
