.DEFAULT_GOAL := help

COMPOSE ?= docker compose
SERVICE ?= nimino-dev

.PHONY: help image nim-version nimble-version gtk-version webkit-version verify-env shell test check clean

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

check: test ## testの別名

clean: ## 停止済みのComposeコンテナとネットワークを削除する（Nimble cacheは保持）

	$(COMPOSE) down --remove-orphans
