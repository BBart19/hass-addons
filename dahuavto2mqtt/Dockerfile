# syntax=docker/dockerfile:1

ARG TARGETARCH
ARG UPSTREAM_AMD64_PLATFORM=linux/amd64
ARG UPSTREAM_ARM64_PLATFORM=linux/arm64

# DahuaVTO2MQTT publishes separate, single-platform image tags.
FROM --platform=${UPSTREAM_AMD64_PLATFORM} registry.gitlab.com/elad.bar/dahuavto2mqtt@sha256:fa14700f787a013fdeb240115666624b8feea76422e3b745f50cf6d96ce08b34 AS upstream-amd64
FROM --platform=${UPSTREAM_ARM64_PLATFORM} registry.gitlab.com/elad.bar/dahuavto2mqtt@sha256:0e344a73ab0c6940207b5b69bb2ee61a5aece279f32b9a921d41b5e35438fc3b AS upstream-arm64

FROM upstream-${TARGETARCH}

ARG BUILD_ARCH=amd64
ARG BUILD_VERSION=1.0.0

ENV \
    EXPORTER_PORT="9563" \
    PYTHONUNBUFFERED="1"

COPY run.py /usr/local/bin/dahuavto2mqtt-addon
RUN chmod 0755 /usr/local/bin/dahuavto2mqtt-addon

WORKDIR /app
EXPOSE 9563/tcp

ENTRYPOINT ["python3", "/usr/local/bin/dahuavto2mqtt-addon"]

LABEL \
    io.hass.name="Dahua VTO to MQTT" \
    io.hass.description="Publishes Dahua VTO, camera and NVR events to MQTT" \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.type="app" \
    io.hass.arch="${BUILD_ARCH}" \
    org.opencontainers.image.title="Dahua VTO to MQTT for Home Assistant" \
    org.opencontainers.image.description="Home Assistant wrapper for elad-bar/DahuaVTO2MQTT" \
    org.opencontainers.image.source="https://github.com/BBart19/hass-addons"
