.DEFAULT_GOAL := help

DETECTED_CONTAINER_RUNTIME := $(shell \
	if command -v docker >/dev/null 2>&1 && \
			docker info >/dev/null 2>&1 && \
			docker compose version >/dev/null 2>&1; then \
		printf docker; \
	elif command -v podman >/dev/null 2>&1 && \
			podman info >/dev/null 2>&1 && \
			podman compose version >/dev/null 2>&1; then \
		printf podman; \
	fi)
CONTAINER_RUNTIME ?= $(DETECTED_CONTAINER_RUNTIME)
COMPOSE ?= $(if $(strip $(CONTAINER_RUNTIME)),$(CONTAINER_RUNTIME) compose)
NIMBLE ?= bash tools/ci/run_nimble_task.sh
SERVICE ?= nimino-dev
REFERENCE_TEST_ENV = -e NIMINO_TEST_REFERENCE_LINUX=$(NIMINO_TEST_REFERENCE_LINUX) -e NIMINO_TEST_REFERENCE_WINDOWS=$(NIMINO_TEST_REFERENCE_WINDOWS) -e NIMINO_TEST_REFERENCE_WSL=$(NIMINO_TEST_REFERENCE_WSL)
WINDOWS_CLEANUP = powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR)/tools/ci/kill-nimino-windows.ps1)"
WSL_SMOKE_TIMEOUT ?= 120
WSL_INTERACTIVE_TIMEOUT ?= 300
WSL_SITE_TIMEOUT ?= 180
WSL_SITE_READ_TIMEOUT_MS ?= 60000
PACK_SMOKE_URL ?= https://asopi.tech

.PHONY: help container-runtime-check setup setup-contract-test image nim-version nimble-version gtk-version webkit-version verify-env verify-webview2-header verify-webview2-profile-header verify-windows-dialog-abi setup-windows-webview2 kill-nimino-windows shell test webview2-profile-ffi-spike component-versions-test nimble-install-test pack-host-resolution-test pack-host-runtime-test pack-test pack-cli-test pack-sites-test pack-site-release-test component-release-test pack-linux-test pack-flatpak-test pack-popular-catalog-test pack-popular-catalog-generation-test pack-appimage-guardrails pack-appimage-test pack-windows-test pack-windows-smoke rpm-centos-smoke pack-macos-test pack-bundle-test pack-archive-test host-linux host-windows linux-smoke linux-custom-protocol-smoke linux-tray-smoke macos-smoke core-linux-rpc-smoke core-linux-rpc-url-smoke core-linux-rpc-async-smoke windows-cross core-windows-cross wsl-host-cross wsl-host-smoke wsl-site-smoke wsl-host-abnormal-smoke wsl-host-interactive wsl-host-popup-smoke wsl-client-smoke wsl-core-smoke wsl-core-rpc-url-smoke wsl-core-rpc-async-smoke check clean

help: ## 利用可能な固定手順を表示する

	@awk 'BEGIN {FS = ":.*##"}; /^[a-zA-Z][a-zA-Z0-9_-]*:.*##/ {printf "  %-16s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

container-runtime-check: ## Docker ComposeまたはPodman Composeの利用可否を検証する
	@if [ -z "$(strip $(COMPOSE))" ]; then \
		echo "ERROR: neither Docker nor Podman was found; install one with Compose support or set COMPOSE explicitly." >&2; \
		exit 1; \
	fi
	@$(COMPOSE) version >/dev/null 2>&1 || { \
		echo "ERROR: '$(COMPOSE)' is not usable; install or enable its Compose provider, or set COMPOSE explicitly." >&2; \
		exit 1; \
	}
	@echo "Using $(COMPOSE)"

setup: verify-env ## コンテナ内のNim/GTK/WebKitGTKとWindows WebView2 Runtimeを自動準備する
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
	bash tools/ci/test_container_runtime_selection.sh
	bash tools/ci/test_run_nimble_task.sh
	bash tools/ci/test_nimble_entrypoints.sh
	bash tools/ci/test_make_reference_env.sh
	bash tools/ci/test_make_clean.sh
	bash tools/ci/test_wsl_public_site_targets.sh

host-linux: image ## コンテナ内で汎用Linux Nimino hostをビルドする
	$(COMPOSE) run --rm $(SERVICE) $(NIMBLE) buildNiminoHost

