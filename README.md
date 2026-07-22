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

### For beginners: build online

No Nim, Docker, or local GUI SDK installation is required for the online path.

1. Fork this repository.
2. Open **Actions → Nimino Pack Online Build → Run workflow**.
3. Enter the website URL, application name, stable ID, and target package.
4. Download the generated artifact from the completed workflow.

The workflow is defined in [`nimino-pack-online.yml`](.github/workflows/nimino-pack-online.yml). It uses the pinned Docker toolchain and produces a bundle, package, checksum file, and SBOM. Supported targets are Linux `.deb`, Linux `.rpm`, and Windows NSIS.

### Prepack Gallery

Prepacks are reviewed application definitions: URL, window defaults, profile name, package metadata, and an explicit navigation allow-list. They do not contain user credentials and they do not bypass the service's normal login flow.

| App | Open in browser | Default window | Profile | Generate |
| --- | --- | ---: | --- | --- |
| **YouTube** | [youtube.com](https://www.youtube.com/) | 1280 × 800 | `default` | `nimino pack prepack youtube` |
| **Gmail** | [mail.google.com](https://mail.google.com/mail/u/0/) | 1280 × 900 | `default` | `nimino pack prepack gmail` |
| **Google Analytics** | [analytics.google.com](https://analytics.google.com/analytics/web/) | 1440 × 900 | `default` | `nimino pack prepack google-analytics` |

#### Download ready-made installers

When a prepack release is published, download the installer directly from the [Nimino Releases page](https://github.com/asopitech-labs/nimino/releases):

| Target | Release assets |
| --- | --- |
| Debian/Ubuntu | `youtube-*.deb`, `gmail-*.deb`, `google-analytics-*.deb` |
| Fedora/RPM | `youtube-*.rpm`, `gmail-*.rpm`, `google-analytics-*.rpm` |
| Windows | `youtube-*-setup.exe`, `gmail-*-setup.exe`, `google-analytics-*-setup.exe` (NSIS) or the matching `.msi` |

The [`Nimino Prepack Release`](.github/workflows/nimino-prepack-release.yml) workflow builds all three applications for every `v*` tag, attaches installers, SBOM files, and `SHA256SUMS` to the GitHub Release. Verify the checksum before installing. Until the first signed release is published, the gallery has definitions and build automation but no official binary download.

The definitions live in [`catalog/prepacks/`](catalog/prepacks/) and are covered by `make pack-prepack-test`. To create a runnable bundle, provide a compiled Nimino host:

```bash
nimino pack prepack youtube --out dist/youtube --host nimino-host
nimino pack prepack gmail --out dist/gmail --host nimino-host
nimino pack prepack google-analytics --out dist/google-analytics --host nimino-host
```

Then launch the generated bundle's `run-nimino.sh` (Linux) or generated Windows launcher. The first launch opens the service sign-in page; credentials and cookies are stored by the selected Nimino profile.

The commands above are for maintainers and developers who need to regenerate a bundle. End users should download the corresponding installer from Releases instead. These source-controlled definitions are not signed release binaries. The official Popular Packages catalog remains empty until an artifact has independently verified checksums, SBOM, provenance, and signature.

### Installing a generated package

The normal beginner path is the [online build workflow](.github/workflows/nimino-pack-online.yml). Download its artifact, then install the package for your operating system:

When building locally, run these commands inside the Docker development environment (for example with `make shell`) and package a generated bundle first:

```bash
nimino package-linux dist/youtube --format deb --out dist/packages \
  --arch amd64 --maintainer 'Nimino <noreply@nimino.invalid>'
nimino package-windows dist/youtube --format nsis --out dist/packages
```

```bash
# Debian/Ubuntu
sudo apt install ./dist/packages/*.deb

# Fedora/RHEL-compatible systems
sudo dnf install ./dist/packages/*.rpm
```

For Windows, run the generated `*-setup.exe`. It is a per-user installer and normally does not require administrator privileges. Nimino uses the Windows WebView2 Evergreen Runtime; the installer does not bundle Chromium or WebView2. `make setup` can install or verify the runtime through elevated PowerShell before the application is started.

For an AppImage, make the file executable and run it:

```bash
chmod +x ./dist/packages/*.AppImage
./dist/packages/*.AppImage
```

`package-linux --format flatpak` currently generates a Flatpak build context. The exported `.flatpak` is produced by the Docker validation/release pipeline; it is not yet a signed public download. Generated packages are not currently published as an official release gallery, so verify the workflow artifact and checksum before installing third-party builds.

To remove an installation, use the platform package manager (`apt remove`/`dnf remove`), the Windows uninstaller shown in **Installed apps**, or delete the AppImage. Profile data is separate from the package and may remain under the platform's Nimino application-data directory.

### For developers: run from Docker

Nim, Nimble, C compilers, GTK/WebKitGTK headers, and packaging tools are provided by Docker. Do not install the development toolchain on the host.

```bash
make setup       # verify the container and prepare Windows WebView2 when WSL Interop is available
make test        # unit and protocol tests
make pack-prepack-test
make pack-prepacks-test
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
nimino pack https://example.com --name Example --id tech.example.app
```

See [`docs/api/nimino-pack.md`](docs/api/nimino-pack.md) for manifests, navigation rules, injection, and package formats.

## Components

| Component | Responsibility |
| --- | --- |
| `nimino-native` | Thin Window/WebView layer, native events, JavaScript evaluation, string messages, and capability reporting. |
| `nimino-core` | App lifecycle, typed RPC, profiles, local assets, navigation and permission policy, downloads, dialogs, notifications, menus, and custom protocols. |
| `nimino-wsl` | Authenticated client/host transport that keeps Nim application logic in WSL and Windows GUI ownership in the host process. |
| `nimino-pack` | URL/manifest wrapping, bundle metadata, icons, injection files, and platform package generation. |

`nimino-native` does not contain RPC, profiles, packaging, WSL transport, or high-level security policy. `nimino-pack` uses only the public `nimino-core` API.

## Platform support

| Target | Native stack | Status |
| --- | --- | --- |
| Windows | Win32 + WebView2 Evergreen Runtime | Supported development target; GUI smoke requires a logged-in Windows desktop. |
| Native Linux | GTK 4 + WebKitGTK 6.0 | Supported development target; tested in the Docker GUI harness. |
| WSL 2 | WSL Nim client + Windows host + WebView2 | Supported development target; requires functional Windows Interop. |
| macOS | Cocoa + WKWebView | Planned; no macOS implementation is included yet. |

Nimino does not use `webview/webview`, Photino.Native, Tauri, Electron, WRY, TAO, CEF, Qt WebEngine, Sciter, or an embedded Chromium runtime.

## WSL and Windows setup

WSL GUI tests require WSL 2, Windows Interop (`powershell.exe`, `cmd.exe`, and `$WSL_INTEROP`), Docker Compose, a logged-in Windows desktop, and WebView2 Evergreen Runtime. `make setup` performs the Docker checks and invokes the WebView2 installer through PowerShell with UAC elevation when required.

```bash
make setup
make wsl-host-cross
make wsl-host-smoke
make wsl-prepack-smoke
```

`make wsl-prepack-smoke` opens YouTube, Gmail, and Google Analytics sequentially, validates WebView2 navigation/JavaScript/message handling, and closes the test host automatically. It does not perform account login.

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

The GitHub Actions CI runs containerized tests, Linux checks, packaging checks, and Windows cross-builds on pushes and pull requests. Windows GUI smoke is an explicit manual job for a self-hosted `wsl2,windows-gui` runner.

## Repository layout

```text
packages/native/   nimino-native
packages/core/     nimino-core
packages/wsl/      nimino-wsl client and Windows host
packages/pack/     nimino-pack library and CLI support
catalog/           prepack and Popular Packages metadata
examples/          small usage examples
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

The Windows, Linux, WSL, RPC, profile, navigation, permission, download, desktop integration, and packaging paths are under active development. macOS, signed public releases, and clean-machine installer upgrade verification are not complete. The README describes the supported workflow; detailed implementation decisions and remaining risks belong in the architecture and ADR documents.

## License

[MIT](LICENSE)
