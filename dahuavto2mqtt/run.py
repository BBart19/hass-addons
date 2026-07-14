#!/usr/bin/env python3
"""Translate Home Assistant app options to DahuaVTO2MQTT environment variables."""

from __future__ import annotations

import json
import os
from pathlib import Path
import sys
from typing import Mapping


OPTIONS_PATH = Path("/data/options.json")
UPSTREAM_ENTRYPOINT = Path("/app/DahuaVTO.py")

OPTION_TO_ENVIRONMENT = {
    "dahua_vto_host": "DAHUA_VTO_HOST",
    "dahua_vto_username": "DAHUA_VTO_USERNAME",
    "dahua_vto_password": "DAHUA_VTO_PASSWORD",
    "mqtt_broker_host": "MQTT_BROKER_HOST",
    "mqtt_broker_port": "MQTT_BROKER_PORT",
    "mqtt_broker_username": "MQTT_BROKER_USERNAME",
    "mqtt_broker_password": "MQTT_BROKER_PASSWORD",
    "mqtt_broker_topic_prefix": "MQTT_BROKER_TOPIC_PREFIX",
    "mqtt_broker_client_id": "MQTT_BROKER_CLIENT_ID",
    "debug": "DEBUG",
}

STRING_OPTIONS = (
    "dahua_vto_host",
    "dahua_vto_username",
    "dahua_vto_password",
    "mqtt_broker_host",
    "mqtt_broker_username",
    "mqtt_broker_password",
    "mqtt_broker_topic_prefix",
    "mqtt_broker_client_id",
)


class ConfigurationError(ValueError):
    """Raised when Home Assistant options cannot be used safely."""


def load_options(path: Path = OPTIONS_PATH) -> dict[str, object]:
    """Load the options supplied by Home Assistant Supervisor."""
    try:
        with path.open(encoding="utf-8") as options_file:
            options = json.load(options_file)
    except FileNotFoundError as error:
        raise ConfigurationError(f"Missing options file: {path}") from error
    except (OSError, json.JSONDecodeError) as error:
        raise ConfigurationError(f"Cannot read options file {path}: {error}") from error

    if not isinstance(options, dict):
        raise ConfigurationError("The Home Assistant options must be a JSON object")

    return options


def validate_options(options: Mapping[str, object]) -> None:
    """Validate values before replacing the upstream placeholder defaults."""
    for option_name in STRING_OPTIONS:
        value = options.get(option_name)
        if not isinstance(value, str) or not value.strip():
            raise ConfigurationError(
                f"Option '{option_name}' must be configured and cannot be empty"
            )

    port = options.get("mqtt_broker_port")
    if isinstance(port, bool) or not isinstance(port, int) or not 1 <= port <= 65535:
        raise ConfigurationError(
            "Option 'mqtt_broker_port' must be an integer between 1 and 65535"
        )

    debug = options.get("debug")
    if not isinstance(debug, bool):
        raise ConfigurationError("Option 'debug' must be true or false")

    dahua_host = str(options["dahua_vto_host"])
    if "://" in dahua_host:
        raise ConfigurationError(
            "Option 'dahua_vto_host' must contain only a hostname or IP address, "
            "without http:// or https://"
        )

    mqtt_host = str(options["mqtt_broker_host"])
    if "://" in mqtt_host:
        raise ConfigurationError(
            "Option 'mqtt_broker_host' must contain only a hostname or IP address, "
            "without a protocol"
        )

    topic_prefix = str(options["mqtt_broker_topic_prefix"])
    if topic_prefix.endswith("/"):
        raise ConfigurationError(
            "Option 'mqtt_broker_topic_prefix' must not end with a slash"
        )
    if "+" in topic_prefix or "#" in topic_prefix:
        raise ConfigurationError(
            "Option 'mqtt_broker_topic_prefix' must not contain MQTT wildcards"
        )


def environment_value(value: object) -> str:
    """Render values exactly as expected by the upstream application."""
    if isinstance(value, bool):
        return "True" if value else "False"
    return str(value)


def build_environment(
    options: Mapping[str, object],
    base_environment: Mapping[str, str] | None = None,
) -> dict[str, str]:
    """Build the child process environment without logging credentials."""
    validate_options(options)
    environment = dict(os.environ if base_environment is None else base_environment)

    for option_name, environment_name in OPTION_TO_ENVIRONMENT.items():
        environment[environment_name] = environment_value(options[option_name])

    # Keep the exporter aligned with config.yaml's fixed container port.
    environment["EXPORTER_PORT"] = "9563"
    return environment


def main() -> int:
    """Validate configuration and replace the launcher with DahuaVTO2MQTT."""
    try:
        options = load_options()
        environment = build_environment(options)
    except ConfigurationError as error:
        print(f"[ERROR] {error}", file=sys.stderr, flush=True)
        return 1

    if not UPSTREAM_ENTRYPOINT.is_file():
        print(
            f"[ERROR] Upstream entrypoint not found: {UPSTREAM_ENTRYPOINT}",
            file=sys.stderr,
            flush=True,
        )
        return 1

    print(
        "[INFO] Starting DahuaVTO2MQTT: "
        f"VTO={options['dahua_vto_host']}, "
        f"MQTT={options['mqtt_broker_host']}:{options['mqtt_broker_port']}, "
        f"topic={options['mqtt_broker_topic_prefix']}, exporter=9563",
        flush=True,
    )

    try:
        os.execve(
            sys.executable,
            [sys.executable, str(UPSTREAM_ENTRYPOINT)],
            environment,
        )
    except OSError as error:
        print(
            f"[ERROR] Cannot start DahuaVTO2MQTT: {error}",
            file=sys.stderr,
            flush=True,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
