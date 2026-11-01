#!/bin/bash
# build-packages.sh — build PhantomOS's own metapackages from the manifests and publish
# them into a signed local pool that live-build installs from.
#
# Everything about these packages derives from manifests/*.pkgs, which derive from
# §5. The Depends lines are generated, never hand-written, so the metapackages and the
# M1 inventory diff cannot drift apart.
#
# The pool is a directory on the build host, not content copied into the chroot. That is
# live-build's own mechanism for a local archive: chroot_archives bind-mounts the path named
# by a file:// line in config/archives/*.list.chroot into the chroot
# (/usr/lib/live/build/chroot_archives:67 → Chroot_try_bind_path in
# /usr/share/live/build/functions/chroot_bind_path.sh:18) before its first apt-get update,
# and chroot_archives remove unmounts it, deletes the sources entry (chroot_archives:360-366)
# and deletes the key (:398-409) at the end of the chroot stage — then runs apt-get update
# again without them (:475). Two shapes of that line are load-bearing and both were found by
# a failed build rather than by reading the docs: three slashes after `file:`, and the deb
# line being the first line of the file. See the contract check below it.
#
# This replaced an earlier design that put the pool in
# config/includes.chroot_before_packages/, and the reason it has to be archives and not
# includes is stage order: /usr/lib/live/build/chroot runs the archives step at line 34 and
# the includes-before-packages step at line 40, so apt reads the pool's entry before the
# pool is on disk. The first M1 build failed exactly that way — "Err:2 file:/phantomos-pool
# ./ Release — File not found" (logs/M1-lb-build-pool-order.log:723-739, §9.1).
#
# Because the pool is only ever mounted, it cannot reach the image, and §8's "no dead
# channel in a shipped image" is live-build's behaviour rather than a cleanup step of
# ours. Measured, not assumed: scripts/m1-diff.sh asserts the absence on the built tree and
# harness/commands/M1.txt asserts it on the running image.
#
# The pool is signed with the build key (§8's "our key pinned"). The private half is
# NOT in this repo and not in the image: it lives outside the tree at
# $PHANTOMOS_KEYDIR (default /root/phantomos-key), created by
# scripts/init-signing-key.sh. Only the armored public key is committed, at
# live/config/archives/phantomos.key.chroot, which is what the build host trusts.
#
# This is a pre-repo mechanism. §12 item 3 (where the hosted signed repo lives) is
# still open, so a built image carries no PhantomOS apt channel. §8's HTTPS requirement
# is therefore not satisfied by M1 and M1 does not claim it is; what M1 proves is that the
# §5 Depends resolve against trixie, and that the keyring + signature machinery works.
#
# Must run as root (or under fakeroot): §9 — this toolchain runs in WSL Debian as
# root. dpkg-deb --root-owner-group normalises ownership regardless.
#
# Usage: scripts/build-packages.sh [repo-root]
#   PHANTOMOS_BUILDDIR  host staging directory; the pool is $PHANTOMOS_BUILDDIR/pool and
#                       live-build binds that exact path into the chroot, so moving it
#                       means editing the deb line in the archives file (checked below)

set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
VERSION="${PHANTOMOS_VERSION:-0.1.0-1}"
MAINTAINER="${PHANTOMOS_MAINTAINER:-PhantomOS Maintainer <root@localhost>}"
KEYDIR="${PHANTOMOS_KEYDIR:-/root/phantomos-key}"
KEYID="${PHANTOMOS_KEYID:-PhantomOS Archive Signing Key}"
LIST_FILE="$ROOT/live/config/archives/phantomos.list.chroot"
PUBKEY="$ROOT/live/config/archives/phantomos.key.chroot"
# Staging goes on the build host's own filesystem, not the repo copy. Two reasons, both
# learned the hard way on this machine (§9): dpkg-deb refuses a control directory with
# 777, which is what every directory under /mnt/c reports, and a mode that comes from
# Windows would otherwise be baked into the package.
#
# Where on that filesystem is load-bearing too, and /var/tmp — where this used to live — is
# wrong. A bind-mounted archive is visible to the chroot at the same absolute path, and
# live-build's own default hooks clean the chroot's filesystem after the packages are
# installed: 8070-remove-temporary-files.hook.chroot:6-12 is `for _DIRECTORY in /tmp
# /var/tmp; do rm -rf ${_DIRECTORY}; mkdir -p …; chmod 1777 …`. rm -rf recurses *through*
# the bind, so it deleted the pool at its own source and then failed on the mountpoint
# itself with EBUSY, which aborted the build (logs/M1-lb-build-pool-hook.log:5842-5844,
# §9.1). The directory-level removals in the whole default normal-hook set are /tmp,
# /var/tmp, /var/cache/man/* and /var/cache/ldconfig — that is the hazard list, read out of
# /usr/share/live/build/hooks/normal on 2026-10-30. /opt is on none of them, and it is also
# the honest name for a staging area that outlives a build.
BUILD_ROOT="${PHANTOMOS_BUILDDIR:-/opt/phantomos-build}"
BUILD="$BUILD_ROOT/packages"
POOL="$BUILD_ROOT/pool"

