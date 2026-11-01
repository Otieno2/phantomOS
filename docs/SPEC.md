# PhantomOS — specification

Status: **draft v0.2**, 2026-10-24. v0.1 carried an AI/dev tier; it was dropped on maintainer
request the same day. This file is the authority for what gets built and in
which order. If a TODO, backlog note, or chat message disagrees with this file, this file
wins and the other gets corrected. Nothing counts as done until it has been run and the
result recorded (§11).

## 1. What it is

A Debian-derived Linux distribution: an amd64 live/install ISO for a **hardened, minimal
workstation**, used by the maintainer and a small circle of friends.

Hardened and minimal are compatible goals, so there is no role-tier machinery. The image is one
curated package set. Anything GPU/ML-related is installed by hand if it is ever needed and is
explicitly out of scope (§2).

## 2. Non-goals

- Not a general-public distro. No mirrors, no support forum, no marketing.
- No custom kernel in v1. Debian's kernel is used as-is (§6.4).
- No own desktop environment. No DDE. (§3.2)
- No AI/ML or GPU stack. No NVIDIA driver, no CUDA, no container platform in the image.
  Removed from scope 2026-10-24; if it returns it returns as its own opt-in package, never as a
  default.
- No `.iso`-level customization baked into squashfs that cannot be fixed post-install (§4.3).
- No Ubuntu/PPA package sources. Base is Debian; anything else enters through our own repo.
- No ARM builds.

## 3. Base

### 3.1 Facts checked for this spec (2026-10-24; build-host rows 2026-10-29; archive re-read 2026-10-31; shipped-image rows 2026-11-01)

| Item | Value | Source |
|---|---|---|
| Debian current stable | 13 "trixie", point release 13.7 (2026-09-12) | debian.org/releases |
| Debian testing | "forky", expected as Debian 14 in 2027 | debian.org/releases |
| `xfce4` metapackage in trixie | 4.20.1 | packages.debian.org/trixie/xfce4 |
| DDE shell in Debian (`dde-daemon`, `dde-dock`, `dde-desktop`, `dde-session-shell`, `dde-kwin`) | **absent from every suite** | packages.debian.org name search |
| Deepin-branded apps | `deepin-terminal`, `deepin-icon-theme` 2025.03.27-1 present in trixie. **`deepin-gtk-theme` is in no Debian suite** — this row said "present (sid/trixie)" until 2026-10-24 and was wrong; re-checked with a `suite=all` name search that returned "Sorry, your search gave no results" | packages.debian.org name search, suite=all |
| `deepin-icon-theme` contents | installs "Deepin Icon Theme", "Sea Icon Theme" **and "Deepin Cursor Theme"** — one package covers both §12 item 2 candidates | packages.debian.org/trixie/deepin-icon-theme |
| Identity fonts in trixie | `fonts-montserrat` 7.222-3 and `fonts-jetbrains-mono` 2.304+ds-5, both in **main**; `fonts-ubuntu` absent | packages.debian.org/trixie/<pkg> |
| Xfce shell plugins in trixie | `xfce4-whiskermenu-plugin` 2.9.2-1, `xfce4-docklike-plugin` 0.4.3-1, `plank` 0.11.89-6+b1, `light-locker` 1.8.0-3 | packages.debian.org/trixie/<pkg> |
| `rofi` in trixie | 1.7.5-0.1 — "window switcher, run dialog and dmenu replacement", X11 | packages.debian.org/trixie/rofi |
| `picom` in trixie | 12.5-1, X11 compositor with blur — the only route to a blurred launcher overlay, and it replaces xfwm4's own compositor | packages.debian.org/trixie/picom |
| `xfdashboard` (DDE-style overview) | **not in any Debian suite** (bookworm, trixie, forky, sid) — no package exists to install | packages.debian.org name search |
| `calamares` in trixie | 3.3.14-1, with `calamares-settings-debian`; depends on KDE Frameworks and Qt | packages.debian.org/trixie/calamares |
| Build-host distro image | Debian 13 "trixie", `DEBIAN_VERSION_FULL=13.5`, amd64, kernel `6.18.33.2-microsoft-standard-WSL2`. The image is a **13.5 point release while the archive is at 13.7** — the base is trixie, not "13.7", and every package version below was read from the archive index, not from this image | `cat /etc/os-release`, `uname -r`, `dpkg --print-architecture` inside the WSL instance, 2026-10-29 |
| Stock live ISO, as booted | `DEBIAN_VERSION_FULL=13.7`, `VERSION_CODENAME=trixie`, `IMAGE_ID=live`, `BUILD_ID=20261029T062739Z`, kernel `6.12.113+deb13-amd64`, root `overlay` over `filesystem.squashfs`. Read from the **running** guest, not from the host or the archive: the built image follows the archive (13.7), not the build host's base (13.5), and it carries Debian's kernel rather than the WSL one | run H, 2026-10-30 — `logs/evidence/M0-runH-os-release.png`, `M0-runH-session-facts.png` |
| PhantomOS live ISO, as shipped | `DEBIAN_VERSION_FULL=13.7`, `VERSION_CODENAME=trixie`, `IMAGE_ID=live`, `BUILD_ID=20261101T140728Z`; ISO volume id `Debian trixie 20261101-17:07`. Extracted out of the archived artifact's squashfs rather than read off a running guest — and this row's first version quoted that `BUILD_ID` before anyone had read it anywhere, so it was withdrawn and re-made as a measurement. The volume id is the *same* timestamp rendered in **local** time at minute resolution, because `LB_UTC_TIME="false"`; `BUILD_ID` is rendered with an explicit `--utc` and so is not affected by that switch | run M artifact `2026-11-01T140727Z`, extracted 2026-11-01 — `logs/M1-buildid-per-run.txt` |
| Two runs of this tree are **not** byte-identical | run M `BUILD_ID=20261101T140728Z`, run N `BUILD_ID=20261101T172103Z` — each exactly one second after the stamp `scripts/build-iso.sh` gave the run. Their `/etc/os-release` files differ in that one line and nothing else (`cmp` identical once `^BUILD_ID=` is stripped from both), and their 98-assignment config dumps are byte-identical. Cause: nothing exports `SOURCE_DATE_EPOCH`, so live-build defaults it to the wall clock (§12 item 16). **This also invalidates artifact mtimes as evidence of when a build finished**: `/usr/lib/live/build/binary_iso:230` `touch`es the ISO to the epoch, so run M's 908 066 816-byte artifact reports mtime `17:07:28 +0300` — one second after the run *started*, ~105 minutes before it ended | `logs/M1-buildid-per-run.txt`, 2026-11-01 |
| Archive versions re-read from the archive itself, 2026-10-31 | Not a web check — the four `…_Packages` files the build resolves from, in the build host's `/var/lib/apt/lists`. Everything above still holds. Three rows are one **binNMU** behind apt's candidate: `xfce4-docklike-plugin` 0.4.3-1+b1, `light-locker` 1.8.0-3+b1, `rofi` 1.7.5-0.1+b2 — same source version, so no §5 claim moves. The one that is not a suffix: **`firefox-esr` in trixie-security is a different ESR series than in trixie** (153.6.0esr vs 140.15.0esr) and the image installs security's, as it installs security's `flatpak` 1.16.6-1~deb13u3 — measured from the image's own build log, not from the index. And the build host's **backports index does not reach the image**, proved twice inside one artifact: kernel `6.12.113+deb13-amd64` from security rather than backports' `7.2.11-1~bpo13+1`, and `wireplumber` 0.5.8-2 rather than 0.5.12-1~bpo13+1. The absence rows above are **not** covered by this re-read: the host has main-only indices, so "absent" there still rests on the 2026-10-24 `suite=all` searches | `logs/M1-facts-recheck-2026-10-31.txt`, 2026-10-31 |

### 3.2 Base decision

Base on **trixie**, not forky or sid. Rationale: trixie's security team absorbs CVE work for
free, and a derivative living in testing spends its life chasing breakage instead of shipping.
Rebase to forky **after** Debian 14 releases; do not track it.

Desktop is **Xfce 4.20 with a Deepin-style theming layer**. Chosen over KDE Plasma (heavier,
theme churns on point releases) and GNOME (largest baseline surface, extension maintenance
tax), and over building real DDE from linuxdeepin source, which would mean packaging and
maintaining dozens of interdependent Qt components forever. The Deepin look is delivered by
theme, not by upstream shell.

### 3.3 Known upstream constraint

Desert OS — named during scoping — is not a desktop environment. It is an Ubuntu-based,
SourceForge-distributed Xfce remix. Only its *visual recipe* is reusable here; none of its
packages, PPA, or update channel may be pulled into PhantomOS.

## 4. Architecture

### 4.1 Layers

| Layer | Contents | Owner |
|---|---|---|
| base suite | trixie, unmodified package set | Debian |
| `phantomos-base` | hardening, keys, default policy, dotfile skeleton | us |
| `phantomos-desktop` | Xfce + theming + workstation apps | us |
| image | live-build config that installs both | us |

### 4.2 Package split

Two metapackages, both always installed together in the shipped image:

- **`phantomos-base`** — hardening policy, keys, defaults. Makes no GUI assumption, so a friend
  who wants a headless box can install it alone.
- **`phantomos-desktop`** — Xfce, theming, workstation apps. Depends on base.

This is a *packaging* split, not an install-time role selector. v0.1 had a selectable third tier
for GPU/ML work; it is gone (§2), so no task/profile mechanism is needed and none should be
built.

### 4.3 Customization lives in `.deb` packages

Every customization is delivered as a source package built into our repo. Specifically:

