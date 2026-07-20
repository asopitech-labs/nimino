.DEFAULT_GOAL := help

COMPOSE ?= docker compose
SERVICE ?= nimino-dev

.PHONY: help image nim-version nimble-version gtk-version webkit-version verify-env verify-webview2-header verify-webview2-profile-header shell test webview2-profile-ffi-spike pack-test pack-cli-test pack-bundle-test pack-archive-test linux-smoke core-linux-rpc-smoke core-linux-rpc-url-smoke core-linux-rpc-async-smoke windows-cross core-windows-cross wsl-host-cross wsl-host-smoke wsl-host-abnormal-smoke wsl-host-interactive wsl-host-popup-smoke wsl-client-smoke wsl-core-smoke wsl-core-rpc-url-smoke wsl-core-rpc-async-smoke check clean

help: ## 利用可能な固定手順を表示する

	@awk 'BEGIN {FS = ":.*##"}; /^[a-zA-Z][a-zA-Z0-9_-]*:.*##/ {printf "  %-16s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

image: ## Nim/GTK/WebKitGTK開発イメージをビルドする

	$(COMPOSE) build $(SERVICE)

nim-version: image ## コンテナ内のNimバージョンを確認する

	$(COMPOSE) run --rm $(SERVICE) nim --version

nimble-version: image ## コンテナ内のNimbleバージョンを確認する

	$(COMPOSE) run --rm $(SERVICE) nimble --version

gtk-version: image ## コンテナ内のGTK 4開発環境を確認する

	$(COMPOSE) run --rm $(SERVICE) pkg-config --modversion gtk4

webkit-version: image ## コンテナ内のWebKitGTK 6.0開発環境を確認する

	$(COMPOSE) run --rm $(SERVICE) pkg-config --modversion webkitgtk-6.0

verify-env: nim-version nimble-version gtk-version webkit-version ## M0のDocker開発環境を検証する

verify-webview2-header: image ## WebView2 permission/download APIの公式ヘッダーを検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'curl --fail --silent --show-error -L -o /tmp/webview2.nupkg https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/1.0.3967.48/microsoft.web.webview2.1.0.3967.48.nupkg && unzip -p /tmp/webview2.nupkg build/native/include/WebView2.h | grep -q ICoreWebView2PermissionRequestedEventHandler && unzip -p /tmp/webview2.nupkg build/native/include/WebView2.h | grep -q ICoreWebView2DownloadStartingEventHandler'

verify-windows-tray-abi: image ## MinGW Win32 SDKのNOTIFYICONDATAW ABIを検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc "printf '#include <windows.h>\\n#include <shellapi.h>\\ntypedef char notify_icon_data_w_size[(sizeof(NOTIFYICONDATAW) == 976) ? 1 : -1];\\n' | x86_64-w64-mingw32-gcc -x c -c -o /tmp/nimino-notify-icon-layout.o -"

verify-webview2-profile-header: image ## WebView2 Profile/CookieManager APIの公式ヘッダーを検証する

	$(COMPOSE) run --rm $(SERVICE) bash tools/bindings/verify_webview2_profile_header.sh

shell: image ## コンテナ内の対話shellを開く

	$(COMPOSE) run --rm $(SERVICE) bash

test: image ## M1以降のNimbleテストをコンテナ内で実行する

	$(COMPOSE) run --rm $(SERVICE) nimble test

webview2-profile-ffi-spike: image verify-webview2-profile-header ## WebView2 Profile/CookieManagerのprivate ABIスパイクを検証する

	$(COMPOSE) run --rm $(SERVICE) nimble testWebView2ProfileFfi
	$(COMPOSE) run --rm $(SERVICE) nimble testWindowsProfileFfiCross

pack-test: image ## nimino-packのmanifest解析テストをコンテナ内で実行する

	$(COMPOSE) run --rm $(SERVICE) nimble testPackManifest

pack-cli-test: image ## nimino pack CLIのmanifest検証を実行する

	$(COMPOSE) run --rm $(SERVICE) nimble buildPackCli

pack-bundle-test: image ## nimino packのmanifest bundle生成を検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; nimble buildPackCli && nimble testPackCli'

pack-archive-test: image ## Linux tar.gzとWindows zip形式のpack配布物を検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; nimble buildPackCli && nimble testPackCli && nimble testPackArchive'

linux-smoke: image ## Xvfb上でLinux GTK/WebKitGTKのM1 smoke testを実行する

	$(COMPOSE) run --rm -e WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 $(SERVICE) nimble testLinuxSmoke

