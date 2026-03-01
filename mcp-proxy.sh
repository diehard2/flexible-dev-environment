#!/usr/bin/env bash
set -euo pipefail

# mcp-proxy.sh — Start the MCP proxy server
#
# Exposes stdio-based MCP servers (defined in mcp-servers.json) over HTTP
# so that Claude Code (in WSL2) can reach them via http://localhost:MCP_PROXY_PORT
# and Docker containers can reach them via http://host.docker.internal:MCP_PROXY_PORT
#
# Usage:
#   ./mcp-proxy.sh              Start the proxy (foreground)
#   ./mcp-proxy.sh --bg         Start the proxy (background, logs to file)
#   ./mcp-proxy.sh --stop       Stop a running background proxy
#   ./mcp-proxy.sh --status     Check if the proxy is running

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/mcp-servers.json"
MCP_PROXY_PORT="${MCP_PROXY_PORT:-8808}"
MCP_PROXY_HOST="0.0.0.0"
PIDFILE="$SCRIPT_DIR/.mcp-proxy.pid"
LOGFILE="$SCRIPT_DIR/.mcp-proxy.log"

# ── Helpers ──────────────────────────────────────────────────────────

die()  { echo "Error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

ensure_uv() {
    if command -v uv &>/dev/null; then
        return
    fi
    info "uv not found, installing..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # uv installs to ~/.local/bin; add to PATH for this session
    export PATH="$HOME/.local/bin:$PATH"
    command -v uv &>/dev/null || die "uv installed but not on PATH. Check your PATH."
}


ensure_mcp_proxy() {
    if command -v mcp-proxy &>/dev/null; then
        return
    fi
    info "mcp-proxy not found, installing..."
    ensure_uv
    uv tool install mcp-proxy
    # uv tools are in ~/.local/bin
    export PATH="$HOME/.local/bin:$PATH"
    command -v mcp-proxy &>/dev/null || die "mcp-proxy installed but not on PATH. Check your PATH."
}

is_running() {
    [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

# ── Commands ─────────────────────────────────────────────────────────

do_stop() {
    if is_running; then
        local pid
        pid=$(cat "$PIDFILE")
        info "Stopping mcp-proxy (PID $pid)..."
        kill "$pid" 2>/dev/null || true
        rm -f "$PIDFILE"
        info "Stopped."
    else
        info "mcp-proxy is not running."
        rm -f "$PIDFILE"
    fi
}

do_status() {
    if is_running; then
        local pid
        pid=$(cat "$PIDFILE")
        info "mcp-proxy is running (PID $pid) on port $MCP_PROXY_PORT"
        echo "    Named servers config: $CONFIG"
        echo "    Endpoints:"
        python3 -c "
import json, sys
with open('$CONFIG') as f:
    cfg = json.load(f)
for name in cfg.get('mcpServers', {}):
    print(f'      http://host.docker.internal:$MCP_PROXY_PORT/servers/{name}/sse')
" 2>/dev/null || true
    else
        info "mcp-proxy is not running."
    fi
}

do_start_fg() {
    if is_running; then
        die "mcp-proxy already running (PID $(cat "$PIDFILE")). Use --stop first."
    fi
    [[ -f "$CONFIG" ]] || die "Config file not found: $CONFIG"
    ensure_mcp_proxy
    info "Starting mcp-proxy on $MCP_PROXY_HOST:$MCP_PROXY_PORT ..."
    info "Config: $CONFIG"
    exec mcp-proxy \
        --host="$MCP_PROXY_HOST" \
        --port="$MCP_PROXY_PORT" \
        --pass-environment \
        --named-server-config "$CONFIG"
}

do_start_bg() {
    if is_running; then
        die "mcp-proxy already running (PID $(cat "$PIDFILE")). Use --stop first."
    fi
    [[ -f "$CONFIG" ]] || die "Config file not found: $CONFIG"
    ensure_mcp_proxy
    info "Starting mcp-proxy in background on $MCP_PROXY_HOST:$MCP_PROXY_PORT ..."
    info "Config: $CONFIG"
    info "Log:    $LOGFILE"
    nohup mcp-proxy \
        --host="$MCP_PROXY_HOST" \
        --port="$MCP_PROXY_PORT" \
        --pass-environment \
        --named-server-config "$CONFIG" \
        > "$LOGFILE" 2>&1 &
    echo $! > "$PIDFILE"
    sleep 1
    if is_running; then
        info "mcp-proxy started (PID $(cat "$PIDFILE"))"
        do_status
    else
        rm -f "$PIDFILE"
        die "mcp-proxy failed to start. Check $LOGFILE"
    fi
}

# ── Main ─────────────────────────────────────────────────────────────

case "${1:-}" in
    --stop)   do_stop ;;
    --status) do_status ;;
    --bg)     do_start_bg ;;
    *)        do_start_fg ;;
esac
