FROM alpine/curl AS downloader

# Populated automatically by Docker buildx
ARG TARGETARCH

RUN ARCH=$([ "${TARGETARCH}" = "amd64" ] && echo "x86_64" || echo "${TARGETARCH}") && \
    curl -L -O https://github.com/rclone/gphotosdl/releases/latest/download/gphotosdl_Linux_${ARCH}.zip && \
    unzip gphotosdl_Linux_*.zip

FROM ghcr.io/ferferga/debian:latest

# Create a helper for running chromium inside Docker
COPY <<-"EOF" /usr/bin/wrapped-chromium
#!/bin/bash

# Cleanup
if ! pgrep chromium > /dev/null;then
  rm -f $HOME/.config/chromium/Singleton*
fi

exec /usr/bin/chromium-browser \
    --ignore-gpu-blocklist \
    --no-first-run \
    --password-store=basic \
    --simulate-outdated-no-au='Tue, 31 Dec 2099 23:59:59 GMT' \
    --start-maximized \
    --user-data-dir "$@" > /dev/null 2>&1
EOF

RUN chmod +x /usr/bin/wrapped-chromium && \
    install_packages chromium chromium-sandbox && \
    mv /usr/bin/chromium /usr/bin/chromium-browser && \
    mv /usr/bin/wrapped-chromium /usr/bin/chromium 
COPY --from=downloader /gphotosdl /usr/local/bin/gphotosdl
RUN chmod +x /usr/local/bin/gphotosdl && \
    adduser --system --shell /bin/false --home /home/gphotosdl --disabled-login --disabled-password --gecos "gphotosdl user" --group gphotosdl

USER gphotosdl
WORKDIR /home/gphotosdl
