ARG NIM_IMAGE=nimlang/nim:latest
FROM ${NIM_IMAGE}

ARG WEBVIEW2_SDK_VERSION=1.0.3967.48
ARG WEBVIEW2_SDK_SHA256=c66357ac7f324ec9bcafe5241706a023b4122d8c22300c31de4b0eb220db689e
ARG APPIMAGETOOL_VERSION=1.9.1
ARG APPIMAGETOOL_X86_64_SHA256=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      gcc-mingw-w64-x86-64 \
      git \
      nsis \
      pkg-config \
      rpm \
      desktop-file-utils \
      squashfs-tools \
      libgtk-4-dev \
      libwebkitgtk-6.0-dev \
      unzip \
      xauth \
      xvfb \
    && rm -rf /var/lib/apt/lists/*

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

WORKDIR /workspace
