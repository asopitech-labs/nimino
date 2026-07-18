ARG NIM_IMAGE=nimlang/nim:latest
FROM ${NIM_IMAGE}

ARG WEBVIEW2_SDK_VERSION=1.0.3967.48
ARG WEBVIEW2_SDK_SHA256=c66357ac7f324ec9bcafe5241706a023b4122d8c22300c31de4b0eb220db689e

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      gcc-mingw-w64-x86-64 \
      git \
      pkg-config \
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

WORKDIR /workspace
