FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    bash \
    ca-certificates \
    curl \
    git \
    iproute2 \
    jq \
    mosquitto-clients \
    libssl-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/virtual-supla

RUN git clone --depth 1 https://github.com/BBart19/virtual-supla.git . \
    && bash ./install.sh \
    && install -m 0755 ./src/supla-dev/Release/supla-virtual-device /usr/local/bin/supla-virtual-device \
    && install -m 0644 ./supla-virtual-device.cfg.sample /usr/local/share/supla-virtual-device.cfg.sample \
    && rm -rf /opt/virtual-supla

COPY run.sh /usr/local/bin/run.sh
RUN chmod +x /usr/local/bin/run.sh

WORKDIR /data

CMD ["/usr/local/bin/run.sh"]

LABEL \
    io.hass.version="VERSION" \
    io.hass.type="addon" \
    io.hass.arch="amd64|aarch64|armv7"
