# Gaze face authentication with IPU6/IPU7 (libcamera) cameras

[Gaze](https://github.com/GunduLabs/gaze) (Gundu Labs, GPL-3.0-or-later) is a modern face-authentication
system for Linux.

> **Fixed upstream: use Gaze 0.5.0 or newer.** The changes that let Gaze use these cameras were merged
> into Gaze as [PR #918](https://github.com/GunduLabs/gaze/pull/918) and shipped in
> [v0.5.0](https://github.com/GunduLabs/gaze/releases/tag/v0.5.0). The Gaze maintainer extended them,
> adding `gaze doctor` checks and a retry when another program is holding the camera.
> **No patching or rebuilding is needed any more.** The `000*.patch` files here are kept only for
> reference: they apply to the old v0.4.2 tag.

What 0.5.0 supports:
- `libcamera:<camera name>` as an `rgb` or `ir` camera source.
- The values the Gaze GUI saves for libcamera cameras (`pipewiresrc target-object=libcamera_input.<id>`).
  The daemon opens these with its own libcamera and never reads frames from your PipeWire session.
- A fix for the capture stall after the first black frame on IPU6.

## Install

1. Install the official packages from the Gundu Labs apt repo, version 0.5.0 or newer (see Gaze's
   README). To set up PAM yourself, opt out of the automatic PAM changes first:

   ```bash
   sudo mkdir -p /etc/gaze && sudo touch /etc/gaze/pam.optout
   sudo apt install gaze gaze-gui gaze-gnome-extension
   ```

2. Set the cameras (`config/<model>/gaze-cameras.toml`).
3. Enroll with the Gaze GUI. Pick "Front Camera" and "IR Camera", **not** "Primary camera": "Primary camera" still selects the IR sensor on these laptops.
4. Test with `gaze test`, then check everything with `gaze doctor`.

**Login integration.**
- `sudo pam-auth-update` → *Gaze Face Authentication (Sequential)* covers `sudo` and polkit. Keep
*Fingerprint authentication* ticked if you use it.
- The **lock screen and GDM** need the GNOME extension:

```bash
gnome-extensions enable gaze@gundulabs.com
dconf write /org/gnome/shell/extensions/gaze/enable-face-authentication true          # lock screen
printf '[org/gnome/shell/extensions/gaze]\nenable-face-authentication=true\n' | \
  sudo tee /etc/dconf/db/gdm.d/99-gaze && sudo dconf update                          # GDM, after reboot
```

Template encryption (`encrypt_templates`, on by default) requires a TPM. Without full-disk encryption,
the TPM seal does not protect templates from someone who boots another OS, so leave keyring unlock off.

## Upgrading from the patched 0.4.2 daemon

If you followed the earlier version of this guide, and so have a patched `gazed` diverted over the stock
one with the packages held, switch back to the official packages like this:

```bash
sudo mv /usr/bin/gazed ~/gazed-patched-0.4.2.bak     # keep the patched binary as a backup
sudo dpkg-divert --remove --rename /usr/bin/gazed    # puts the packaged gazed back
sudo apt-mark unhold gaze gaze-gui gaze-gnome-extension
sudo apt install gaze gaze-gui gaze-gnome-extension  # 0.5.0 or newer
sudo systemctl restart gazed
gaze doctor && gaze test
```

Your existing `/etc/gaze/config.toml`, enrolled faces and PAM setup are kept. The camera values the GUI saved
work unchanged with 0.5.0.

## Files here

- `000*.patch`: the original changes, against v0.4.2. **Historical: not needed with Gaze 0.5.0+.**
- `tools/camtest.rs`: a small example program. Drop it into `crates/gaze-vision/examples/` of a Gaze source
  tree. It opens a camera exactly like the daemon (`Camera::open_privileged` / `open_ir_privileged`) and
  prints frame timing and brightness, which helps when debugging camera problems.

Undo Gaze entirely: `gaze uninstall`.
