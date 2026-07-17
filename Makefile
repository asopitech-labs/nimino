.DEFAULT_GOAL := help

COMPOSE ?= docker compose
SERVICE ?= nimino-dev

.PHONY: help image nim-version nimble-version gtk-version webkit-version verify-env shell test linux-smoke core-linux-rpc-smoke windows-cross core-windows-cross wsl-host-cross wsl-host-smoke wsl-client-smoke wsl-core-smoke check clean

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

shell: image ## コンテナ内の対話shellを開く

	$(COMPOSE) run --rm $(SERVICE) bash

test: image ## M1以降のNimbleテストをコンテナ内で実行する

	$(COMPOSE) run --rm $(SERVICE) nimble test

linux-smoke: image ## Xvfb上でLinux GTK/WebKitGTKのM1 smoke testを実行する

	$(COMPOSE) run --rm -e WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 $(SERVICE) nimble testLinuxSmoke

core-linux-rpc-smoke: image ## Xvfb上でLinux core RPC bootstrap smoke testを実行する

	$(COMPOSE) run --rm -e WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 -e NIMINO_TEST_ALLOW_NATIVE_IN_WSL=1 $(SERVICE) nimble testCoreLinuxRpcSmoke

windows-cross: image ## MinGWを使いWindows x64向けnative smokeバイナリをクロスコンパイルする

	$(COMPOSE) run --rm $(SERVICE) nimble testWindowsCross

core-windows-cross: image ## MinGWを使いWindows x64向けcore RPC facadeをクロスコンパイルする

	$(COMPOSE) run --rm $(SERVICE) nimble testCoreWindowsCross

wsl-host-cross: image ## MinGWを使いWindows x64向けnimino-wsl-host.exeをクロスコンパイルする

	$(COMPOSE) run --rm $(SERVICE) nimble buildWslHost

wsl-host-smoke: image ## WSLからWindows hostの認証済みstdio handshakeとshutdownを実機確認する

	$(COMPOSE) run --rm $(SERVICE) nimble buildWslHostArtifact
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR)/tools/ci/wsl-host-smoke.ps1)" -HostExecutable "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)"

wsl-client-smoke: image ## WSL clientからWindows hostを起動しWindow/WebView/shutdownを実機確認する

	$(COMPOSE) run --rm $(SERVICE) nimble buildWslHostArtifact
	$(COMPOSE) run --rm $(SERVICE) nimble buildWslClientArtifact
	./.tmp/nimino-wsl-client-smoke "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)"

wsl-core-smoke: image ## 通常のcore APIからWSL Windows hostを選択してWindow/WebView/shutdownを実機確認する

	$(COMPOSE) run --rm $(SERVICE) nimble buildWslHostArtifact
	$(COMPOSE) run --rm $(SERVICE) nimble buildWslCoreClientArtifact
	./.tmp/nimino-wsl-core-client-smoke "$$(wslpath -w $(CURDIR)/.tmp/nimino-wsl-host.exe)"

check: test ## testの別名

clean: ## Compose資源とプロジェクト内の一時クロスビルド成果物を削除する

	$(COMPOSE) down --remove-orphans
	$(COMPOSE) run --rm --no-deps --entrypoint sh $(SERVICE) -c 'rm -rf /workspace/.tmp'
