FROM ghcr.io/astral-sh/uv:latest AS uv
FROM ghcr.io/aaif-goose/goose:latest

COPY --from=uv /uv /uvx /bin/

USER root

RUN mkdir -p /home/goose/.local/share \
             /home/goose/.local/state \
             /home/goose/.cache/uv \
    && chown -R goose:goose /home/goose/.local \
    && chown -R goose:goose /home/goose/.cache

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         chromium \
         ca-certificates \
         fonts-liberation \
         libnss3 libatk-bridge2.0-0 libxkbcommon0 libgbm1 libasound2 \
    && rm -rf /var/lib/apt/lists/* \
    && chromium --version

RUN uv tool install --python 3.12 --upgrade --force browser-harness \
    && ln -sf /home/goose/.local/bin/browser-harness /usr/local/bin/browser-harness

ENV UV_CACHE_DIR=/home/goose/.cache/uv \
    UV_PYTHON_INSTALL_DIR=/home/goose/.local/share/uv/python \
    UV_TOOL_DIR=/home/goose/.local/share/uv/tools \
    UV_LINK_MODE=copy

USER goose
