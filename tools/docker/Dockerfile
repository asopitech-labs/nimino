# Keep the compiler/toolchain reproducible. Updating Nim is an intentional
# dependency change that must update this digest.
ARG NIM_IMAGE=docker.io/nimlang/nim:latest@sha256:62428daa4a39baeb6f5e429a9c2ca3cee27a80ef880fe6e1bf3e29cc2296ac1b
FROM ${NIM_IMAGE} AS dev

ARG WEBVIEW2_SDK_VERSION=1.0.3967.48
ARG WEBVIEW2_SDK_SHA256=c66357ac7f324ec9bcafe5241706a023b4122d8c22300c31de4b0eb220db689e
ARG APPIMAGETOOL_VERSION=1.9.1
ARG APPIMAGETOOL_X86_64_SHA256=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
ARG LINUXDEPLOY_VERSION=1-alpha-20240109-1
ARG LINUXDEPLOY_X86_64_SHA256=c86d6540f1df31061f02f539a2d3445f8d7f85cc3994eee1e74cd1ac97b76df0

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      gcc-mingw-w64-x86-64 \
      git \
      nsis \
      flatpak \
      flatpak-builder \
      ostree \
      patchelf \
      pax-utils \
      pkg-config \
      python3 \
      rpm \
      desktop-file-utils \
      file \
      squashfs-tools \
      bubblewrap \
      xdg-dbus-proxy \
      libgtk-4-dev \
      libssl-dev \
      libwebkitgtk-6.0-dev \
      libgdk-pixbuf2.0-bin \
      minisign \
      msitools \
      wixl \
      unzip \
      zip \
      xauth \
      xvfb \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/gdk-pixbuf-query-loaders \
      /usr/local/bin/gdk-pixbuf-query-loaders

RUN curl --fail --location --retry 3 --silent --show-error \
      --output /tmp/Microsoft.Web.WebView2.${WEBVIEW2_SDK_VERSION}.nupkg \
      https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/${WEBVIEW2_SDK_VERSION}/microsoft.web.webview2.${WEBVIEW2_SDK_VERSION}.nupkg \
    && echo "${WEBVIEW2_SDK_SHA256}  /tmp/Microsoft.Web.WebView2.${WEBVIEW2_SDK_VERSION}.nupkg" | sha256sum --check --status \
    && install -d /opt/nimino/webview2/x64 \
    && unzip -p /tmp/Microsoft.Web.WebView2.${WEBVIEW2_SDK_VERSION}.nupkg build/native/x64/WebView2Loader.dll \
      > /opt/nimino/webview2/x64/WebView2Loader.dll \
    && unzip -p /tmp/Microsoft.Web.WebView2.${WEBVIEW2_SDK_VERSION}.nupkg LICENSE.txt \
      > /opt/nimino/webview2/LICENSE.txt \
    && unzip -p /tmp/Microsoft.Web.WebView2.${WEBVIEW2_SDK_VERSION}.nupkg NOTICE.txt \
      > /opt/nimino/webview2/NOTICE.txt \
    && test -s /opt/nimino/webview2/x64/WebView2Loader.dll \
    && rm /tmp/Microsoft.Web.WebView2.${WEBVIEW2_SDK_VERSION}.nupkg

# AppImage/appimagetool publishes its Linux tool as an AppImage.  The immutable
# versioned release URL and GitHub release asset digest are both pinned here.
# The wrapper extracts the tool at execution time because the Docker test
# container intentionally does not mount FUSE.
RUN curl --fail --location --retry 3 --silent --show-error \
      --output /tmp/appimagetool-x86_64.AppImage \
      https://github.com/AppImage/appimagetool/releases/download/${APPIMAGETOOL_VERSION}/appimagetool-x86_64.AppImage \
    && echo "${APPIMAGETOOL_X86_64_SHA256}  /tmp/appimagetool-x86_64.AppImage" | sha256sum --check --status \
    && install -d /opt/nimino/appimagetool \
    && install -m 0755 /tmp/appimagetool-x86_64.AppImage /opt/nimino/appimagetool/appimagetool-x86_64.AppImage \
    && printf '%s\n' '#!/bin/sh' 'exec env APPIMAGE_EXTRACT_AND_RUN=1 ARCH=x86_64 /opt/nimino/appimagetool/appimagetool-x86_64.AppImage "$@"' \
      > /usr/local/bin/appimagetool \
    && chmod 0755 /usr/local/bin/appimagetool \
    && rm /tmp/appimagetool-x86_64.AppImage