host-windows: image ## コンテナ内で汎用Windows Nimino hostをクロスビルドする
	$(COMPOSE) run --rm $(SERVICE) $(NIMBLE) buildNiminoHostWindows

image: container-runtime-check ## Nim/GTK/WebKitGTK開発イメージをビルドする

	$(COMPOSE) build $(SERVICE)

nim-version: image ## コンテナ内のNimバージョンを確認する

	$(COMPOSE) run --rm $(SERVICE) nim --version

nimble-version: image ## コンテナ内のNimbleバージョンを確認する

	$(COMPOSE) run --rm $(SERVICE) $(NIMBLE) --version

gtk-version: image ## コンテナ内のGTK 4開発環境を確認する

	$(COMPOSE) run --rm $(SERVICE) pkg-config --modversion gtk4

webkit-version: image ## コンテナ内のWebKitGTK 6.0開発環境を確認する

	$(COMPOSE) run --rm $(SERVICE) pkg-config --modversion webkitgtk-6.0

verify-env: nim-version nimble-version gtk-version webkit-version ## M0のコンテナ開発環境を検証する

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

	$(COMPOSE) run --rm $(REFERENCE_TEST_ENV) $(SERVICE) $(NIMBLE) test

webview2-profile-ffi-spike: image verify-webview2-profile-header ## WebView2 Profile/CookieManagerのprivate ABIスパイクを検証する

	$(COMPOSE) run --rm $(SERVICE) $(NIMBLE) testWebView2ProfileFfi
	$(COMPOSE) run --rm $(SERVICE) $(NIMBLE) testWindowsProfileFfiCross

setup-windows-webview2: ## Windows PowerShellでWebView2 Evergreen Runtimeを導入・検証する
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR)/tools/ci/setup-windows-webview2.ps1)"

kill-nimino-windows: ## Nimino hostとNimino由来WebView2プロセスをWindows側で回収する
	$(WINDOWS_CLEANUP)

component-versions-test: ## コンポーネント間の依存の下限がリリース版と一致することを検証する

	bash tools/ci/test_component_versions.sh

nimble-install-test: image ## 公開手順のnimble installでCLIが入ることを検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; bash tools/ci/test_nimble_install.sh'

pack-host-resolution-test: image ## --host省略時にpackがhostを見つけることを検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; $(NIMBLE) testPackHostResolution'

pack-host-runtime-test: image ## packがhostの隣のランタイムを同梱することを検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; $(NIMBLE) testPackHostRuntime'

pack-test: image ## nimino-packのmanifest解析テストをコンテナ内で実行する

	$(COMPOSE) run --rm $(SERVICE) $(NIMBLE) testPackManifest

pack-cli-test: image ## nimino pack CLIのmanifest検証を実行する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; $(NIMBLE) buildPackCli && $(NIMBLE) testPackCli'

pack-sites-test: image ## YouTube/Gmail/Google AnalyticsのURL-only bundleを検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; $(NIMBLE) buildPackCli && $(NIMBLE) testPackSites'

pack-site-release-test: image ## 3つのレビュー済みWebサイトの配布物を再ビルドし検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; $(NIMBLE) testSiteRelease'

component-release-test: image ## nimino-coreとnimino-packの単体配布アーカイブを検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; $(NIMBLE) testComponentRelease'

pack-linux-test: image ## nimino-packのDebian/RPM生成とFlatpak contextを検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; $(NIMBLE) buildPackCli && $(NIMBLE) testPackLinux'

pack-flatpak-test: image ## nimino-packのFlatpak runtime/SDK上で実bundle生成を検証する

	$(COMPOSE) run --rm nimino-flatpak bash -lc 'export PATH=/opt/nim/bin:$$PATH; $(NIMBLE) buildPackCli && $(NIMBLE) testPackFlatpak'

pack-online-test: image ## URLからbundleとDebian artifactを生成するオンラインpack smoke

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; $(NIMBLE) testPackOnline'

pack-popular-catalog-test: image ## Popular Packagesのcatalog・checksum・生成元・署名検証を実行する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; $(NIMBLE) testPackPopularCatalog'

pack-popular-catalog-generation-test: image ## release assetから署名済みPopular Packages catalogを生成する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; $(NIMBLE) testPopularCatalogGeneration'

