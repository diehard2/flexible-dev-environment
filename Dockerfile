FROM rockylinux/rockylinux:10

# Update the system and install basic utilities
RUN dnf -y update && \
    dnf -y install \
    dnf-plugins-core \
    curl \
    nano \
    git \
    sudo \
    && dnf clean all

# Enable PowerTools/CRB repo and install dev toolchain
RUN dnf config-manager --set-enabled crb && \
    dnf -y install \
    gcc-toolset-14 \
    gcc-toolset-14-binutils \
    gcc-toolset-14-gdb \
    valgrind \
    cmake \
    ninja-build \
    autoconf \
    automake \
    && dnf clean all

# Install GitHub CLI
RUN dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo && \
    dnf -y install gh && \
    dnf clean all

# Install Node.js (LTS) and Claude Code CLI
RUN curl -fsSL https://rpm.nodesource.com/setup_24.x | bash - && \
    dnf -y install nodejs && \
    dnf clean all && \
    npm install -g @anthropic-ai/claude-code

# Build gimli addr2line, register with update-alternatives, then remove toolchain
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
    . /root/.cargo/env && \
    cargo install addr2line --features bin && \
    cp /root/.cargo/bin/addr2line /usr/local/bin/addr2line-gimli && \
    rm -rf /root/.cargo /root/.rustup && \
    update-alternatives --install /usr/bin/addr2line addr2line /usr/local/bin/addr2line-gimli 100 && \
    { update-alternatives --install /usr/bin/addr2line addr2line /usr/bin/addr2line-binutils 50 2>/dev/null || true; }

# Create dev user and configure sudo
RUN useradd -m -s /bin/bash dev && \
    echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/dev && \
    chmod 0440 /etc/sudoers.d/dev

# Create persistent storage directory for history
RUN mkdir -p /home/dev/persist && chown dev:dev /home/dev/persist

# Pre-populate GitHub known_hosts so git/ssh doesn't prompt on first use
RUN mkdir -p /home/dev/.ssh && \
    ssh-keyscan github.com >> /home/dev/.ssh/known_hosts && \
    chown -R dev:dev /home/dev/.ssh && \
    chmod 700 /home/dev/.ssh && \
    chmod 600 /home/dev/.ssh/known_hosts

# Entrypoint for non-interactive setup (gh auth, etc.)
COPY --chown=dev:dev entrypoint.sh /home/dev/entrypoint.sh
RUN chmod +x /home/dev/entrypoint.sh

# Configure .bashrc
RUN cat >> /home/dev/.bashrc << 'EOF'

# Source personal bashrc if it exists
[[ -f ~/.bashrc.personal ]] && source ~/.bashrc.personal

# Toolset
source scl_source enable gcc-toolset-14
export CC=$(which gcc)
export CXX=$(which g++)

# Persistent history (mount a volume at /home/dev/persist)
export HISTFILE=/home/dev/persist/.bash_history
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTTIMEFORMAT="%F %T  "
shopt -s histappend
PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

# Useful aliases
alias ll='ls -alF'
alias la='ls -A'
alias grep='grep --color=auto'
EOF

# Volume for persistent history
VOLUME ["/home/dev/persist"]

# Set the working directory to dev user's home
WORKDIR /home/dev

# Set dev as the default user
USER dev

ENTRYPOINT ["/home/dev/entrypoint.sh"]
CMD ["/bin/bash"]
