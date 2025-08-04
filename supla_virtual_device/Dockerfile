FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive


RUN apt-get update && apt-get install -y \
    bash \
    curl \
    git \
    libssl-dev \
    build-essential \
    jq \
    && rm -rf /var/lib/apt/lists/*


COPY run.sh /app/
RUN chmod +x /app/run.sh

WORKDIR /app

CMD ["/app/run.sh"]

LABEL \
    io.hass.version="VERSION" \
    io.hass.type="addon" \
    io.hass.arch="amd64|aarch64|armv7"
