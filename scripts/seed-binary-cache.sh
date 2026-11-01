#!/bin/bash
# seed-binary-cache.sh — put the .debs that live-build's *binary* stages fetch outside its own
# caches into live/cache/packages.binary, so the last minute of a build does not need the network.
#
# The gap this closes, measured on run L (logs/M1-runL-binary-rootfs-dns.txt):
#
#   /usr/lib/live/build/binary_rootfs, squashfs branch, lines 265-271:
#       Check_package chroot /usr/share/doc/squashfs-tools squashfs-tools
#       Restore_package_cache binary
#       Install_packages
#   i.e. an apt install of squashfs-tools into the build chroot at the very END of every build.
#   Run L reached it 48 minutes in, WSL's resolver returned "Temporary failure resolving
#   'deb.debian.org'", all five Acquire::Retries failed, and the build died 249 kB from an ISO.
#   Run K died the same way one stage earlier.
#
#   squashfs-tools was in NONE of the five caches (cache/{bootstrap,packages.bootstrap,
#   packages.chroot,packages.binary,contents.chroot}); cache/packages.binary held 25 .debs —
#   xorriso, mtools, grub-efi-*, shim-*, librsvg2-bin — every one of them a binary_iso or
#   binary_grub-efi helper, whose Save_package_cache runs before their Remove_packages.
#   binary_rootfs saves at line 378, after Remove_packages at 345, so its helper never lands.
#
# Restore_package_cache (functions/cache.sh:12) copies cache/packages.<stage>/*.deb into
# chroot/var/cache/apt/archives before Install_packages, and apt then installs from disk. That
# mechanism is not theoretical here: run L's chroot_install-packages stage spent 11m44s
# installing the whole desktop set and printed no "Fetched" line at all, because
# cache/packages.chroot (574 MB) served it. This script points the same mechanism at the one
# stage that was missing from it.
#
# The seed is build-side only. squashfs-tools, xorriso, mtools and dosfstools are absent from
# logs/M1-image-installed-raw.txt (the 838 packages dpkg reports inside the shipped squashfs);
# liblzo2-2 is present there because the image needs it independently, not because of this.
#
# Residual exposure, stated rather than hidden: apt reuses a cached .deb only when it matches the
# candidate version, so if Debian releases a new squashfs-tools between this script resolving the
# candidate and the build's own apt-get update, the build falls back to the network for that one
# package. The window is minutes and the seed is additive (old versions are kept, they cost only
# disk), so a run that seeds often is exposed for less time than one that seeds once.
#
# Usage: scripts/seed-binary-cache.sh [work-dir]     (default /root/phantomos-m1)

set -euo pipefail
export LC_ALL=C

WORK="${1:-/root/phantomos-m1}"
CACHE="$WORK/live/cache/packages.binary"
LB="${LIVE_BUILD:-/usr/lib/live/build}"

# binary_rootfs's squashfs branch, and the one dependency that install pulls with it. The first
# entry is derived from the Check_package call above; the second from squashfs-tools' own Depends.
# Both derivations are re-run below so a live-build upgrade that changes the need, or a Debian
# release that changes the dependency, shows up in the log instead of silently reopening the hole.
PRIMARY="squashfs-tools"

[ -d "$WORK/live" ] || { echo "E: $WORK/live does not exist — run this after lb config" >&2; exit 2; }
mkdir -p "$CACHE"

echo "=== live-build still asks for $PRIMARY in binary_rootfs? ==="
if LINE=$(grep -n "Check_package[^\"]*$PRIMARY" "$LB/binary_rootfs" 2>/dev/null | head -1) && [ -n "$LINE" ]; then
	echo "  yes: binary_rootfs:$LINE"
else
	echo "  E: no Check_package in $LB/binary_rootfs names $PRIMARY — upstream moved." >&2
	echo "     Re-derive the list before trusting this seed; an unchecked cache is a stale cache." >&2
	exit 2
fi

