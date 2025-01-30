###>>>~~~                         ~~~<<<###
# CPU version of chatthy and dependencies #
###>>>~~~                         ~~~<<<###

# faiss-cpu build fails on 3.13
ARG PYTHON_VERSION_SHORT="3.12"

FROM python:${PYTHON_VERSION_SHORT}-bookworm

# Using FROM resets ARG.
ARG PYTHON_VERSION_SHORT

LABEL ltd.agalmic.name="chatthy-server"

# update the debian image
RUN DEBIAN_FRONTEND=noninteractive \
    apt-get update && \
    apt-get -y upgrade && \
    apt-get -y install --no-install-recommends \
    build-essential swig \
    libmagic-dev \
    terminfo foot-terminfo \
    zlib1g-dev libssl-dev neovim && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
    wheel setuptools \
    "hyjinx[dev]"

# CPU pytorch
RUN pip install \
    --no-cache-dir \
    --index-url https://download.pytorch.org/whl/cpu \
    torch

RUN pip install --no-cache-dir faiss-cpu

RUN pip install --no-cache-dir \
    deepmultilingualpunctuation \
    trag fvdb \
    "chatthy[server] @ git+https://github.com/atisharma/chatthy"

# EXPECTED FILES TO SET IN DOCKER-COMPOSE
# /root/.config/fvdb/config.toml
# /root/.config/chatthy/server.toml (for server)
# /root/.config/chatthy/client.toml (for client)

EXPOSE 23456/tcp
ENTRYPOINT ["/usr/local/bin/chatthy"]
CMD ["serve"]