pack-appimage-guardrails: image ## 不完全なAppImage依存閉包が成功扱いされないことを検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; $(NIMBLE) buildPackCli && $(NIMBLE) testPackAppImageGuardrails'

pack-appimage-test: image ## 完全なAppImage依存閉包を生成しAppDir内容を検査する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; $(NIMBLE) buildPackCli && $(NIMBLE) buildNiminoHost && $(NIMBLE) testPackAppImage'

pack-windows-test: image ## nimino-packのNSIS/MSI Windows setup生成と構造を検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; $(NIMBLE) buildPackCli && $(NIMBLE) testPackWindows'

pack-macos-test: ## macOS app bundle/DMG生成を検証する
	$(NIMBLE) testPackMacos

pack-bundle-test: image ## nimino packのmanifest bundle生成を検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; $(NIMBLE) buildPackCli && $(NIMBLE) testPackCli'

pack-archive-test: image ## Linux tar.gzとWindows zip形式のpack配布物を検証する

	$(COMPOSE) run --rm $(SERVICE) bash -lc 'export PATH=/opt/nim/bin:$$PATH; $(NIMBLE) buildPackCli && $(NIMBLE) testPackCli && $(NIMBLE) testPackArchive'

linux-smoke: image ## Xvfb上でLinux GTK/WebKitGTKのM1 smoke testを実行する

	$(COMPOSE) run --rm -e WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 $(SERVICE) $(NIMBLE) testLinuxSmoke

macos-smoke: ## macOS AppKit/WKWebViewのnative smoke testをローカルGUIで実行する

	$(NIMBLE) testMacosSmoke

linux-custom-protocol-smoke: image ## Xvfb上でLinux WebView custom protocol harnessを実行する

	$(COMPOSE) run --rm -e WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 $(SERVICE) $(NIMBLE) testLinuxCustomProtocolSmoke

linux-tray-smoke: image ## Xvfbとprivate D-Bus上でLinux StatusNotifierItem/dbusmenu harnessを実行する

	$(COMPOSE) run --rm $(SERVICE) $(NIMBLE) testLinuxTraySmoke

core-linux-rpc-smoke: image ## Xvfb上でLinux core RPC bootstrap smoke testを実行する

	$(COMPOSE) run --rm -e WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 -e NIMINO_TEST_ALLOW_NATIVE_IN_WSL=1 $(SERVICE) $(NIMBLE) testCoreLinuxRpcSmoke

core-linux-rpc-url-smoke: image ## Xvfb上でLinux core URLのdocument-start RPCを実行する

	$(COMPOSE) run --rm -e WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 -e NIMINO_TEST_ALLOW_NATIVE_IN_WSL=1 $(SERVICE) $(NIMBLE) testCoreLinuxRpcUrlSmoke

core-linux-rpc-async-smoke: image ## Xvfb上でLinux core RPCのasync/timeout smoke testを実行する

	$(COMPOSE) run --rm -e WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 -e NIMINO_TEST_ALLOW_NATIVE_IN_WSL=1 $(SERVICE) $(NIMBLE) testCoreLinuxRpcAsyncSmoke

windows-cross: image verify-windows-tray-abi verify-windows-dialog-abi ## MinGWを使いWindows x64向けnative smokeバイナリをクロスコンパイルする

	$(COMPOSE) run --rm $(SERVICE) $(NIMBLE) testWindowsCross

core-windows-cross: image ## MinGWを使いWindows x64向けcore RPC facadeをクロスコンパイルする

	$(COMPOSE) run --rm $(SERVICE) $(NIMBLE) testCoreWindowsCross

rpm-centos-smoke: image ## 生成RPMをCentOS Stream 10コンテナへinstallし起動確認する

	$(COMPOSE) run --rm -e NIMINO_PACK_SMOKE_URL=$(PACK_SMOKE_URL) $(SERVICE) $(NIMBLE) buildRpmSmokeArtifact
	bash tools/ci/test_rpm_centos.sh "$(CONTAINER_RUNTIME)" "$$(ls .tmp/rpm-smoke/packages/*.rpm)"

