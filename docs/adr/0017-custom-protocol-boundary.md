# ADR-0017: Custom WebView scheme と OS deep link の分離

Status: Accepted

## Context

`customProtocol` という名前は、WebView内部のリソースschemeと、OSがアプリを起動するdeep linkの二つを指し得る。WebView2の`WebResourceRequested`とWebKitGTKの`register_uri_scheme`は前者のAPIであり、Windows registry、Linux Desktop Entry、単一起動・URL転送は後者のAPIである。これらを一つのCapabilityや一つのcallbackへまとめると、認証・URL検証・ライフサイクル境界が曖昧になる。

## Decision

- `customProtocol` Capabilityは、WebView内部のリソースschemeだけを意味する。Windowsは`WebResourceRequested`、LinuxはWebKitGTK URI scheme callbackへ接続済みで、WSLはrelay未実装のため`false`または`unsupported`を返す。
- OS deep linkは別Capability/API（将来の`openUrl`または`deepLink`）として設計する。`nimino-pack`のmanifest、Windows per-user registry、Linux Desktop Entry、WSL host activation relayを同時に設計・検証する。
- 任意scheme、任意OS API、未検証の外部URLを暗黙に許可しない。schemeはmanifestで明示し、handlerはWindow/App scopeの許可リストに限定する。
- Windows実装ではWebView2 SDK headerから`WebResourceRequested`のIID、vtable slot、callback寿命を固定確認し、LinuxではWebKitGTK 6.0 headerからURI scheme requestのGObject寿命を固定確認する。推測したFFI slotでは実装しない。

## Consequences

Windows/Linux nativeで`customProtocol`を成功扱いにするには、scheme handlerのbody/status/MIME、navigation policy、閉鎖時callback解放、deep linkとの非混同を含む独立ハーネスが必要になる。WSL relayは未実装なのでWSLのCapabilityをfalseに維持する。
