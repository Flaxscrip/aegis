#!/bin/bash
set -euo pipefail

# SANDBOX FIX — bind-mounted over the vendor image's
# /usr/local/bin/lightningd-wrapper.sh (ghcr.io/lightning-goats/cl-hive-node).
#
# That image's entrypoint always writes `grpc-port=9937` and
# `clnrest-port=3001` (+ clnrest-protocol/clnrest-host) into the generated
# lightningd config, but its bundled lightningd (v25.12.1) has no gRPC and
# no native clnrest plugin at all (confirmed via `lightningd --help` — none
# of those options exist; the plugin binaries aren't in
# /usr/local/libexec/c-lightning/plugins). lightningd rejects each as an
# unknown option and exits 1 on every start. Reproduces on both 3.1.0 and
# 3.4.0, on mainnet and regtest alike — not specific to this sandbox
# profile. The image separately bundles a third-party REST gateway
# (/opt/c-lightning-REST) but never actually runs it via supervisord, so
# port 3001 has nothing listening on it regardless — that's why LNbits is
# reconfigured to talk to CLN over the raw RPC socket
# (CoreLightningWallet) instead of CLNRestWallet in docker-compose.lightning-zap.yml,
# rather than trying to stand up that gateway ourselves.
#
# The config file is regenerated unconditionally on every container start,
# so the fix has to run every time (a one-off edit would be clobbered on
# the next restart), which is why this replaces the wrapper script rather
# than patching the config file once.
#
# This intentionally drops the vendor wrapper's SIGTERM/pre-stop graceful
# shutdown handling for simplicity — acceptable for a short-lived sandbox
# demo, not appropriate to carry into a production deployment unmodified.

NETWORK="${NETWORK:-bitcoin}"
LIGHTNING_DIR="${LIGHTNING_DIR:-/data/lightning/$NETWORK}"

sed -i -E '/^(grpc-port|clnrest-port|clnrest-protocol|clnrest-host)=/d' "$LIGHTNING_DIR/config"

exec /usr/local/bin/lightningd --lightning-dir="$LIGHTNING_DIR" --conf="$LIGHTNING_DIR/config"
