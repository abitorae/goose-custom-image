FROM ghcr.io/astral-sh/uv:latest AS uv
FROM ghcr.io/aaif-goose/goose:latest

COPY --from=uv /uv /uvx /usr/local/bin/

ENV UV_CACHE_DIR=/home/goose/.cache/uv \
    UV_PYTHON_INSTALL_DIR=/home/goose/.local/share/uv/python \
    UV_LINK_MODE=copy

RUN uv --version && uvx --version