echo "=== dependencies that install would fetch with it ==="
DEPENDS=$(apt-cache depends --no-recommends --no-suggests --no-conflicts --no-breaks \
	--no-replaces --no-enhances "$PRIMARY" 2>/dev/null | awk '/^  Depends: /{print $2}')
[ -n "$DEPENDS" ] || { echo "E: apt-cache depends returned nothing for $PRIMARY" >&2; exit 2; }
echo "$DEPENDS" | sed 's/^/  /'
# Only the ones the build chroot does not already have will actually be downloaded, and that set
# is the chroot's business, not this script's. Seed all of them: an extra .deb in
# cache/packages.binary costs disk and nothing else, a missing one costs a 48-minute build.
PACKAGES="$PRIMARY $DEPENDS"

echo "=== what is already cached ==="
for P in $PACKAGES; do
	HAVE=$(ls "$CACHE" 2>/dev/null | grep -c "^${P}[_%].*\.deb$" || true)
	echo "  $P: $HAVE file(s) in cache/packages.binary"
	ls "$CACHE" 2>/dev/null | grep "^${P}[_%]" | sed 's/^/    /' || true
done

echo "=== candidate versions on this host ==="
for P in $PACKAGES; do
	echo "  $P: $(apt-cache policy "$P" 2>/dev/null | awk '/Candidate:/{print $2}')"
done

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
# apt drops to the _apt user to write downloads; a root-only 0700 tmpdir makes it fall back to an
# unsandboxed fetch and prints a warning that reads like a failure in the build log.
id _apt >/dev/null 2>&1 && chown _apt "$WORKDIR"
( cd "$WORKDIR" && apt-get download $PACKAGES )

echo "=== downloaded ==="
ls -la "$WORKDIR"/*.deb | sed 's/^/  /'

# apt only reuses a cached .deb whose name is the one it would have downloaded, so the naming
# convention is checked against a file apt itself produced during a real install rather than
# assumed. cache/packages.chroot was filled by Save_package_cache out of a live chroot's
# /var/cache/apt/archives, which makes it ground truth for the form apt uses.
# The interesting cases are the two characters apt encodes in URIs: ':' as %3a (see
# isolinux_3%3a6.04~…deb already in cache/packages.binary) and '+' as %2b (run L's error text
# said liblzo2-2_2.10-3%2bb1_amd64.deb). Whichever form apt-get download produces has to be the
# form apt looks for, or this whole script seeds files that are never read.
echo "=== naming convention cross-check ==="
GROUND=$(ls "$WORK/live/cache/packages.chroot"/liblzo2-2_*.deb 2>/dev/null | head -1 || true)
GOT=$(ls "$WORKDIR"/liblzo2-2_*.deb 2>/dev/null | head -1 || true)
if [ -n "$GROUND" ] && [ -n "$GOT" ]; then
	GN=$(basename "$GROUND"); TN=$(basename "$GOT")
	echo "  apt's own name from a real install: $GN"
	echo "  apt-get download produced:          $TN"
	if [ "$GN" = "$TN" ]; then
		echo "  OK: identical — the seed will be read by Restore_package_cache"
	else
		echo "  E: names differ, so apt would ignore the seed and fetch anyway" >&2
		echo "     refusing to copy a file that cannot be used; fix the naming first" >&2
		exit 1
	fi
else
	echo "  W: cross-check skipped (ground truth: ${GROUND:-none}, downloaded: ${GOT:-none})" >&2
	echo "     the naming claim is then unverified — check the next build log for a squashfs-tools fetch" >&2
fi

echo "=== copying into $CACHE (additive: existing versions are kept) ==="
for F in "$WORKDIR"/*.deb; do
	N=$(basename "$F")
	if [ -e "$CACHE/$N" ]; then
		echo "  already there: $N"
	else
		cp "$F" "$CACHE/$N"
		echo "  seeded: $N ($(stat -c %s "$CACHE/$N") bytes)"
	fi
done

echo "=== cache/packages.binary now holds $(ls "$CACHE"/*.deb 2>/dev/null | wc -l) .deb(s), $(du -sh "$CACHE" | awk '{print $1}') ==="
