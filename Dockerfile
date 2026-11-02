# goose custom image: C / Java / Python 3.12 development environment.
#
# Base: official goose image, with uv/uvx, chromium (browser extension),
# and browser-harness. Layers add the native toolchains so recipes like
# code-workflow (python3 -m pytest) and chores-workflow run inside.
#
# Python is unified on 3.12 (system + uv default) to avoid an mcp-server-fetch
# / anyio BrokenPipeError that triggers on Python 3.15 when a stdio client
# disconnects before the server finishes initialising.
#
# Build: docker build -t goose-custom-image .
# Run:   docker run --rm -it goose-custom-image

FROM ghcr.io/astral-sh/uv:latest AS uv
FROM ghcr.io/aaif-goose/goose:latest

# Bring the static uv + uvx binaries into the base image.
COPY --from=uv /uv /uvx /bin/

USER root

# Prepare per-user dirs owned by goose so uv / goose cache + tool dirs
# are writable when the session drops privileges.
RUN mkdir -p /home/goose/.local/share \
             /home/goose/.local/state \
             /home/goose/.cache/uv \
    && chown -R goose:goose /home/goose/.local \
    && chown -R goose:goose /home/goose/.cache

# Headless browser runtime for the browser extension.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         chromium \
         ca-certificates \
         fonts-liberation \
         libnss3 libatk-bridge2.0-0 libxkbcommon0 libgbm1 libasound2 \
    && rm -rf /var/lib/apt/lists/* \
    && chromium --version

# C toolchain: compile + build native code (code-workflow, chores-workflow).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         gcc g++ libc6-dev make cmake \
    && rm -rf /var/lib/apt/lists/*

# Java toolchain: default-jdk-headless gives OpenJDK 17 + javac.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         default-jdk-headless \
    && rm -rf /var/lib/apt/lists/*

# Python 3.12 (system): unify on 3.12 to avoid mcp-server-fetch / anyio
# BrokenPipeError that triggers on Python 3.15 when client disconnects early.
# python3/python symlinks point at 3.12 so every toolchain shares one version.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         python3.12 python3.12-venv python3.12-dev python3-pip \
    && ln -sf /usr/bin/python3.12 /usr/local/bin/python3 \
    && ln -sf /usr/bin/python3.12 /usr/local/bin/python \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 100 \
    && rm -rf /var/lib/apt/lists/*

# Python test tooling: required by code-workflow test_cmd (python3 -m pytest).
RUN pip3 install --break-system-packages pytest

# Browser-automation helper, pinned to the same 3.12 interpreter.
RUN uv tool install --python 3.12 --upgrade --force browser-harness \
    && ln -sf /home/goose/.local/bin/browser-harness /usr/local/bin/browser-harness

# Point uv at the goose-owned cache/tool dirs and use copy link mode.
ENV UV_CACHE_DIR=/home/goose/.cache/uv \
    UV_PYTHON_INSTALL_DIR=/home/goose/.local/share/uv/python \
    UV_TOOL_DIR=/home/goose/.local/share/uv/tools \
    UV_LINK_MODE=copy

# Build-time self-check: fail the build if any toolchain is missing or the
# python3/python symlinks resolved to the wrong interpreter.
# Verify toolchains
RUN python3 --version \
    && gcc --version | head -1 \
    && make --version | head -1 \
    && javac -version

USER goose
