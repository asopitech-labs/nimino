ARG NIM_IMAGE=nimlang/nim:latest
FROM ${NIM_IMAGE}

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      git \
      pkg-config \
      libgtk-4-dev \
      libwebkitgtk-6.0-dev \
      xauth \
      xvfb \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
