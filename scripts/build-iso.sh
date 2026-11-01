#!/bin/bash
# build-iso.sh — one command, from the committed tree to a built image.
#
# It does six things, in this order, and fails on the first one that fails:
#   1. copy this repo into a build directory on the WSL filesystem
#   2. normalise file modes (a Windows-mounted tree reports 777 for everything; see
#      §9 — dpkg-deb refuses such a control directory outright)
#   3. lb config, then generate the package lists from the manifests, then build and
#      sign our metapackages into the host pool that live-build bind-mounts into the
#      chroot (default /opt/phantomos-build/pool; see scripts/build-packages.sh for why that
#      path and not /var/tmp)
#   4. seed live-build's binary-stage package cache, which upstream leaves empty for the one
#      helper binary_rootfs needs (scripts/seed-binary-cache.sh)
#   5. lb build
#   6. move the ISO into $WORK/artifacts/<run>/, and copy the build log plus the artifact's
#      size + SHA256 back into logs/
#
# It also re-execs a private copy of itself first, because bash reads a script from a byte offset
# into the file it was given and editing this file mid-run kills the run. See below.
#
# The build does not run in place. M0 built in /root/m0-live for the same reason:
# squashfs, loop mounts and dpkg want a Linux filesystem, and drvfs is neither fast nor
# honest about permissions.
#
# The copy step excludes the build scratch directories, so a second run resumes where a
# failed one stopped rather than throwing away an hours-long download: live-build skips a
# stage whose stamp is in $WORK/live/.build, and debootstrap reuses
# $WORK/live/chroot/var/cache/apt/archives. That is a resume, not a rebuild — for a clean
# build from zero, remove the work directory ($PHANTOMOS_WORK) first. §9.1 records both
# halves of this: the resume was needed because one bootstrap download wedged at 700 B/s
# (logs/M1-build-throughput.txt), and a resumed build is a weaker claim than a cold one,
# so the cold run is what the milestone is closed with.
#
# rsync --delete is why this run's own output goes under $WORK/logs, which is excluded: an
# earlier version wrote build.log at the top of $WORK, and the next run's --delete removed
# the previous failure log before it had been copied out again (the copy already in logs/
# survived, which is why §9.1 has the pool-ordering failure at all). Timestamped names keep
# every run in $WORK/logs even though only the newest is copied out.
#
# Usage: scripts/build-iso.sh [repo-root]
#   PHANTOMOS_WORK=…  build directory (default /root/phantomos-m1)
#   PHANTOMOS_LOG=…   name for the log copied into logs/ (default M1-lb-build-<run>.log,
#                     where <run> is the same UTC stamp the artifact directory gets)

set -euo pipefail

REPO="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
WORK="${PHANTOMOS_WORK:-/root/phantomos-m1}"
# Resolved below, once $START exists. It used to default to the fixed name `M1-lb-build.log` here,
# which every run overwrote — see the comment at the cp.
LOGNAME="${PHANTOMOS_LOG:-}"

# Refuse to start on top of a build that is already running, before the first line below that can
# damage one. Everything this script does next — mv of live/*.iso, rsync --delete, the recursive
# chmod, lb config — is destructive to a tree live-build is actively reading, and none of it
# reports itself as damage: it surfaces hours later as a failed run (§9.1: run K died at 51 minutes,
# run L at 48, both after their expensive stages had completed).
#
# The probe answers from live/.lock plus the process table rather than from a lock file of ours, so
# it also catches `lb build` started by hand, which would take no lock. That is the whole point: a
# lock only holds against callers who choose to take it.
#
# --exclude-pid is this process. The re-exec below keeps the same pid and the guard runs in both
# passes, so without it this run would block on itself.
if ! BUILD_STATE=$(bash "$REPO/scripts/build-status.sh" --work "$WORK" --exclude-pid $$ 2>&1); then
	printf '%s\n' "$BUILD_STATE"
	if [ "${PHANTOMOS_ALLOW_CONCURRENT_BUILD:-0}" != 1 ]; then
		echo "E: refusing to start — $WORK is not idle." >&2
		echo "   Wait for the run named above, or set PHANTOMOS_ALLOW_CONCURRENT_BUILD=1 to" >&2
		echo "   override deliberately. Do not override to work around an unexpected answer:" >&2
		echo "   the commonest cause is a build still writing this tree, and overriding that is" >&2
		echo "   how a resume destroys the chroot it is resuming." >&2
		exit 1
	fi
	echo "W: PHANTOMOS_ALLOW_CONCURRENT_BUILD=1 — proceeding over the state above." >&2
fi

