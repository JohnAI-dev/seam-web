#!/usr/bin/env bash
# The single test entry point used by CI and by the Grok agent.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check_site.py
