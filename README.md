# Nimino

Nimino is a lightweight desktop application foundation for building Web UI applications in Nim. It wraps the operating system's WebView without bundling Chromium or requiring Node.js at runtime.

The same application model targets Windows, native Linux, and WSL:

```text
Nim application
    └─ nimino-core
        └─ nimino-native
            ├─ Win32 + WebView2
            └─ GTK + WebKitGTK

WSL application
    └─ nimino-wsl client ── authenticated IPC ── nimino-wsl-host.exe
                                               └─ Win32 + WebView2
```

## Start here

### For Nim developers: install with nimble

The Nim packages install straight from this repository through nimble's `?subdir=` URL form. **Until [nim-lang/packages#3447](https://github.com/nim-lang/packages/pull/3447) is merged, use the repository URLs below — package-name installs such as `nimble install nimino_core` do not resolve yet.** Run the four commands in this order; the later packages depend on the earlier ones. Once the registration merges, this tutorial switches to name-based installs.

```bash
# Application framework and its platform layers
nimble install "https://github.com/asopitech-labs/nimino?subdir=packages/native"
nimble install "https://github.com/asopitech-labs/nimino?subdir=packages/wsl"
nimble install "https://github.com/asopitech-labs/nimino?subdir=packages/core"

# Packaging toolkit and the `nimino` CLI (standard library only)
nimble install "https://github.com/asopitech-labs/nimino?subdir=packages/pack"
```