# Which manifest each package's Depends come from. release and config carry files, not
# selections, so they depend on nothing.
depends_manifest() {
	case "$1" in
		phantomos-base) echo base.pkgs ;;
		phantomos-desktop) echo desktop.pkgs ;;
		*) echo "" ;;
	esac
}

description_of() {
	case "$1" in
	phantomos-base) printf '%s\n' \
		"PhantomOS base policy and hardening metapackage" \
		" PhantomOS is a hardened Debian trixie derivative for a small group of users." \
		" This package pulls the hardening controls and base tooling the spec lists as" \
		" phantomos-base. It makes no GUI assumption, so a headless box can install it" \
		" alone." ;;
	phantomos-desktop) printf '%s\n' \
		"PhantomOS desktop metapackage" \
		" The Xfce session, its panel apps and the workstation and development tools" \
		" that the spec inventories for the desktop image. Depends on phantomos-base." ;;
	phantomos-release) printf '%s\n' \
		"PhantomOS apt archive keyring" \
		" The public half of the key that signs the PhantomOS package pool. Installing" \
		" this package does not enable a PhantomOS apt channel: the repository location" \
		" is still an open decision, and a sources entry pointing at nothing would break" \
		" apt update on every machine that installed it." ;;
	phantomos-config) printf '%s\n' \
		"PhantomOS configuration skeleton (no content yet)" \
		" PLACEHOLDER. The Xfconf and gsettings defaults, dotfile skeleton, sysctl," \
		" AppArmor profiles, systemd drop-ins and firewall rules land here in M2. It" \
		" ships now, empty, so that phantomos-base depends on the set of packages the" \
		" inventory names and the M1 diff measures the real package set." ;;
	esac
}