# linuxdeploy is pinned to a dated release rather than the mutable
# `continuous` channel.  APPIMAGE_EXTRACT_AND_RUN keeps Docker independent of
# FUSE while retaining linuxdeploy's normal CLI contract.
RUN curl --fail --location --retry 3 --silent --show-error \
      --output /tmp/linuxdeploy-x86_64.AppImage \
      https://github.com/linuxdeploy/linuxdeploy/releases/download/${LINUXDEPLOY_VERSION}/linuxdeploy-x86_64.AppImage \
    && echo "${LINUXDEPLOY_X86_64_SHA256}  /tmp/linuxdeploy-x86_64.AppImage" | sha256sum --check --status \
    && install -d /opt/nimino/linuxdeploy \
    && install -m 0755 /tmp/linuxdeploy-x86_64.AppImage /opt/nimino/linuxdeploy/linuxdeploy-x86_64.AppImage \
    && printf '%s\n' '#!/bin/sh' 'exec env APPIMAGE_EXTRACT_AND_RUN=1 /opt/nimino/linuxdeploy/linuxdeploy-x86_64.AppImage "$@"' \
      > /usr/local/bin/linuxdeploy \
    && chmod 0755 /usr/local/bin/linuxdeploy \
    && rm /tmp/linuxdeploy-x86_64.AppImage

# The generic Windows host uses Nim's std/re, which loads pcre64.dll at
# process start.  Stage the official Nim Windows runtime DLL so packagers can
# place it beside the cross-compiled host executable.  The archive URL is not
# versioned upstream, so the digest pin makes any silent content change fail
# this build loudly.
ARG NIM_WINDOWS_DLLS_SHA256=4b20b0fc775d2cfece0c1a09d4ec0bdbcd01d257ce8d556d9a8a88e6c4cd6961
RUN curl --fail --location --retry 3 --silent --show-error \
      --output /tmp/nim-windows-dlls.zip \
      https://nim-lang.org/download/dlls.zip \
    && echo "${NIM_WINDOWS_DLLS_SHA256}  /tmp/nim-windows-dlls.zip" | sha256sum --check --status \
    && install -d /opt/nimino/windows-dlls \
    && unzip -p /tmp/nim-windows-dlls.zip pcre64.dll \
      > /opt/nimino/windows-dlls/pcre64.dll \
    && test -s /opt/nimino/windows-dlls/pcre64.dll \
    && rm /tmp/nim-windows-dlls.zip

# Debian 13 dropped legacy PCRE1, and EL10-family distributions never ship
# it, but Nim's std/re loads libpcre at process start.  Build a static,
# PIC-enabled PCRE so the Linux host links it in and runs without a system
# libpcre.  The tarball digest is pinned; 8.45 is the final PCRE1 release.
ARG PCRE_VERSION=8.45
ARG PCRE_SHA256=4dae6fdcd2bb0bb6c37b5f97c33c2be954da743985369cddac3546e3218bffb8
RUN curl --fail --location --retry 3 --silent --show-error \
      --output /tmp/pcre-${PCRE_VERSION}.tar.bz2 \
      https://downloads.sourceforge.net/project/pcre/pcre/${PCRE_VERSION}/pcre-${PCRE_VERSION}.tar.bz2 \
    && echo "${PCRE_SHA256}  /tmp/pcre-${PCRE_VERSION}.tar.bz2" | sha256sum --check --status \
    && tar -xjf /tmp/pcre-${PCRE_VERSION}.tar.bz2 -C /tmp \
    && cd /tmp/pcre-${PCRE_VERSION} \
    && ./configure --prefix=/opt/nimino/pcre --disable-shared --enable-static \
      --enable-utf --enable-unicode-properties --with-pic >/dev/null \
    && make -j"$(nproc)" >/dev/null \
    && make install >/dev/null \
    && test -s /opt/nimino/pcre/lib/libpcre.a \
    && rm -rf /tmp/pcre-${PCRE_VERSION} /tmp/pcre-${PCRE_VERSION}.tar.bz2

