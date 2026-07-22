#!/usr/bin/env python3
"""Generate the signed Popular Packages catalog from a site release.

The input is deliberately the release asset directory produced by
build_site_release.sh.  No package metadata is re-authored here: the manifest
inside each bundle is the source of identity, URL, and version.  Every catalog
entry signs the same canonical statement consumed by nimino-pack/catalog.nim.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import pathlib
import re
import subprocess
import tempfile


REPOSITORY = "https://github.com/asopitech-labs/nimino"
WORKFLOW = ".github/workflows/nimino-site-release.yml"
APPS = ("youtube", "gmail", "google-analytics")


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def statement(entry: dict) -> str:
    return "".join(
        (
            "nimino-popular-package-v1\n",
            f"slug={entry['slug']}\n",
            f"name={entry['name']}\n",
            f"appId={entry['appId']}\n",
            f"websiteUrl={entry['websiteUrl']}\n",
            f"version={entry['version']}\n",
            f"target={entry['target']}\n",
            f"architecture={entry['architecture']}\n",
            f"format={entry['format']}\n",
            f"artifact.url={entry['artifact']['url']}\n",
            f"artifact.fileName={entry['artifact']['fileName']}\n",
            f"artifact.sha256={entry['artifact']['sha256']}\n",
            f"artifact.size={entry['artifact']['size']}\n",
            f"signature.algorithm={entry['signature']['algorithm']}\n",
            f"signature.keyId={entry['signature']['keyId']}\n",
            f"source.repository={entry['source']['repository']}\n",
            f"source.commit={entry['source']['commit']}\n",
            f"source.workflow={entry['source']['workflow']}\n",
            f"source.runId={entry['source']['runId']}\n",
            f"source.manifestSha256={entry['source']['manifestSha256']}\n",
            f"source.sbomUrl={entry['source']['sbomUrl']}\n",
            f"source.sbomSha256={entry['source']['sbomSha256']}\n",
        )
    )


def artifact_for(assets: pathlib.Path, app: str, target: str) -> tuple[pathlib.Path, str]:
    if target == "linux":
        candidates = sorted(assets.glob(f"{app}-*.deb"))
        fmt = "deb"
    else:
        candidates = sorted(assets.glob(f"{app}-*-setup.exe"))
        fmt = "nsis"
    if len(candidates) != 1:
        raise SystemExit(f"expected exactly one {target} artifact for {app}, found {len(candidates)}")
    return candidates[0], fmt


def sign(minisign: str, secret_key: pathlib.Path, payload: str, key_id: str) -> str:
    with tempfile.TemporaryDirectory(prefix="nimino-popular-sign-") as directory:
        payload_path = pathlib.Path(directory) / "statement.txt"
        signature_path = pathlib.Path(directory) / "statement.minisig"
        payload_path.write_text(payload, encoding="utf-8")
        command = [minisign, "-S", "-s", str(secret_key), "-m", str(payload_path),
                   "-x", str(signature_path), "-q"]
        completed = subprocess.run(command, capture_output=True, text=True)
        if completed.returncode != 0:
            raise SystemExit(f"minisign signing failed: {completed.stderr.strip()}")
        # The Nim verifier decodes the complete minisign file, not just the
        # base64 signature line.  Canonical base64 avoids alternate encodings.
        return base64.b64encode(signature_path.read_bytes()).decode("ascii")


def build_entry(assets: pathlib.Path, app: str, target: str, tag: str,
                commit: str, run_id: str, key_id: str, minisign: str,
                secret_key: pathlib.Path) -> dict:
    manifest_path = assets / f"{app}-{target}-nimino-manifest.json"
    sbom_path = assets / f"{app}-{target}-nimino-sbom.cdx.json"
    if not manifest_path.is_file() or not sbom_path.is_file():
        raise SystemExit(f"missing manifest or SBOM for {app}/{target}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    artifact_path, package_format = artifact_for(assets, app, target)
    version = manifest["package"]["version"]
    filename = artifact_path.name
    entry = {
        "slug": f"{app}-{target}-amd64",
        "name": manifest["name"],
        "appId": manifest["id"],
        "websiteUrl": manifest["url"],
        "version": version,
        "target": target,
        "architecture": "amd64",
        "format": package_format,
        "artifact": {
            "url": f"{REPOSITORY}/releases/download/{tag}/{filename}",
            "fileName": filename,
            "sha256": sha256(artifact_path),
            "size": artifact_path.stat().st_size,
        },
        "signature": {
            "algorithm": "minisign-ed25519",
            "keyId": key_id,
            "value": "",
        },
        "source": {
            "repository": REPOSITORY,
            "commit": commit,
            "workflow": WORKFLOW,
            "runId": run_id,
            "manifestSha256": sha256(manifest_path),
            "sbomUrl": f"{REPOSITORY}/releases/download/{tag}/{sbom_path.name}",
            "sbomSha256": sha256(sbom_path),
        },
    }
    entry["signature"]["value"] = sign(minisign, secret_key, statement(entry), key_id)
    return entry


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--assets-dir", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--secret-key", required=True, type=pathlib.Path)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--minisign", default="minisign")
    args = parser.parse_args()
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.+-]+)?", args.tag):
        raise SystemExit("release tag must be a SemVer tag such as v1.2.3")
    if not re.fullmatch(r"[0-9a-f]{40}", args.commit):
        raise SystemExit("commit must be a 40-character lowercase SHA-1")
    if not re.fullmatch(r"[0-9]+", args.run_id):
        raise SystemExit("run-id must be numeric")
    if not args.secret_key.is_file():
        raise SystemExit(f"minisign secret key does not exist: {args.secret_key}")
    entries = [
        build_entry(args.assets_dir, app, target, args.tag, args.commit,
                    args.run_id, args.key_id, args.minisign, args.secret_key)
        for app in APPS
        for target in ("linux", "windows")
    ]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({"schemaVersion": 1, "entries": entries},
                                      indent=2, sort_keys=False) + "\n",
                            encoding="utf-8")


if __name__ == "__main__":
    main()
