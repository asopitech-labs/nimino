.DEFAULT_GOAL := help

COMPOSE ?= docker compose
SERVICE ?= nimino-dev
WSL_SMOKE_TIMEOUT ?= 120
WSL_INTERACTIVE_TIMEOUT ?= 300
WSL_SITE_TIMEOUT ?= 180

.PHONY: help setup setup-contract-test image nim-version nimble-version gtk-version webkit-version verify-env verify-webview2-header verify-webview2-profile-header verify-windows-dialog-abi setup-windows-webview2 kill-nimino-windows shell test webview2-profile-ffi-spike pack-test pack-cli-test pack-sites-test pack-site-release-test pack-linux-test pack-flatpak-test pack-popular-catalog-test pack-popular-catalog-generation-test pack-appimage-guardrails pack-appimage-test pack-windows-test pack-macos-test pack-bundle-test pack-archive-test host-linux host-windows linux-smoke linux-custom-protocol-smoke linux-tray-smoke macos-smoke core-linux-rpc-smoke core-linux-rpc-url-smoke core-linux-rpc-async-smoke windows-cross core-windows-cross wsl-host-cross wsl-host-smoke wsl-site-smoke wsl-host-abnormal-smoke wsl-host-interactive wsl-host-popup-smoke wsl-client-smoke wsl-core-smoke wsl-core-rpc-url-smoke wsl-core-rpc-async-smoke check clean

help: ## 利用可能な固定手順を表示する

	@awk 'BEGIN {FS = ":.*##"}; /^[a-zA-Z][a-zA-Z0-9_-]*:.*##/ {printf "  %-16s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

setup: verify-env ## DockerのNim/GTK/WebKitGTKとWindows WebView2 Runtimeを自動準備する
	@command -v powershell.exe >/dev/null 2>&1 || { \
		echo "ERROR: Windows Interop (powershell.exe) is required; WebView2 Runtime cannot be installed automatically." >&2; \
		exit 1; \
	}
	@test -n "$$WSL_INTEROP" || { \
		echo "ERROR: WSL_INTEROP is not set; restart WSL Interop before running make setup." >&2; \
		exit 1; \
	}
	$(MAKE) setup-windows-webview2

setup-contract-test: ## GTK/WebKitGTK/WebView2自動準備の契約を検証する
	bash tools/ci/test_setup_contract.sh

host-linux: image ## Docker内で汎用Linux Nimino hostをビルドする
	$(COMPOSE) run --rm $(SERVICE) nimble buildNiminoHost

host-windows: image ## Docker内で汎用Windows Nimino hostをクロスビルドする
	$(COMPOSE) run --rm $(SERVICE) nimble buildNiminoHostWindows

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

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'curl --fail --silent --show-error -L -o /tmp/webview2.nupkg https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/1.0.3967.48/microsoft.web.webview2.1.0.3967.48.nupkg && bash tools/ci/verify-webview2-header.sh /tmp/webview2.nupkg'

verify-windows-tray-abi: image ## MinGW Win32 SDKのNOTIFYICONDATAW ABIを検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc "printf '#include <windows.h>\\n#include <shellapi.h>\\ntypedef char notify_icon_data_w_size[(sizeof(NOTIFYICONDATAW) == 976) ? 1 : -1];\\n' | x86_64-w64-mingw32-gcc -x c -c -o /tmp/nimino-notify-icon-layout.o -"

verify-windows-dialog-abi: image ## MinGW Win32 SDKのOPENFILENAMEW ABIを検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc "printf '#include <windows.h>\\n#include <commdlg.h>\\ntypedef char openfilenamew_size[(sizeof(OPENFILENAMEW) == 152) ? 1 : -1];\\n' | x86_64-w64-mingw32-gcc -x c -c -o /tmp/nimino-openfilename-layout.o -"

verify-webview2-profile-header: image ## WebView2 Profile/CookieManager APIの公式ヘッダーを検証する

	$(COMPOSE) run --rm $(SERVICE) bash tools/bindings/verify_webview2_profile_header.sh

