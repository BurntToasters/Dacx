#!/bin/sh
set -eu

# Vendored media libs resolve through the binary's $ORIGIN/lib RPATH (set
# when the portable bundle was staged). The Flatpak runtime's own GTK/GLib
# stack must keep resolving to the runtime, so this launcher deliberately
# sets no LD_LIBRARY_PATH.
exec /app/lib/dacx/dacx "$@"
