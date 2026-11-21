# syntax=docker/dockerfile:1.4
#
# Custom goose image: official goose + C/C++ toolchain + Python dev +
# headless browser automation (browser-harness skill + headless-shell).
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
#     uv tool install --python 3.11 --force browser-harness
#     browser-harness skill > <skills-dir>/browser-harness/SKILL.md
#   - chromedp/headless-shell: multi-arch image of chrome-headless-shell
#     (standalone binary, CDP-compatible, no GUI).
#     Chrome 132+: old headless is a separate binary "chrome-headless-shell".
#     CDP fully supported; extension system absent.
#
# Runtime: headless-shell starts in headless mode with CDP on 9222.
# browser-harness connects via BU_CDP_URL=http://localhost:9222.

# ---------------------------------------------------------------------------
# Stage 1: uv binaries from the official distroless image (uv Docker guide).
# ---------------------------------------------------------------------------
FROM ghcr.io/astral-sh/uv:latest AS uv-bin

# ---------------------------------------------------------------------------
# Stage 2: chrome-headless-shell binary from the chromedp image.
# The chromedp image contains the binary at /headless-shell/headless-shell.
# ---------------------------------------------------------------------------
FROM chromedp/headless-shell:latest AS hs-bin

# ---------------------------------------------------------------------------
# Final stage: official goose image
# ---------------------------------------------------------------------------
FROM ghcr.io/aaif-goose/goose:latest

# uv/uvx from the distroless image (recommended by the uv Docker guide).
# NOTE: for reproducible builds, pin a version:
#   COPY --from=ghcr.io/astral-sh/uv:0.13.9 /uv /uvx /bin/
COPY --from=uv-bin /uv /uvx /bin/

# Extract chrome-headless-shell binary from the chromedp image.
# USER root is set for the apt-get below (goose cannot apt); COPY itself is
# performed by the builder and is independent of the active USER.
# glibc note: the chromedp image is built on trixie-slim (glibc 2.41); the
# binary must not reference GLIBC symbols newer than bookworm's 2.36.
# The build-time `headless-shell --version` check below fails the build if
# it does.
EXPOSE 9222
USER root
COPY --from=hs-bin /headless-shell/headless-shell /usr/local/bin/headless-shell

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

# browser-harness CDP endpoint. headless-shell runs on localhost:9222.
# Setting BU_CDP_URL tells browser-harness to use "cdp" mode
# (BROWSER_KIND = "cdp" when BU_CDP_URL is set), not "local" mode
# which requires a running desktop Chrome with remote-debugging enabled.
ENV BU_CDP_URL=http://localhost:9222

# ---------------------------------------------------------------------------
# System packages (Debian bookworm latest): C/C++ + Python dev + fonts.
# Single layer; --no-install-recommends keeps the image lean; apt lists
# removed so no package metadata survives in the image.
#
# NOTE: chromium apt package is NO LONGER installed. Instead the
# chrome-headless-shell binary is COPY'd from the chromedp stage above.
# headless-shell is a standalone binary; it needs glibc, fonts
# (fonts-liberation below), and the NSS/NSPR/expat libs installed below.
# ---------------------------------------------------------------------------
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        # C/C++ toolchain (gcc/g++ 12, make 4.3, cmake 3.25). libc6-dev is a
        # transitive dep of g++ and is pulled automatically.
        gcc g++ make cmake \
        # Python dev (python3.11, venv, dev headers, pip)
        python3 python3-venv python3-dev python3-pip \
        # Minimal fonts so rendered pages/screenshots contain text
        fonts-liberation \
        # headless-shell runtime libraries (chromedp Containerfile deps):
        # libnspr4, libnss3: NSS/NSPR for TLS/certificate handling
        # libexpat1: XML parsing
        # libfontconfig1: font rendering
        # libuuid1: UUID generation
        # curl: CDP readiness probe in entrypoint.sh
        # tini: init process to reap zombie headless-shell child (chromedp docs warn about zombies).
        # -g flag (used in ENTRYPOINT below) forwards signals to the whole process group
        # so headless-shell gets SIGTERM on container stop, not just goose.
        curl libnspr4 libnss3 libexpat1 libfontconfig1 libuuid1 tini \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# uv tools (headless browser automation + web fetch) installed as uv tools.
# Runs as the goose user so all uv state lands goose-owned (no chown needed).
# `--python 3.11` reuses the system Python 3.11 already installed above
# (browser-harness requires >=3.11; mcp-server-fetch requires >=3.10), so uv
# resolves against the system 3.11.2 without a managed download, avoiding a
# ~50MB managed CPython download.
# NOTE: if a future tool bumps its requires-python above the system Python,
# uv will fall back to a managed CPython download. Pin uv image tag for
# reproducible builds if needed.
# ddgs (web-search skill backend) is pre-installed so temporary containers
# do not re-download it on every session.
# ---------------------------------------------------------------------------
USER goose
# `--python 3.11` reuses the system Python 3.11 installed via apt above,
# avoiding a managed CPython download (~50MB). browser-harness supports
# >=3.11; mcp-server-fetch requires >=3.10; ddgs has no minimum Python
# floor. 3.12 is preferred by upstream browser-harness but 3.11 is the
# system version already present in the image, so no extra Python is pulled.
RUN uv tool install --python 3.11 --force browser-harness && \
    uv tool install --python 3.11 --force mcp-server-fetch && \
    uv tool install --python 3.11 --force ddgs && \
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
    test -x /home/goose/.local/bin/mcp-server-fetch && \
    test -x /home/goose/.local/bin/ddgs && \
    gcc --version | head -n1 && \
    g++ --version | head -n1 && \
    make --version | head -n1 && \
    cmake --version | head -n1 && \
    python3 --version && \
    python3 -m pip --version && \
    headless-shell --version && \
    test -s /home/goose/.agents/skills/browser-harness/SKILL.md

# ---------------------------------------------------------------------------
# Entrypoint script: start headless-shell in the background with CDP
# on port 9222, wait for the port to be ready, then exec goose.
# headless-shell is chrome-headless-shell: a standalone binary that still
# needs --no-sandbox in a non-root container without a seccomp profile
# (the official chromedp run.sh uses --no-sandbox for the same reason).
# --disable-dev-shm-usage is still recommended because /dev/shm defaults to
# 64 MB in most containers, too small for Chromium rendering.
# ---------------------------------------------------------------------------
COPY --chmod=0755 entrypoint.sh /entrypoint.sh

USER goose

# Keep the official non-root user; WORKDIR inherited from base image.
WORKDIR /home/goose

# tini wraps the entrypoint as PID 1 (reaps zombie headless-shell children).
# -g: forward signals to the process group so headless-shell gets SIGTERM
# too, not just goose. Without -g, headless-shell is killed abruptly when
# the container stops.
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/entrypoint.sh"]

# Runtime health check: probe the CDP endpoint to confirm headless-shell is
# actually serving (not just that the binary exists). goose --version and
# headless-shell --version confirm the core binaries are reachable.
HEALTHCHECK --interval=30s --timeout=15s --start-period=30s --retries=3 \
    CMD curl -sf http://localhost:9222/json/version && goose --version && headless-shell --version && browser-harness --version

LABEL org.opencontainers.image.title="goose-custom" \
      org.opencontainers.image.description="goose + C/C++ + Python dev + headless browser (browser-harness + headless-shell)" \
      org.opencontainers.image.vendor="AAIF" \
      org.opencontainers.image.source="https://github.com/aaif-goose/goose"
