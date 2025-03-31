# We're using Brave because Chromium controlled by gphotosdl (go-rod module) gets detected by Google as an "unsafe" browser
FROM alpine/curl AS downloader

# Populated automatically by Docker buildx
ARG TARGETARCH

RUN ARCH=$([ "${TARGETARCH}" = "amd64" ] && echo "x86_64" || echo "${TARGETARCH}") && \
    curl -L -O https://github.com/rclone/gphotosdl/releases/latest/download/gphotosdl_Linux_${ARCH}.zip && \
    curl -fsSLo brave-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg && \
    unzip gphotosdl_Linux_*.zip

FROM ghcr.io/ferferga/debian:latest
ARG USER_DIR=/home/gphotosdl
ENV XDG_CONFIG_HOME=${USER_DIR}/.config/gphotosdl XDG_CACHE_HOME=/tmp/.chromium

COPY --from=downloader /brave-keyring.gpg /usr/share/keyrings/brave-keyring.gpg
RUN install_packages ca-certificates && \
    chmod +r /usr/share/keyrings/brave-keyring.gpg && \
    mkdir -p /etc/apt/sources.list.d && \
    echo "deb [signed-by=/usr/share/keyrings/brave-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" > /etc/apt/sources.list.d/brave.list && \
    install_packages brave-browser

# Create a helper for running Brave inside Docker
COPY <<-"EOF" /usr/bin/chromium
#!/bin/bash

# Cleanup old lockfiles
rm -f $HOME/.config/{chromium,BraveBrowser,gphotosdl/browser}/Singleton*

exec /usr/bin/brave-browser \
    --no-sandbox \
    --headless \
    --disable-gpu \
    --disable-dev-shm-usage \
    --disable-crash-reporter \
    --no-crashpad \
    --disable-blink-features \
    --disable-blink-features=AutomationControlled \
    --no-first-run \
    "$@"
EOF

COPY --from=downloader /gphotosdl /usr/local/bin/gphotosdl
RUN chmod +x /usr/local/bin/gphotosdl /usr/bin/chromium && \
    adduser --system --shell /bin/false --home "${USER_DIR}" --disabled-login --disabled-password --gecos "gphotosdl user" --group gphotosdl

USER gphotosdl
WORKDIR $USER_DIR
ENTRYPOINT [ "/usr/local/bin/gphotosdl" ]

## Files that need  to be mounted from the host:
#    - /home/gphotosdl/.config/gphotosdl