# Run as a normal user. The container mounts the repository at /workspace, so
# anything a build writes there lands on the host with the container's owner:
# building as root leaves files the developer cannot delete without sudo.
# The uid must match the owner of the checkout the caller bind-mounts, not a
# fixed account baked into the image: a chown inside the image is replaced by
# the bind mount, so a mismatch fails at the first write to /workspace. A
# developer passes their own id, and a GitHub-hosted runner checks out as uid
# 1001, so both are build arguments rather than constants.
ARG NIMINO_UID=1000
ARG NIMINO_GID=1000
## The home directory is named for the project rather than for the base
## image's `node` account, because that account only exists at uid 1000 and
## the build user is whatever the caller passed.
ENV HOME=/home/nimino
RUN install -d -o ${NIMINO_UID} -g ${NIMINO_GID} /workspace \
  ## nim writes compilation caches under .cache/nim and nimble keeps its
  ## package index under .nimble; both are created on first use, so the
  ## parent directories have to belong to the build user.
  && install -d -o ${NIMINO_UID} -g ${NIMINO_GID} ${HOME} \
  && install -d -o ${NIMINO_UID} -g ${NIMINO_GID} ${HOME}/.cache \
  && install -d -o ${NIMINO_UID} -g ${NIMINO_GID} ${HOME}/.cache/nim \
  && install -d -o ${NIMINO_UID} -g ${NIMINO_GID} ${HOME}/.cache/nimble \
  && install -d -o ${NIMINO_UID} -g ${NIMINO_GID} ${HOME}/.nimble \
  ## Nimble writes its package index beside the compiler, and the toolchain
  ## itself is read-only for a normal user, so hand both to the build user.
  && chown -R ${NIMINO_UID}:${NIMINO_GID} /opt/nim

USER ${NIMINO_UID}:${NIMINO_GID}

WORKDIR /workspace

## Build the CLI in the development image, then ship it from a base that
## carries only what running it needs. The dev stage holds the Nim compiler,
## the cross toolchain, and the GUI headers: none of that is used by a caller
## who only wants to wrap a URL.
FROM dev AS build
USER root
COPY . /src
WORKDIR /src
RUN export PATH=/opt/nim/bin:$PATH \
  && nimble buildPackCli \
  && install -D -m 0755 /tmp/nimino /out/usr/local/bin/nimino \
  && /out/usr/local/bin/nimino --help 2>&1 | grep -q 'usage: nimino pack'

## The distribution image. nimino itself links against libc alone -- Nim
## statically links the rest -- but it shells out to the generator for each
## package format, and loads OpenSSL at run time to fetch icons and hosts.
FROM debian:13-slim AS dist

ARG NIMINO_UID=1000
ARG NIMINO_GID=1000

RUN apt-get update \
  && apt-get install --no-install-recommends -y \
    ca-certificates \
    curl \
    desktop-file-utils \
    dpkg-dev \
    libssl3 \
    nsis \
    rpm \
    unzip \
    msitools \
  && rm -rf /var/lib/apt/lists/* \
  && groupadd -g ${NIMINO_GID} nimino \
  && useradd -u ${NIMINO_UID} -g ${NIMINO_GID} -m -s /bin/bash nimino \
  && install -d -o ${NIMINO_UID} -g ${NIMINO_GID} /work \
  ## The caller mounts their own directory here and must run as the account
  ## that owns it, which is not always the uid this image was built for. The
  ## CLI caches downloaded hosts under $HOME, so HOME has to be a path any
  ## uid can write; a home created by useradd only serves the built-in one,
  ## and an unwritable HOME makes every run re-download the host.
  && install -d -m 1777 /home/nimino

COPY --from=build /out/usr/local/bin/nimino /usr/local/bin/nimino

USER ${NIMINO_UID}:${NIMINO_GID}
ENV HOME=/home/nimino
WORKDIR /work

ENTRYPOINT ["nimino"]
CMD ["--help"]
