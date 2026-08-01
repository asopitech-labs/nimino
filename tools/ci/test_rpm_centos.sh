#!/usr/bin/env bash
set -euo pipefail

runtime=${1:?usage: test_rpm_centos.sh <docker|podman> <rpm-file>}
rpm_file=${2:?usage: test_rpm_centos.sh <docker|podman> <rpm-file>}
image=${NIMINO_CENTOS_IMAGE:-quay.io/centos/centos:stream10}

test -s "$rpm_file" || { echo "rpm centos smoke: RPM does not exist: $rpm_file" >&2; exit 1; }
rpm_dir=$(cd "$(dirname "$rpm_file")" && pwd)
rpm_name=$(basename "$rpm_file")

# EPEL supplies webkitgtk6.0 for EL10; CRB is required because EPEL's weston
# depends on turbojpeg, which only CRB carries.  Weston provides the headless
# Wayland session: EL10 no longer packages an X11 server, and GTK 4 talks
# Wayland natively.
"$runtime" run --rm -v "$rpm_dir":/nimino-assets:ro "$image" bash -c '
set -eu
dnf -y -q install epel-release dnf-plugins-core >/dev/null
dnf config-manager --set-enabled crb >/dev/null
dnf -y -q install "/nimino-assets/'"$rpm_name"'" >/dev/null
echo "rpm centos smoke: package installed with dependency resolution"
rpm -q gtk4 webkitgtk6.0 >/dev/null
dnf -y -q install weston dbus-daemon dbus-tools mesa-dri-drivers >/dev/null
app_root=$(ls -d /opt/nimino/*/ | head -1)
test -x "${app_root}run-nimino.sh"
export XDG_RUNTIME_DIR=/tmp/nimino-xdg
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
weston --backend=headless --socket=wl-nimino --width=1280 --height=800 >/tmp/weston.log 2>&1 &
sleep 3
export WAYLAND_DISPLAY=wl-nimino GDK_BACKEND=wayland LIBGL_ALWAYS_SOFTWARE=1
# WebKitGTK sandboxes its web process with bubblewrap, which needs an
# unprivileged user namespace. Ubuntu 24.04 hosts restrict those by default
# (kernel.apparmor_restrict_unprivileged_userns), so inside an unprivileged
# container bwrap fails with "Creating new namespace failed" and the app
# exits before it can be observed. The same escape hatch the Xvfb smokes
# already use applies here. It does not weaken what this test checks: the
# subject is RPM dependency resolution and launch, and a real CentOS machine
# has the namespaces the sandbox needs.
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
# On a WSL-hosted kernel every container looks like WSL to the host; the
# escape hatch exists for exactly this Docker smoke situation.  A real
# CentOS machine never needs it.
export NIMINO_TEST_ALLOW_NATIVE_IN_WSL=1
dbus-run-session -- "${app_root}run-nimino.sh" >/tmp/app.log 2>&1 &
app_pid=$!
sleep 15
if ! kill -0 "$app_pid" 2>/dev/null; then
  echo "rpm centos smoke: application exited prematurely" >&2
  cat /tmp/app.log >&2
  tail -5 /tmp/weston.log >&2 || true
  exit 1
fi
kill "$app_pid" 2>/dev/null || true
echo "rpm centos smoke: application stayed alive under weston headless"
'
