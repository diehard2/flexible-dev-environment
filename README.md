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