# bash executes a script from one open fd and a byte offset it maintains itself, re-reading as it
# goes. Edit the file underneath a running build and that offset lands mid-line in the new content,
# so bash parses a fragment and dies. Measured on run L (started 2026-10-31T00:43:22Z): the
# artifact-loss fix below lengthened this file while the run was in `lb build`, and the run's output
# ends with
#   /mnt/c/…/scripts/build-iso.sh: line 85: syntax error near unexpected token `('
#   /mnt/c/…/scripts/build-iso.sh: line 85: ` are optional (M1 ships none — see the header of …'
# which is the tail of the "Hooks are optional" comment — prose, because that is where the stale
# offset fell. `lb build` was an orphaned child and ran on for another 40 minutes, but bash was
# gone, so the log copy into logs/ and the artifact record never happened and the failure below was
# only found by reading $WORK/logs by hand.
#
# So the script re-execs a private copy under $WORK. rsync excludes it, and even without the
# exclusion an unlinked inode that bash already holds open cannot change.
#
# Two things about the re-exec that were checked rather than assumed. There is no `chmod` on the
# copy: it is started as `bash "$RUNNING"`, which reads the file and never consults the execute bit,
# so setting a mode there could only suggest the bit matters. And the guard does hold — a
# `VAR=value exec …` prefix carries the assignment into the exec'd child's environment even though
# `exec` is a special builtin (measured 2026-11-01 with a two-line probe); if it did not, the test
# below would never be true and this would re-exec forever.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
RUNNING="$WORK/.build-iso.running.sh"
if [ "${PHANTOMOS_RUNNING_COPY:-}" != "$RUNNING" ]; then
	mkdir -p "$WORK"
	cp "$SELF" "$RUNNING"
	PHANTOMOS_RUNNING_COPY="$RUNNING" exec bash "$RUNNING" "$REPO"
fi

# The exclusions below are the same paths .gitignore calls build scratch.
#
# artifacts/ is the fifth exclusion and it is here because of a measured loss: live-build writes
# the ISO at $WORK/live/live-image-amd64.hybrid.iso, which is *not* one of the scratch paths, so
# --delete treats it as a stray repo file. The build that started 2026-10-30T20:44:33Z produced a
# 910,163,968-byte ISO there (logs/M1-shipped-squashfs.txt §1) and the next run's rsync removed it
# before that run failed — leaving the milestone with an artifact whose size and SHA256 existed
# only in a hand-written log. An artifact now leaves live/ before the next run can reach it.
mkdir -p "$WORK" "$WORK/logs" "$WORK/artifacts"
find "$WORK/live" -maxdepth 1 -name '*.iso' -exec mv -f -t "$WORK/artifacts" {} + 2>/dev/null || true
rsync -a --delete \
	--exclude '.git/' --exclude 'logs/' --exclude 'docs/' --exclude 'artifacts/' \
	--exclude '.build-iso.running.sh' \
	--exclude 'live/chroot/' --exclude 'live/binary/' --exclude 'live/cache/' \
	--exclude 'live/tmp/' --exclude 'live/.build/' --exclude 'live/.lock' \
	"$REPO/" "$WORK/"

# Modes are normalised on the repo copy only, and the exclusion list is load-bearing: the
# same chmod over a resumed tree's live/chroot strips the executable bit from everything in
# it, including /usr/bin/env and apt's methods. Measured on 2026-10-30 — a resume run died
# with "chroot: failed to run command '/usr/bin/env': Permission denied" and the chroot had
# to be discarded (§9.1). rsync never writes into these paths, so there is nothing there
# that needs normalising.
find "$WORK" \( -name '*\.git' -o -name logs -o -name docs -o \
	-path "$WORK/live/chroot" -o -path "$WORK/live/binary" -o \
	-path "$WORK/live/cache" -o -path "$WORK/live/tmp" -o -path "$WORK/live/.build" \) \
	-prune -o -type d -exec chmod 0755 {} +
find "$WORK" \( -name '*\.git' -o -name logs -o -name docs -o \
	-path "$WORK/live/chroot" -o -path "$WORK/live/binary" -o \
	-path "$WORK/live/cache" -o -path "$WORK/live/tmp" -o -path "$WORK/live/.build" \) \
	-prune -o -type f -exec chmod 0644 {} +
