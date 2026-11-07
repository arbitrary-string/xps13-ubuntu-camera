#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Pre-grant the xdg-desktop-portal camera permission to Google Chrome (.deb build).
#
# Why: with chrome://flags "PipeWire Camera support" enabled, Chrome asks the camera portal for
# access. For the unsandboxed .deb Chrome, GNOME refuses to show the access dialog ("Only the
# focused app is allowed to show a system access dialog") and the portal treats that as a deny,
# so getUserMedia never resolves and Google Meet shows a blank page.
#
# This stores "yes" for Chrome's two possible app IDs, exactly as clicking "Allow" would.
# It deliberately does NOT grant the empty app ID (that would cover every unsandboxed program).
# Websites still need their own camera permission inside Chrome. Run as your normal user.
#
# Undo: Settings -> Apps -> Google Chrome -> Camera, or re-run with "no".
set -euo pipefail
answer=${1:-yes}
for app in google-chrome com.google.Chrome; do
  gdbus call --session --dest org.freedesktop.impl.portal.PermissionStore \
    --object-path /org/freedesktop/impl/portal/PermissionStore \
    --method org.freedesktop.impl.portal.PermissionStore.SetPermission \
    devices true camera "$app" "['$answer']" >/dev/null
  echo "camera permission for $app: $answer"
done
gdbus call --session --dest org.freedesktop.impl.portal.PermissionStore \
  --object-path /org/freedesktop/impl/portal/PermissionStore \
  --method org.freedesktop.impl.portal.PermissionStore.Lookup devices camera
