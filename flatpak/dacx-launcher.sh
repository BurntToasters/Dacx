#!/bin/sh
set -eu

export LD_LIBRARY_PATH="/app/lib/dacx/lib:${LD_LIBRARY_PATH:-}"
exec /app/lib/dacx/dacx "$@"