shell: image ## コンテナ内の対話shellを開く

	$(COMPOSE) run --rm $(SERVICE) bash

test: image ## M1以降のNimbleテストをコンテナ内で実行する

	$(COMPOSE) run --rm $(SERVICE) nimble test

webview2-profile-ffi-spike: image verify-webview2-profile-header ## WebView2 Profile/CookieManagerのprivate ABIスパイクを検証する

	$(COMPOSE) run --rm $(SERVICE) nimble testWebView2ProfileFfi
	$(COMPOSE) run --rm $(SERVICE) nimble testWindowsProfileFfiCross

setup-windows-webview2: ## Windows PowerShellでWebView2 Evergreen Runtimeを導入・検証する
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR)/tools/ci/setup-windows-webview2.ps1)"

kill-nimino-windows: ## Nimino hostとNimino由来WebView2プロセスをWindows側で回収する
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR)/tools/ci/kill-nimino-windows.ps1)"

pack-test: image ## nimino-packのmanifest解析テストをコンテナ内で実行する

	$(COMPOSE) run --rm $(SERVICE) nimble testPackManifest

pack-cli-test: image ## nimino pack CLIのmanifest検証を実行する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; nimble buildPackCli && nimble testPackCli'

pack-sites-test: image ## YouTube/Gmail/Google AnalyticsのURL-only bundleを検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; nimble buildPackCli && nimble testPackSites'

pack-site-release-test: image ## 3つのレビュー済みWebサイトの配布物を再ビルドし検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; nimble testSiteRelease'

pack-linux-test: image ## nimino-packのDebian/RPM生成とFlatpak contextを検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; nimble buildPackCli && nimble testPackLinux'

pack-flatpak-test: image ## nimino-packのFlatpak runtime/SDK上で実bundle生成を検証する

	$(COMPOSE) run --rm nimino-flatpak bash -lc 'export PATH=/opt/nim/bin:$$PATH; nimble buildPackCli && nimble testPackFlatpak'

pack-online-test: image ## URLからbundleとDebian artifactを生成するオンラインpack smoke

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; nimble testPackOnline'

pack-popular-catalog-test: image ## Popular Packagesのcatalog・checksum・生成元・署名検証を実行する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; nimble testPackPopularCatalog'

pack-popular-catalog-generation-test: image ## release assetから署名済みPopular Packages catalogを生成する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; nimble testPopularCatalogGeneration'

pack-appimage-guardrails: image ## 不完全なAppImage依存閉包が成功扱いされないことを検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; nimble buildPackCli && nimble testPackAppImageGuardrails'

pack-appimage-test: image ## 完全なAppImage依存閉包を生成しAppDir内容を検査する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; nimble buildPackCli && nimble buildNiminoHost && nimble testPackAppImage'

pack-windows-test: image ## nimino-packのNSIS/MSI Windows setup生成と構造を検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; nimble buildPackCli && nimble testPackWindows'

pack-macos-test: ## macOS app bundle/DMG生成を検証する
	nimble testPackMacos

pack-bundle-test: image ## nimino packのmanifest bundle生成を検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; nimble buildPackCli && nimble testPackCli'

pack-archive-test: image ## Linux tar.gzとWindows zip形式のpack配布物を検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; nimble buildPackCli && nimble testPackCli && nimble testPackArchive'

linux-smoke: image ## Xvfb上でLinux GTK/WebKitGTKのM1 smoke testを実行する

	$(COMPOSE) run --rm -e WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 $(SERVICE) nimble testLinuxSmoke

macos-smoke: ## macOS AppKit/WKWebViewのnative smoke testをローカルGUIで実行する

	nimble testMacosSmoke

linux-custom-protocol-smoke: image ## Xvfb上でLinux WebView custom protocol harnessを実行する

	$(COMPOSE) run --rm -e WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 $(SERVICE) nimble testLinuxCustomProtocolSmoke

