# dev-env

Rocky Linux dev container with GCC 14, CMake, Ninja, Valgrind, and Rust. Persistent shell history across sessions.

## Usage

```bash
# Start a project
./dev.sh <project-dir>

# Shut down a project
./dev.sh --shutdown <project-dir>
```

Examples:

```bash
./dev.sh ~/projects/myapp     # mount ~/projects/myapp into the container
./dev.sh .                    # mount current directory

./dev.sh --shutdown ~/projects/myapp
```

On startup the script:
1. Starts the container (and any project-level services) detached
2. Opens VS Code attached to the container at the project path
3. Drops into an interactive shell

## Project compose files

If your project has a `docker-compose.yml`, it is automatically merged into the session. Services share a network with the dev container, so you can reach them by service name (e.g. `psql -h postgres`).

## Persistence

`/home/dev/persist` is a named Docker volume — shell history and anything else stored there survives container restarts.

## Authentication

### SSH keys

SSH agent from the host is forwarded into the container. Make sure your keys are added to the agent on the host:

```bash
ssh-add ~/.ssh/id_ed25519
```

This is automatically done if you add to your `~/.bashrc`:

```bash
eval $(ssh-agent -s)
ssh-add ~/.ssh/id_ed25519 2>/dev/null || true
```

Git operations in the container will use your host's SSH keys. For full github CLI usage, add a PAT into your .bashrc/.zshrc as GITHUB_TOKEN=xxxxxxx. The CLI will be availabe in the container

## Personal bashrc

`~/.bashrc` on the host is mounted as `~/.bashrc.personal` inside the container and sourced at shell startup. Container settings take precedence.

## MCP servers (Claude Code)

MCP servers run on the WSL2 host and are exposed to both the host and the container via `mcp-proxy`. `dev.sh` starts the proxy automatically, but you must do a one-time setup to register the servers with Claude Code.

### How it works

```
mcp-servers.json        — defines stdio-based MCP servers (e.g. docker.exe mcp gateway run)
mcp-proxy.sh            — wraps them in an HTTP server on port 8808
~/.claude.json          — tells Claude Code where to find each server
```

- Claude Code on WSL2 reaches the proxy at `http://localhost:8808`
- Claude Code inside the container reaches it at `http://host.docker.internal:8808`

### One-time setup

**1. Add the servers to `~/.claude.json` on the host:**

```bash
# Used by Claude Code running inside the dev container
claude mcp add --scope user --transport sse docker-mcp-container \
  http://host.docker.internal:8808/servers/docker/sse

# Used by Claude Code running directly in WSL2
claude mcp add --scope user --transport sse docker-mcp-local \
  http://localhost:8808/servers/docker/sse
```

**2. Verify the entries were written:**

```bash
claude mcp list
```

You should see both `docker-mcp-container` and `docker-mcp-local`.

**3. Set up the SessionStart hook** so Claude Code auto-starts the proxy on WSL2 (add to `~/.claude/settings.json`):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "test -f /home/<your-user>/dev_env/mcp-proxy.sh && { /home/<your-user>/dev_env/mcp-proxy.sh --status &>/dev/null || /home/<your-user>/dev_env/mcp-proxy.sh --bg; } || true"
          }
        ]
      }
    ]
  }
}
```

Replace `<your-user>` with your WSL2 username. The `test -f` guard makes the hook a no-op inside the container (where the host path doesn't exist).

### Adding a new MCP server

1. Add it to `mcp-servers.json`:

```json
{
  "mcpServers": {
    "docker": {
      "command": "docker.exe",
      "args": ["mcp", "gateway", "run"]
    },
    "my-server": {
      "command": "my-server-binary",
      "args": ["--flag"]
    }
  }
}
```

2. Restart the proxy:

```bash
./mcp-proxy.sh --stop && ./mcp-proxy.sh --bg
```

3. Register the new endpoint with Claude Code:

```bash
claude mcp add --scope user --transport sse my-server-container \
  http://host.docker.internal:8808/servers/my-server/sse

claude mcp add --scope user --transport sse my-server-local \
  http://localhost:8808/servers/my-server/sse
```

### Manual proxy management

```bash
./mcp-proxy.sh --status   # check if running and list endpoints
./mcp-proxy.sh --bg       # start in background
./mcp-proxy.sh --stop     # stop
./mcp-proxy.sh            # start in foreground (for debugging)
```
