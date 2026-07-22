# Keep the compiler/toolchain reproducible. Updating Nim is an intentional
# dependency change that must update this digest.
ARG NIM_IMAGE=nimlang/nim:latest@sha256:62428daa4a39baeb6f5e429a9c2ca3cee27a80ef880fe6e1bf3e29cc2296ac1b
FROM ${NIM_IMAGE}

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
      squashfs-tools \
      bubblewrap \
      xdg-dbus-proxy \
      libgtk-4-dev \
      libwebkitgtk-6.0-dev \
      libgdk-pixbuf2.0-bin \
      minisign \
      msitools \
      wixl \
      unzip \
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

WORKDIR /workspace