linux-tray-smoke: image ## Xvfbとprivate D-Bus上でLinux StatusNotifierItem/dbusmenu harnessを実行する

	$(COMPOSE) run --rm $(SERVICE) nimble testLinuxTraySmoke

core-linux-rpc-smoke: image ## Xvfb上でLinux core RPC bootstrap smoke testを実行する

	$(COMPOSE) run --rm -e WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 -e NIMINO_TEST_ALLOW_NATIVE_IN_WSL=1 $(SERVICE) nimble testCoreLinuxRpcSmoke

core-linux-rpc-url-smoke: image ## Xvfb上でLinux core URLのdocument-start RPCを実行する

	$(COMPOSE) run --rm -e WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 -e NIMINO_TEST_ALLOW_NATIVE_IN_WSL=1 $(SERVICE) nimble testCoreLinuxRpcUrlSmoke

core-linux-rpc-async-smoke: image ## Xvfb上でLinux core RPCのasync/timeout smoke testを実行する

	$(COMPOSE) run --rm -e WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 -e NIMINO_TEST_ALLOW_NATIVE_IN_WSL=1 $(SERVICE) nimble testCoreLinuxRpcAsyncSmoke

windows-cross: image verify-windows-tray-abi verify-windows-dialog-abi ## MinGWを使いWindows x64向けnative smokeバイナリをクロスコンパイルする

	$(COMPOSE) run --rm $(SERVICE) nimble testWindowsCross

core-windows-cross: image ## MinGWを使いWindows x64向けcore RPC facadeをクロスコンパイルする

	$(COMPOSE) run --rm $(SERVICE) nimble testCoreWindowsCross

wsl-host-cross: image ## MinGWを使いWindows x64向けnimino-wsl-host.exeをクロスコンパイルする

	$(COMPOSE) run --rm $(SERVICE) nimble buildWslHost

wsl-host-smoke: image ## WSLからWindows hostのWebView2生成・HTML・JavaScript・shutdownを実機確認する

	$(COMPOSE) run --rm $(SERVICE) nimble buildWslHostArtifact
	(timeout --foreground $(WSL_SMOKE_TIMEOUT)s powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR)/tools/ci/wsl-host-smoke.ps1)" -HostExecutable "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)") || { status=$$?; taskkill.exe /IM nimino-wsl-host.exe /T /F >/dev/null 2>&1 || true; exit $$status; }

wsl-site-smoke: image ## YouTube/Gmail/Google Analyticsの実サイトWebView2読込を確認する

	@command -v powershell.exe >/dev/null 2>&1 || { echo "ERROR: powershell.exe is unavailable; restore Windows Interop first." >&2; exit 1; }
	@powershell.exe -NoProfile -Command "exit 0" >/dev/null 2>&1 || { echo "ERROR: Windows Interop is not responding. In elevated Windows PowerShell run: wsl --shutdown; Restart-Service LxssManager; then reopen WSL." >&2; exit 1; }
	$(COMPOSE) run --rm $(SERVICE) nimble buildWslHostArtifact
	@for url in "https://www.youtube.com/" "https://mail.google.com/mail/u/0/" "https://analytics.google.com/analytics/web/"; do \
		echo "Nimino site URL smoke: $$url"; \
		(timeout --foreground $(WSL_SITE_TIMEOUT)s powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR)/tools/ci/wsl-host-smoke.ps1)" -HostExecutable "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)" -InitialUrl "$$url") || { status=$$?; taskkill.exe /IM nimino-wsl-host.exe /T /F >/dev/null 2>&1 || true; exit $$status; }; \
	done

wsl-host-abnormal-smoke: image ## WSL clientのstdin異常終了時にWindows hostが終了することを確認する

	$(COMPOSE) run --rm $(SERVICE) nimble buildWslHostArtifact
	(timeout --foreground $(WSL_SMOKE_TIMEOUT)s powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR)/tools/ci/wsl-host-smoke.ps1)" -HostExecutable "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)" -AbnormalClientEof) || { status=$$?; taskkill.exe /IM nimino-wsl-host.exe /T /F >/dev/null 2>&1 || true; exit $$status; }

