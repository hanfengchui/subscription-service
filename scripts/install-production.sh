#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PRODUCTION_MODE=true exec bash "$SCRIPT_DIR/install.sh" --production "$@"
