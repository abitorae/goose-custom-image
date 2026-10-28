FROM ghcr.io/astral-sh/uv:latest AS uv
FROM ghcr.io/aaif-goose/goose:latest

COPY --from=uv /uv /uvx /bin/

USER root

RUN mkdir -p /home/goose/.local/share \
             /home/goose/.local/state \
             /home/goose/.cache/uv \
    && chown -R goose:goose /home/goose/.local \
    && chown -R goose:goose /home/goose/.cache

ENV UV_CACHE_DIR=/home/goose/.cache/uv \
    UV_PYTHON_INSTALL_DIR=/home/goose/.local/share/uv/python \
    UV_TOOL_DIR=/home/goose/.local/share/uv/tools \
    UV_LINK_MODE=copy

USER goose