Building an application against `nimino_core` needs the GTK 4 and WebKitGTK 6.0 development headers on Linux (`libgtk-4-dev` and `libwebkitgtk-6.0-dev` on Debian/Ubuntu) and the WebView2 loader on Windows; `nimino_pack` needs no GUI stack at all. Start from [a minimal application](#a-minimal-application), then wrap any site with the installed CLI:

```bash
nimino pack https://example.com --out dist/example --host <nimino-host>
```

The flow above is verified with the stable nimble shipped with Nim 2.2 (0.18); the devel nimble 0.22 vnext resolver currently has an upstream regression with `?subdir=` URLs.

### For beginners: build online

No Nim, Docker, or local GUI SDK installation is required for the online path.

1. Fork this repository.
2. Open **Actions → Nimino Pack Online Build → Run workflow**.
3. Enter the website URL and target package. Application name and stable ID are optional; Nimino derives them from the URL when omitted.
4. Download the generated artifact from the completed workflow.

The workflow is defined in [`nimino-pack-online.yml`](.github/workflows/nimino-pack-online.yml). It uses the pinned Docker toolchain and produces a bundle, package, checksum file, and SBOM. Supported targets are Linux `.deb`, Linux `.rpm`, Windows NSIS/MSI, and macOS `.app`/`.dmg` when run on macOS.

### Ready-made site installers

The release workflow packages YouTube, Gmail, and Google Analytics from their URLs. Nimino derives the profile, window defaults, package metadata, and navigation behavior from each URL; the reviewed display names and stable application IDs are pinned in the release script because both Google properties would otherwise derive the same "Google" name. No site-specific navigation allow-list or credentials are embedded; the normal sign-in page and profile cookie store are used.

| App | Open in browser | Default window | Profile | Maintainer rebuild |
| --- | --- | ---: | --- | --- |
| **YouTube** | [youtube.com](https://www.youtube.com/) | URL-derived defaults | `default` | Release installer |
| **Gmail** | [mail.google.com](https://mail.google.com/mail/u/0/) | URL-derived defaults | `default` | Release installer |
| **Google Analytics** | [analytics.google.com](https://analytics.google.com/analytics/web/) | URL-derived defaults | `default` | Release installer |

#### Download ready-made installers

Download the installer directly from the [Nimino Releases page](https://github.com/asopitech-labs/nimino/releases):

| Target | Release assets |
| --- | --- |
| Debian/Ubuntu | `youtube-*.deb`, `gmail-*.deb`, `google-analytics-*.deb` |
| Fedora/RPM | `youtube-*.rpm`, `gmail-*.rpm`, `google-analytics-*.rpm` |
| Windows | `youtube-*-setup.exe`, `gmail-*-setup.exe`, `google-analytics-*-setup.exe` (NSIS) or matching `.msi`; the installer checks and installs WebView2 when needed |

The same release publishes the two components on their own, for building your own applications rather than installing a ready-made one: `nimino-core-*` (the runtime) and `nimino-pack-*` (the packaging CLI). See [Two released packages](#two-released-packages).

The [`Nimino Site Release`](.github/workflows/nimino-site-release.yml) workflow builds all three applications for every `v*` tag, attaches installers, SBOM files, `SHA256SUMS`, and the signed `popular-packages.json` catalog to the GitHub Release. Configure the repository secrets `NIMINO_POPULAR_CATALOG_SECRET_KEY`, `NIMINO_POPULAR_CATALOG_PUBLIC_KEY`, and `NIMINO_POPULAR_CATALOG_KEY_ID` before running a release; the workflow fails if signing material is missing. Verify `SHA256SUMS` before installing.

**Windows installer behavior:** NSIS and MSI installers check the WebView2 Evergreen Runtime and download the official Microsoft Bootstrapper only when the runtime is missing. Internet access is required for that first-time download. `WebView2Loader.dll` and `pcre64.dll` are bundled with the application.

For manual repair or development setup, use the optional verified script:

```powershell
$p = Join-Path $env:TEMP 'Nimino-WebView2-Setup.ps1'
Invoke-WebRequest -UseBasicParsing 'https://github.com/asopitech-labs/nimino/releases/download/v0.1.1/Nimino-WebView2-Setup.ps1' -OutFile $p
if ((Get-FileHash -Algorithm SHA256 $p).Hash -ne 'FBB373CC34D49F8B1FBA0792363103455EEE30608D16F7BBD32E78197E1D6F8A') { throw 'WebView2 setup script SHA-256 mismatch' }
Set-ExecutionPolicy -Scope Process Bypass
& $p
```

To rebuild a site bundle during development, pass its URL directly to `nimino pack`. Window size, injection files, permissions, and navigation rules can be supplied as URL options; end users should download the corresponding installer from Releases. No named site alias or site-specific definition is required.

### Installing a generated package

The normal beginner path is the [online build workflow](.github/workflows/nimino-pack-online.yml). Download its artifact, then install the package for your operating system:

When building locally, run these commands inside the container development environment (for example with `make shell`) and package a generated bundle first:

```bash
nimino package-linux dist/youtube --format deb --out dist/packages \
  --arch amd64 --maintainer 'Nimino <noreply@nimino.invalid>'
nimino package-windows dist/youtube --format nsis --out dist/packages
# macOS host
nimino package-macos dist/youtube --format app --out dist/packages
nimino package-macos dist/youtube --format dmg --out dist/packages
```

```bash
# Debian/Ubuntu
sudo apt install ./dist/packages/*.deb

# Fedora/RHEL-compatible systems
sudo dnf install ./dist/packages/*.rpm
```

The generated Debian package declares `libgtk-4-1` and `libwebkitgtk-6.0-4`; the RPM declares
`gtk4` and `webkitgtk6.0`, so the package manager resolves the native WebKit dependencies.
They are not downloaded by the Nimino host and are not bundled into the Debian/RPM archive.
On EL10-family systems (CentOS Stream 10, RHEL 10) `webkitgtk6.0` comes from EPEL, so enable
the EPEL repository first; EL9 does not ship WebKitGTK 6.0 and is not supported.
`make rpm-centos-smoke` installs and launches the generated RPM inside a CentOS Stream 10
container as a verification target.

The release catalog is the `popular-packages.json` asset. Download it together with
`nimino-popular-packages.pub`; applications must pin that public key out-of-band and
verify the catalog entry, installer, and SBOM before presenting a Popular Package.

For Windows, run the generated `*-setup.exe` or `.msi`. The installer checks WebView2 and bootstraps it when needed. `make setup` is the equivalent developer setup when working from a checkout.

For an AppImage, make the file executable and run it:

```bash
chmod +x ./dist/packages/*.AppImage
./dist/packages/*.AppImage
```

`package-linux --format flatpak` currently generates a Flatpak build context. The exported `.flatpak` is produced by the Docker validation/release pipeline; it is not yet a signed public download. Custom packages generated by the online workflow are not added to the ready-made gallery; verify the workflow artifact and checksum before installing them.

To remove an installation, use the platform package manager (`apt remove`/`dnf remove`), the Windows uninstaller shown in **Installed apps**, or delete the AppImage. Profile data is separate from the package and may remain under the platform's Nimino application-data directory.

### For developers: run from Docker or Podman

Nim, Nimble, C compilers, GTK/WebKitGTK headers, and packaging tools are provided by the development container. Do not install the development toolchain on the host.

Install either Docker with Docker Compose or Podman with a working Compose provider. Make targets prefer a working `docker compose`, fall back to `podman compose`, and preserve the installed runtime in the error when its Compose provider is unavailable. Set `COMPOSE` explicitly to override the detected command. Container-backed targets fail before building when the selected Compose command is unavailable.

```bash
make setup       # verify the container and prepare Windows WebView2 when WSL Interop is available
make test        # unit and protocol tests
make pack-sites-test
```

## A minimal application

Low-level native API:

```nim
import nimino_native

let app = newNativeApp()
let window = app.newWindow(title = "Nimino", width = 1200, height = 800)
let view = window.newWebView()
view.loadUrl("https://example.com")
app.run()
```

Application framework API:

```nim
import nimino_core

let app = newApp(id = "tech.example.app", name = "Example")
let window = app.newWindow(title = "Example", width = 1200, height = 800)

window.rpc.register("system.version") do () -> string:
  "1.0.0"

window.loadAssets("dist")
window.loadEntry("index.html")
app.run()
```

URL packaging:

```bash
nimino pack https://example.com --out dist/example --host nimino-host

# Optional overrides; URL-only generation remains the default.
nimino pack https://example.com --name Example --id tech.example.app --out dist/example --host nimino-host

# Declarative TOML (also accepted as `nimino pack <manifest.toml>`)
nimino pack --config app.toml --out build/app --host nimino-host

# Pake-style JSON config is also accepted
nimino pack --config pake.json --out build/app --host nimino-host

# Build the bundle and supported Windows/Linux installers together
nimino pack https://example.com --out build/example --host nimino-host \
  --targets deb,rpm,nsis,msi --json

# Local static site (directory must contain index.html)
nimino pack ./dist --name ExampleLocal --out build/example-local --host nimino-host

# Single HTML plus sibling assets (Pake-compatible opt-in)
nimino pack ./site/index.html --use-local-file --out build/site --host nimino-host

# Optional native file-drop events (Core window.onFileDrop)
nimino pack https://example.com --enable-drag-drop --out build/example-drop --host nimino-host
```

URL包装では、利用者がURL以外の内部定義を書く必要はありません。Niminoがホスト名からアプリ名と安定IDを生成し、既定のWindow設定、プロファイル、パッケージ情報を補います。生成マニフェストにサイト固有の認証ドメインやnavigation allow-listは埋め込みません。`nimino-core`が同一サイトとOAuth/SSO遷移を汎用判定し、認証ポップアップはユーザー操作時に明示的なWindowとして生成します。`--name`、`--id`、`--profile`、`--app-version`は必要な場合だけ上書き指定します。ローカル入力はbundleの`assets/`へ配置し、`index.html`を`localEntry`としてhostが`loadAssets`/`loadEntry`経由で開きます。HTTP(S)または`data:`の`--icon`はpack時にbundleへ取得・ステージングします。
`--enable-drag-drop`は、WebViewの既定ドロップ処理を置き換えてネイティブWindowへのファイルドロップを`window.onFileDrop`へ渡す明示オプションです。Windows/Linux/WSLで同じAPIを使えます。単一インスタンスは既定で有効で、並列起動が必要な場合だけ`--multi-instance`を指定します。

そのため、認証が必要なサイトでも、サービスごとに`accounts.google.com`や`googleusercontent.com`を事前列挙する作業は不要です。認証情報とCookieは通常のログイン画面を通じてプロファイルへ保存されます。

See [`docs/api/nimino-pack.md`](docs/api/nimino-pack.md) for manifests, navigation rules, injection, and package formats.

## Components

| Component | Responsibility |
| --- | --- |
| `nimino-native` | Thin Window/WebView layer, native events, JavaScript evaluation, string messages, and capability reporting. |
| `nimino-core` | App lifecycle, typed RPC, profiles, local assets, navigation and permission policy, downloads, dialogs, menus, custom protocols, and notifications (see the caveat below). |
| `nimino-wsl` | Authenticated client/host transport that keeps Nim application logic in WSL and Windows GUI ownership in the host process. |
| `nimino-pack` | URL/manifest wrapping, bundle metadata, icons, injection files, and platform package generation. |

`nimino-native` does not contain RPC, profiles, packaging, WSL transport, or high-level security policy. `nimino-pack` imports no other Nimino package: it depends on the Nim standard library alone and receives a host executable by path (`--host`), never by linkage.

**Notifications are untested.** Treat them as unverified rather than as a working feature. Nothing checks that a notification is ever delivered or activated: the automated tests assert only that the capability reports itself available, that registering an activation callback succeeds, and — on Linux — that the GNotification request returns without error, which GIO does not tie to the desktop shell actually showing anything. The one end-to-end check needs an Apple-issued development identity and a person to click the notification, so it does not run in CI.

### Two released packages

The components are released together from this monorepo as two independently distributable packages. Neither is built from the other.

| Package | Contents | Audience | Release assets |
| --- | --- | --- | --- |
| **nimino-core** | `nimino-host`, the runtime every packaged application embeds | End users receive it inside an installer; embedders who build their own bundles download it directly | `nimino-core-<version>-linux-x86_64.tar.gz`, `nimino-core-<version>-windows-x64.zip` |
| **nimino-pack** | `nimino`, the packaging toolkit CLI | Developers and CI | `nimino-pack-<version>-linux-x86_64.tar.gz` |

`nimino-core` needs GTK 4 + WebKitGTK 6.0 on Linux and the WebView2 Runtime on Windows. `nimino-pack` links no GUI stack at all; it needs OpenSSL for HTTPS icon discovery plus the generator for each package format it is asked to produce (`dpkg-deb`, `rpmbuild`, `appimagetool`, `makensis`, `wixl`). It is published for Linux only because those generators are Linux tools.

All four Nim components (`nimino_core`, `nimino_native`, `nimino_wsl`, `nimino_pack`) are also installable as standalone Nimble packages; see [For Nim developers: install with nimble](#for-nim-developers-install-with-nimble).

## Platform support

| Target | Native stack | Status |
| --- | --- | --- |
| Windows | Win32 + WebView2 Evergreen Runtime | Supported development target; GUI smoke requires a logged-in Windows desktop. |
| Native Linux | GTK 4 + WebKitGTK 6.0 | Supported development target; tested in the container GUI harness. |
| WSL 2 | WSL Nim client + Windows host + WebView2 | Supported development target; requires functional Windows Interop. |
| macOS | Cocoa + WKWebView | Native backend and `.app`/`.dmg` generation implemented; use `make macos-smoke` and `nimble testPackMacos`. Signing/notarization require explicit Apple credentials. Local unsigned/Ad-hoc builds can validate UI and Deep Link, but macOS notification testing requires an Apple-issued development identity; see [`docs/api/nimino-pack.md`](docs/api/nimino-pack.md). |

Nimino does not use `webview/webview`, Photino.Native, Tauri, Electron, WRY, TAO, CEF, Qt WebEngine, Sciter, or an embedded Chromium runtime.

## WSL and Windows setup

WSL GUI tests require WSL 2, Windows Interop (`powershell.exe`, `cmd.exe`, and `$WSL_INTEROP`), Docker Compose or Podman Compose, a logged-in Windows desktop, and WebView2 Evergreen Runtime. `make setup` verifies the selected container environment and invokes the WebView2 installer through PowerShell with UAC elevation when required.

```bash
make setup
make wsl-host-cross
make wsl-host-smoke
make wsl-site-smoke
```

`make wsl-site-smoke` opens YouTube, the public Nim repository on GitHub, and OpenStreetMap sequentially without signing in. It requires each page to complete navigation and expose a ready document with a non-empty title and body before validating JavaScript/message handling and closing the test host automatically. The reviewed target list lives in `tools/ci/wsl-public-sites.txt`.

If `powershell.exe` reports `UtilBindVsockAnyPort: socket failed`, repair Windows Interop from an elevated Windows PowerShell and reopen WSL:

```powershell
wsl --shutdown
Restart-Service LxssManager
```

Detailed setup and runtime ownership rules are documented in [`docs/architecture/`](docs/architecture/) and [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Development commands

Use `make help` for the complete fixed command list. Common checks are:

```bash
make verify-env
make test
make linux-smoke
make windows-cross
make core-windows-cross
make wsl-host-cross
make pack-linux-test
make pack-flatpak-test
make pack-windows-test
make clean
```

The GitHub Actions [CI](.github/workflows/ci.yml) builds the pinned development image and runs `verify-env`, `setup-contract-test`, `test`, `pack-test`, `pack-cli-test`, and `pack-popular-catalog-test` in the container on pushes to `main` and on pull requests.

The ready-made site installers and the two component archives are rebuilt and verified by the [release workflow](.github/workflows/nimino-site-release.yml) on every `v*` tag, before anything is published; that run retains the whole build output as a workflow artifact. Platform-specific suites are opt-in through `NIMINO_TEST_REFERENCE_LINUX`, `NIMINO_TEST_REFERENCE_WINDOWS`, and `NIMINO_TEST_REFERENCE_WSL`, and the Windows and WSL GUI smokes need a logged-in Windows desktop, so they are run from a developer machine rather than by CI.

## Repository layout

```text
packages/native/   nimino-native
packages/core/     nimino-core
packages/wsl/      nimino-wsl client and Windows host
packages/pack/     nimino-pack library, CLI, and its standalone .nimble
catalog/           Popular Packages metadata
docs/              API, architecture, and ADR documentation
tools/ci/          reproducible setup and smoke harnesses
reference/         ignored Tauri/Pake reference checkouts
```

## Documentation

- [Architecture](ARCHITECTURE.md)
- [Native API](docs/api/nimino-native.md)
- [Core API](docs/api/nimino-core.md)
- [Pack API](docs/api/nimino-pack.md)
- [Architecture and ADR index](docs/README.md)
- [Online build and Popular Packages ADR](docs/adr/0018-pack-online-build-and-popular-catalog.md)

## Project status

The Windows, Linux, WSL, macOS, RPC, profile, navigation, permission, download, desktop integration, and packaging paths are under active development. macOS signing/notarization and clean-machine installer upgrade verification require an Apple release environment and are explicit release steps. The README describes the supported workflow; detailed implementation decisions and remaining risks belong in the architecture and ADR documents.

## License

[MIT](LICENSE)