pack-windows-smoke: image ## URLをpackしたWindows bundleを実WindowsのWebView2で起動確認する

	@command -v powershell.exe >/dev/null 2>&1 || { echo "ERROR: powershell.exe is unavailable; restore Windows Interop first." >&2; exit 1; }
	@powershell.exe -NoProfile -Command "exit 0" >/dev/null 2>&1 || { echo "ERROR: Windows Interop is not responding. In elevated Windows PowerShell run: wsl --shutdown; Restart-Service LxssManager; then reopen WSL." >&2; exit 1; }
	$(COMPOSE) run --rm -e NIMINO_PACK_SMOKE_URL=$(PACK_SMOKE_URL) $(SERVICE) $(NIMBLE) buildPackWindowsSmokeArtifact
	(timeout --foreground $(WSL_SMOKE_TIMEOUT)s powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR)/tools/ci/pack-windows-smoke.ps1)" -BundleDirectory "$$(wslpath -w $(CURDIR)/.tmp/pack-windows-smoke)") || { status=$$?; $(WINDOWS_CLEANUP) >/dev/null 2>&1 || true; exit $$status; }

wsl-host-cross: image ## MinGWを使いWindows x64向けnimino-wsl-host.exeをクロスコンパイルする

	$(COMPOSE) run --rm $(SERVICE) $(NIMBLE) buildWslHost

wsl-host-smoke: image ## WSLからWindows hostのWebView2生成・HTML・JavaScript・shutdownを実機確認する

	$(COMPOSE) run --rm $(SERVICE) $(NIMBLE) buildWslHostArtifact
	(timeout --foreground $(WSL_SMOKE_TIMEOUT)s powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR)/tools/ci/wsl-host-smoke.ps1)" -HostExecutable "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)") || { status=$$?; $(WINDOWS_CLEANUP) >/dev/null 2>&1 || true; exit $$status; }

wsl-site-smoke: image ## ログイン不要の公開サイトをWebView2で読込・内容確認する

	@command -v powershell.exe >/dev/null 2>&1 || { echo "ERROR: powershell.exe is unavailable; restore Windows Interop first." >&2; exit 1; }
	@powershell.exe -NoProfile -Command "exit 0" >/dev/null 2>&1 || { echo "ERROR: Windows Interop is not responding. In elevated Windows PowerShell run: wsl --shutdown; Restart-Service LxssManager; then reopen WSL." >&2; exit 1; }
	$(COMPOSE) run --rm $(SERVICE) $(NIMBLE) buildWslHostArtifact
	@while IFS= read -r url <&3; do \
		[ -n "$$url" ] || continue; \
		echo "Nimino site URL smoke: $$url"; \
		(timeout --foreground $(WSL_SITE_TIMEOUT)s powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR)/tools/ci/wsl-host-smoke.ps1)" -HostExecutable "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)" -InitialUrl "$$url" -VerifyPublicPage -ReadTimeoutMs $(WSL_SITE_READ_TIMEOUT_MS)) || { status=$$?; $(WINDOWS_CLEANUP) >/dev/null 2>&1 || true; exit $$status; }; \
	done 3< tools/ci/wsl-public-sites.txt

wsl-host-abnormal-smoke: image ## WSL clientのEOF・protocol破損時にWindows hostが正しいstatusで終了することを確認する

	$(COMPOSE) run --rm $(SERVICE) $(NIMBLE) buildWslHostArtifact
	(timeout --foreground $(WSL_SMOKE_TIMEOUT)s powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR)/tools/ci/wsl-host-smoke.ps1)" -HostExecutable "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)" -AbnormalClientEof) || { status=$$?; $(WINDOWS_CLEANUP) >/dev/null 2>&1 || true; exit $$status; }
	(timeout --foreground $(WSL_SMOKE_TIMEOUT)s powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR)/tools/ci/wsl-host-smoke.ps1)" -HostExecutable "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)" -MalformedClientFrame) || { status=$$?; $(WINDOWS_CLEANUP) >/dev/null 2>&1 || true; exit $$status; }
	(timeout --foreground $(WSL_SMOKE_TIMEOUT)s powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR)/tools/ci/wsl-host-smoke.ps1)" -HostExecutable "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)" -MalformedClientFrameAfterUi) || { status=$$?; $(WINDOWS_CLEANUP) >/dev/null 2>&1 || true; exit $$status; }

wsl-host-interactive: image ## WebView2実Windowを開き、ユーザー操作を待つ

	$(COMPOSE) run --rm $(SERVICE) $(NIMBLE) buildWslHostArtifact
	(timeout --foreground $(WSL_INTERACTIVE_TIMEOUT)s powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR)/tools/ci/wsl-host-interactive.ps1)" -HostExecutable "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)") || { status=$$?; $(WINDOWS_CLEANUP) >/dev/null 2>&1 || true; exit $$status; }