# deps_of <package> -> comma-separated Depends value, or empty
deps_of() {
	local pkg="$1" list=() m
	# §4.2: desktop always pulls base. Not in any manifest, because §5's desktop
	# inventory describes software, not our own packaging graph.
	if [ "$pkg" = "phantomos-desktop" ]; then list+=(phantomos-base); fi
	m="$(depends_manifest "$pkg")"
	if [ -n "$m" ]; then
		while IFS= read -r name; do
			list+=("$name")
		done < <(sed -e 's/#.*//' "$ROOT/manifests/$m" | awk 'NF' | sed -e 's/[[:space:]]*$//')
	fi
	[ ${#list[@]} -gt 0 ] || return 0
	printf '%s' "${list[0]}"
	printf ', %s' "${list[@]:1}"
}

# The archives file is the contract with live-build: it names the host path that gets
# bind-mounted, and the two have to agree or the build installs from a pool that is not the
# one just signed. Checked rather than trusted because the path is also a variable.
#
# The check runs live-build's own extractor, not a grep of our invention, so it tests the
# mechanism instead of restating it. chroot_archives:67 calls Chroot_try_bind_path_from_list,
# which takes the URI out of ${FILE} with `... | head -1`: the first line of this file is the
# only line ever examined, and if it is a comment the bind silently does not happen. That was
# the second failed M1 build (logs/M1-lb-build-first-line.log, logs/M1-pool-bind-first-line.txt).
if [ ! -f "$LIST_FILE" ]; then
	echo "E: $LIST_FILE missing — the chroot needs a deb line pointing at $POOL" >&2
	exit 1
fi
EXPECTED_FIRST="deb file://$POOL ./"
BOUND_URI=$(sed --regexp-extended -e 's/.*(file:\/\/[^ ]+).*/\1/' "$LIST_FILE" | head -1)
if [ "$BOUND_URI" != "file://$POOL" ]; then
	echo "E: live-build would bind nothing from $LIST_FILE." >&2
	echo "   live-build's own extractor (chroot_bind_path.sh:63-72, \`... | head -1\`) read:" >&2
	echo "       $BOUND_URI" >&2
	echo "   and only binds paths matching ^file://(localhost)?/ — three slashes." >&2
	echo "   It reads the FIRST line of the file, so the deb line cannot sit below a comment." >&2
	exit 1
fi
if [ "$(head -1 "$LIST_FILE")" != "$EXPECTED_FIRST" ]; then
	echo "E: the first line of $LIST_FILE is not this pool." >&2
	echo "   expected on line 1:  $EXPECTED_FIRST" >&2
	echo "   got:                 $(head -1 "$LIST_FILE")" >&2
	exit 1
fi

# The same contract, the other half: the path in that line must not be under a directory the
# default chroot hooks clear, because a bound archive is reachable at it from inside the
# chroot and rm -rf there deletes the pool at its source. The list below is read out of
# /usr/share/live/build/hooks/normal (logs/M1-pool-hook-hazard.txt), not recalled.
for haz in /tmp /var/tmp /var/cache/man /var/cache/ldconfig; do
	case "$POOL/" in
		"$haz"/*)
			echo "E: the pool would be bind-mounted at $POOL, inside $haz." >&2
			echo "   8070-remove-temporary-files.hook.chroot runs 'rm -rf /tmp /var/tmp' inside" >&2
			echo "   the chroot, after the packages are installed and before the archives stage" >&2
			echo "   unmounts — that is how a pool at /var/tmp/phantomos-build/pool was deleted" >&2
			echo "   off the build host and the build aborted on EBUSY (§9.1)." >&2
			exit 1 ;;
	esac
done

# A build that was interrupted leaves the pool mounted inside the chroot. Take it down
# before removing anything: rm -rf recurses *through* a bind mountpoint and deletes the pool
# at its own source, then fails on the rmdir with EBUSY (measured twice — logs/M1-pool-uri.txt
# for our own rm, logs/M1-pool-hook-hazard.txt for live-build's hook doing it to us).
# umount -R on a parent directory is not the fix either; it only works on a path that is
# itself a mountpoint, so the targets have to come out of /proc/mounts. Matched by name rather
# than by $POOL exactly, so a leftover mount at a path this script used before the pool moved
# is taken down too.
awk -v d="$ROOT/live/chroot" 'index($2, d) == 1 && $2 ~ /phantomos-build/ { print $2 }' /proc/mounts \
	| while IFS= read -r m; do
		umount "$m"
	done

rm -rf "$BUILD" "$POOL"
mkdir -p "$POOL"

for pkg in phantomos-release phantomos-config phantomos-base phantomos-desktop; do
	dir="$BUILD/$pkg"
	mkdir -p "$dir/DEBIAN"
	{
		echo "Package: $pkg"
		echo "Version: $VERSION"
		echo "Architecture: all"
		echo "Maintainer: $MAINTAINER"
		echo "Priority: optional"
		echo "Section: metapackages"
		d="$(deps_of "$pkg")"
		if [ -n "$d" ]; then echo "Depends: $d"; fi
		# description_of prints the summary line bare; dpkg needs the field name on it
		description_of "$pkg" | awk 'NR==1{print "Description: " $0; next} {print}'
	} > "$dir/DEBIAN/control"

	if [ -d "$ROOT/packages/$pkg/root" ]; then
		cp -a "$ROOT/packages/$pkg/root/." "$dir/"
		# Whatever the source tree's modes were (on a Windows-mounted repo copy they are
		# all 777), a shipped package gets 755 dirs and 644 files.
		find "$dir" -type d -exec chmod 0755 {} +
		find "$dir" -type f -exec chmod 0644 {} +
	fi

	# The keyring is generated from the committed public key, so the file the image
	# ships cannot drift from the key that signed the pool.
	if [ "$pkg" = "phantomos-release" ]; then
		if [ ! -f "$PUBKEY" ]; then
			echo "E: $PUBKEY missing — run scripts/init-signing-key.sh first" >&2
			exit 1
		fi
		mkdir -p "$dir/usr/share/keyrings"
		gpg --dearmor < "$PUBKEY" > "$dir/usr/share/keyrings/phantomos-archive.gpg"
	fi

	dpkg-deb -Zxz --root-owner-group -b "$dir" "$POOL/${pkg}_${VERSION}_all.deb"
	echo "built ${pkg}_${VERSION}_all.deb ($(wc -c < "$POOL/${pkg}_${VERSION}_all.deb") bytes)"
done

# Index and sign. apt prefers a clearsigned InRelease over Release + Release.gpg; both
# are produced so a problem with either is visible rather than silent.
# Flat repository ("deb file:... ./"), which is what a pool of our own metapackages is;
# no dists/ tree, so no Suite is declared.
cd "$POOL"
apt-ftparchive packages . > Packages
gzip -9nkf Packages
apt-ftparchive -o APT::FTPArchive::Release::Origin="PhantomOS" release . > Release
GNUPGHOME="$KEYDIR" gpg --batch --yes --local-user "$KEYID" \
	--armor --detach-sign --output Release.gpg Release
GNUPGHOME="$KEYDIR" gpg --batch --yes --local-user "$KEYID" \
	--clearsign --output InRelease Release
echo "pool signed: $(ls | tr '\n' ' ')"
