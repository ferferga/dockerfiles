FROM debian:stable-slim

COPY scripts/debian/postunpack.sh /postunpack.sh
RUN chmod +x /postunpack.sh && \
    /postunpack.sh && \
    rm /postunpack.sh

LABEL org.opencontainers.image.authors="ferferga" org.opencontainers.image.source="https://github.com/ferferga/dockerfiles"