chmod +x "$WORK"/scripts/*.sh "$WORK"/live/auto/config
# Hooks are optional (M1 ships none — see the header of scripts/build-packages.sh for why
# the pool needs no cleanup hook), and an unmatched glob would abort this script.
find "$WORK"/live/config/hooks -name '*.hook.*' -exec chmod +x {} + 2>/dev/null || true

( cd "$WORK/live" && lb config )
"$WORK/scripts/gen-package-lists.sh" "$WORK"
"$WORK/scripts/build-packages.sh" "$WORK"
# live-build's own package cache does not cover binary_rootfs's helper install, and that install
# is the last network access in a build. Two milestone-closing runs were lost to it; see the header
# of scripts/seed-binary-cache.sh and logs/M1-runL-binary-rootfs-dns.txt.
"$WORK/scripts/seed-binary-cache.sh" "$WORK"

START=$(date -u +%Y-%m-%dT%H%M%SZ)
BUILD_LOG="$WORK/logs/lb-build-$START.log"
DUMP="$WORK/logs/config-dump-$START.txt"
LOGNAME="${LOGNAME:-M1-lb-build-$START.log}"

echo "=== effective config of the tree about to be built ==="
"$WORK/scripts/config-audit.sh" dump "$WORK/live" > "$DUMP"
echo "  $(wc -l < "$DUMP") assignments -> $DUMP"

set +e
( cd "$WORK/live" && lb build ) > "$BUILD_LOG" 2>&1
RC=$?
set -e
END=$(date -u +%Y-%m-%dT%H%M%SZ)
echo "lb build log: $BUILD_LOG"
# Both repo-side copies carry $START, the same stamp the artifact directory and
# logs/M1-artifact-$START.txt already got. They did not, and it cost a citation: these two were
# fixed names, so run M's copy (2026-11-01 18:52 local) silently replaced the 2026-10-30T204433Z
# build's, and logs/M1-firmware-chroot-off-run.txt had been citing `logs/M1-lb-build.log` as *that*
# build's log — a citation that read fine and pointed at the wrong run. The host side never had the
# problem (`lb-build-$START.log` just above); only the copy into the repo did. The overwritten log
# was recovered from the host as logs/M1-lb-build-2026-10-30T204433Z.log (sha256 619cca2b…, 5055
# lines). PHANTOMOS_LOG still overrides, for a run that wants a human name.
cp "$BUILD_LOG" "$REPO/logs/$LOGNAME"
cp "$DUMP" "$REPO/logs/M1-config-dump-$START.txt"
echo "lb build exit: $RC ($START .. $END)"

ISO=$(ls "$WORK"/live/binary*.iso "$WORK"/live/live-image-*.iso 2>/dev/null | head -1 || true)
if [ -n "${ISO:-}" ]; then
	ARCH="$WORK/artifacts/$START"
	mkdir -p "$ARCH"
	mv -f "$ISO" "$ARCH/"
	SIZE=$(stat -c %s "$ARCH/$(basename "$ISO")")
	SHA=$(sha256sum "$ARCH/$(basename "$ISO")" | awk '{print $1}')
	# The build tree's own squashfs, hashed here because this is the last moment it is
	# guaranteed to exist. Run M's record could not carry this: its tree copy was deleted by the
	# cold-clean that run N started from, so when SPEC's "byte-identical, both 837 292 032 B,
	# sha256 5c285984…" turned out to have been printed only to a terminal, the ISO half could be
	# re-measured out of the archived artifact and the tree half could not be re-made at all
	# (logs/M1-runM-shipped-squashfs.txt, "what this file cannot show, and why"). One pass over a
	# file that is already on local disk, and no mount — the ISO's copy stays inside the ISO until
	# something opens it, and this script is the wrong place to take a loop device, because a mount
	# left behind here fails the next run's cold-clean precondition.
	#
	# Not exercised by the run that was building when this was added (run N, lb build started
	# 2026-11-01T17:21:02Z): it had already re-exec'd its private copy of this file, so run N's
	# record has no tree-squashfs lines and its comparison is made by hand instead. First run to
	# carry them is the next one. The registered driver was re-run after this change
	# (2026-11-01T18:27:46Z: 2 registered, 2 passed, 0 failed) with run N still building.
	TSQ="$WORK/live/binary/live/filesystem.squashfs"
	TSIZE="ABSENT"
	TSHA="ABSENT"
	if [ -f "$TSQ" ]; then
		TSIZE=$(stat -c %s "$TSQ")
		TSHA=$(sha256sum "$TSQ" | awk '{print $1}')
	fi
	{
		echo "run: $START .. $END (lb build exit $RC)"
		echo "path: $ARCH/$(basename "$ISO")"
		echo "size: $SIZE bytes"
		echo "sha256: $SHA"
		echo "build tree squashfs: $TSQ"
		echo "build tree squashfs size: $TSIZE"
		echo "build tree squashfs sha256: $TSHA"
	} > "$REPO/logs/M1-artifact-$START.txt"
	echo "artifact: $ARCH/$(basename "$ISO")"
	echo "  size: $SIZE bytes"
	echo "  sha256: $SHA"
	echo "  build tree squashfs: $TSIZE bytes, sha256 $TSHA"
	echo "  recorded in: logs/M1-artifact-$START.txt"
else
	echo "artifact: none found (build failed? see logs/$LOGNAME)"
fi
exit $RC