wsl-host-interactive: image ## WebView2実Windowを開き、ユーザー操作を待つ

	$(COMPOSE) run --rm $(SERVICE) nimble buildWslHostArtifact
	(timeout --foreground $(WSL_INTERACTIVE_TIMEOUT)s powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR)/tools/ci/wsl-host-interactive.ps1)" -HostExecutable "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)") || { status=$$?; taskkill.exe /IM nimino-wsl-host.exe /T /F >/dev/null 2>&1 || true; exit $$status; }

wsl-host-popup-smoke: image ## WebView2新規Window要求・明示popup message受信を実機確認する

	$(COMPOSE) run --rm $(SERVICE) nimble buildWslHostArtifact
	(timeout --foreground $(WSL_SMOKE_TIMEOUT)s powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR)/tools/ci/wsl-host-smoke.ps1)" -HostExecutable "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)" -VerifyNewWindow) || { status=$$?; powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR)/tools/ci/kill-nimino-windows.ps1)" >/dev/null 2>&1 || true; exit $$status; }

wsl-client-smoke: image ## WSL clientからWindows hostを起動しWindow/WebView/shutdownを実機確認する

	$(COMPOSE) run --rm $(SERVICE) nimble buildWslHostArtifact
	$(COMPOSE) run --rm $(SERVICE) nimble buildWslClientArtifact
	(timeout --foreground $(WSL_SMOKE_TIMEOUT)s ./.tmp/nimino-wsl-client-smoke "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)") || { status=$$?; taskkill.exe /IM nimino-wsl-host.exe /T /F >/dev/null 2>&1 || true; exit $$status; }

wsl-core-smoke: image ## 通常のcore APIからWSL Windows hostを選択してWindow/WebView/shutdownを実機確認する

	$(COMPOSE) run --rm $(SERVICE) nimble buildWslHostArtifact
	$(COMPOSE) run --rm $(SERVICE) nimble buildWslCoreClientArtifact
	(timeout --foreground $(WSL_SMOKE_TIMEOUT)s ./.tmp/nimino-wsl-core-client-smoke "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)") || { status=$$?; taskkill.exe /IM nimino-wsl-host.exe /T /F >/dev/null 2>&1 || true; exit $$status; }

wsl-core-rpc-async-smoke: image ## WSL coreのasync RPC・timeout・Window更新をWindows WebView2実機で確認する

	$(COMPOSE) run --rm $(SERVICE) nimble buildWslHostArtifact
	$(COMPOSE) run --rm $(SERVICE) nimble buildWslCoreRpcAsyncClientArtifact
	(timeout --foreground $(WSL_SMOKE_TIMEOUT)s ./.tmp/nimino-wsl-core-rpc-async-client-smoke "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)") || { status=$$?; taskkill.exe /IM nimino-wsl-host.exe /T /F >/dev/null 2>&1 || true; exit $$status; }

wsl-core-rpc-url-smoke: image ## WSL core URLのdocument-start RPCをWindows WebView2実機で確認する

	$(COMPOSE) run --rm $(SERVICE) nimble buildWslHostArtifact
	$(COMPOSE) run --rm $(SERVICE) nimble buildWslCoreRpcUrlClientArtifact
	(timeout --foreground $(WSL_SMOKE_TIMEOUT)s ./.tmp/nimino-wsl-core-rpc-url-client-smoke "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)") || { status=$$?; taskkill.exe /IM nimino-wsl-host.exe /T /F >/dev/null 2>&1 || true; exit $$status; }

check: test ## testの別名

clean: ## Compose資源とプロジェクト内の一時クロスビルド成果物を削除する

	taskkill.exe /IM nimino-wsl-host.exe /T /F >/dev/null 2>&1 || true
	$(COMPOSE) down --remove-orphans
	$(COMPOSE) run --rm --no-deps --entrypoint sh $(SERVICE) -c 'rm -rf /workspace/.tmp'
