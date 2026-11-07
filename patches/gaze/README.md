# Gaze patches — face authentication with IPU6/IPU7 (libcamera) cameras

[Gaze](https://github.com/GunduLabs/gaze) (Gundu Labs, GPL-3.0-or-later) is a modern face-authentication
system for Linux. Its privileged daemon `gazed` only trusts real `/dev/video*` nodes, which on Intel
IPU laptops are raw capture nodes, so it cannot use these cameras. These patches (same licence) apply
to the **v0.4.2** tag:

| Patch | Change |
|---|---|
| `0001` | New camera source `libcamera:<camera name>` for `rgb` and `ir`; the daemon opens it with its own `libcamerasrc` (same trust model as Gaze's built-in `primary` libcamera fallback). |
| `0002` | The GUI saves choices as `pipewiresrc target-object=libcamera_input.<id>`; the daemon maps that back to the libcamera camera by reversing WirePlumber's name sanitising. No frames are ever read from the user's PipeWire session. |
| `0003` | Don't clock-sync the appsink for `libcamerasrc` — its timestamps don't follow the pipeline clock and capture stalls after one black frame. **This also affects stock Gaze's IPU6/IPU7 `primary` fallback.** |

`tools/camtest.rs` is a small example program (drop it into `crates/gaze-vision/examples/`) that opens
a camera exactly like the daemon and prints frame timing/brightness — useful for testing as root.

## Build and install (only the daemon is replaced)

```bash
# official packages from the Gundu Labs apt repo (see Gaze's README), but opt out of automatic PAM changes first:
sudo mkdir -p /etc/gaze && sudo touch /etc/gaze/pam.optout
sudo apt install gaze gaze-gui gaze-gnome-extension

# build the patched daemon from the same version
sudo apt install build-essential pkg-config clang libclang-dev libopencv-dev libv4l-dev libpam0g-dev \
  libtss2-dev libssl-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev gstreamer1.0-libcamera \
  gstreamer1.0-pipewire rustc cargo git libdbus-1-dev
git clone --branch v0.4.2 https://github.com/GunduLabs/gaze.git && cd gaze
git am /path/to/this/repo/patches/gaze/*.patch
cargo build --locked -p gazed --release

# swap it in; dpkg-divert keeps apt from overwriting it
sudo dpkg-divert --add --rename --divert /usr/bin/gazed.distrib /usr/bin/gazed
sudo install -m 0755 target/release/gazed /usr/bin/gazed
sudo systemctl restart gazed
sudo apt-mark hold gaze gaze-gui gaze-gnome-extension    # rebuild the patches before upgrading
```

Then set the cameras (`config/<model>/gaze-cameras.toml`), enroll with the Gaze GUI ("Front Camera" /
"IR Camera" — **not** "Primary camera"), test with `gaze auth --verbose`.

**Login integration:** `sudo pam-auth-update` → *Gaze Face Authentication (Sequential)* covers `sudo`
and polkit (keep *Fingerprint authentication* ticked if you use it). The **lock screen and GDM** need
the GNOME extension:

```bash
gnome-extensions enable gaze@gundulabs.com
dconf write /org/gnome/shell/extensions/gaze/enable-face-authentication true          # lock screen
printf '[org/gnome/shell/extensions/gaze]\nenable-face-authentication=true\n' | \
  sudo tee /etc/dconf/db/gdm.d/99-gaze && sudo dconf update                          # GDM, after reboot
```

Template encryption (`encrypt_templates`, default on) requires a TPM. Without full-disk encryption the
TPM seal does not protect templates from someone booting another OS — leave keyring unlock off.

Undo: `sudo dpkg-divert --remove --rename /usr/bin/gazed` then `gaze uninstall`.