wsl-host-popup-smoke: image ## WebView2新規Window要求・明示popup message受信を実機確認する

	$(COMPOSE) run --rm $(SERVICE) $(NIMBLE) buildWslHostArtifact
	(timeout --foreground $(WSL_SMOKE_TIMEOUT)s powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR)/tools/ci/wsl-host-smoke.ps1)" -HostExecutable "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)" -VerifyNewWindow) || { status=$$?; $(WINDOWS_CLEANUP) >/dev/null 2>&1 || true; exit $$status; }

wsl-client-smoke: image ## WSL clientからWindows hostを起動しWindow/WebView/shutdownを実機確認する

	$(COMPOSE) run --rm $(SERVICE) $(NIMBLE) buildWslHostArtifact
	$(COMPOSE) run --rm $(SERVICE) $(NIMBLE) buildWslClientArtifact
	(timeout --foreground $(WSL_SMOKE_TIMEOUT)s ./.tmp/nimino-wsl-client-smoke "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)") || { status=$$?; $(WINDOWS_CLEANUP) >/dev/null 2>&1 || true; exit $$status; }

wsl-core-smoke: image ## 通常のcore APIからWSL Windows hostを選択してWindow/WebView/shutdownを実機確認する

	$(COMPOSE) run --rm $(SERVICE) $(NIMBLE) buildWslHostArtifact
	$(COMPOSE) run --rm $(SERVICE) $(NIMBLE) buildWslCoreClientArtifact
	(timeout --foreground $(WSL_SMOKE_TIMEOUT)s ./.tmp/nimino-wsl-core-client-smoke "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)") || { status=$$?; $(WINDOWS_CLEANUP) >/dev/null 2>&1 || true; exit $$status; }

wsl-core-rpc-async-smoke: image ## WSL coreのasync RPC・timeout・Window更新をWindows WebView2実機で確認する

	$(COMPOSE) run --rm $(SERVICE) $(NIMBLE) buildWslHostArtifact
	$(COMPOSE) run --rm $(SERVICE) $(NIMBLE) buildWslCoreRpcAsyncClientArtifact
	(timeout --foreground $(WSL_SMOKE_TIMEOUT)s ./.tmp/nimino-wsl-core-rpc-async-client-smoke "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)") || { status=$$?; $(WINDOWS_CLEANUP) >/dev/null 2>&1 || true; exit $$status; }

wsl-core-rpc-url-smoke: image ## WSL core URLのdocument-start RPCをWindows WebView2実機で確認する

	$(COMPOSE) run --rm $(SERVICE) $(NIMBLE) buildWslHostArtifact
	$(COMPOSE) run --rm $(SERVICE) $(NIMBLE) buildWslCoreRpcUrlClientArtifact
	(timeout --foreground $(WSL_SMOKE_TIMEOUT)s ./.tmp/nimino-wsl-core-rpc-url-client-smoke "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)") || { status=$$?; $(WINDOWS_CLEANUP) >/dev/null 2>&1 || true; exit $$status; }

check: test ## testの別名

clean: ## Compose資源とプロジェクト内の一時クロスビルド成果物を削除する
	@if command -v powershell.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then \
		$(WINDOWS_CLEANUP); \
	else \
		echo "Skipping Windows process cleanup: Windows Interop is unavailable"; \
	fi
	@if ! rm -rf -- "$(CURDIR)/.tmp"; then \
		if [ -z "$(strip $(COMPOSE))" ] || ! $(COMPOSE) version >/dev/null 2>&1; then \
			echo "ERROR: cannot remove $(CURDIR)/.tmp locally and no Compose runtime is usable" >&2; \
			exit 1; \
		fi; \
		$(COMPOSE) run --rm --no-deps --entrypoint sh $(SERVICE) -c 'rm -rf /workspace/.tmp'; \
	fi
	@if [ -n "$(strip $(COMPOSE))" ] && $(COMPOSE) version >/dev/null 2>&1; then \
		$(COMPOSE) down --remove-orphans; \
	else \
		echo "Skipping Compose cleanup: Docker/Podman Compose is unavailable"; \
	fi
