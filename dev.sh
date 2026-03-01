#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage:
  dev.sh <project-dir>              Start dev environment for a project
  dev.sh --shutdown <project-dir>   Shut down a project environment
EOF
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure SSH agent is running and key is loaded
if [[ -z "${SSH_AUTH_SOCK:-}" ]] || ! ssh-add -l &>/dev/null; then
    unset SSH_AUTH_SOCK SSH_AGENT_PID
    eval "$(ssh-agent -s)" > /dev/null
fi
if ! ssh-add -l &>/dev/null; then
    ssh-add ~/.ssh/id_ed25519 2>/dev/null || true
fi
export SSH_AUTH_SOCK

resolve_project_dir() {
    local raw_dir="$1"
    [[ -d "$raw_dir" ]] || { echo "Error: '$raw_dir' is not a directory" >&2; exit 1; }
    PROJECT_DIR="$(cd "$raw_dir" && pwd)"
    PROJECT_NAME="$(basename "$PROJECT_DIR")"
    export PROJECT_DIR PROJECT_NAME
}

# Detect host shell config file for personal bashrc mount
export BASHRC_FILE=/dev/null
for _f in ~/.bashrc ~/.zshrc ~/.bash_profile; do
    [[ -f "$_f" ]] && BASHRC_FILE="$_f" && break
done
unset _f

# Parse args and resolve project directory
SHUTDOWN=false
if [[ "${1:-}" == "--shutdown" ]]; then
    SHUTDOWN=true
    [[ -z "${2:-}" ]] && usage
    resolve_project_dir "$2"
elif [[ -z "${1:-}" ]]; then
    usage
else
    resolve_project_dir "$1"
fi

# Build compose file list (shared by both startup and shutdown)
COMPOSE_FILES=(-f "$SCRIPT_DIR/docker-compose.yml" -f "$SCRIPT_DIR/project-override.yml")
[[ -f "$PROJECT_DIR/docker-compose.yml" && "$PROJECT_DIR" != "$SCRIPT_DIR" ]] && COMPOSE_FILES+=(-f "$PROJECT_DIR/docker-compose.yml")

if $SHUTDOWN; then
    docker compose -p "$PROJECT_NAME" "${COMPOSE_FILES[@]}" down || {
        echo "Error: Failed to shut down project '$PROJECT_NAME'" >&2
        exit 1
    }
    echo "Project '$PROJECT_NAME' shut down successfully"
    exit 0
fi

COMPOSE_CMD=(docker compose -p "$PROJECT_NAME" "${COMPOSE_FILES[@]}")

# Ensure mcp-proxy is running so Claude Code can reach MCP servers
"$SCRIPT_DIR/mcp-proxy.sh" --status &>/dev/null || "$SCRIPT_DIR/mcp-proxy.sh" --bg

# Start all services detached (tty+stdin_open keeps dev alive without a command override)
if ! "${COMPOSE_CMD[@]}" up -d --no-recreate; then
    echo "Error: Failed to start services for '$PROJECT_NAME'" >&2
    exit 1
fi

# Get the dev container name from compose
CONTAINER_IDS=$("${COMPOSE_CMD[@]}" ps -q dev) || {
    echo "Error: Could not find dev container for '$PROJECT_NAME'" >&2
    exit 1
}
CONTAINER_ID=$(printf '%s' "$CONTAINER_IDS" | head -1)

[[ -z "$CONTAINER_ID" ]] && {
    echo "Error: Dev container is not running for '$PROJECT_NAME'" >&2
    exit 1
}

CONTAINER_NAME=$(docker inspect --format '{{.Name}}' "$CONTAINER_ID" | sed 's|^/||')

# Open VS Code attached to the running dev container at the project path
if command -v code &>/dev/null; then
    HEX=$(printf '{"containerName":"%s"}' "$CONTAINER_NAME" | xxd -p | tr -d '\n')
    code --folder-uri "vscode-remote://attached-container+${HEX}/home/dev/${PROJECT_NAME}" 2>/dev/null || true
else
    echo "Note: 'code' not found, skipping VS Code launch" >&2
fi

# Drop into interactive shell in the same container
exec docker exec -it "$CONTAINER_NAME" /bin/bash