- `phantomos-release` — apt sources list, signing key, branding, `sources.list.d` entries.
- `phantomos-config` — Xfconf/gsettings defaults, dotfiles, sysctl, AppArmor local profiles,
  systemd drop-ins, firewall rules. Ships as `skeleton` + `postinst` that only writes files
  that are absent (never overwrites a user's edit).
- `phantomos-artwork` — plymouth, GRUB, wallpaper, icon theme, cursor.
- `phantomos-installer` — Calamares `settings.conf`, branding descriptor, module configs,
  slideshow (§4.4).
- `phantomos-doctor` — the §6 self-check CLI, shared with `tests/hardening/` (§5.3).

Nothing above the `image` layer may be implemented as raw file copies inside the live-build
hook. Reason: files copied into squashfs are unfixable after release — they cannot be updated,
only replaced by a new ISO. Package-delivered config is upgradable. This is the single most
load-bearing rule in this document.

### 4.4 Installer — Calamares

Decided 2026-10-24: **Calamares from the live session**, not a Debian Installer passthrough.

- **Availability:** `calamares` 3.3.14-1 is in trixie, and `calamares-settings-debian` is the
  packaging precedent to copy rather than reinvent. Requires a live session, which M0 now produces
  and has photographed (§9 run H) — though note that the stock live session it produced is a text
  console, so Calamares still needs a desktop (§4.1) before it can run.
- **Cost accepted:** Calamares depends on KDE Frameworks and Qt. The desktop is Xfce/GTK, so the
  live image carries a second full toolkit — hundreds of MB of Qt/KF libraries — used only by the
  installer. On the installed system the `calamares` package is removed by the post-install job,
  so the tax is live-image-only. This is the one place §5's "minimal" claim has an asterisk, and
  it is a deliberate documented exception, not drift.
- **Config is a package.** `phantomos-installer` (§4.3) ships `settings.conf`,
  `branding/phantomos/descriptor.yaml` + slideshow, and `modules/*.conf` for partition,
  bootloader, displaymanager, users, locale. Upstream Calamares defaults are never edited in the
  squashfs.
- **Disk crypto is unverified, and stays that way in this document.** Calamares' partition module
  documents LUKS support, but the behaviour that matters — passphrase-only vs TPM-bound keyslot,
  `/boot` handling, swap encryption — must be established by an actual install run at M3 and
  written back into §6.1. Until then §6.1 describes intent, not a shipped control.
- **TPM enrollment** is not assumed to be an installer feature. If M3 confirms it is absent, it
  becomes a documented first-boot step from `phantomos-config`, and §6.1 is corrected to say so
  rather than left aspirational.
- **Slideshow discipline:** the installer slideshow shows progress and neutral facts only. It is
  the place derivatives quietly ship claims nobody verified, and §11 forbids that.
- Secure Boot stays off (§6.2), so the `bootloader` module + GRUB path is simple. Revisit only if
  M6 happens.

## 5. Package inventory

Decided 2026-10-24 (maintainer picks): the desktop image ships **dev tools** and **media
playback**, and deliberately ships **no office suite and no mail client**. "Minimal" now means
something specific: the image has no suite people install out of habit.

`phantomos-base` (no GUI): phantomos-release, phantomos-config, sudo, unattended-upgrades,
apparmor, nftables, lvm2, cryptsetup, ca-certificates, apt-listchanges, openssh-client (no
server), flatpak — plus the kernel and the hardware-enablement packages named in this section's
2026-10-31 amendment, which is where the firmware decision lives.

`phantomos-desktop`: xfce4 + panel/thunar/power-manager, rofi 1.7.5 (fullscreen launcher,
§7.2), xfce4-whiskermenu-plugin 2.9.2 (fallback menu), a dock — `plank` 0.11.89 or
`xfce4-docklike-plugin` 0.4.3, choice open (§12 item 8),
xorg (the X server, added 2026-11-01 — see the amendment below), lightdm, light-locker 1.8.0
(session lock), pipewire + pipewire-pulse + wireplumber + pavucontrol,
network-manager + network-manager-applet (this section said "nm-applet" until 2026-11-01; the
substitution and its reason are in `manifests/desktop.pkgs:7-10`),
firefox-esr (+ policies, §6.9), mpv, ristretto, git,
build-essential, python3-venv, fonts (§5 tail).

**Inventory tail — resolved 2026-10-24.** `xfce4-goodies` 4.20.0 is **not** installed as a
metapackage: its Depends list is 30 packages, and an inventory copied from a metapackage is
precisely the "default install with a new name" this section forbids. That list is the menu;
these are taken, each for something the spec already asks for.

| Package | Why it is in the image |
|---|---|
| `xfce4-terminal` | the mono identity font (§7.2) needs a real terminal; also where `phantomos-doctor` output is read |
| `mousepad` | a GUI editor for config edits. Terminal-only `nano` is a worse answer for four non-expert users |
| `thunar-archive-plugin` | right-click extract on downloaded source tarballs, the one dev-workflow applet in the list |
| `xfce4-notifyd` | notifications, and the only surface where ok/err tokens are legal (§7.2) |
| `xfce4-power-manager` | the battery and suspend behaviour the right capsule displays (§7.2); in goodies only as a Recommends |
| `xfce4-battery-plugin` | laptop fleet — the mock's right capsule has a battery readout |
| `xfce4-screenshooter` | §7.4 requires a real screenshot per surface, so the tool that takes them ships |
| `xfce4-taskmanager` | GUI process kill for "this hung" debugging that isn't a `pkill` lesson |
| `xfce4-genmon-plugin` | the only off-the-shelf way to put PhantomOS's own status in a capsule without writing and maintaining a C plugin; also the cheapest candidate route to §12 item 9 |
| `ristretto`, `xfce4-whiskermenu-plugin` | already listed above — both are in the goodies Depends list, which is why they appear once here |

Dropped, 19 of them: `xfburn` (no optical media in scope), `thunar-media-tags-plugin` (no media
library), `xfce4-dict`, `xfce4-verve-plugin`, `xfce4-places-plugin`, `xfce4-timer-plugin`,
`xfce4-xkb-plugin` (single-layout users; `setxkbmap` covers the rest), `xfce4-wavelan-plugin`
(legacy), and every telemetry applet the three-capsule mock has no slot for —
`xfce4-cpugraph-plugin`, `xfce4-cpufreq-plugin`, `xfce4-systemload-plugin`,
`xfce4-netload-plugin`, `xfce4-diskperf-plugin`, `xfce4-fsguard-plugin`,
`xfce4-sensors-plugin`, `xfce4-notes-plugin`.

Three drops are rule conflicts rather than taste, and are worth keeping written down:
`xfce4-mailwatch-plugin` contradicts the no-mail decision above; `xfce4-weather-plugin` pulls
live data from a third-party web service, which is a needless outbound dependency under §6.0's
driftnet posture; `xfce4-clipman-plugin` keeps clipboard history in plaintext on disk, which turns
the remote compromise §6.0 actually assumes into a one-read grab of whatever was ever
copy-pasted — and no capsule in the mock has a clipboard slot.

**Fonts.** Three packages, no font zoo — the base families (`fonts-dejavu`, `fonts-liberation`,
`fonts-noto`) arrive as Xfce/GTK/Firefox dependencies and are not a branding decision.

| Package (trixie, all in main) | Role |
|---|---|
| `fonts-inter` 4.1+ds-1 | UI text: panel capsules, menus, rofi grid, windows |
| `fonts-montserrat` 7.222-3 | display only: the `PHANTOM` wordmark and plymouth |
| `fonts-jetbrains-mono` 2.304+ds-5 | terminal, and the decrypt prompt **if** the console constraint below (§12 item 2) clears |

This is a **delta to §7.2's own wording**, not a silent reinterpretation: that line asked for a
"geometric sans for UI". Inter is a low-contrast grotesque, not geometric, and it is the better
UI face at 10–13px; Montserrat is the geometric one and is in main, so it keeps the wordmark
where the geometry actually reads. §7.2 is amended accordingly.

The constraint nobody has checked yet: **§7.2's "mono for the decrypt prompt" may not be
delivered by a TTF at all.** A GRUB theme consumes a bitmap font built with `grub-mkfont`
(`.pf2`), not TrueType — and if the LUKS prompt is rendered on the initramfs console rather than
by Plymouth, the font is a Linux console `.psf`, again not TrueType. Which renderer owns that
prompt is a question for the first real boot, so it is now part of §12 item 2 and M2's artwork
exit criteria rather than a promise in the identity section.

**Deepin packages.** `deepin-gtk-theme` **does not exist in Debian** (§3.1 said it did; that was
wrong and is corrected). So the "Deepin-style theming layer" of §3.2 cannot come from a GTK theme
package: it is either icons or our own CSS. Decided: `phantomos-artwork` **authors GTK CSS** on
top of the base theme, and `deepin-icon-theme` 2025.03.27-1 is **not** shipped — its icon set is
colourful and rounded, which is not Apparition — but stays documented because the same package
also carries **Deepin Cursor Theme**, making it a live candidate for §12 item 2's cursor pick at
no extra dependency cost.

Justifications were required for each entry because an inventory without them is a default
install with a new name.

**M1 amendments, 2026-10-30.** Two names were added to the `phantomos-desktop` line above, and the
addition is not a taste change — it is what `--apt-recommends false` did to a line that used to
read "pipewire + pavucontrol". From the trixie index
(`logs/M1-recommends-edges.txt`): `pipewire` 1.4.2-1 Depends on adduser, libpipewire-0.3-modules,
pipewire-bin, init-system-helpers and **Recommends nothing at all**; `wireplumber` arrives as a
Recommends of `pipewire-bin`, and `pipewire-pulse` as a Recommends of `wireplumber`, which
Recommends it back. So with Recommends off, the old line installed the daemon and the mixer GUI and
no session manager and no PulseAudio-compatible socket. `pipewire-pulse` and `wireplumber` are named
in the desktop manifest for that reason; nothing else in the inventory can reach them, and none of
the three appears in the 319 (the delta's SET already carried them).

The same reading of the index turned up a class of gaps this section has not closed yet — an auth
agent, GVfs, `udisks2`, the flatpak portals, `wpasupplicant` — each of which used to arrive as a
Recommends of something §5 does name. They are §12 item 12, not silently added and not silently
dropped.

**M1 amendments, 2026-10-31 — hardware enablement, and the end of live-build choosing it.**
The first M1 build's package-set diff came back with seven names in the image that this section
had never named. All seven turned out to be one mechanism, and the mechanism is live-build's, not
a Recommends: with the default `--firmware-chroot true`, `chroot_firmware` downloads the archive's
`Contents-all` and `Contents-<arch>` files and hands apt *every* package that ships a path under
`lib/firmware`, as explicit installs (`/usr/share/live/build/functions/firmwarelists.sh`, whose own
comment states the assumption: "firmware packages install files into /lib/firmware"). Against
trixie main that rule yields six packages — five from `Contents-all` (32 paths) plus `indi-dsi`
from `Contents-amd64` (1 path) — and `chroot_linux-image` adds the seventh, `linux-image-amd64`
(`--linux-packages linux-image` + `--linux-flavours amd64`).
`logs/M1-firmware-contents-repro.txt` reproduces the enumeration from the Contents files the build
cached; `logs/M1-firmware-contents-lines.txt` gives the Contents line, the `.deb` size and the
index fields for each name.

That is not a list that can be reviewed once and trusted, for two measured reasons. It is the
image's package set being decided by a file on the mirror — a point release that moves any
package's data under `lib/firmware` adds it to every future image without a commit in this repo,
which is what §11 forbids. And it scales badly at exactly the door §12 item 11 is about: the same
rule against trixie's `non-free-firmware` yields **34 packages over 4792 paths**, and `contrib` 2
more (`logs/M1-firmware-nonfree-scale.txt`). So enabling that area with the rule switched on is not
"add `firmware-iwlwifi`", it is "add 34 firmware packages and find out what the image weighs".

Decided: `live/auto/config` sets `--firmware-chroot false` (the second behaviour change and the
third line in `scripts/config-audit.sh`'s diff; `--firmware-binary` is left at its default because it is read only by
`installer_debian-installer`, which `--debian-installer none` means never runs), and the enablement
that is actually wanted is named in `manifests/base.pkgs` with the reason for each:

| Package | .deb | Why it is in the image |
|---|---|---|
| `linux-image-amd64` | meta | §6.4: Debian's kernel as shipped, no rebuild. Named here so that the inventory — not only live-build's kernel stage — says it |
| `firmware-linux-free` | 17 832 B | the 24 blobs in-kernel drivers request by name |
| `firmware-ath9k-htc` | 45 040 B | AR7010/AR9271 USB Wi-Fi — the adapter a friend brings to a meeting |
| `firmware-carl9170` | 15 336 B | AR9170 USB Wi-Fi, same reason |
| `wireless-regdb` | 12 400 B | ships `usr/lib/firmware/regulatory.db-debian` (`logs/M1-firmware-contents-lines.txt`), and M0's log line 2407 shows `update-alternatives` installing that as `/lib/firmware/regulatory.db`. Without it the kernel has no regulatory domain and cannot pick legal transmit power. §12 item 12 had it as a `Recommends:` of `network-manager`; naming it closes that one |
| `alsa-topology-conf` | 15 276 B | ships `usr/lib/firmware/skl_hda_dsp_generic-tplg.bin`, the Intel Skylake+ HDA/DSP topology file. The only machine this repo knows about is §9's build host, an HP EliteBook 840 G3 (i5-6200U, Skylake) — no friend's hardware has been recorded, so this is "the machine we have", not "the fleet" |

`indi-dsi` — a Meade Deep Sky Imager camera driver, 56 624 B, present only because of
`usr/lib/firmware/meade-deepskyimager.hex` — goes into `manifests/drops.pkgs`, the guard file, so
that the claim "--firmware-chroot false keeps it out" is checked on every build rather than
believed.

**The ownership claim itself, checked.** "Named because nothing else names them" is only worth having
if the manifest is what keeps each package in the image, so a reverse-Depends scan settled it:
tokenising `Depends:` and `Pre-Depends:` over **335 894** edges in the four **main** indices on the
build host, nothing in the archive depends on `firmware-linux-free`, `firmware-ath9k-htc`,
`firmware-carl9170`, `alsa-topology-conf` or `indi-dsi` at all, and `wireless-regdb` has exactly one
dependent, `reform-desktop-minimal`, which this selection does not pull. All five are in
`phantomos-base`'s generated `Depends:`; `indi-dsi` is not. Deleting a line from
`manifests/base.pkgs` therefore deletes a package from the image — and the same paragraph is the
§12 item 11 warning: opening `non-free-firmware` means re-running this scan, because an edge from
outside **main** would quietly make a line here redundant (`logs/M1-firmware-ownership.txt`).

Two things this amendment does **not** do, and where they live: it does not decide the
`non-free-firmware` area (§12 item 11 is still open, and it is now a decision about named packages
rather than about a rule); and it does not restore ALSA's UCM configuration, which is the companion
package `alsa-ucm-conf` — measured absent from the image, arriving only as a `Recommends:` of
`libasound2-data`, so it is added to §12 item 12 rather than being slipped in here.

**A correction, because the claim was in this file and was wrong.** §9.1 and §12 item 11 both said
M0 installed "exactly three" firmware packages. That count was produced by matching names beginning
with `firmware-`, not by reading the log's install records. On dpkg's own `Setting up` lines, M0 and
the 2026-10-31 M1 build installed the *same six* — `alsa-topology-conf`, `firmware-ath9k-htc`,
`firmware-carl9170`, `firmware-linux-free`, `indi-dsi`, `wireless-regdb` — plus `linux-image-amd64`
(`logs/M1-firmware-m0-correction.txt`). Both lines are amended above; the two original mentions
carry a correction note.

**M1 amendments, 2026-11-01 — the X server was never in this inventory.** §10's M1 exit
criterion has two halves, and only the first had been run. The diff went green on run M
(`logs/M1-diff-runM.txt:86`), but "§5 inventory complete with a justification per entry" had
never been tested against this section's *text* — and it could not be tested by the diff,
because `scripts/m1-diff.sh:37` states the bridge the diff then relies on rather than checks:
"`manifests/base.pkgs`, `manifests/desktop.pkgs` — §5's inventory." The comparison is
manifest against image, so a name that is in a manifest and not in §5 is invisible to both
directions at once.

Reading §5 line by line against all three manifests (`logs/M1-xorg-ownership.txt` §1):
`base.pkgs` 18 of 18, `live.pkgs` 0 of 7 by its own design, `desktop.pkgs` 29 of 31. One of
the two gaps was a spelling: this section said "nm-applet", which is not a package name in any
Debian suite, and `manifests/desktop.pkgs:7-10` had already recorded the substitution to
`network-manager-applet` with its reason — `network-manager-gnome` is only a metapackage for
the applet plus `nm-connection-editor`, and this section names the applet, not the editor. The
inventory line now carries the real name, because an inventory that names a package the archive
does not have is a defect even where everybody knows what it meant. The other gap is `xorg`,
which no line of §5's then-201 mentions in any spelling: a case-insensitive scan for `xorg`,
`xserver`, `x11`, `x server` and
`display server` over the whole section returned nothing, and the line above used to go
straight from the session lock to the audio stack.

It is load-bearing, and that was measured rather than assumed. `xorg` is a hard `Depends:` of
the generated `phantomos-desktop` (32 names = the 31 in `desktop.pkgs` plus `phantomos-base`,
read out of `pool/phantomos-desktop_0.1.0-1_all.deb`), so it survives
`--apt-recommends false`. Every other route to an X server in trixie is a Recommends and is
therefore off: `lightdm Recommends: xserver-xorg`, `xfce4 Recommends: …, xorg`,
`xinit Recommends: xserver-xorg | xserver`, and `lightdm`'s own Depends names no X server at
all. Eight packages in the whole archive hard-depend on `xserver-xorg` or `xorg`; of those
eight, exactly one is in run M's image, and it is `xorg`. Restricting reverse-Depends to the
image gives a chain with one entry point — `phantomos-desktop` -> `xorg` -> `xserver-xorg` ->
`xserver-xorg-core` plus the video and input driver sets — and nothing in the image
hard-depends on `xorg` itself. Delete the line from `manifests/desktop.pkgs` and the image
has no X server by any route; lightdm installs with nothing to start, and the greeter in
§9's M1-boot photographs exists only because that line is there.

So `xorg` is named above, with the versions the index gives and run M unpacked agreeing:
`xorg` 1:7.7+24+deb13u1, `xserver-xorg` 1:7.7+24+deb13u1, `xserver-xorg-core`
2:21.1.16-1.3+deb13u4, `lightdm` 1.32.0-6+b2, `light-locker` 1.8.0-3+b1, `xinit` 1.4.2-1.
It is **not** moved off §12 item 12's list, because it was never on it: that item is about a
Recommends this section used to get for free, and an X server was never in the inventory to
lose. Two things this amendment does not do. It is not an experiment — no build was run with
the line removed, at ~1 h 45 m a run, and the conclusion rests on the archive's edges instead
(`logs/M1-xorg-ownership.txt` §4). And it does not decide X11 against Wayland: §7.2 already
records the session as X11, lightdm + Xfce 4.20 on trixie ships no Wayland session to name,
and the one alternative route that would survive Recommends-off, `task-desktop`, would bring
`tasksel` and `desktop-base` and let a Debian task choose the session — which is the "default
install with a new name" this section's inventory tail exists to refuse.

### 5.1 Sandboxed apps

Flatpak is installed; **Flathub is not preconfigured** (decided 2026-10-24). The sandbox exists
for apps the user vettes deliberately, and nothing installs into it silently or auto-updates
outside our signing key. `snapd` is not installed.

### 5.2 Rollback — the cost of choosing ext4

Filesystem is **ext4 on LVM** (§6.1), so `snapper`-style automatic snapshots are off the table
and a bad PhantomOS update on a friend's machine is a restore-from-backup event. Accepted
2026-10-24 in exchange for the least-surprising Calamares and Debian path.

One partial mitigation stays available, undecided: LVM snapshots work regardless of filesystem,
so `phantomos-snapshot` could take a thin snapshot before `apt full-upgrade` and offer
`lvconvert --merge` on next boot. Sharp edge to respect: an undersized or overfilled snapshot
hangs IO rather than failing cleanly, so it needs a size/TTL policy and a test — it is not a
free feature. Tracked as open question 7.

### 5.3 What makes it a product

Three things are PhantomOS's own, and they are scoped before any wallpaper is picked:

- **`phantomos-doctor`** — a CLI that runs the §6 checks on a live machine and prints pass/fail
  with the command that produced each result. This is what turns "hardened" from a claim into
  something a friend can verify, and it is the only feature here that the spec depends on for
  §6.10 to be satisfiable by users rather than by the maintainer alone. Built as its own package,
  and `tests/hardening/` is the same code behind a different entry point — one implementation,
  two callers, so a check that passes in CI is the check a user can run.
- **First-boot setup** — one guided pass after install: LUKS keyslot hygiene, TPM enrollment if
  §6.1's M3 run shows it is possible, whether to enable `ssh`, accent colour choice. It exists to
  fill the gaps Calamares leaves, and it should stay a thin wrapper over `phantomos-config`, not a
  second place where system state gets written.
- **Firefox policy set** — §6.9.

Everything else in the image is Debian's, and the release notes should say so plainly.

## 6. Hardening specification

### 6.0 Threat model

Decided 2026-10-24: **remote attack and driftnet only.**

- **In scope:** network-borne exploitation, hostile or compromised packages, passive observation
  on networks we actually use, silently-failing updates, and the browser as the main entry point.
- **Out of scope:** physical seizure, boot-chain tampering by someone holding the machine,
  evil-maid attacks, coercive key disclosure.
- **Consequences:** Secure Boot off (§6.2) is acceptable, and **M6 stays deferred** — an unsigned
  boot chain costs little when the adversary never has the hardware. TPM enrollment (§6.1) is
  convenience, not defence.
- **Boundary the docs must hold:** PhantomOS is **not** a defence against someone with the machine
  powered on or the disk pulled. LUKS at rest still helps, but with GRUB/kernel unverified, an
  attacker with physical access does not need our passphrase. Release notes and any README must
  state this rather than let "hardened" imply more.
- Also out of scope: anonymity and traffic analysis (no Tor by default) and any compliance claim.

### Controls

Each numbered item below has a stated verification command (§6.10). A control that cannot be
checked on a running install is not a control. Item **1 is Disk**, referenced elsewhere as §6.1.

1. **Disk:** LUKS2 full-disk with **ext4 on LVM inside** (filesystem decided 2026-10-24, §5.2);
   unlock by passphrase, TPM2 enrollment via
   `systemd-cryptenroll` offered at install. `/boot` unencrypted (SB off, §6.2), so LUKS +
   passphrase policy is the actual protection and is described that way to users. **Status:
   intent, not a shipped control** — how much of this Calamares' partition module can do is
   established by the M3 install run and written back here (§4.4).
2. **Secure Boot:** **off for v1**, decision recorded 2026-10-24. Consequence: boot chain has
   no tamper resistance; revisit as M6 with own MOK key and key-custody procedure if the
   threat model ever includes physical access.
3. **Mandatory access:** AppArmor, enforce mode, with profiles for the browser and any
   network-facing service. Not SELinux — Xfce/desktop integration is far cheaper here.
4. **Kernel:** Debian's `linux-image-amd64` as shipped, no rebuild. Debian already applies the
   hardening compile flags we would want; a custom kernel would cost us Secure Boot signing and
   a per-release rebuild for no measurable gain.
5. **Network:** default-deny inbound via `nftables`; `ssh`, `avahi-daemon`, `cups-browsed`
   disabled by default and enabled explicitly. **Wording corrected by a run, 2026-10-30**
   (`logs/M1-service-closure.txt`): in the §5 selection's dependency closure none of the three is
   present at all — `openssh-client` ships and `openssh-server` does not (§5), and Recommends is
   off (§9.1), which is what used to pull `avahi-daemon`. So the shipped property is *not
   installed*, which is stronger than disabled, and the §6.10 check must assert absence rather than
   masked units or it passes for the wrong reason. The masking still belongs in
   `phantomos-config`: it is what keeps this item true after a friend installs the package.
6. **Updates:** `unattended-upgrades` for both security and our own repo, with our key pinned
   (§8). No install path may result in a system that silently never updates.
7. **User/session:** no root password; sudo with tty; user units hardened via
   `phantomos-config` drop-ins (`PrivateTmp`, `NoNewPrivileges` where compatible with desktop).
8. **Sandbox policy:** flatpak present, **no Flathub remote configured** (§5.1). Adding a remote
   is a deliberate, logged user action, so no third-party auto-updating catalog can ship inside
   a "hardened" image. `snapd` absent.
9. **Browser policy:** Firefox enterprise policies shipped by `phantomos-config` — enforced DoH,
   third-party cookies blocked, extension installs restricted. The browser is where the internet
   actually enters a "hardened workstation", so this control matters more than most sysctls.
10. **Verification:** each control ships with a check in `tests/hardening/` run against a live
   VM; the run log is committed. Controls are reported as pass/fail with the command that
   produced the result.

## 7. Branding and identity

### 7.1 Trademark and upstream obligations

Once the package set differs from Debian's, Debian branding and mirror defaults must be
removed and replaced with our own artwork and repository URLs. From day one: own name, own
logo (no Debian swirl), own GRUB/plymouth, own `Release` origin string.

### 7.2 Visual identity — Apparition

Decided 2026-10-24. **Apparition**: void black, fog grey, one cold accent. **Dark only in v1** —
dropping the light variant is what keeps two palettes from having to stay in sync across panel,
lock, GRUB, plymouth and the installer.

Tokens are the single source of truth; every theme file derives from this table, and nothing
hard-codes a hex elsewhere.

| Token | Hex | Where it is used |
|---|---|---|
| void | `#0B0C0F` | desktop background, plymouth, lock backdrop, GRUB |
| surface | `#14161B` | panel capsules, dock, windows, menu popovers |
| elevated | `#1B1E25` | list rows, app tiles, hover |
| line | `#262B33` | 1px borders |
| text | `#E7ECF3` | primary text |
| muted | `#8A939F` | secondary text, captions |
| accent | `#7DF9FF` | focus ring, active window dot, progress, prompts |
| ok / err | `#7DFFB0` / `#FF6B6B` | **functional only** — terminal and notification output |

One brand hue. The ok/err pair is not identity: it exists because `phantomos-doctor` has to
report pass/fail, and it is confined to terminal and notification contexts. The tray popover
carrying 40% of that cyan would be the moment this theme turns into a nightlight.

**Shell layout (decided):** top panel as **three floating capsules + a dock**.

- left capsule — launcher button, workspace dots
- centre capsule — date · clock
- right capsule — tray: network, sound, battery, power
- dock — bottom-centred floating bar, running indicators in accent
- launcher overlay — `rofi` fullscreen grid on `Super`, panel hidden while it is open
- geometry — capsules fully rounded (17px on a 34px bar), other surfaces 8px
- type — `fonts-inter` for UI, `fonts-montserrat` for the wordmark only, mono
  (`fonts-jetbrains-mono`) for the terminal and the decrypt prompt **if** the console-font
  constraint in §5's tail clears; wordmark `PHANTOM` letterspaced, used in plymouth and as the
  wallpaper's faint mark. Amended 2026-10-24: this line said "system geometric sans for UI", and
  the geometric face (Montserrat) turned out to be the wrong tool at UI sizes.

**Surfaces `phantomos-artwork` must produce:** wallpaper, panel + dock CSS, rofi theme (grid
layout, dim overlay), whisker theme, lock screen, plymouth (wordmark and LUKS prompt), GRUB,
Calamares branding and slideshow, icon and
cursor choices.

**Constraints found when checking the archive (2026-10-24), not negotiable by taste:**

- **Fullscreen launcher** is a maintainer requirement (2026-10-24), and the package that delivers
  it is `rofi` 1.7.5-0.1: `-show drun` themed as a grid covering the whole screen. Rofi is in
  trixie and built for X11, which matches our lightdm + Xfce session. `xfdashboard` — the closer
  functional match — is in **no Debian suite at all**, so that route means packaging and
  maintaining a component ourselves for four users.
  Two deltas, stated here instead of being discovered later: **rofi is keyboard-first** —
  clickable, but not built to be dragged. And **the overview dims the wallpaper rather than
  blurring it.** Blur is not impossible: `picom` 12.5-1 is in trixie and can blur window
  backgrounds, but on Xfce that means switching xfwm4's built-in compositor off and running a
  second one — a configuration that has to be proven at M2, with real risks (tearing,
  double-compositor conflicts, and one more always-running process behind a "hardened" label). So
  **v1 ships the dim overlay**; blur is an explicit M2 stretch goal with a test, not a promise.
  `xfce4-whiskermenu-plugin` 2.9.2 remains installed only as the fallback if rofi theming fights us
  at M2; it is not the primary launcher.
- The capsule panel is GTK CSS applied to `xfce4-panel` 4.20.1. It is the single most likely place
  the delivered result differs from the mock, and **it is unverified** — M2 owes a real screenshot
  per surface plus a written delta, per §7.4.
- `light-locker` 1.8.0-3 themes through GTK CSS only; expect approximation rather than the mock
  reproduced pixel for pixel. `xfce4-screensaver` is the alternative.
- A grouped tray popover like the one mocked has no off-the-shelf Xfce plugin. Open question 9:
  theme standard applet menus, build the popover, or use `xfce4-genmon-plugin` (§5 tail) as a
  script-driven approximation. This line pointed at "open question 8" until 2026-10-24; 8 is the
  dock. Only the third option ships no new code, and none of them has been tried in a session.

### 7.3 Asset rules

- Every third-party asset needs a license that permits **redistribution inside our signed
  repo**. A wallpaper pulled from a photo site is not automatically redistributable; source and
  license get recorded per asset.
- The Deepin-flavoured detail cannot come from `deepin-gtk-theme` — that package is in no Debian
  suite (§3.1), so the theme is **ours**, authored as GTK CSS inside `phantomos-artwork`.
  `deepin-icon-theme` exists but is not shipped by default (§5 tail); the Deepin Cursor Theme in
  the same package stays a §12 item 2 candidate. None of it may be copied into the squashfs
  (§4.3).
- Identity assets are referenced by `phantomos-artwork` and swapped via package updates, so a
  rebrand never requires a new ISO.

### 7.4 Artwork is verified like a control

For each surface in §7.2: a screenshot from a real session, committed, plus one line stating where
it differs from the mock. A mockup is a target, not evidence — the panel capsules especially.

## 8. Repository and distribution

- `aptly` (or `reprepro`) publishing `phantomos-base|desktop` components.
- `debsign` on all uploads; `apt-transport-https`; repo served over HTTPS only.
- Rationale: with even a handful of friends, an unsigned or HTTP apt channel makes PhantomOS
  itself the supply-chain risk. Integrity of `apt update` is a release-blocking requirement,
  not a polish item.
- ISO images published with SHA256 + `.sig` from the same key.
- Key custody: one operator, offline master, documented rotation. Written down before the first
  friend installs, because recovery is impossible afterwards.

## 9. Build environment

Windows is the host; nothing in this toolchain runs natively there. `live-build`, `debootstrap`,
squashfs and loop mounts need Linux with root.

**State of this machine, checked 2026-10-24 — every line below came from a command.** WSL
2.7.10.0, kernel 6.18.33.2-2, WSLg 1.0.73.2, Windows 10.0.26300.9711. Host is an **HP EliteBook
840 G3, Intel i5-6200U**, a 2016 dual-core/4-thread ultrabook: expect ISO builds to be slow and to
want several GB free for the chroot and squashfs stages.

**M0 is blocked by firmware, and Windows has been eliminated as the cause.** The runs, in order:

1. `wsl --install -d Debian --no-launch` → exit 127, `HCS_E_HYPERV_NOT_INSTALLED`, no distro
   registered.
2. Elevated `Enable-WindowsOptionalFeature -FeatureName VirtualMachinePlatform`, then a **manual
   reboot** at 02:44.
3. Elevated read-only re-check of the feature and boot state:

   ```
   FEATURE VirtualMachinePlatform            = Enabled
   FEATURE HypervisorPlatform                = Disabled
   FEATURE Microsoft-Windows-Subsystem-Linux = Enabled
   FEATURE Microsoft-Hyper-V-All             = Enabled
   hypervisorlaunchtype                      = Auto     (bcdedit /enum {current})
   HypervisorPresent                         = False    (Win32_ComputerSystem)
   ```

4. `wsl --install -d Debian --no-launch --web-download` after the reboot: the download **succeeded**
   and registration then failed with
   `Wsl/InstallDistro/Service/RegisterDistro/CreateVm/HCS/HCS_E_HYPERV_NOT_INSTALLED`.
5. `Get-WinEvent` on the System log, provider `Microsoft-Windows-Hyper-V-Hypervisor`:

   ```
   ID 41 [Error] Hypervisor launch failed; Either VMX not present or not enabled in BIOS.
   ```

   — repeated on **every** boot back to 2026-10-15, so it predates anything done for this project.

**Conclusion (2026-10-24):** Intel VT-x (VMX) was off in firmware. There was nothing to change in
Windows — VMP, the Linux-subsystem feature and the Hyper-V role were all Enabled, and the boot
configuration already launched the hypervisor. The fix was **F10 at power-on → System
Configuration → Virtualization Technology → Enabled**, then reboot, with `HypervisorPresent`
(`Win32_ComputerSystem`) becoming `True` as the authoritative check. A BIOS change on the
maintainer's machine is not something to automate from here.

**Unblocked 2026-10-29:** the maintainer enabled VT-x and rebooted at 09:10. `HypervisorPresent` is
now **True** and `wsl --install -d Debian --no-launch --web-download` reported *"Distribution
successfully installed"*; `wsl -l -v` shows `Debian … 2`. No further Windows change was needed.

**Build-host preflight, run as root inside that instance on 2026-10-29:**

| Check | Result |
|---|---|
| `overlay`, `squashfs`, `fuse`, `ext4` in `/proc/filesystems` | all present |
| `/dev/loop-control`, `losetup -f` | present, `/dev/loop0` free |
| `mount -t tmpfs` as root | ok |
| `deb.debian.org` resolves | ok |
| root shell without the first-run wizard | `wsl -d Debian -u root` works; no user creation needed |
| CPUs / memory visible to the guest | 4 CPUs, **3.77 GiB RAM** (WSL2 defaults to half the host's 7.9 GB) |
| Free space | host `C:` had **41.2 GB**. The guest's `df` claims 956 GB and that figure is worthless for planning: the vhdx grows dynamically into the host partition, so 41.2 GB is the real ceiling |

**The build tree goes inside the WSL filesystem, never under `/mnt/c`.** The project directory sits
on a Windows partition mounted through drvfs, which is slow across the tens of thousands of small
files a chroot contains and does not carry Linux ownership or device-node semantics. `live-build`
runs in the guest; only the log and the finished ISO are copied out, and §9 already requires that
ISOs stay out of git.

**Toolchain installed 2026-10-29** (`apt-get install live-build debootstrap squashfs-tools
dosfstools xorriso git curl`, exit 0, `dpkg --audit` clean): live-build `1:20250505+deb13u1`,
debootstrap `1.0.141`, squashfs-tools `1:4.6.1-1` (`mksquashfs version 4.6.1`), xorriso
`1.5.6-1.2+b1`, dosfstools `4.2-1.2`, git `1:2.47.3-0+deb13u1`, curl `8.14.1-2+deb13u7`. Log:
`logs/M0-toolchain.log`. 227 packages installed in total.

**Stock live-build defaults, read from the config tree `lb config` generated on 2026-10-29** —
none of these are what a person would guess, and two of them change what we have to do later:

- `LB_COMPRESSION="none"`. **This one was misread on 2026-10-29 and corrected on 2026-10-30.** It
  does not touch the squashfs: `grep -rn LB_COMPRESSION /usr/lib/live/build` finds it only in
  `binary_tar`, `binary_netboot`, `source_tar` and `binary_zsync` — none of which run for
  `iso-hybrid`. The rootfs is built by `binary_rootfs`, which reads
  `LB_CHROOT_SQUASHFS_COMPRESSION_TYPE` and, when that is empty as it is by default, passes
  `-comp xz` to mksquashfs. Proof from the M0 artifact itself: `unsquashfs -s
  binary/live/filesystem.squashfs` → `Compression xz`, filesystem size 295856912 bytes. So there
  was never an uncompressed image, and M1 had no size delta to measure. M1 still pins
  `--chroot-squashfs-compression-type xz` explicitly, which changes nothing today and stops an
  upstream change of that hardcoded default from altering the artifact silently.
- `config/package-lists/live.list.chroot` is `live-boot`, `live-config`, `live-config-systemd`,
  `systemd-sysv` — no desktop at all, so M0's ISO boots to a text console, and the stock live
  system is **systemd**-based. That matters later for how `phantomos-config` gets tested.
- `LB_IMAGE_TYPE="iso-hybrid"`, `LB_BINARY_FILESYSTEM="fat32"` (the EFI partition), BIOS bootloader
  `syslinux`, EFI bootloader `grub-efi`, `LB_CHECKSUMS="sha256"`.
- Mirrors are plain HTTP: `http://deb.debian.org/debian/` and `http://security.debian.org/`. This
  is not a §8 violation — integrity comes from the signed `InRelease` (`I: Valid Release signature`
  in the build log), not from the transport. §8's HTTPS-only rule governs *our* apt channel.
- `lb config noauto` writes **no `auto/config`**, so the invocation lives only in a log line, not
  in the tree. For M1 the config must be committed as `auto/config`: a build that can only be
  reproduced from someone's shell history is not a build.

**M0 stock build, run 2026-10-29 in `/root/m0-live` (no PhantomOS content).**
`lb config noauto --architectures amd64 --binary-images iso-hybrid --distribution trixie`, then
`lb build` → **`P: Build completed successfully`, exit 0**, 09:27:39 → 10:10:53 = **43 m 14 s** on
4 vCPU / 3.77 GiB. Artifact `live-image-amd64.hybrid.iso`: **363,855,872 bytes (347 MiB)**,
SHA256 `871d7984f6be0d261ab10a493311113d0ccb9dff379e9dc0ce873d4c8bf7c61c`. Log kept as
`logs/M0-lb-build.log` (3696 lines); the ISO itself stays out of git. Contents: squashfs rootfs
296 MiB (**xz-compressed** — see the `LB_COMPRESSION` correction above; the ISO is larger than the
rootfs because of the FAT EFI image and the boot tree), `vmlinuz` 13 MiB, `initrd.img` 42 MiB, plus
`isolinux/`, `boot/`, `EFI/`. `fdisk` on the ISO shows an MBR with a 3.3 MiB EFI FAT partition — a
real hybrid image, not an ISO that only works in a VM. Kernel **inside the image** is
`6.12.113+deb13-amd64`, which is not the WSL host kernel (`6.18.33.2-microsoft-standard-WSL2`):
the image carries Debian's kernel, as §6.4 requires.

Two findings from those runs that change later work:

- **The stock image carries no user account, and the stock live system logs one in anyway.** In the
  built chroot, `/etc/passwd` has no `user` entry at all — the last accounts are `uuidd` and
  `messagebus` — and root's shadow field is `*`. That is not the whole story, and the first version
  of this bullet got it wrong by saying the image "has no login". Reading the shipped scripts,
  2026-10-30:
  - `live-config`'s component `/lib/live/config/0030-user-setup` creates the account at first boot
    through debconf, and it runs because **`user-setup` 1.107 is installed** (line 224 of
    `chroot.packages.install`, alongside `sudo` 1.9.16p2-3+deb13u2 at line 217). Its defaults come
    from `/lib/live/init-config.sh`: `LIVE_USERNAME="user"`, `LIVE_USER_FULLNAME="Debian Live user"`,
    and a hardcoded `_PASSWORD="8Ab05sVQ4LLps"` which the script's own comment says is **`live`**.
    The same script sets root's password to `*` deliberately.
  - Console autologin comes from **`/usr/lib/systemd/system-generators/live-config-getty-generator`**
    — a systemd *generator*, which is why grepping the image for a getty override finds nothing: the
    drop-in does not exist until the generator runs. Booted with `boot=live` it writes, for tty1–tty6,
    `getty@ttyN.service.d/live-config_autologin.conf` containing
    `ExecStart=-/sbin/agetty --autologin user --noclear %I $TERM`. It exits early on the kernel
    parameters `noautologin` / `nottyautologin`, and also early **if that exact conf path already
    exists**.
  - Confirmed on screen, run H below: `debian login: user (automatic login)` and a
    `user@debian:~$` prompt, with `id` reporting `uid=1000(user) … 27(sudo)`.
  Two consequences, both for M1+. **(a)** A stock live image hands an unauthenticated,
  sudo-group shell on all six virtual terminals, protected only by a password (`live`) that is
  printed in the shipped script — §6's threat model (§6.0 assumes remote adversaries) cannot start
  from that, so `phantomos-config` must own user creation *and* console login explicitly rather
  than inherit it. **(b)** The generator's "already exists" check is the clean hook: shipping a
  file at `/etc/systemd/system/getty@tty1.service.d/live-config_autologin.conf` makes live-config
  stand down without masking a generator or adding a boot parameter. That is the mechanism to use,
  and it must be verified in a run before it is relied on.
- **Loop-mounting the hybrid ISO from a file works in WSL2** (`mount -o loop,ro`, verified
  2026-10-30), so a built image can be inspected without a VM. An earlier attempt here failed on
  `failed to setup loop device` and the script printed "mounted" anyway; the real cause was a wrong
  path, not the kernel. ISO layout as built: `boot/`, `EFI/`, `efi.img`, `isolinux/`, `live/`,
  `sha256sum.txt` — the rootfs is `live/filesystem.squashfs` (295,858,176 bytes on the ISO, and the
  same file pre-ISO at `binary/live/filesystem.squashfs`). **A harness must test `mountpoint -q`
  after mounting**; an unchecked mount turns into a confident conclusion drawn from an empty
  directory.

**M0 boot test — which run produced which artifact.** Same ISO throughout
(SHA256 `871d7984…c61c`), same QEMU invocation shape (`-m 1024 -smp 2 -accel kvm -display none`,
framebuffer pulled with the monitor's `screendump` and converted by `pnmtopng`). Runs A, E, F and G
are BIOS-path; I and J add the UEFI path. `logs/evidence/M0-evidence-sha256.txt` checksums the
artifacts; the per-run harness logs are `logs/M0-run{G,H,I,J}.log`.

| run | date | how it was booted | what it proves | artifact |
|---|---|---|---|---|
| A | 2026-10-29 | ISO in QEMU, VGA visible | the ISO's own isolinux menu renders | `logs/evidence/M0-bootA-syslinux-menu.png` |
| E | 2026-10-29 | `-cdrom` ISO, headless, `sendkey ret` at 30 s | the default entry boots and reaches a shell — **confirmed only on 2026-10-30**, when the frames were finally looked at; on the night it ran, this claim rested on four differing framebuffer hashes | `logs/evidence/M0-runE-iso-booted-vga.png` |
| F | 2026-10-29 | `-kernel`/`-initrd` extracted from the ISO, `console=ttyS0` | the kernel + live-boot initramfs mount the squashfs and reach `debian login:` unattended | `logs/evidence/M0-serial-transcript.txt`, `M0-runF-serial-session-vga.png` |
| G | 2026-10-30 | `-cdrom` ISO, `sendkey ret` at 8 s | the live-boot splash renders with the image's own build metadata; also the run that typed into a blank console and proved nothing (below) | `logs/evidence/M0-runG-live-boot-splash.png` |
| H | 2026-10-30 | `-cdrom` ISO, `sendkey ret` at 30 s, shell typed into at 250 s | **M0's exit criterion**: `cat /etc/os-release` from the running ISO, booted by the ISO's own isolinux | `logs/evidence/M0-runH-os-release.png`, `M0-runH-session-facts.png` |
| I | 2026-10-30 | `-cdrom` ISO, `-machine q35` + OVMF pflash | the same ISO boots and reaches the same shell by the **EFI** path; `info kvm` → `kvm support: enabled` | `logs/evidence/M0-runI-uefi-os-release.png` |
| J | 2026-10-30 | as I | that I really was UEFI: `ls /sys/firmware/efi` → `config_table efivars fw_platform_size fw_vendor mok-variables runtime runtime-map systab` | `logs/evidence/M0-runJ-uefi-sys-firmware-efi.png`, `M0-runJ-uefi-efivars-mok.png` |

Run I's os-release frame is **byte-identical** to run H's (both SHA256 `33f353d8…5c7a`). That is
what a correct cross-check looks like — same squashfs, same getty, same screen — but it also means
run I is not an independent picture of the session. The UEFI-specific evidence is run J's
`/sys/firmware/efi`, not the os-release frame. `mok-variables` being present in that listing is
noted for §6.2 without being leaned on: MOK stays deferred with M6.


Run H's screen, read off the framebuffer: `debian login: user (automatic login)`, then from
`user@debian:~$` — `cat /etc/os-release` → `PRETTY_NAME="Debian GNU/Linux 13 (trixie)"`,
`VERSION_ID="13"`, `VERSION_CODENAME=trixie`, **`DEBIAN_VERSION_FULL=13.7`**, `ID=debian`,
`IMAGE_ID=live`, `BUILD_ID=20261029T062739Z`; `uname -r` → `6.12.113+deb13-amd64`; `findmnt /` →
`overlay rw,noatime,lowerdir=/run/live/rootfs/filesystem.squashfs/,upperdir=/run/live/overlay/rw,
workdir=/run/live/overlay/work,redirect_dir=on`; `cat /proc/cmdline` →
`BOOT_IMAGE=/live/vmlinuz boot=live components quiet splash initrd=/live/initrd.img`; `id` →
`uid=1000(user) gid=1000(user) groups=1000(user),24(cdrom),25(floppy),27(sudo),29(audio),30(dip),
44(video),46(plugdev),100(users),101(netdev)`.

Three things in that output are worth holding onto:

- `BOOT_IMAGE=/live/vmlinuz` in `/proc/cmdline` is what makes run H a test of *the ISO* rather than
  of my own kernel handout: those arguments were composed by `isolinux.cfg` inside the image
  (`append boot=live components quiet splash`, `live.cfg`). Run F, which used `-kernel`/`-initrd`
  extracted from the ISO, cannot make that claim — it tests the same files by a different path, so
  it is kept as corroboration and not as the milestone gate.
- `BUILD_ID=20261029T062739Z` is 06:27:39 UTC = **09:27:39 EAT**, which is the `lb build` start time
  recorded above and the string the splash in run G printed. Build metadata survived from the build
  into the running system, so an ISO can be identified from inside it — that matters for §10's
  support window and for a friend reporting a bug.
- `DEBIAN_VERSION_FULL=13.7` in the image against **13.5** on the build host (§3.1) confirms the
  built image tracks the archive rather than the host's base image.

Runs G and H also differ in one way that cost a wasted run and is worth writing down: **the
framebuffer goes blank between the live-boot splash and the login banner.** Run G pressed Enter at
8 s, saw the splash at 20–40 s, then captured uniform black from 60 s on and typed its username and
`cat /etc/os-release` into that window — every frame after the typing differed from the one before
by nothing more than the cursor blink, and the run looked like a hung image. Run H waited 240 s
before touching the keyboard and the shell was sitting there. A blank screendump is not evidence
about the guest; a hash that changes is not evidence that anything was typed. The check that
distinguishes them is *looking at the frame*, which costs nothing and had not been done until run H.


Also noted for M0's second half: `HypervisorPlatform` — the nested-virtualisation feature — read
**Disabled** on 2026-10-24, so "QEMU with KVM inside WSL2" had to be proven rather than assumed.
**Checked 2026-10-29 after the firmware fix:** the guest has `/dev/kvm` (`crw-rw---- root kvm`),
`kvm_intel` and `kvm` are loaded, and `/dev/vhost-net` exists — so the preferred route of building
*and* boot-testing in one WSL2 environment is open. What remains unproven is that QEMU actually
starts with `-accel kvm` there; that is a one-command check once QEMU is installed, not a theory to
argue with.

- Primary (intended): WSL2 Debian instance with `live-build` and `debootstrap` installed, building
  as root inside that distro (live-build needs mount namespace control).
- Known risk, **narrowed but not closed** by the preflight above: WSL2's kernel does have
  loop/squashfs/overlay/fuse, so the original worry ("the mounts may not exist") is gone. What is
  still unproven is live-build's own use of mount namespaces and `debootstrap` under a Microsoft
  kernel. If `lb build` fails on mount errors that do not reproduce on a real kernel, move to a
  Debian VM rather than debugging WSL. Do not sink days into WSL-specific workarounds.
- **Two halves of M0, and they need different things:** *building* the ISO happens in WSL2;
  *booting* it needs a VM. Preference is QEMU inside WSL2 with `nestedVirtualization=true` in
  `.wslconfig` and WSLg showing the display, so build and test share one environment. If KVM is
  unavailable or nested virt is flaky, fall back to a Windows-side hypervisor — and say which was
  used in the M0 log rather than leaving it implicit.
  **Resolved 2026-10-29:** QEMU 10.0.13 runs in the guest with `-accel kvm`, so build and boot-test
  do share one environment and no separately-launched Windows VM was needed. WSLg turned out to be
  unnecessary — the guest is run `-display none` and the framebuffer is captured with the monitor
  command `screendump`, which produces the screenshot artifact without a window to photograph.
  **KVM claimed, 2026-10-29; KVM verified, 2026-10-30:** run I asked the monitor `info kvm` and got
  `kvm support: enabled`. The earlier sentence had been written from `-accel kvm` being on the
  command line, which only says what was requested, and the command I first reached for there
  (`info accelerators`) does not exist.
- **Memory ceiling measured, not assumed:** a QEMU guest at `-m 2048` inside the WSL VM (3.77 GiB
  total) produced `Wsl/Service/CreateInstance/HCS_E_CONNECTION_TIMEOUT` and restarted the whole
  WSL instance on 2026-10-29. In-guest VMs run at `-m 1024`, and any heavier boot test has to be
  budgeted against 3.77 GiB, not the host's 7.9 GB.
- **Harness bugs found the hard way, all three worth keeping written down:** the QEMU monitor keysym
  for Enter is `ret`, not `enter` — a `sendkey` that silently does nothing looks exactly like an
  image that will not boot. A "console is ready" detector must not use loose patterns: grepping for
  `root@` matched `debian-kernel@lists.debian.org` inside the kernel version string and typed
  commands into a machine that had no shell yet. And framebuffer hashes are a weak signal in both
  directions — equal hashes can hide a blinking cursor, and differing hashes can be *nothing but* a
  blinking cursor (run G). The reliable checks are: compare a frame against a known-good render by
  looking at it, and treat `Login incorrect` on a serial console as a clue about what was typed, not
  about the image — run F failed there because it sent shell commands to a `login:` prompt that was
  asking for a username, and `user`/`live` is what that prompt wanted.
- `info accelerators` is **not** a QEMU HMP command (`unknown command`), so any "which accelerator
  did it use" claim must come from `info kvm` / `query-kvm` or from `-accel kvm` failing loudly, not
  from that string.
- `sendkey` mangles some characters without complaining. Letters, digits, `slash`, `minus` and `dot`
  all arrived correctly across runs H–J; `cat /sys/firmware/efi/fw_platform_size` arrived as
  `cat /sys/firmware/efi/fwuplatformsize` — the first underscore became a `u` and the second vanished
  (visible in `M0-runJ-uefi-efivars-mok.png`). Anything typed into a headless guest must be read
  back off the frame before its output is believed, and commands with shift-layer characters should
  be avoided in favour of ones the plain keysyms cover.
- systemd: **this build host does run systemd, contrary to what this section assumed.** Checked
  2026-10-29: PID 1 is `systemd`, `/etc/wsl.conf` carries `[boot] systemd=true`, and
  `systemctl is-system-running` reports `running` with no failed units. So maintainer scripts that
  call `systemctl` at install time behave here the way they will on a real machine, and §6's
  `systemctl`-based checks can be exercised on the build host itself rather than only in a VM. The
  recurring `wsl: Failed to start the systemd user session for 'root'` line is the *user* session
  (lingering) failing to start, not the system manager — do not mistake it for a broken init.
- Test target: QEMU or GNOME Boxes VM, amd64 UEFI, Secure Boot off. M0 exercised both firmware
  paths of the same hybrid ISO in QEMU 10.0.13: BIOS/isolinux (runs A, E, G, H) and UEFI via
  `-machine q35` with `ovmf` 2025.02-8+deb13u1 pflash (runs I, J). GNOME Boxes is still untested,
  and Secure Boot is still off everywhere — §6.2's MOK question stays deferred with M6.
- Artifacts land in this repo only as metadata; ISOs stay out of git.

### 9.1 M1 — the build tree, and what the runs so far established

M1 turns the shell history that produced M0 into a committed tree. Work in progress as of
2026-11-01; everything below is backed by a run, and what has not been run yet is called out
as not run.

**Layout.** `manifests/` holds the package selections with a justification per line and a
pointer to the §-number that asked for each one; `live/` is the live-build source tree
(`auto/config`, and `config/archives/` with the committed pool entry and its key;
`config/package-lists/` is generated at build time); `packages/` holds the file trees our
metapackages install; `scripts/` is the plumbing; `harness/` is M0's QEMU runner turned into one
reusable script. Generated things are gitignored: the live-build config files `lb config` writes and
the package lists. The pool is not in the tree at all — it lives on the build host and is mounted in
(§9.1, pool-ordering subsection), which is also why M1 has no `config/hooks/`: nothing needs a cleanup
step any more.

Two facts about `lb config` that the tree depends on, both measured on a resumed tree rather than
read off the manual. `lb config` re-executes `auto/config` **whenever that file is executable** —
`Maybe_auto_redirect` tests `-x auto/config` and re-runs the command through it
(`/usr/share/live/build/functions/init.sh`); the only thing that skips it is the `noauto` first
argument, and whether a config tree already exists is not part of the condition. `live/auto/config`
therefore says `lb config noauto` inside itself, or it recurses. And because a resume re-enters that
path, the re-run was diffed against the audited dump: 98 assignments, **no difference** — re-running
`lb config` on an existing tree is a no-op for the values, which is what makes
`scripts/build-iso.sh` safe to run twice.

**`scripts/config-audit.sh`, run 2026-10-30** (`logs/M1-config-verify.txt`). The committed
`live/auto/config` was expanded by `lb config` in a throwaway tree and the resulting assignments
diffed against `logs/M0-effective-config.txt` (M0's generated config, captured the same way). 98
assignments on each side, two differences:

```
-LB_APT_RECOMMENDS="true"                  +LB_APT_RECOMMENDS="false"
-LB_CHROOT_SQUASHFS_COMPRESSION_TYPE=""    +LB_CHROOT_SQUASHFS_COMPRESSION_TYPE="xz"
```

`lb config`'s own stderr on that run is empty. That line of the output is there because a typo in
a *flag* is a different failure from a wrong *value*: tested on 2026-10-30,
`lb config --totally-made-up-option foo` exits 1 with `unrecognized option` and writes no config
tree at all, so a misspelled option cannot pass unnoticed — whereas `--apt-source-archives false`,
the mistake below, is a perfectly valid flag that quietly deviated from the default. Only the diff
catches the second kind.

An earlier run of the same check showed a **third** line, `LB_APT_SOURCE_ARCHIVES="false"`. Two of
the original three were mistakes in the first draft of `auto/config` — a restatement of a default
that is not a default, written while nobody had checked — and the `xz` pin is deliberate and
behaviour-preserving for the reason in the correction above. `LB_APT_SOURCE_ARCHIVES` was put back
to `true`. The file now produces exactly the deviations it claims, which is the whole point of
having the audit script rather than trusting the comments.

**Re-run 2026-10-31 after §5's firmware amendment** (`logs/M1-config-verify.txt`, same command, and
the same file each run overwrites — today's copy is kept as
`logs/M1-config-verify-2026-10-31.txt`): 98 assignments on each side, three differences — the two
above plus `-LB_FIRMWARE_CHROOT="true" / +LB_FIRMWARE_CHROOT="false"`, and `lb config`'s stderr
still empty. The 2026-10-30 result is quoted above from the version of that file it produced; today's
diff contains those same two lines, so the earlier claim is not left without an artifact — it is
just no longer the newest one. So the count this file claims and the count the toolchain produces
agree, and §5's 2026-10-31 amendment is what the third line is for.

Two more things learned by reading the toolchain instead of guessing from its docs: `lb config`
has **no option** for `LB_UNION_FILESYSTEM` or the BIOS/EFI bootloader pair, so those stay
defaults and the dump diff is what proves they have not moved; and the options are
`--architecture`/`--binary-image` singular in the help text while M0 ran the plural forms, so
`auto/config` keeps the plural forms M0 actually used (the audit above is the check that they
are still accepted).

**`--apt-recommends false`, measured before it was chosen.** `logs/M1-recommends-delta.txt`
has the method and the full list. Against the build host's trixie 13.7 indices with an empty
dpkg status: **735** packages for the §5 selection without Recommends, **1054** with them, so
319 packages arrive because some maintainer elsewhere thought a user might like them. Three of
those are `desktop-base`, `gnome-icon-theme` and `tango-icon-theme` — Debian branding and two
icon themes, in an image whose identity is §7's and whose icon theme §12 item 2 has not picked.
Two more are `avahi-daemon` (a service §6.5 says off) and `modemmanager`. That is the basis for
turning Recommends off, and it is also a debt: a Recommends that a session actually needs is
now invisible, so §12 item 12 tracks the candidates the delta file names.
`logs/M1-recommends-edges.txt` is the follow-up run — it reads the `Recommends:` fields out of the
trixie index instead of recalling them, and confirms all sixteen candidates it checked are in the
319, i.e. genuinely gone: `mate-polkit` (recommended by `xfce4`), `gvfs`, `tumbler`, `udisks2`,
`xdg-user-dirs` (by `thunar`), `wpasupplicant` and `wireless-regdb` (by `network-manager`),
`xdg-desktop-portal` and `xdg-desktop-portal-gtk` (by `flatpak`). `upower`, `xfdesktop4` and `xfwm4`
were checked in the same pass and do arrive through `Depends:` — one stanza each in run M's image.
**`polkitd` does not.** It has zero stanzas in run M's image and zero in M0's. This line originally
grouped it with the three that arrive, on the strength of `logs/M1-recommends-edges.txt:172`
("polkitd: not in the 319 -> arrives by Depends"), which was a one-hop inference over a two-hop
question: that file's own lines 62, 162 and 163 show polkitd is a *Recommends* of `udisks2`,
`network-manager` and `flatpak`, and all three carriers are themselves inside the 319. With every
carrier dropped there was nothing left to pull it in. Corrected 2026-11-01 against run M's squashfs;
the consequence — no authorization daemon in the image, and the `ukui-polkit` accident that
followed from the hole — is `logs/M1-no-live-user.txt` §5-§6.

A third run, `logs/M1-service-closure.txt`, took the same empty-status simulation and asked what
§6.5's "disabled by default" actually means now: `avahi-daemon`, `cups-browsed` and
`openssh-server` are **not in the 735 at all**, so there is no unit to disable. §6.5 is amended to
say so.

**The pool and its signature, with negative controls, run 2026-10-30** (`logs/M1-pool-signature.txt`,
produced by `scripts/pool-signature-test.sh`, which is re-runnable and is what to run again after any
re-key). Our metapackages are built by `scripts/build-packages.sh` from the manifests (`Depends:` is
generated, never typed) into a pool on the **build host** at `/opt/phantomos-build/pool`, indexed
with `apt-ftparchive` and signed with a local GPG key. `config/archives/phantomos.list.chroot` names it
as `deb file:///opt/phantomos-build/pool ./` — that line is the **first** line of the file, which is
what makes the bind happen at all — with no `[trusted=yes]`; live-build bind-mounts that
path into the chroot and installs the matching `phantomos.key.chroot` into `trusted.gpg.d` (§9.1, the
pool-ordering subsection below). Against that pool, with the keyring pinned by `signed-by`:

| case | result |
|---|---|
| pool signed by the build key, pinned keyring = the committed public key | accepted; `phantomos-base` and `phantomos-desktop` both get candidate `0.1.0-1` |
| same package bytes re-signed with a key generated for the run, keyring unchanged | `Sub-process /usr/bin/sqv returned an error code (1) … Missing key 151BABBCDC7ED9AFA93419EA4C369C9326A33209, which is needed to verify signature`, `E: … InRelease' is not signed.`, apt exit 100, no candidate |
| `InRelease` and `Release.gpg` deleted | `E: The repository 'file:… ./ Release' is not signed.`, apt exit 100, no candidate |

The second row is the one that matters: it is the only case that would fail loudly if trust came from
somewhere other than the pinned keyring, and the script checks that the re-sign actually changed the
bytes (`InRelease f5828523… → 86339dd6…`) before reporting it — an earlier attempt at this table
"passed" because `gpg --quick-gen-key` had silently not produced a second key, so apt was verifying the
original signature and accepting it.

Not tested: a tampered `.deb` whose hash no longer matches `Packages`. That failure happens at
download, not at `update`, and no run here has exercised it — `live/config/archives/` says so in
its own comment rather than claiming the whole chain.

The build key is a **build** key with no passphrase, created 2026-10-30, fingerprint
`366B8D046A9E55F676F8B81C579EA1F72B8507E6`, private half in `/root/phantomos-key` outside the
repo, public half committed as `live/config/archives/phantomos.key.chroot` and shipped inside
`phantomos-release` as `/usr/share/keyrings/phantomos-archive.gpg`. §8's offline master, custody
note and rotation plan are M5's job and are not satisfied by this; nothing in the repo says they
are. Because §12 item 3 (where a published repo lives) is still open, nothing in the image keeps the
channel: live-build deletes the `.list.chroot` entry and the `.key.chroot` key and unmounts the pool at
the end of the chroot stage, and `scripts/m1-diff.sh` asserts — against the shipped squashfs, for the
reason two paragraphs below — that
`etc/apt/sources.list.d/phantomos.list`, `etc/apt/trusted.gpg.d/phantomos.key.*`, the pool mountpoint
and any `phantomos_*all.deb` in the apt cache are all absent. A shipped system therefore has no
PhantomOS channel and no dead one either; the consequence for M4 is that its upgrade test cannot run
until item 3 is decided.

**Build-host changes made during M1, recorded so they are not folklore.** `gnupg` installed
2026-10-30 (`gpg (GnuPG) 2.4.7`) — M0's toolchain list did not include it and nothing in live-build
pulls it. `apt-utils` was already present (live-build depends on it for `apt-ftparchive`).
`/root/.wgetrc` added 2026-10-30 with `timeout/read_timeout 30`, `connect_timeout 20`, `tries 8`,
`wait 3`: debootstrap calls plain `wget -nv -O …` and waits on it forever, and one of those
connections wedged (below). It is host configuration, not repo configuration —
`scripts/config-audit.sh` sees none of it, and the tree builds the same way on a machine without
that file.

**The first M1 build was stopped, not finished, and here is why** (`logs/M1-build-throughput.txt`,
`logs/M1-lb-build-interrupted.log`). At 20:38 `lb build` entered the bootstrap; at 21:21 it had
133 `.deb`s and was on its 27th minute of a single `systemd` download stuck at ~700 B/s on a
connection that was still `ESTAB` to 151.101.66.132:80 with `Recv-Q 0`. Two things had to be
distinguished before touching it. First, whether it was WSL: the same 3,093,632-byte file fetched
from Windows PowerShell on the same machine at the same moment took 51,957 ms, and from WSL
52,006 ms — the same number, so it is not a guest-networking artefact (and IPv6 has no route here
at all, `ip -6 route get` → `Network is unreachable`, so every Debian CDN connection is forced onto
IPv4). Second, whether the mirror was the problem: measured uncontended after the stop,
`deb.debian.org` did 313 KB/s and `mirror.dkm.cz` 520 KB/s, while
`mirror.netcologne.de` — which had measured 431 KB/s twenty minutes earlier — did 38 KB/s. Nothing
about that supports switching the build to a third-party mirror, and there is a reason not to: live-build
writes `/etc/apt/sources.list` from `LB_PARENT_MIRROR_*` (`/usr/share/live/build/functions/sourcelist.sh`,
derivative=false path), so **the mirror the build fetches from is the mirror the shipped system is
configured to use.** The build was therefore restarted against stock `deb.debian.org`, with
`/root/.wgetrc` giving the stuck-stream case a timeout and eight retries instead of an infinite
wait, and `harness/commands/M1.txt` now cats `sources.list` on the booted image so that
parent-mirror-ships-as-child relationship is checked rather than assumed.

**The pool was delivered at the wrong stage, and live-build has a mechanism that delivers it
at the right one.** The first build to reach the chroot stage died inside it, at 21:34:12, on the
`apt-get update` that closes the archives step (`logs/M1-lb-build-pool-order.log:723-739`, where the
Debian channels on the next lines all fetch fine):

```
[2026-10-30 21:34:12] lb chroot_archives chroot install
P: Configuring file /etc/apt/sources.list
Ign:1 file:/phantomos-pool ./ InRelease
Err:2 file:/phantomos-pool ./ Release
  File not found - /phantomos-pool/./Release (2: No such file or directory)
Hit:3 http://deb.debian.org/debian trixie InRelease
…
E: The repository 'file:/phantomos-pool ./ Release' does not have a Release file.
E: An unexpected failure occurred, exiting...
```

That log survived only because `build-iso.sh` had already copied it into `logs/` under the default
name; the copy in `$PHANTOMOS_WORK` was removed by the next run's `rsync --delete` before it could be
saved a second time. `build-iso.sh` now writes to `$WORK/logs/lb-build-<UTC timestamp>.log`, which the
rsync excludes protect, so a run's log outlives the next run and two runs of the same milestone are
distinguishable in the repo. This file is renamed `M1-lb-build-pool-order.log` for that reason: the
default name belongs to whatever run closed the milestone, not to a failure.

The cause is stage order, and it is only visible in the script that implements the stage.
`/usr/lib/live/build/chroot` runs `lb chroot_prep install all mode-archives-chroot` at line 34 — and
the last helper that `chroot_prep` runs is `archives`, whose install branch ends in `Apt chroot update`
(`/usr/lib/live/build/chroot_archives:290`) — and only then runs
`chroot_includes_before_packages` at line 40. So a pool copied in by `includes.chroot_before_packages`
is not on disk when apt first reads the `deb file:` line that points at it. Reading the same script for
the fix found the mechanism that is already there: `chroot_archives:67` calls
`Chroot_try_bind_path_from_list`, which reads one line of the list fragment — the first — and
`mount --bind`s the host directory it names into the chroot at the same absolute path
(`functions/chroot_bind_path.sh:18-37`) — *before* the `Apt chroot update`. "One line, and the first"
is what the next paragraph had to learn the hard way. The end of the chroot stage
does the mirror image: the `.list.chroot` entry is deleted (`chroot_archives:360-366`), the
`.key.chroot` trust anchor is deleted with it (`:398-409`), apt is run once more with only the shipped
channels to prove the result is usable (`:475`), and then the pool is unmounted. So the pool is never
copied into the image, `9000-drop-build-pool.hook.chroot` was doing by hand what live-build does
natively and at the wrong moment, and it is deleted. §8's "no dead channel in a shipped image" is now
carried by upstream behaviour plus two assertions on the result — `scripts/m1-diff.sh` against the
shipped squashfs and `harness/commands/M1.txt` against the running image — not by a cleanup step of
ours.

**Both of those assertions had to be re-pointed, and the first version of the guard passed for the
wrong reason.** When `scripts/m1-diff.sh` was run against the finished build it reported
`chroot/etc/apt/sources.list.d/phantomos.list` and `chroot/opt/phantomos-build/pool` as a leak — and
both were absent from the shipped root filesystem. The stage order explains it, and the build log
records it (`logs/M1-shipped-squashfs.txt` §1, §3): `binary_chroot` renames the completed chroot to
`chroot/chroot` and drops a copy of `cache/bootstrap` in its place (`binary_chroot:59-74`),
`binary_rootfs` then squashes `chroot/chroot` (`binary_rootfs:337` through `Chroot()`,
`functions/chroot.sh:33`), and *only after that* do two more `chroot_archives` runs bind the pool
again — `chroot install` at 00:49:10 into the bootstrap copy, `binary install` at 01:10:51 for the
bootloader. So `live/chroot` at the end of a build is not the image; it is a bootstrap chroot with the
build pool mounted into it, produced by stages that run after the artifact was made. The guard's
subject is now `binary/live/filesystem.squashfs` — extracted with `unsquashfs`, both its records and
its path listing — and the ISO's copy of that archive is byte-identical to it (sha256
`f2f7d1ee9e18569eaed4fec586ace41dea4aefaf681509a6654502b77cc61dc8` on both sides,
`logs/M1-shipped-squashfs.txt` §4). The host-tree leftovers are still printed, under "build tree, not
the image", and cannot fail a run. On that subject the §8 result is clean: no `phantomos*` file in
`sources.list.d` or `trusted.gpg.d` inside the archive, no `opt/phantomos-build/pool` in the extracted
tree or in the archive's own path listing, no `phantomos_*.deb` in the image's apt cache, and the
only channels the image ships are Debian's three suites — each as a `deb` **and** a `deb-src` line,
six lines total, which is the traffic §12 item 14 costs out (`logs/M1-diff.txt`; the same six lines
ship in run M's artifact, `logs/M1-diff-runM.txt`).

**One limitation the same run found, worth knowing before someone tries to audit a shipped image.**
`/var/log/apt/{history.log,term.log,eipp.log.xz}` inside the built squashfs are all **0 bytes**
(`logs/M1-explicit-attribution2.txt` §0), so live-build's cleanup leaves a user — and this checker —
no record inside the image of which command line installed what. Every attribution claim in §5's
2026-10-31 amendment therefore comes from the build log, live-build's own source, the cached Contents
files and the apt indices, all on the build host, and not from the artifact. If a friend ever needs to
know how their image was assembled, the answer is this repo and `logs/`, which is an argument for
keeping both.

**Moving the file to `config/archives/` was necessary and not sufficient, and the build that proved
it cost another ten minutes of the same log.** The archives fragment was written as documentation with
the `deb` line at the bottom of it, which is how a `.list` file is allowed to be shaped — for apt.
The next run failed identically (`logs/M1-lb-build-first-line.log:709-728`, started 22:12:22, dead at
22:26 in `lb chroot_archives chroot install`, and with `Binding local repository path` appearing zero
times in all 731 lines). The reason is that the mount decision is not made by apt: `chroot_archives:62-66`
sed-copies the fragment into `chroot/etc/apt/sources.list.d/` comments and all, so apt *does* see the
`deb file:` line — that is why the error names the repository instead of ignoring it — and then
`Chroot_try_bind_path_from_list` decides separately whether anything exists at that path. That function
is eight lines long, and the line that matters is the sixth:

```
URI=$(sed --regexp-extended -e 's/.*(file:\/\/[^ ]+).*/\1/' ${FILE} | head -1)
```

`head -1` is *after* the substitution, and sed without a `/p` flag passes non-matching lines through
unchanged, so `URI` is simply "whatever line 1 of the fragment is". With a comment block on top it was
the opening sentence of a paragraph, `Chroot_try_bind_path`'s `^file://(localhost)?/` test failed against
prose, and the function returned 0 having done nothing. The unbind at the end of the stage is called the
same way from the same file, so the failure is symmetric and leaves no trace. The fragment is now
one `deb file:///…` line on line 1 with the explanation underneath it, and
`scripts/build-packages.sh` runs live-build's own extractor against the file instead of grepping for a
`deb` line anywhere in it — `grep -qx "deb file://$POOL ./"` accepts the file that broke this build, so
a check shaped like the tool's behaviour is the only check that can fail the way the tool fails.
`logs/M1-pool-bind-first-line.txt` is the write-up; its raw halves are
`logs/M1-pool-bind-first-line-extractor.txt` (both file shapes through the upstream extractor, plus the
contract check run against the bad shape: it exits 1 and refuses to sign, aborting before the `rm -rf`
so a rejected file cannot destroy a good pool) and `logs/M1-pool-bind-first-line-unit.txt`
(`Chroot_try_bind_path_from_list` called unchanged against a throwaway chroot directory: the comment-first
file creates nothing and mounts nothing, the deb-first file puts
`/dev/sdd /tmp/fakechroot-new/var/tmp/phantomos-build/pool` in `/proc/mounts` and lists 9 entries through
it, including `InRelease` and the `.deb`s; the test unmounts again and refuses to `rm -rf` while anything
is still mounted, for the reason in the previous paragraph).

**The bind worked, the pool installed, and then live-build's own housekeeping deleted it off the build
host.** The next run got further than either before it — `logs/M1-lb-build-pool-hook.log` line 711 is
the first `P: Binding local repository path` this project has ever produced, lines 2194-2197 fetch all
four metapackages out of the bound pool, and 5100/5755/5756 set them up — and then died at 23:32 in the
hook stage:

```
5842:P: Executing hook config/hooks/normal/8070-remove-temporary-files.hook.chroot...
5843:rm: cannot remove '/var/tmp/phantomos-build/pool': Device or resource busy
5844:E: config/hooks/normal/8070-remove-temporary-files.hook.chroot failed (exit non-zero).
```

`8070` is not ours; it is one of the default hooks live-build symlinks into every tree
(`live/config/hooks/normal/` in that run is 22 symlinks to `/usr/share/live/build/hooks/normal/`, and
the repo still has no hooks of its own). Its body is a two-line loop over `/tmp` and `/var/tmp`, and
the bind means the chroot's `/var/tmp/phantomos-build/pool` **is** the build host's pool. `rm -rf`
recurses through the mountpoint, emptied the pool at its source — `InRelease`, `Release`, `Release.gpg`
and the four signed `.deb`s — and then failed to remove the mountpoint itself. `set -e` in the hook,
non-zero exit, build aborted. The directory was left empty but mounted, and the archives stage that
would have unmounted it never ran.

So a bound archive's host path is constrained by what the chroot does to itself *after* the packages
are installed, which is nowhere in the option reference. `logs/M1-pool-hook-hazard.txt` measures the
constraint instead of arguing from the one failure: the same throwaway pool, bind-mounted at its own
path, with the verbatim hook loop run over the fake chroot both times. `/var/tmp` → exit 1, `Device or
resource busy`, and `InRelease gone` from the source; `/opt` → exit 0, all three files still there. The
log also lists every removal in the whole default normal-hook set, which is how the hazard list is
known rather than guessed: the only directory-level ones are `/tmp`, `/var/tmp` (8070),
`/var/cache/man/*` (9020) and `/var/cache/ldconfig` (8080); everything else is file-level (`*-old`,
`machine-id`, host keys, `icon-theme.cache`). The pool now lives at `/opt/phantomos-build/pool`, and
`scripts/build-packages.sh` refuses any `PHANTOMOS_BUILDDIR` under those four paths before it builds or
deletes anything — the same negative control as the first-line check, in the same block of that log.
`scripts/m1-diff.sh` reads the pool path out of the committed archives line instead of repeating it, so
the §8 guard cannot go on checking a location the pool left.

Two claims in that paragraph needed a run of their own.

*Three slashes.* `Chroot_try_bind_path` matches `^file://(localhost)?/`, so `deb file:/var/tmp/…` is
not read as a local path and nothing is mounted. `logs/M1-pool-uri.txt` calls the function itself —
sourced, not reimplemented — against a scratch directory and the real pool for four URI forms:
`file:///var/tmp/…` and `file://localhost/var/tmp/…` both print `I: Binding local repository path …`,
appear in `/proc/mounts` and list the index and the four `.deb`s through the mount; `file://var/tmp/…`
and `file:/var/tmp/…` print nothing, mount nothing and show an empty directory. The first attempt at
that measurement was wrong and is worth recording: it ran the real `lb chroot_archives chroot install`
with a two-slash line and read "zero `Binding local repository path` messages" as the result — but the
run had already died in an earlier `Chroot` call (the chmod bug below), *before* the line that decides
the bind, so all four forms "measured" the same zero. A measurement that cannot distinguish the cases
is not a control, and the log now says which half is whose: the URI forms are the unit test's claim,
and that the mounted pool is then installed from is the build log's.

The same log records a near-miss that is the reason `scripts/build-packages.sh` unmounts before it
removes anything: leaving a bind mount up and running `rm -rf` on the directory above it recurses
*through* the mountpoint and deletes the pool at its own source. `umount -R` on the parent does not
help, because `-R` requires its argument to be a mountpoint itself; the targets have to come out of
`/proc/mounts`.

*The chmod was destroying resumed chroots.* Same command, different line of output: `chroot: failed to
run command '/usr/bin/env': Permission denied`. `build-iso.sh` normalised modes with
`find $WORK -type f -exec chmod 0644` over the **whole** work directory, and on a resumed tree that
includes `live/chroot` — every file in the bootstrapped system lost its executable bit
(`ls -l` showed `chroot/usr/bin/env` and `chroot/usr/lib/apt/methods/http` as `-rw-r--r--`). The
fix is the same exclusion list rsync already uses (§9.1 above): normalise the repo copy, never the
build scratch inside it. The damage is why the closing run restarts from a cold chroot: the cached
`cache/bootstrap` tarball is a cache *of the damaged tree*, so restoring from it would restore the
damage, and a chroot whose file modes were repaired by hand is a chroot nobody can say anything
about. `cache/packages.bootstrap` (144 `.deb`s, verified against the bootstrapped chroot's own dpkg
status: 144 names, no difference in either direction) is kept, so the re-run downloads nothing it
already has. **Every stage of the closing run executes; only the fetch is cached.**

`scripts/build-iso.sh` was changed in the same breath: its `rsync --delete` used to take the build
scratch directories with it, so a second run threw away an hours-long download. It now excludes
`live/chroot/`, `live/binary/`, `live/cache/`, `live/tmp/`, `live/.build/` and `live/.lock` — the
same paths `.gitignore` calls scratch — and the restart confirmed the effect in the log: 133 cached
`.deb`s came back as `I: Validating …` lines with no `I: Retrieving` for them. **A resumed build is
a weaker claim than a cold one**, so this is recorded as the reason the milestone's closing run has
to be a cold one.

"Cold" needs a test, because "empty `$PHANTOMOS_WORK`" is not what gets kept: the download caches
are inside it, and throwing away 687 MB of `.deb`s to make a sentence true would only make the run
longer, not weaker. The test is whether **debootstrap runs**. `live/cache/bootstrap` is a snapshot
of a chroot, so a build that restores it is not building a chroot — that is the case the chmod
paragraph above is about, and run K's own log line 10 is the signature of the shortcut:
`W: Skipping bootstrap, already done`, with `bootstrap_cache restore` taking 21 s and
`bootstrap_debootstrap` taking none. So the closing run deletes `live/.build`, `live/chroot*`,
`live/binary`, `live/tmp`, `live/.lock` and `live/cache/bootstrap`, and keeps
`live/cache/packages.{bootstrap,chroot,binary}` and `live/cache/contents.chroot`, which are
fetches. Nothing is skipped, and every stage still executes. Before any of it is deleted,
`grep phantomos-m1 /proc/mounts` has to be empty — the stale-bind hazard above ate a pool once.


**drvfs is not only slow, it is unbuildable.** The line above this section says the build tree
lives inside the WSL filesystem; M1 found the second reason. Staging package trees under
`/mnt/c` made `dpkg-deb` fail with `control directory has bad permissions 777 (must be >=0755
and <=0775)`, because drvfs reports 777 for everything. `scripts/build-iso.sh` therefore copies
the repo to `$PHANTOMOS_WORK` (default `/root/phantomos-m1`), normalises every directory to 0755
and every file to 0644 — *outside* the build scratch paths, for the reason in the paragraph above —
and then sets the execute bit on the scripts and `auto/config`.
`scripts/build-packages.sh` additionally re-normalises the copied file trees before packing, so a
mode inherited from Windows cannot be baked into a shipped package.

**§5 gaps found while writing the manifests, not after installing them.** §5's desktop line said
"pipewire + pavucontrol"; a session with only `pipewire` has no PulseAudio-compatible server and
no session manager, so `pipewire-pulse` and `wireplumber` are named in
`manifests/desktop.pkgs` alongside it and §5 is amended to match, with the index fields that make
it a real gap rather than a stylistic one: `pipewire` 1.4.2-1 Depends on adduser,
libpipewire-0.3-modules, pipewire-bin, init-system-helpers and Recommends **nothing**, and
`wireplumber` is a Recommends of `pipewire-bin` while `pipewire-pulse` is a Recommends of
`wireplumber` — so with Recommends off the old line installed a daemon with nobody to manage it.
§5 also says nothing about flatpak portals (§5.1): with Recommends off, nothing in the image
provides `xdg-desktop-portal`, which is how a sandboxed app gets a file picker. That one is **not**
amended into §5 yet — it is §12 item 12, along with the auth agent and the supplicant, because
whether each is load-bearing is a behaviour question and the behaviour has not been run.
`pavucontrol`'s own Recommends are `(pulseaudio | pipewire-pulse)` — from the same index read —
so naming it cannot drag the real PulseAudio daemon back in.

**Two findings that belong to other sections.** Firmware (`logs/M1-firmware-areas.txt`):
`--archive-areas main` is live-build's own default, and it reaches only the DFSG-free firmware
packages. The sentence this section used to carry here — "M0's log shows exactly three
(`firmware-linux-free`, `firmware-ath9k-htc`, `firmware-carl9170`)" — was a name-prefix count and is
**wrong**: measured on dpkg's `Setting up` lines, M0 installed six packages carrying `lib/firmware`
paths, the same six the pre-amendment M1 build of 2026-10-31 installed (five of them named by hand
after the amendment, `indi-dsi` dropped — §5's 2026-10-31 amendment,
`logs/M1-firmware-m0-correction.txt`, `logs/M1-diff-preconfig.txt`). This machine's Wi-Fi is an Intel Dual Band Wireless-AC 8260,
which needs `firmware-iwlwifi` 20250410-2, `Section non-free-firmware/kernel`, and that package is
not in the trixie **main** index at all, so it is not in the image. That is now §12 item 11 rather
than a silent default. Branding: an M1-built ISO still calls itself `Debian Live` in its ISO metadata
and boot menu, because those strings are live-build's defaults and §7's branding is an M2
deliverable — recorded here so nobody reads a "hardened PhantomOS image" claim into an artifact that
is labelled as somebody else's product (§7.1).

**Three more M1 build runs, and two ways a run can die after the artifact is already built.** M1's
builds are lettered on from M0's boot runs (A–J in §9), so they are K, L, M. Every row says which
clock it quotes, because `scripts/build-iso.sh` names its files with `date -u` while live-build
stamps `[YYYY-MM-DD HH:MM:SS]` in host-local EAT (UTC+3): the log named
`lb-build-2026-10-30T231811Z.log` contains the stamp `[2026-10-31 02:18:11]` and those are the same
instant. `logs/M1-runK-rootfs-iso-failure.txt`'s header is the worked example. The same trap caught
an audit on 2026-11-01: `find -newermt` also takes **local** time, so a cut written as the run's UTC
start selected three hours too much and reported four changed files where the true answer was one.

- **Run K** — `2026-10-30T23:18:11Z` → `2026-10-31T00:09:06Z`, 51 min.
  `logs/M1-lb-build-firmware.log`, config `logs/M1-config-dump-2026-10-30T231811Z.txt`
  (98 assignments, `LB_FIRMWARE_CHROOT="false"`, the §5 2026-10-31 amendment). Every `chroot_*`
  stage ran; `binary_rootfs` produced `live/binary/live/filesystem.squashfs`, **837,296,128 bytes**,
  sha256 `30876ccbefe4575241e745740db89aca7ac5a1942f9d89a891cbe2c59b9ce76d`; `scripts/m1-diff.sh`
  against it reported 834 installed packages, 150 manual selections, a 684-package closure, 197
  expected selections and **both directions empty**. That is §10's M1 exit criterion,
  satisfied — on the rootfs. The citation this row used to carry, `logs/M1-diff.txt`, is **not run
  K's**: that file is the earlier build's *failing* diff (838 installed, 42 `MISSING`, 7 `EXTRA`,
  `M1 EXIT CRITERION: NOT MET`), its mtime is 01:42 against run K's `binary_rootfs` at 02:53:46, and
  it is the pool-ordering failure this same section records. Run K's diff stdout was never archived;
  what was is the seven data files the script writes beside it, `logs/runK/*.txt`, all mtime 03:12,
  and the verdict above was re-made from them at 2026-11-01T17:29Z with the script's own `comm`
  comparisons under its pinned `LC_ALL=C` — both empty, and the line counts 55 / 197 / 834 / 150 /
  684 / 47 705 (`logs/M1-runK-rootfs-iso-failure.txt` §1). The drop-guard and build-pool guards are
  **not** reproducible from those files and are no longer claimed for run K; run M's
  `logs/M1-diff-runM.txt` carries both, as stdout that was archived. The run then died in
  `binary_rootfs`'s teardown
  (`/usr/lib/live/build/binary_rootfs:347-362`), which moves the image chroot aside and re-runs
  live-build's archive bookkeeping, and that bookkeeping runs `apt-get update`: the resolver went
  away and three `InRelease` fetches failed. **The ISO was never assembled.** Run K is also the run
  whose log line 10 reads `W: Skipping bootstrap, already done`, so it is not a cold run.
- **Run L** — started `2026-10-31T00:43:22Z`. `logs/M1-runL-binary-rootfs-dns.txt` (the analysis),
  `logs/M1-lb-build-runL.log`, `logs/M1-runL-launcher.out`,
  `logs/M1-config-dump-2026-10-31T004330Z.txt`. **Cold**: `bootstrap_debootstrap` started at
  03:43:32 local and `bootstrap_cache save` followed at 03:51:42, and no `Skipping`/`already done`/
  `Restoring` line appears anywhere in the log.
  It died twice, and neither death caused the other:
  1. `scripts/build-iso.sh` was edited while it was running. bash executes a script from one open fd
     plus a byte offset it maintains itself, re-reading as it goes, so the next `read()` landed
     mid-line in the new content and bash aborted with
     `line 85: syntax error near unexpected token '('`. Everything after that line never ran —
     including the `cp` that copies the build log and config dump into `logs/`, which is why run L's
     evidence had to be pulled off the build host by hand afterwards.
  2. `lb build` ran on independently, for 48 minutes, and died in `binary_rootfs` fetching
     `squashfs-tools` and `liblzo2-2` — `Temporary failure resolving 'deb.debian.org'`, five
     `Ign:`/`Err:` pairs per package, then `E: An unexpected failure occurred, exiting...`.
- **Run M** — started `2026-11-01T14:03:27Z` (`lb config`), cold-cleaned by the test two paragraphs
  above, with the seed of the paragraph below applied first. **The first M1 run to assemble an
  ISO.** `logs/M1-artifact-2026-11-01T140727Z.txt` records the window `14:07:27Z .. 15:52:06Z`,
  `lb build exit 0`, 908 066 816 bytes, sha256 `f256cefc66d9ab31031501469080bbe154b16e7844453ac6e108221a4d69a2a5`,
  at `/root/phantomos-m1/artifacts/2026-11-01T140727Z/live-image-amd64.hybrid.iso`; the build log is
  `logs/M1-lb-build-runM.log` (4 971 lines, `P: Build completed successfully`, zero `E:` lines) and
  the stage-by-stage cost is `logs/M1-build-cost-runM.txt`. Three things it settled:
  - **The seed worked, exactly as predicted.** `binary_rootfs` printed `Need to get 0 B/249 kB of
    archives` for `liblzo2-2 squashfs-tools` and unpacked both from the seeded filenames; 249 kB is
    193 888 + 55 100, so the total apt quoted is itself the evidence. `P: Preparing squashfs
    image...` followed 22 s later. No `Get:`/`Ign:`/`Err:`/`Hit:` line anywhere names any of the five
    ISO tools. The run L mystery is closed by this: K, L and M have identical config dumps on every
    cache variable, so the difference was `scripts/seed-binary-cache.sh`, which did not exist for L.
  - **It passed the point that killed run K.** The same `chroot_archives binary remove` teardown,
    same benign `rmdir … Directory not empty`, but its `apt-get update` succeeded because the
    resolver was up. Which is also the whole of the difference from run K: nothing in the tree
    changed between them except the seed and the clock.
  - **§10's diff, against a shipped image at last.** The squashfs the ISO ships is 837 292 032 B,
    sha256 `5c28598459d38f95a6ae89380100749a81926c9f360b47739292d7f20ed2688e`, xz, 47 705 paths —
    re-measured out of the archived artifact by read-only loop mount at 2026-11-01T17:24Z
    (`logs/M1-runM-shipped-squashfs.txt`), because the first measurement of it went to a terminal and
    was never captured, and §11 does not accept scrollback as a log. `scripts/m1-diff.sh` ran against
    the build tree's copy and reported 834 installed, 150 manual selections, closure 684, expected
    197, and `M1 EXIT CRITERION: MET (both directions empty, drop guard clean, no pool inside the
    image)` (`logs/M1-diff-runM.txt`). **The tree copy was sha256-compared against the ISO's at the
    time and matched, but that comparison was not archived either and can no longer be re-made** —
    run N's cold-clean deleted `live/binary` wholesale. What stands in its place is the mechanism
    (live-build copies the squashfs into the ISO image tree rather than rewriting it, and an earlier
    build's *archived* evidence shows the two paths sha256-identical,
    `logs/M1-shipped-squashfs.txt:107-109`) plus every checkable number in `m1-diff.sh`'s run-M
    output agreeing with the ISO's own contents: 834 packages, 47 705 paths, the same six shipped
    channels. That is an argument and a set of coincidences, not a measurement, and it is recorded as
    such; run N redoes the comparison with both copies present. Run K and run M produced **identical**
    834-name sets and identical 47 705 paths; the `diff` noise between the two runs' files was
    collation alone — run K's file fails `sort -c` at line 97 on `g++-x86-64-linux-gnu`, exactly as
    run K's own log predicted, because `export LC_ALL=C` was pinned in `scripts/m1-diff.sh` between
    the runs.
  And one thing it did not settle, which the next paragraph and `logs/M1-no-live-user.txt` are about:
  **the ISO boots and cannot be logged into.**

- **Run M1-boot** — 2026-11-01, `harness/boot-test.sh --mode bios --wait 300` against run M's ISO,
  commands `harness/commands/M1.txt`. First successful execution of the harness, and the run that
  found the defect above: frame `boot-300` is the lightdm greeter with an empty username box, and
  frame `cmd-2` reads `debian login: user (automatic login)` / `Authentication failure` — the
  getty generator did its job for a user the image never created. `kvm support: enabled`,
  28 commands sent, 35 frames, all in `logs/evidence/M1-boot-*` with
  `logs/evidence/M1-boot-artifacts-sha256.txt` verifying 35/35. The harness had four bugs, all found
  by this being its first real run; they are listed in its header. The finding is
  `logs/M1-no-live-user.txt`, and run N below is the rebuild it forced.

- **Run N** — started 2026-11-01T17:07Z, in flight while this paragraph is written. Same cold-clean
  as run M, with `manifests/live.pkgs` carrying `user-setup`, `locales` and `live-tools` for the
  reasons written in that file. Its job is narrow: produce an ISO whose console logs someone in,
  and pass `scripts/m1-diff.sh` again with the three new names in the expected set. Until it does,
  §10's M1 row stays where it is.

**`binary_rootfs`'s helper install is the one fetch live-build's package cache does not cover, and
it killed two milestone-closing runs.** `Check_package chroot /usr/share/doc/squashfs-tools
squashfs-tools` at `/usr/lib/live/build/binary_rootfs:265` puts `squashfs-tools` into
`_LB_PACKAGES`, `Restore_package_cache binary` runs at :268 and `Install_packages` at :271. Restore
only copies what `cache/packages.binary` already holds, and that directory holds what a *previous*
run's `Save_package_cache binary` moved there — so on a cold tree, or one whose last run never
reached the squashfs branch, the helper install needs the network. It is the **last** network access
in a build, after 48 minutes of work, and it is two `.deb`s. `scripts/seed-binary-cache.sh` closes
it: it derives the primary package from the `Check_package` line itself (hard-failing if upstream
moved it rather than silently seeding the wrong thing), derives its dependencies with `apt-cache
depends`, downloads them with `apt-get download` into a `_apt`-owned temp dir, and copies additively
into `cache/packages.binary`. It also cross-checks the naming convention — apt writes an epoch as
`%3a` on disk but not in the pool URI, so `squashfs-tools_1%3a4.6.1-1_amd64.deb` is the destfile
while `.../squashfs-tools_4.6.1-1_amd64.deb` is the URL — by comparing `apt-get download`'s filename
for `liblzo2-2` against a filename apt itself produced during a real install, and exiting non-zero
if they differ (`logs/M1-binary-cache-seed.txt`: 32 `.deb`s, 19 MB, names identical). That apt
honours the seed at all is measured, not assumed: `apt-get install --download-only -o
Dir::Cache::Archives=<dir>` reports `Need to get 0 B/194 kB` for a pre-seeded `squashfs-tools`, and
tolerates the absent `partial/` that `Restore_package_cache` never creates
(`logs/M1-acng-offline-serving.txt` §4).

**`live/config/apt/apt.conf` is very nearly a placebo, and this section used to imply otherwise.**
Its `Acquire::Retries "5"` is redundant: `/usr/share/live/build/functions/configuration.sh:120` sets
`APT_OPTIONS="${APT_OPTIONS:---yes -o Acquire::Retries=5}"` and every networked apt call in
live-build passes `${APT_OPTIONS}` on the command line (`packages.sh:56`, `chroot_archives:262/280`,
`chroot_install-packages:88`, `binary_package-lists:69`, `installer_debian-installer:546`). A
command-line `-o` beats any config file. Run L's five `Ign:`/`Err:` pairs per package are that
default doing its work *with this file already in the tree*, and the outage outlasted them. The
other line, `Acquire::http::Timeout "30"`, is the only setting this file is the source of, and it
does nothing for the failure that motivated it: "Temporary failure resolving" is the resolver
answering with nothing, which is immediate, not a timeout. The file is kept as the record of that
rather than as a mitigation, and the seed above is what actually removes the `.deb` half of the
failure. The resolver half is a host property — one nameserver, `10.255.255.254`, no fallback — and
is not configurable from this repository.

**A caching proxy was measured and not adopted.** apt-cacher-ng 3.7.5-1 was installed on the build
host and tested in a loopback-only network namespace, which is a total upstream outage and therefore
a superset of the resolver failure that killed runs K and L. Result: `pool/*.deb` is served from
cache byte-identical with upstream gone (HTTP 200, matching sha256), while `dists/*` is revalidated
and returns 503 even with a fresh copy on disk — apt-cacher-ng's own static/volatile split
(`acng.conf:230-232`). A negative control that was never cached returned the same 503, so the
isolation was real. It is not adopted: it is redundant with the seed for the `.deb` half, it does
not cover the `InRelease` half that killed run K, there is no speed win to have (run L fetched
17.8 MB total and zero `.deb`s in 48 minutes — the cost is 25 m 46 s of apt *parsing* across five
`chroot_archives` invocations), it is host state outside the repository, which is the defect M1a
exists to remove, and `LB_APT_HTTP_PROXY` is never applied by live-build anyway — the only mechanism
is an exported `http_proxy`, so adopting it would add a daemon that has to be probed and guarded.
The daemon is stopped and disabled; nothing measured here is assumed
(`logs/M1-acng-offline-serving.txt`).

**A running build is a snapshot of the tree, and editing the repository underneath it changes
nothing.** `build-iso.sh` rsyncs the repo into `$WORK` once, at the start. On 2026-11-01 a
comment-only edit to `live/config/apt/apt.conf` landed at `14:08:08Z`, forty seconds after run M's
rsync and after its `lb config`; run M therefore built with the previous text. That was established
by auditing the tree rather than by guessing: exactly one rsync'd file had an mtime after the
snapshot, and diffing the two copies' non-comment lines showed the effective directives identical,
so the artifact still corresponds to the current tree. Two things follow. First, any claim that an
artifact corresponds to the committed tree needs that audit, not an assumption. Second, a mid-build
rsync is actively dangerous: `lb config` **generates** most of `live/config/` (`bootstrap`, `common`,
`binary`, `chroot`, `source`, `includes*`, `hooks/`, `packages*`, `local/bin`) and the repository
commits only a few files under it, so `rsync --delete` from the repo would tear the configured tree
down while `lb build` is reading it. A dry-run of exactly that was used to establish the list and
must not be run for real against a live build.

**`build-iso.sh` now re-execs a private copy of itself.** The re-exec block copies the script to
`$WORK/.build-iso.running.sh` and `exec bash`es it unless `PHANTOMOS_RUNNING_COPY` already says it
is running from there, so the file bash holds open is one no editor will touch. Run M's process list
is the evidence: `bash /root/phantomos-m1/.build-iso.running.sh /mnt/c/…/phantomOS`, and that copy
diffs identical to `scripts/build-iso.sh`. One detail is worth recording because the code states an
intent reality does not have: the block's `chmod 0755 "$RUNNING"` is undone seconds later by the
script's own recursive `chmod 0644` over `$WORK`, and the file is in fact 0644 on disk. It does not
matter — `exec bash <file>` needs no execute bit — but the line should not claim otherwise.

**The artifact was destroyed by the next run's rsync, and now cannot be.** `live-image-amd64.hybrid.iso`
is written to `$WORK/live/`, which is *not* one of the scratch paths `rsync --delete` excludes, so
`--delete` treats a finished ISO as a stray repo file and removes it. A 910,163,968-byte ISO was
listed at `$WORK/live/live-image-amd64.hybrid.iso` at 01:30 local on 2026-10-31
(`logs/M1-shipped-squashfs.txt` §0–§1) and is not there now; the next `build-iso.sh` invocation after
that listing was run L's, at 03:43 local, and `scripts/build-iso.sh`'s header records the loss.
The milestone was left with an artifact whose size existed only in a hand-written listing and whose
bytes existed nowhere. `build-iso.sh` now moves every `live/*.iso` into `$WORK/artifacts/<run>/`
before rsync runs, `artifacts/` is a fifth rsync exclusion, and the size and SHA256 are written to
`logs/M1-artifact-<run>.txt` in the same breath. An artifact leaves `live/` before the next run can
reach it.

**What has not been run yet.** Shorter than it was: run M built to completion and shipped an ISO,
`scripts/build-iso-artifact-test.sh` has been executed (16 assertions, all passing) and is
registered in `scripts/run-tests.sh` alongside `scripts/pool-signature-test.sh`
(`registered: 2 passed: 2 failed: 0 missing: 0`), and the desktop image has been boot-tested
(run M1-boot above). What the boot test could *not* exercise, because the image had no login, is
everything that needs a session: whether the graphical session comes up on its own VT once a user
exists (run M1-boot shows lightdm's greeter, which is the display manager running but no session
behind it), whether `/etc/apt/apt.conf.d/00recommends` survives into the image as installed
behaviour, and whether `harness/boot-test.sh`'s `shift-minus` mapping actually delivers an
underscore — M0's run J proved `sendkey` does not do that reliably, and run M1-boot typed its
underscores into a console that was not reading. All three are run N's boot test's job now, and
`harness/commands/M1.txt` still carries them. The `dpkg`/`apt-mark` diff against §5 in both
directions is no longer on this list: `scripts/m1-diff.sh` was run against run K's squashfs and came
back empty both ways (reproduced 2026-11-01 from the archived data files in `logs/runK/`, since that
run's stdout was never captured — see §9.1's run K row), and again against run M's shipped image
(`logs/M1-diff-runM.txt`). It runs again on run N, because the manifest changed.

## 10. Milestones

Each milestone closes only when its exit criteria have been executed and logged.

- **M0 — toolchain proof. DONE 2026-10-30.** Stock trixie live ISO builds and boots in VM. No
  PhantomOS content. Exit: build log + VM screenshot + `cat /etc/os-release` from the running ISO —
  all three are in `logs/` (§9's run table says which run produced which), the ISO being
  `871d7984…c61c`, 347 MiB, built 2026-10-29 and boot-tested over both firmware paths 2026-10-30.
  What the milestone was for: it de-risked the idea cheaply and it came back with three findings
  that changed §5.3, §6 and §9 — the stock live image autologs a sudo-group user (§12 item 10), the
  image's own identity is readable from inside it via `BUILD_ID`, and the build host is not the
  image (13.5 vs 13.7).
- **M1 — package sets. IN PROGRESS 2026-11-01.** `phantomos-base` and `phantomos-desktop`
  metapackages defined, §5 inventory complete with a justification per entry. Exit: `dpkg -l` from
  the built image diffed against §5 comes back empty, in both directions. The exit criterion has now
  been executed against a **shipped image**: run M's ISO came back 834 installed, both directions
  empty, drop guard clean, no build pool inside it (`logs/M1-diff-runM.txt`, run on a build-tree
  squashfs whose identity with the ISO's own copy was checked at the time but not archived — the
  ISO's copy is measured in `logs/M1-runM-shipped-squashfs.txt`, and §9.1's run M row states what
  does and does not stand behind the comparison). That is the criterion as written, and it passed.
  **It is not sufficient, and run M1-boot is why**: the same ISO boots to
  `debian login: user (automatic login)` / `Authentication failure`, because `--apt-recommends false`
  dropped `user-setup`, which is the gate on the component that creates the live account
  (`logs/M1-no-live-user.txt`). A diff is only as good as the two lists it compares, and neither list
  ever named the package whose absence makes the image unusable. So M1's exit criterion keeps its
  wording and gains a second half in practice: the image must also be one a friend can log into.
  Run N rebuilds with `user-setup`, `locales` and `live-tools` named in `manifests/live.pkgs`; M1
  closes when run N's artifact passes `scripts/m1-diff.sh` **and** its boot test reaches a session.
- **M2 — customization packages.** `phantomos-release`, `-config`, `-artwork`, `-installer`,
  `-doctor` built, signed,
  installable from the repo. Exit: `apt install phantomos-desktop` on plain Debian yields the
  PhantomOS look and hardening state, without any ISO rebuild.
- **M3 — install to disk.** The Calamares path (§4.4) produces a booting system. Exit: install in
  VM, reboot, the §6 hardening checks pass, all data present after first login, and `calamares`
  absent from the installed package list. Whatever the partition module actually did with LUKS and
  TPM is written back into §6.1 from that run, not from its documentation.
- **M4 — upgrade path.** The load-bearing milestone for real users. Exit: change a file in
  `phantomos-config`, publish, and confirm a M3 install picks it up via `apt full-upgrade` with
  user edits preserved.
- **M5 — release engineering.** Versioning scheme, checksums, signatures, reproducible-enough
  rebuild, written install/upgrade notes for friends. Exit: a second person installs from the
  published artifact without live help.
- **M6 (deferred)** — Secure Boot with own MOK key. Only if the threat model changes (§6.2).

Installer front-end is decided (Calamares, §4.4); M3's remaining risk is what the partition module
actually does with LUKS and TPM, not which installer runs.

## 11. Verification protocol

- No claim in this file, in README, or in release notes may be written from assumption. It gets
  a run and a log.
- **A log with a fixed filename is not a log for a run.** The bullet above fails quietly when the
  next run writes the same path. Found 2026-11-01: three citations pointed at `logs/M1-lb-build.log`
  as the 838-package build's log, and run M had replaced that file with a different build's at 18:52
  local. The build host never had the problem — it writes `lb-build-<run>.log` and keeps every run —
  only the copy into the repo did. `scripts/m1-diff.sh` had the same shape: `OUT` hardcoded to
  `logs/` and seven fixed-name data files, so run K's set survives only because it was hand-moved to
  `logs/runK/` afterwards, and run K's stdout report was lost outright, which is why its verdict had
  to be re-made with `comm` from the data files (`logs/M1-runK-rootfs-iso-failure.txt` §1). Both
  scripts now stamp the run or accept a per-run output directory (`PHANTOMOS_OUT`). A third
  instance turned up the same day, in `harness/boot-test.sh`, and it was worse than an overwrite:
  the harness opened with `rm -rf "$OUTROOT/$RUN"` where `--run` is caller-supplied *and* is the
  filename prefix of every frame it writes, so reusing a name deleted that run's photographs
  without reporting it. Run M's 74 frames are the evidence behind `logs/M1-no-live-user.txt`, and
  `logs/evidence/` holds them under the same fixed names, so one repeated `--run M1-boot` would
  have destroyed them on the host and then replaced the repo's copies with different pictures under
  the names older write-ups cite. It now refuses a non-empty run directory unless
  `PHANTOMOS_ALLOW_RUN_OVERWRITE=1`, all three branches were run with the destructive one aimed at
  a copy, and testing it found a fifth defect in the same file (`logs/M1-boot-overwrite-guard.txt`).
  The rule going
  forward: anything copied into `logs/` carries the run stamp or goes into the run's own directory,
  and a citation names the file whose contents were actually read — never the file a script happens
  to write to today.
- Before declaring a milestone done: re-run the gate, the hardening checks, and any command
  quoted in docs, then update §3.1's fact table if versions moved.
- The §3.1 DDE-availability row is the one that decides the desktop choice, so it goes stale
  silently. Re-query `packages.debian.org/search?searchon=names&keywords=dde` before any
  discussion of switching desktops, and record the date the check was run.
- Documentation updates are part of the work item, not follow-up.
- A mockup, board or render is a target, never evidence. Artwork claims are governed by §7.4:
  real screenshot per surface plus the delta from the mock.
- Feature tests must be registered in their own driver; a defined-but-unregistered test counts
  as not done. The driver is `scripts/run-tests.sh`, and its first execution (2026-11-01) is the
  reason this bullet has teeth: `scripts/build-iso-artifact-test.sh` had been written, never run,
  and was carrying three bugs — a function called in a pipeline so its exit code died in a
  subshell, a quoted `"$@"` that turned `NAME=value` into a command name, and an unstubbed helper
  that made a bookkeeping test depend on the network. All three surfaced on the first run, none
  would have surfaced on the hundredth read. Registered and passing: `pool-signature-test.sh`,
  `build-iso-artifact-test.sh` (16 assertions). Per-run logs in `logs/tests/`. Its **second**
  execution (17:47Z the same day) found a fourth defect, of a different kind: the test runs the real
  `build-iso.sh`, whose idle guard reads the whole process table rather than only its own `$WORK`, so
  with run N live the test came back 6/16 and every run had exited on `E: refusing to start` — while
  both files carried the claim "safe to run while a build is in progress". The test now overrides the
  guard deliberately and says why at the call site; re-run at 17:51:55Z with the same build still
  live, 2 registered, 2 passed, 16 assertions, 0 failed. That first failure is also the only positive
  evidence so far that the guard fires against a real concurrent build.
- No commit without the maintainer asking for one.

## 12. Open questions

1. **§5 inventory tail** — **resolved 2026-10-24**: the `xfce4-goodies` subset is picked with a
   justification per entry and a written reason for each of the 19 drops, the fonts are three
   packages, and the Deepin question answered by the archive itself (`deepin-gtk-theme` does not
   exist in any suite). Written into §5. No longer blocks M1.
2. **Identity tail (§7.2)** — direction and tokens are locked; still missing the logo mark, a
   licensed wallpaper source, and icon/cursor picks. Now also carrying two items that came out of
   §5's tail: **which renderer owns the decrypt prompt** (GRUB consumes a `.pf2` bitmap, the
   initramfs console a `.psf`, Plymouth a TrueType — so the mono identity font may be unusable
   exactly where §7.2 promised it), and whether `xfce4-genmon-plugin` is an acceptable answer to
   item 9. Blocks M2 artwork.
3. **Repo hosting** — where the signed repo and ISOs live, and who operates it. Blocks M5.
4. **Release cadence:** rebase-on-trixie-point-release vs monthly refresh vs on-demand. Blocks M5.
5. **Support window:** how long a PhantomOS build stays installable after the next one ships.
   Must be decided before the first friend depends on it.
6. **Threat model** — **resolved 2026-10-24**: remote attack and driftnet only, written up as
   §6.0. M6 stays deferred, and the docs boundary in §6.0 applies.
7. **`phantomos-snapshot`** — pre-upgrade LVM thin snapshot with `lvconvert --merge` rollback,
   which is the only rollback left after choosing ext4 (§5.2). Needs a size/TTL policy and a test
   that overfills it. Decided: not in v1 unless the maintainer wants it.
8. **Dock** — `plank` 0.11.89 is a separate floating dock and the closer match to the mock;
   `xfce4-docklike-plugin` 0.4.3 puts window buttons inside the left capsule, which is tidier but
   changes what "dock" means. Both are in trixie (§3.1). Decided by M2 with a real session in
   front of us, not from a mockup.
9. **Tray** — one grouped popover (network + toggles + power) as mocked, or standard Xfce applet
   menus that each open their own window. The grouped version has no off-the-shelf plugin, so
   choosing it means writing or packaging one (§7.2).
10. **Console login on the live media** — found in run H, §9: a stock live ISO autologs a
    sudo-group `user` on tty1–tty6 through a live-config systemd generator, with a password printed
    in the shipped script. For a machine that boots from USB in the threat model of §6.0 that is a
    hole, not a convenience. Open: does PhantomOS ship the live session with autologin (matching
    Debian's expectation that a live USB is used by its owner, and keeping Calamares one click from
    the desktop, §4.4) or at a login prompt (safer, and it makes the "just boot it and it works"
    story worse)? The mechanism for either choice is already known — the generator stands down when
    `/etc/systemd/system/getty@tty1.service.d/live-config_autologin.conf` exists — so this is a
    decision, not research. Blocks M2 (`phantomos-config` owns the file).

11. **Firmware area** — found while writing `live/auto/config`, measured in
    `logs/M1-firmware-areas.txt`. `--archive-areas main` is *live-build's own default*
    (`logs/M0-effective-config.txt`: `LB_ARCHIVE_AREAS="main"`), so the image has never
    consciously chosen its firmware; main carries only DFSG-free blobs. (What this item used to
    say — "M0 installed exactly three" — was a name-prefix count and is corrected in §5 and §9.1:
    six packages carrying `lib/firmware` paths were in M0, and the same six in the first M1 build.)
    The build host's Wi-Fi
    is an **Intel Dual Band Wireless-AC 8260**, which needs `firmware-iwlwifi` — version 20250410-2,
    `Section non-free-firmware/kernel`, and not in the trixie main index, so the blob is not in the
    image and the `iwlwifi` driver in the shipped kernel has no firmware file to request. That is an
    inference from two indexes plus one adapter name; **it has not been observed at boot**, and
    QEMU cannot observe it because no such device can be passed through — the ISO has only ever run
    in a VM (§9). trixie's non-free-firmware is 44 packages and the laptop-relevant ones are heavy:
    `firmware-iwlwifi` 114123 KiB installed, `firmware-sof-signed` 35000 KiB (Intel audio DSP),
    `firmware-intel-graphics` 28978 KiB, `intel-microcode` 20908 KiB. Debian's own answer is
    `live-task-non-free-firmware-pc` (9 KiB, **no Depends** — the blobs come from its postinst, so
    a `phantomos-*` metapackage cannot inherit them). Open: enable `non-free-firmware` and name the
    packages, keep the task package and let its postinst decide, or stay free-only and tell friends
    to bring a USB Ethernet. §6.4's kernel claim rides on the same door: on a machine whose firmware
    microcode predates a mitigation, the mitigation may simply be unavailable, and this repo has not
    measured which ones that affects — the sysfs readings in the log are the Windows host's,
    surfaced through WSL, and say nothing about a friend's laptop. Blocking: an ISO that cannot join
    a network cannot be tested past the console, so this decides whether M2 happens on real hardware.
    **Changed 2026-10-31, in a way that makes this item cheaper to decide:** live-build's
    Contents-based firmware enumeration is now off (§5's amendment, `--firmware-chroot false`), so
    enabling `non-free-firmware` adds the names this section lists rather than the 34 packages and
    4792 paths that rule would pick up on its own (`logs/M1-firmware-nonfree-scale.txt`). The area
    choice is still open; it is no longer bundled with an unreviewed package list.
12. **Recommends debt** — §9.1 records `--apt-recommends false` as a behaviour change in the
    build tree, justified by `logs/M1-recommends-delta.txt` (735 packages without Recommends, 1054
    with, 319 added, including `desktop-base`, `gnome-icon-theme`, `tango-icon-theme`,
    `avahi-daemon`, `modemmanager`). The price is that a Recommends the session genuinely needs is
    now invisible instead of automatic. `logs/M1-recommends-edges.txt` reads the edges out of the
    index rather than recalling them, and all sixteen candidates it checked are confirmed turned off,
    among them the four that look load-bearing: `mate-polkit` (a Recommends of `xfce4` — no
    authentication agent in the session), `gvfs`, `tumbler`, `udisks2`, `xdg-user-dirs` (Recommends
    of `thunar`), `wpasupplicant` and `wireless-regdb` (Recommends of `network-manager`), and
    `xdg-desktop-portal` / `xdg-desktop-portal-gtk` / `xdg-user-dirs` (Recommends of `flatpak`, which
    is what §5.1's sandbox talks to for file pickers). `ppp` and `dnsmasq-base` are in the same set
    and are fine to lose. `upower`, `xfdesktop4` and `xfwm4` were checked and do arrive through
    Depends; `polkitd` does not — zero stanzas in run M's image and in M0's, its only carriers being
    three packages that are themselves in the dropped set (§9.1, corrected 2026-11-01). The hole is
    not theoretical: `network-manager-applet` and `nm-connection-editor` both Depend on
    `policykit-1-gnome | polkit-1-auth-agent`, and the resolution landed on `ukui-polkit` — the UKUI
    desktop's agent, 10 277 KiB installed with OpenCV among its Depends, in an Xfce image,
    autostarting into a system with no authorization daemon for it to register with. Why apt
    preferred it over `policykit-1-gnome` is not established; run M kept no index
    (`LB_CACHE_INDICES=false`). Both halves are `logs/M1-no-live-user.txt` §5-§6. Whether each of the load-bearing four is actually
    needed is a behaviour question and has **not** been run — the M2 session is the test. Open: name
    the needed ones in §5 (the right place, since the alternative is trusting Recommends again), and
    decide what `phantomos-desktop` Depends on so that `apt install phantomos-desktop` on a stock
    Debian gives a working session rather than a panel with no auth agent and Wi-Fi with no
    supplicant. Blocks M2.
    **Moved, 2026-10-31:** `wireless-regdb` is off this list — §5 names it now, with the reason in
    the amendment. One candidate is **added**: `alsa-ucm-conf` is a `Recommends:` of
    `libasound2-data` and is measured absent from the built image
    (`logs/M1-firmware-contents-lines.txt` §7, which is where the `libasound2-data` edge was read),
    while `alsa-topology-conf` — its companion, and the other half of ALSA's card configuration —
    is present only because §5 now names it. On Intel DSP laptops the two usually matter together;
    whether this fleet needs UCM is a behaviour question for the M2 session, and `phantomos-doctor`
    or the audio smoke test is where it gets answered.
13. **The build host's resolver is a single point of failure for the build, and it has already
    cost two milestone-closing runs.** `/etc/resolv.conf` on the WSL2 build host carries one
    nameserver (`10.255.255.254`, WSL's own forwarder) and no fallback. When it stopped answering
    for a few minutes, run K died on three `InRelease` fetches after 51 minutes with the squashfs
    already built, and run L died on two `.deb` fetches after 48 minutes (§9.1). Everything in-tree
    that could be done has been done and measured: `scripts/seed-binary-cache.sh` removes the last
    `.deb` fetch from a build entirely, `live/config/apt/apt.conf` was found to mitigate nothing
    because live-build passes its own `Acquire::Retries=5` on the command line, and a local
    apt-cacher-ng was measured to serve `pool/*.deb` byte-identical with upstream totally
    unreachable but to 503 on `dists/*`, so it would have saved run L and not run K — and was
    rejected anyway as host state outside the repository (`logs/M1-acng-offline-serving.txt`).
    What is left is a host decision that has deliberately **not** been taken: add a second
    nameserver to `/etc/wsl.conf`, or accept that a build can die on the network and must simply be
    re-run, which at ~50 minutes a run and with the fetch caches intact is annoying but not
    expensive. Open. Blocks nothing, but it is the reason M1 has taken three runs to close.
14. **`chroot_archives` is 46 % of the build and fetches no packages; two levers would cut it and
    neither has been pulled.** Measured on run M (§9.1, `logs/M1-build-cost-runM.txt`): six
    `chroot_archives` invocations total 2918 s of that build's 6276 s — more than debootstrap
    (1031 s), more than installing the whole desktop set (925 s), more than the xz squashfs of an
    837 MB image (669 s) — and 2706 s of it is `Fetched` traffic: 135 MB, not one byte of which is a
    `.deb`. ~10.7 MB per pass is `trixie/main Sources`, the single largest object in the five passes
    that carry it, expanding to 57 MB of index that apt then parses, there only because three
    `deb-src` lines are in the chroot's `sources.list`. Those lines are inherited rather than
    chosen: nothing in this tree writes `deb-src` (the one `grep` hit, in `scripts/m1-diff.sh`, reads
    them), `/usr/share/live/build/functions/sourcelist.sh:143-149` comments them back out only when
    `LB_APT_SOURCE_ARCHIVES != "true"`, and `"true"` is live-build's own default
    (`logs/M0-effective-config.txt:24`) — so `auto/config`'s "three deviations" claim still holds and
    this is not a fourth one. The two levers, both confirmed against the installed
    `live-build 1:20250505+deb13u1` rather than a captured help text: `--cache-indices true` keeps
    `lists/` between runs so a second build revalidates instead of re-fetching, and changes no
    shipped file; `--apt-source-archives false` removes the ~10.7 MB and the 57 MB parse per pass but
    also removes the three `deb-src` lines from the *shipped* `sources.list`, which would be an
    image-visible difference with an argument on both sides and a genuine fourth deviation needing
    `auto/config`'s header and `config-audit.sh`'s baseline updated. Neither was pulled, because §11
    requires the gate re-run after any build-input change, and changing an input to make the *next*
    build faster in the same session that the current one finally passed trades a measured result for
    an unmeasured one. A caching proxy is not a lever and was measured not to be one: apt-cacher-ng
    revalidates `dists/*` against upstream on every request (item 13,
    `logs/M1-acng-offline-serving.txt` §2), and `dists/*` is the whole of this cost. No speedup is
    claimed anywhere in this item — the prediction is falsifiable and specific, and is written down in
    `logs/M1-build-cost-runM.txt` §5 so a future run can contradict it. Open. Blocks nothing.
15. **`live-tools` diverts `update-initramfs`, and neither of its branches has been executed in a
    PhantomOS image.** Naming `live-tools` in `manifests/live.pkgs` — part of the fix for the M1
    no-login defect (`logs/M1-no-live-user.txt`) — brings in a package that ships its own
    `/usr/sbin/update-initramfs` and, in `preinst`, diverts initramfs-tools' 7530-byte copy of the
    same path to `/usr/sbin/update-initramfs.orig.initramfs-tools` (plus the matching man page). So
    from run N onward `dpkg -S /usr/sbin/update-initramfs` answers `live-tools` where run M's answers
    `initramfs-tools`, and the program every kernel package's postinst calls is a 95-line wrapper.
    Read in full, the wrapper is benign, and the reason it is benign is that its branches key off the
    kernel command line rather than off package presence: a system with no `boot=live` in
    `/proc/cmdline` (or with `/.live-build` present, i.e. inside a build) gets a straight
    pass-through to the diverted original and its exit status, and a live system whose
    `/run/live/medium` is not writable gets `I: update-initramfs is disabled (live system is running
    on read-only media)` and exit 0. The only branch that does anything is the writable-live-USB one,
    which cannot fire from an ISO. **Neither branch has been run**: run M's image does not contain the
    package, and run N's will contain it but has not been installed from. The M3 question is whether
    Calamares' target system ends up with `live-tools` at all — it sits in the live-media bucket, not
    in §5's inventory, so it should not, but that is a reading of a bucket boundary and not a
    measurement of an installed system. Measured 2026-11-01 from the downloaded `.deb` and its
    maintainer scripts (`logs/M1-no-live-user.txt` §9), which is also the only reason the manifest's
    comment for this package names real files: the index's own `Description` says only "extra
    components for live systems". Open. Blocks nothing in M1; M3 owns it.
16. **Nothing exports `SOURCE_DATE_EPOCH`, so no two builds of this tree are byte-comparable, and
    setting it is one line with two consequences.** live-build treats the variable as its
    reproducible-build switch (`configuration.sh:49` `_REPRODUCIBLE="${SOURCE_DATE_EPOCH:-false}"`)
    and then sets it to the wall clock anyway when it is unset (`:57` `export
    SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(date '+%s')}"`). That one value reaches at least six
    places in the artifact: `/etc/os-release`'s `BUILD_ID` (`bootstrap_debootstrap:140`, rendered
    `--utc`), the ISO volume id (`binary_iso:120`, rendered with `$DATE_UTC_OPTION`, i.e. **local**),
    the ISO9660 modification date (`binary_iso:125`), the ISO file's own mtime (`binary_iso:230`
    `touch`es it), every mtime under `binary/` newer than the epoch (`binary:74`, a `find … -exec
    touch` that is **not** gated on `_REPRODUCIBLE` and so runs on every build, listing what it
    rewound in `binary.modified_timestamps`), and through that the squashfs superblock's creation
    time. Measured on two runs of the same committed tree with byte-identical 98-assignment config
    dumps: `BUILD_ID` `20261101T140728Z` versus `20261101T172103Z`, each exactly one second after
    its run's stamp, and their `/etc/os-release` files differ in that line and nothing else
    (`logs/M1-buildid-per-run.txt`).

    Two things follow, and only the first is a fix. **Already applied:** an artifact's mtime is the
    second the run *started*, not when it finished, so no log may quote one as a finish time — run
    M's 908 066 816-byte ISO reports `17:07:28 +0300` and its last stage ran until ~18:52. Use the
    run record's `run: $START .. $END` or the log's last stage stamp. **The decision, not taken:**
    exporting `SOURCE_DATE_EPOCH` in `auto/config` would pin all six at once, but it also flips
    `_REPRODUCIBLE` true, which makes `LB_UTC_TIME` default to true (`configuration.sh:54`,
    currently `"false"` at config-dump line 96), which switches live-build's own stage stamps from
    host-local EAT to UTC. Every timestamp already written into §9.1's run table and into `logs/`
    was compared across those two clocks with the offset stated by hand; after the change the offset
    disappears and the older comparisons still say `+03:00`. It also changes the volume id, which is
    image-visible, so like item 14's second lever it would need `auto/config`'s deviation header and
    `config-audit.sh`'s baseline updated.

    What setting it would **not** do, so that nobody claims it later: pinning the epoch removes
    timestamp variation and nothing else. Two runs days apart still resolve different package
    versions out of the archive, so this is not a route to a byte-identical image and no such test
    has been run. §10's M5 row ("reproducible-enough") is where the trade belongs, and M1a is
    untouched by it — M1a's claim is about *inputs*, that any run started from this tree builds the
    same image with no step living in shell history, which is what run N tests. Open. Blocks
    nothing in M1; M5 owns it.

Resolved 2026-10-24: installer = Calamares (§4.4); filesystem = ext4 on LVM (§5.2); app sourcing
= flatpak with no default remote (§5.1); image ships dev tools + `mpv`, no office, no mail (§5);
feature set = doctor, Firefox policies, first-boot (§5.3); identity = Apparition, dark only,
three-capsule top panel + dock (§7.2); launcher = fullscreen rofi grid, dim overlay in v1 and blur
as a tested M2 stretch goal (§7.2); inventory tail = the 11-package goodies subset, three identity
fonts, and our own GTK CSS because no Deepin GTK theme exists in Debian (§5, §7.3).
