#!/usr/bin/env bash
set -euo pipefail

# The components in this repository are released together: one tag carries one
# version of all of them, and the release preparation bumps every manifest at
# once. A dependency between them therefore has exactly one correct floor --
# the version being released -- because no other version of the dependency
# exists inside the tag a caller installs from.
#
# Naming an older floor is what broke `nimble install nimino_core`: the
# manifests only exist from v0.2.2, the floor still said 0.2.1, and nimble
# resolved a dependency from the floor upward into a tag that had no manifest
# in the subdirectory. It reported "Could not find a file with a .nimble
# extension" and the install stopped there. Nothing about that is visible in a
# build, so it is checked here instead.

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

manifests=()
while IFS= read -r line; do
  manifests+=("$line")
done < <(find "$root/packages" -mindepth 2 -maxdepth 2 -name '*.nimble' | sort)

test "${#manifests[@]}" -gt 0 \
  || { echo "component versions: no component manifests under packages/" >&2; exit 1; }

# The names a dependency can refer to, so a requirement on an unrelated
# package is left alone.
component_names=()
for manifest in "${manifests[@]}"; do
  component_names+=("$(basename "$manifest" .nimble)")
done

read_version() {
  sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -1
}

root_version=$(read_version "$root/nimino.nimble")
test -n "$root_version" \
  || { echo "component versions: the root manifest declares no version" >&2; exit 1; }

status=0

for manifest in "${manifests[@]}"; do
  version=$(read_version "$manifest")
  name=$(basename "$manifest" .nimble)

  if [ "$version" != "$root_version" ]; then
    echo "component versions: $name is $version, the root manifest is $root_version" >&2
    status=1
  fi

  # requires "nimino_native >= 0.2.2"  ->  nimino_native 0.2.2
  while IFS= read -r requirement; do
    dependency=$(printf '%s' "$requirement" | sed -n 's/^requires[[:space:]]*"\([A-Za-z0-9_]*\).*/\1/p')
    floor=$(printf '%s' "$requirement" | sed -n 's/.*>=[[:space:]]*\([0-9][0-9.]*\).*/\1/p')

    for component in "${component_names[@]}"; do
      if [ "$dependency" = "$component" ] && [ "$floor" != "$root_version" ]; then
        echo "component versions: $name requires $dependency >= $floor, but the tag ships $root_version" >&2
        echo "  a floor below the released version resolves into a tag that may not carry the manifest" >&2
        status=1
      fi
    done
  done < <(grep '^requires' "$manifest" || true)
done

test "$status" -eq 0 \
  || {
    echo "component versions: a release bumps every manifest together, so raise" >&2
    echo "  the versions and the intra-repository floors to the same number." >&2
    exit 1
  }

echo "component versions: $root_version across ${#manifests[@]} components, intra-repository floors match"
