# Custom AGFS server image with simpcurlfs + summaryfs prebuilt
FROM c4pt0r/agfs-server:latest

# Install build dependencies
RUN apk add --no-cache gcc musl-dev curl-dev make

# Copy plugin sources into the image
COPY simpcurlfs /tmp/simpcurlfs
COPY summaryfs /tmp/summaryfs

# Build simpcurlfs and summaryfs, then copy shared libraries to /app/plugins
RUN mkdir -p /app/plugins && \
    cd /tmp/simpcurlfs && make clean && make && cp libsimpcurlfs.* /app/plugins/ && \
    cd /tmp/summaryfs && make clean && make && cp libsummaryfs.* /app/plugins/ && \
    rm -rf /tmp/simpcurlfs /tmp/summaryfs

# Copy preconfigured config.yaml (auto-mounts simpcurlfs + summaryfs)
COPY docker-image/config.yaml /app/config.yaml
ENV AGFS_CONFIG=/app/config.yaml

WORKDIR /app
ENTRYPOINT ["./agfs-server"]
