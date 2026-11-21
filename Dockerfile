# syntax=docker/dockerfile:1.4
#
# Custom goose image: official goose + C/C++ toolchain + Python dev +
# headless browser automation (browser-harness skill).
#
# Sources / recommendations followed:
#   - Official goose image: ghcr.io/aaif-goose/goose:latest
#     (debian:bookworm-slim, non-root user `goose` UID 1000, binary at
#      /usr/local/bin/goose, config at /home/goose/.config/goose)
#   - Official custom-image pattern (goose BUILDING_DOCKER.md):
#     FROM ghcr.io/aaif-goose/goose:latest -> USER root -> apt-get -> USER goose
#   - uv Docker guide (docs.astral.sh/uv/guides/integration/docker):
#     COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
#   - browser-harness install.md (github.com/browser-use/browser-harness):
#     uv tool install --python 3.12 --upgrade --force browser-harness
#     browser-harness skill > <skills-dir>/browser-harness/SKILL.md
#
# Runtime note: headless Chromium in a container must be started with
# --no-sandbox and usually --disable-dev-shm-usage (/dev/shm defaults to
# 64MB, too small for Chromium). These are runtime flags, not build-time.

# ---------------------------------------------------------------------------
# Stage 1: uv binaries from the official distroless image (uv Docker guide).
# The distroless image contains only the uv/uvx static binaries.
# ---------------------------------------------------------------------------
FROM ghcr.io/astral-sh/uv:latest AS uv-bin

# ---------------------------------------------------------------------------
# Final stage: official goose image
# ---------------------------------------------------------------------------
FROM ghcr.io/aaif-goose/goose:latest

# uv/uvx from the distroless image (recommended by the uv Docker guide).
# NOTE: for reproducible builds, pin a version, e.g. ghcr.io/astral-sh/uv:0.13.9
COPY --from=uv-bin /uv /uvx /bin/

# Rely on uv's documented default storage paths. For the non-root `goose`
# user these already resolve under ~ (XDG fallback to $HOME):
#   UV_CACHE_DIR         -> ~/.cache/uv
#   UV_TOOL_DIR          -> ~/.local/share/uv/tools
#   UV_TOOL_BIN_DIR      -> ~/.local/bin
#   UV_PYTHON_INSTALL_DIR -> ~/.local/share/uv/python
# All under /home/goose, so goose-owned (no chown needed).
#
# Only PATH needs overriding: `uv tool install` drops browser-harness into
# ~/.local/bin, which is not on the inherited PATH.
ENV PATH="/home/goose/.local/bin:${PATH}"

# ---------------------------------------------------------------------------
# System packages (Debian bookworm latest): C/C++ + Python dev + Chromium.
# Single layer; --no-install-recommends keeps the image lean; apt lists
# removed so no package metadata survives in the image.
# ---------------------------------------------------------------------------
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        # C/C++ toolchain (gcc/g++ 12, make 4.3, cmake 3.25). libc6-dev is a
        # transitive dep of g++ and is pulled automatically.
        gcc g++ make cmake \
        # Python dev (python3.11, venv, dev headers, pip)
        python3 python3-venv python3-dev python3-pip \
        # Headless browser (chromium 120+; run with --no-sandbox in containers)
        chromium \
        # Minimal fonts so rendered pages/screenshots contain text
        fonts-liberation \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# browser-harness (headless browser automation) installed as a uv tool.
# Runs as the goose user so all uv state lands goose-owned (no chown needed).
# `--python 3.11` reuses the system Python 3.11 already installed above
# (package requires >=3.11), avoiding a ~50MB managed CPython 3.12 download.
# ---------------------------------------------------------------------------
USER goose
RUN uv tool install --python 3.11 --upgrade --force browser-harness && \
    # Register the skill where goose discovers skills. `browser-harness skill`
    # already emits the full SKILL.md including its YAML frontmatter (name +
    # description), so redirect it directly — do NOT prepend another
    # frontmatter block. (goose docs: ~/.agents/skills/<name>/SKILL.md)
    mkdir -p /home/goose/.agents/skills/browser-harness && \
    browser-harness skill > /home/goose/.agents/skills/browser-harness/SKILL.md && \
    # Build-time verification: every toolchain component must work
    goose --version && \
    uv --version && \
    browser-harness --version && \
    gcc --version | head -n1 && \
    g++ --version | head -n1 && \
    make --version | head -n1 && \
    cmake --version | head -n1 && \
    python3 --version && \
    python3 -m pip --version && \
    chromium --version && \
    test -s /home/goose/.agents/skills/browser-harness/SKILL.md

# Keep the official non-root user; ENTRYPOINT ["/usr/local/bin/goose"] and
# CMD ["--help"] are inherited from the base image.
WORKDIR /home/goose

# Runtime health check: core goose + browser toolchain must respond.
HEALTHCHECK --interval=30s --timeout=15s --start-period=10s --retries=3 \
    CMD goose --version && chromium --version && browser-harness --version

LABEL org.opencontainers.image.title="goose-custom" \
      org.opencontainers.image.description="goose + C/C++ + Python dev + headless browser (browser-harness)" \
      org.opencontainers.image.vendor="AAIF" \
      org.opencontainers.image.source="https://github.com/aaif-goose/goose"
