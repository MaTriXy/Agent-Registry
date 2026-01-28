#!/usr/bin/env python3
"""
Anonymous Telemetry Module

Privacy-first, fire-and-forget usage tracking for Agent Registry.
No personal information or search queries are collected.

Opt-out:
  export AGENT_REGISTRY_NO_TELEMETRY=1
  export DO_NOT_TRACK=1

Automatically disabled in CI environments.
"""

import os
import sys
import platform
import threading
from urllib.request import urlopen, Request
from urllib.parse import urlencode

ENDPOINT = "https://t.insightx.pro"
VERSION = "1.0.0"
TOOL_ID = "agent-registry"  # Unique identifier for this project

# CI environment variable names to detect
CI_VARS = ["CI", "GITHUB_ACTIONS", "GITLAB_CI", "CIRCLECI", "TRAVIS", "BUILDKITE", "JENKINS_URL"]


def is_disabled() -> bool:
    """Check if telemetry is disabled via env vars or CI."""
    # Explicit opt-out
    if os.environ.get("AGENT_REGISTRY_NO_TELEMETRY"):
        return True
    if os.environ.get("DO_NOT_TRACK"):
        return True
    # CI detection - telemetry disabled in automated environments
    return any(os.environ.get(v) for v in CI_VARS)


def _send(url: str) -> None:
    """Send telemetry request (internal, runs in background thread)."""
    try:
        req = Request(url, headers={"User-Agent": f"agent-registry/{VERSION}"})
        urlopen(req, timeout=2)
    except Exception:
        pass  # Silent failure - never impact user experience


def track(event: str, data: dict = None) -> None:
    """
    Fire-and-forget telemetry. Never blocks, never fails.

    Args:
        event: Event name (e.g., 'search', 'get', 'list')
        data: Optional event-specific data points (no PII)
    """
    if is_disabled():
        return

    try:
        # Build payload with system context
        payload = {
            "t": TOOL_ID,  # Tool identifier - distinguishes this project from others
            "e": event,
            "v": VERSION,
            "py": platform.python_version(),
            "os": sys.platform,
        }

        # Add event-specific data
        if data:
            payload.update(data)

        url = f"{ENDPOINT}?{urlencode(payload)}"

        # Fire and forget via daemon thread
        threading.Thread(target=_send, args=(url,), daemon=True).start()
    except Exception:
        pass  # Silent failure - telemetry should never break functionality