core-linux-rpc-smoke: image ## Xvfb上でLinux core RPC bootstrap smoke testを実行する

	$(COMPOSE) run --rm -e WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 -e NIMINO_TEST_ALLOW_NATIVE_IN_WSL=1 $(SERVICE) nimble testCoreLinuxRpcSmoke

core-linux-rpc-url-smoke: image ## Xvfb上でLinux core URLのdocument-start RPCを実行する

	$(COMPOSE) run --rm -e WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 -e NIMINO_TEST_ALLOW_NATIVE_IN_WSL=1 $(SERVICE) nimble testCoreLinuxRpcUrlSmoke

core-linux-rpc-async-smoke: image ## Xvfb上でLinux core RPCのasync/timeout smoke testを実行する

	$(COMPOSE) run --rm -e WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 -e NIMINO_TEST_ALLOW_NATIVE_IN_WSL=1 $(SERVICE) nimble testCoreLinuxRpcAsyncSmoke

windows-cross: image verify-windows-tray-abi ## MinGWを使いWindows x64向けnative smokeバイナリをクロスコンパイルする

	$(COMPOSE) run --rm $(SERVICE) nimble testWindowsCross

core-windows-cross: image ## MinGWを使いWindows x64向けcore RPC facadeをクロスコンパイルする

	$(COMPOSE) run --rm $(SERVICE) nimble testCoreWindowsCross

wsl-host-cross: image ## MinGWを使いWindows x64向けnimino-wsl-host.exeをクロスコンパイルする

	$(COMPOSE) run --rm $(SERVICE) nimble buildWslHost

wsl-host-smoke: image ## WSLからWindows hostのWebView2生成・HTML・JavaScript・shutdownを実機確認する

	$(COMPOSE) run --rm $(SERVICE) nimble buildWslHostArtifact
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR)/tools/ci/wsl-host-smoke.ps1)" -HostExecutable "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)"

wsl-host-abnormal-smoke: image ## WSL clientのstdin異常終了時にWindows hostが終了することを確認する

	$(COMPOSE) run --rm $(SERVICE) nimble buildWslHostArtifact
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR)/tools/ci/wsl-host-smoke.ps1)" -HostExecutable "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)" -AbnormalClientEof

wsl-host-interactive: image ## WebView2実Windowを開き、ユーザー操作を待つ

	$(COMPOSE) run --rm $(SERVICE) nimble buildWslHostArtifact
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR)/tools/ci/wsl-host-interactive.ps1)" -HostExecutable "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)"

wsl-host-popup-smoke: image ## popupクリック後のpopup message受信を自動判定する

	$(COMPOSE) run --rm $(SERVICE) nimble buildWslHostArtifact
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR)/tools/ci/wsl-host-interactive.ps1)" -HostExecutable "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)" -WaitForPopupMessage

wsl-client-smoke: image ## WSL clientからWindows hostを起動しWindow/WebView/shutdownを実機確認する

	$(COMPOSE) run --rm $(SERVICE) nimble buildWslHostArtifact
	$(COMPOSE) run --rm $(SERVICE) nimble buildWslClientArtifact
	./.tmp/nimino-wsl-client-smoke "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)"

wsl-core-smoke: image ## 通常のcore APIからWSL Windows hostを選択してWindow/WebView/shutdownを実機確認する

	$(COMPOSE) run --rm $(SERVICE) nimble buildWslHostArtifact
	$(COMPOSE) run --rm $(SERVICE) nimble buildWslCoreClientArtifact
	./.tmp/nimino-wsl-core-client-smoke "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)"

wsl-core-rpc-async-smoke: image ## WSL coreのasync RPC・timeout・Window更新をWindows WebView2実機で確認する

	$(COMPOSE) run --rm $(SERVICE) nimble buildWslHostArtifact
	$(COMPOSE) run --rm $(SERVICE) nimble buildWslCoreRpcAsyncClientArtifact
	./.tmp/nimino-wsl-core-rpc-async-client-smoke "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)"

wsl-core-rpc-url-smoke: image ## WSL core URLのdocument-start RPCをWindows WebView2実機で確認する

	$(COMPOSE) run --rm $(SERVICE) nimble buildWslHostArtifact
	$(COMPOSE) run --rm $(SERVICE) nimble buildWslCoreRpcUrlClientArtifact
	./.tmp/nimino-wsl-core-rpc-url-client-smoke "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)"

check: test ## testの別名

clean: ## Compose資源とプロジェクト内の一時クロスビルド成果物を削除する

	$(COMPOSE) down --remove-orphans
	$(COMPOSE) run --rm --no-deps --entrypoint sh $(SERVICE) -c 'rm -rf /workspace/.tmp'
