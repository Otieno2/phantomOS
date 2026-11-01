#!/bin/bash
# m1-diff.sh — M1's exit criterion: the package set of the built image, diffed against
# the §5 inventory in both directions.
#
# What "in both directions" can and cannot mean, and why this script is written the way
# it is:
#
#   direction 1 — named by §5, not in the image. §10's exit criterion says `dpkg -l`, so
#                 this direction tests *presence*: every name in manifests/{base,desktop,live}.pkgs
#                 and every phantomos-* metapackage must be installed. It deliberately does not
#                 care whether a name arrived as a selection or as a dependency — most of the §5
#                 names arrive as dependencies of the two metapackages, so a marking-based test
#                 would have reported them as missing. The marking is still reported, because it is
#                 a property worth knowing (see "auto-marked" below).
#   direction 2 — in the image, not named by §5. Taken literally this can never be
#                 empty: installing the §5 selection pulls a dependency closure of 682
#                 packages, and §5 itself says the base fonts "arrive as Xfce/GTK/Firefox
#                 dependencies and are not a branding decision". So the subject of this
#                 direction is the set of *manual selections*, which is what an inventory
#                 is a list of. The dependency closure is reported as a count, not a diff.
#
# A manual selection is a name with no `Auto-Installed: 1` record: either apt was told to
# install it by name, or it never went through apt at all (debootstrap installs with dpkg).
# That second kind is the reason the bootstrap bucket exists — see below.
#
# "auto-marked" is reported, not failed. A §5 name in that list reached the image through a
# dependency edge rather than by being named on a command line: for the names carried by
# phantomos-base/phantomos-desktop that is the expected shape, because scripts/build-packages.sh
# generates the metapackages' `Depends:` from these manifests. It is still worth reading after
# every manifest change, because the mark is the only place this run records *how* a package
# arrived, and a §5 name that arrives through some third party's Depends: — not ours — is a name
# we do not control. Whether any of them can be removed by `apt autoremove` on an installed
# system is a claim about apt's algorithm and needs its own run; this script does not test it.
#
# The buckets a manual selection must fall into, and why each is there:
#
#   manifests/base.pkgs, manifests/desktop.pkgs  — §5's inventory. This is what the exit
#         criterion actually means.
#   manifests/live.pkgs                          — the live medium. §5 says nothing about
#         live-boot, but an ISO that cannot boot is not an image, so these are a choice made
#         in §4 rather than drift.
#   the four phantomos-* metapackages            — our own packages (§4.2).
#   the bootstrap set                            — Debian's base system, read out of
#         live-build's own cache/packages.bootstrap/*.deb. debootstrap installs those with
#         dpkg, not apt, so nothing marks them Auto-Install and every one of them reappears
#         in the image as a "manual" selection. §5 does not enumerate bash, coreutils or dpkg
#         and should not have to — but the alternative to naming them here is a direction-2
#         list of ~140 packages reported as drift on every build ever. It is also the bucket
#         worth watching: a point release that changes the base set shows up as a real
#         difference, which is the §11 reason for having this check at all.
#
# Anything outside those is drift and fails the check. What it found on the first run, and what
# was therefore changed: seven names in the image that no manifest named — six (alsa-topology-conf,
# firmware-ath9k-htc, firmware-carl9170, firmware-linux-free, indi-dsi, wireless-regdb) put there by
# live-build's chroot_firmware stage, which installs every package shipping a lib/firmware path as
# read out of the archive's Contents files, and linux-image-amd64 put there by chroot_linux-image.
# docs/SPEC.md §5's 2026-10-31 amendment is the decision: that enumeration is off now
# (--firmware-chroot false), the five names worth keeping are in manifests/base.pkgs, indi-dsi is in
# the drop guard, and the kernel is named. Evidence: logs/M1-firmware-contents-repro.txt,
# logs/M1-firmware-contents-lines.txt, logs/M1-firmware-nonfree-scale.txt, and the "before" run at
# logs/M1-diff-preconfig.txt. A direction-2 entry should always be read as "who named this, and does
# §5 know" — that is the whole check.
#
# Third check, not part of the exit criterion but part of the same run: the guard list in
# manifests/drops.pkgs. A dropped package reaching the image through a dependency is worth
# knowing about even when the selection diff is clean.
#
# Fourth check, §8 rather than §5: the build pool must not have reached the image.
#
# WHY THE SUBJECT IS THE SQUASHFS AND NOT THE BUILD TREE. The first version of this script
# read the host `chroot` directory and live-build's `chroot.packages.live`, and on the first
# successful build it reported a leak that did not exist: `chroot/etc/apt/sources.list.d/
# phantomos.list` and `chroot/opt/phantomos-build/pool` were both present, and both were
# absent from the shipped root filesystem. The build log says why (logs/M1-shipped-squashfs.txt
# §1, §3):
#
#   [00:48:40] lb binary_chroot     — renames the finished chroot to chroot/chroot and puts a
#                                     copy of cache/bootstrap at chroot (binary_chroot:59-74)
#   [00:49:10] lb chroot_archives chroot install — binds the pool, into the BOOTSTRAP copy
#   [00:51:27] lb binary_rootfs     — Chroot chroot "mksquashfs chroot filesystem.squashfs"
#                                     (binary_rootfs:337; Chroot() = functions/chroot.sh:33)
#                                     walks chroot/chroot: the snapshot, which has no /opt
#   [01:02:42] lb chroot_archives binary remove
#   [01:10:51] lb chroot_archives binary install — binds the pool again, for the bootloader
#   [01:18:13] P: Build completed successfully
#
# So the paths in `chroot/` are build-tree state from a stage that runs after the image was
# made; they are not in the image, and asserting on them was asserting on the wrong object.
# This script therefore reads `var/lib/dpkg/status` and `var/lib/apt/extended_states` out of
# `binary/live/filesystem.squashfs` — the filesystem that boots — and reads the §8 paths out
# of the same archive. The host chroot is still reported, but as "build tree, not the image"
# and it cannot fail the run. The ISO's copy of that squashfs is byte-identical to the one
# live-build left in binary/live (sha256 f2f7d1ee9e18569eaed4fec586ace41dea4aefaf681509a6654502b77cc61dc8
# both sides, logs/M1-shipped-squashfs.txt §4), so the archive is the shipped object.
#
# Three file-format details that the first run got wrong, each measured in
# logs/M1-diff-defects.txt and logs/M1-shipped-dpkg.txt:
#
#   apt marks auto-installs with `Auto-Installed: 1`. `Auto-Install: yes` is not in the file
#     (grep for it: 0 lines out of 2732), and reading it wrong makes every one of the 838
#     installed packages look like a manual selection.
#   `dpkg-deb -f a.deb b.deb ... Package` over more than one archive prints ONE line,
#     `Package: adduser`, and exits 0. One file at a time prints the bare value and yields
#     all 144 names, so the bootstrap bucket is read in a loop.
#   names in a dpkg database may carry an `:arch` qualifier (535 of 838 in
#     chroot.packages.live) while the same database read with `dpkg-query -f '${Package}'`
#     outside a chroot prints 0 of 838. A Debian package name cannot contain a colon (Policy
#     §5.6-1), so stripping at the first colon is lossless — and it is checked, not assumed:
#     the script compares the unique raw names against the unique stripped names and fails on
#     a collision, which is what a genuine multi-arch install of one name would produce.
#
# Input: the live-build tree of a finished build (default /root/phantomos-m1/live).

set -euo pipefail

# Collation is pinned because every direction of this diff is a `sort` followed by a `comm`,
# and `comm` only behaves if both sides are ordered the way it expects. Measured 2026-10-31:
# the lists this script writes are NOT in byte order (`sort -c` stops at line 97,
# `g++-x86-64-linux-gnu`, in both the 838-line and the 834-line image list), so the ordering
# in force is the caller's LC_COLLATION. Re-checking the amendment's delta under LC_ALL=C gave
# the same answer — but only because sort and comm happened to share an environment here, which
# is a fact about the shell this script is invoked from and not about the gate. The exit
# criterion in §10 is "comes back empty, in both directions", so the ordering must not be a
# variable: byte order, always, whatever the caller exports.
export LC_ALL=C

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TREE="${1:-/root/phantomos-m1/live}"
SQ="$TREE/binary/live/filesystem.squashfs"
CHROOT="$TREE/chroot"
# Overridable because the seven data files below have fixed names, and a fixed name in logs/ means
# each run quietly replaces the last one's evidence. That already happened: run K's set survives only
# because it was hand-moved to logs/runK/ afterwards, and its stdout report was never captured at
# all — logs/M1-runK-rootfs-iso-failure.txt §1 records the verdict being re-made from those seven
# files with `comm` because there was nothing else to read it off. Point PHANTOMOS_OUT at a
# per-run directory and both the data files and (by redirecting stdout into the same place) the
# report are archived by the run itself instead of by whoever remembers to copy them.
OUT="${PHANTOMOS_OUT:-$REPO/logs}"

[ -f "$SQ" ] || { echo "E: $SQ missing — has the build run?" >&2; exit 2; }
[ -f "$TREE/chroot.packages.live" ] || { echo "E: $TREE/chroot.packages.live missing — has the build run?" >&2; exit 2; }
BOOTCACHE="$TREE/cache/packages.bootstrap"
[ -d "$BOOTCACHE" ] || { echo "E: $BOOTCACHE missing — this is the bootstrap bucket; without it direction 2 reports Debian's base system as drift" >&2; exit 2; }

mkdir -p "$OUT"
sel() { sed -e 's/#.*//' "$REPO/manifests/$1" | awk 'NF' | sed -e 's/[[:space:]]*$//'; }
strip_arch() { sed 's/:.*$//'; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The two records the diff is built from, pulled out of the archive rather than off the host.
unsquashfs -q -dest "$WORK/root" "$SQ" \
	var/lib/dpkg/status var/lib/apt/extended_states \
	etc/apt/sources.list etc/apt/sources.list.d etc/apt/trusted.gpg.d usr/share/keyrings \
	>"$WORK/unsquashfs.out" 2>&1 || echo "W: unsquashfs exited non-zero; see its output below" >&2
R="$WORK/root"
[ -f "$R/var/lib/dpkg/status" ] || { cat "$WORK/unsquashfs.out" >&2; echo "E: no dpkg status inside $SQ" >&2; exit 2; }
[ -f "$R/var/lib/apt/extended_states" ] || { echo "E: no extended_states inside $SQ — apt's auto-install marks are the only thing that separates a selection from the closure it pulls" >&2; exit 2; }
# Full path listing: the §8 checks are about paths, and a path that is absent has to be
# absent in a listing that is otherwise known to be complete.
unsquashfs -ls "$SQ" > "$WORK/paths.txt" 2>/dev/null
printf 'squashfs path entries listed: %s\n' "$(wc -l < "$WORK/paths.txt")" > "$OUT/M1-squashfs-entries.txt"

# Installed = the stanzas dpkg itself calls installed. dehashqualified in `raw`, stripped of
# :arch in `names`; the two counts are compared below.
awk '/^Package: /{p=$2} /^Status: install ok installed$/{print p}' "$R/var/lib/dpkg/status" > "$WORK/installed.raw"
sort -u "$WORK/installed.raw" > "$OUT/M1-image-installed-raw.txt"
strip_arch < "$WORK/installed.raw" | sort -u > "$OUT/M1-image-installed.txt"
# A collision is a name that exists as two arch-qualified stanzas: stripping would merge them
# and hide a real difference. Measured 0 on this build (838 raw unique, 838 stripped).
if [ "$(wc -l < "$OUT/M1-image-installed-raw.txt")" != "$(wc -l < "$OUT/M1-image-installed.txt")" ]; then
	echo "E: stripping :arch merged two stanzas into one name — the diff would be reading a set that is not the image's" >&2
	strip_arch < "$WORK/installed.raw" | sort | uniq -d >&2
	exit 2
fi

awk '/^Package: /{p=$2} /^Auto-Installed: /{if ($2 == "1") print p}' \
	"$R/var/lib/apt/extended_states" | strip_arch | sort -u > "$OUT/M1-image-auto.txt"
comm -23 "$OUT/M1-image-installed.txt" "$OUT/M1-image-auto.txt" > "$OUT/M1-image-selections.txt"
# A filter that reads nothing produces an empty set, and an empty set makes both diff
# directions empty. That is the shape of a green check that proved nothing, and this script
# produced one by calling a stdin filter with a filename argument (logs/M1-diff.txt 2026-10-31
# run: installed 0, selections 0, and the §5 diff "came back empty" until a count check was
# added). So the counts have to be plausible before the diffs are read.
[ -s "$OUT/M1-image-installed.txt" ] || { echo "E: the image's installed set is empty — the extraction or the awk read nothing" >&2; exit 2; }
[ "$(wc -l < "$OUT/M1-image-installed.txt")" -gt 300 ] || { echo "E: only $(wc -l < "$OUT/M1-image-installed.txt") packages in the image set; a §5 desktop is not that small" >&2; exit 2; }

# Bootstrap bucket, one archive per dpkg-deb call for the reason above.
: > "$WORK/bootstrap.raw"
for f in "$BOOTCACHE"/*.deb; do
	dpkg-deb -f "$f" Package >> "$WORK/bootstrap.raw"
done
strip_arch < "$WORK/bootstrap.raw" | sort -u > "$WORK/bootstrap.txt"

{ sel base.pkgs; sel desktop.pkgs; sel live.pkgs; \
  echo phantomos-base; echo phantomos-config; echo phantomos-desktop; echo phantomos-release; \
  cat "$WORK/bootstrap.txt"; } | sort -u > "$OUT/M1-expected-selections.txt"
{ sel base.pkgs; sel desktop.pkgs; sel live.pkgs; \
  echo phantomos-base; echo phantomos-config; echo phantomos-desktop; echo phantomos-release; \
  } | sort -u > "$OUT/M1-expected-named.txt"
cp "$OUT/M1-expected-named.txt" "$WORK/named.txt"
# The same vacuous-green rule as above, on the other side of the comparison: a manifest that
# parses to nothing makes direction 1 empty because there is nothing to look for.
[ "$(wc -l < "$OUT/M1-expected-named.txt")" -gt 30 ] || { echo "E: only $(wc -l < "$OUT/M1-expected-named.txt") names read out of the manifests — §5's inventory is not that small" >&2; exit 2; }

# live-build's own record, for the cross-check that the archive really is the chroot it
# finished with.
cut -f1 "$TREE/chroot.packages.live" | strip_arch | sort -u > "$WORK/chroot-packages-live.txt"

MISSING=$(comm -23 "$OUT/M1-expected-named.txt" "$OUT/M1-image-installed.txt")
NAMED_AUTO=$(comm -12 "$OUT/M1-expected-named.txt" "$OUT/M1-image-auto.txt")
EXTRA=$(comm -13 "$OUT/M1-expected-selections.txt" "$OUT/M1-image-selections.txt")
CLOSURE_LIVE=$(comm -3 "$OUT/M1-image-installed.txt" "$WORK/chroot-packages-live.txt")
DROPPED=$(grep -Fxf <(sel drops.pkgs) "$OUT/M1-image-installed.txt" || true)

# The pool path comes out of the committed archives file rather than being repeated here, so
# this guard cannot silently keep checking an old location — the pool moved out of /var/tmp
# for the reason in §9.1 (live-build's 8070-remove-temporary-files hook rm -rf's /var/tmp
# inside the chroot, i.e. through the bind).
POOL=$(sed -n '1p' "$REPO/live/config/archives/phantomos.list.chroot" \
	| sed -E -e 's|.*file://(localhost)?||' -e 's| +[^ ]+$||' -e 's|/$||')
[ -n "$POOL" ] && [ "${POOL#/}" != "$POOL" ] || { echo "E: could not read the pool path from the archives file (got '$POOL')" >&2; exit 2; }

LEAK=()
for p in "etc/apt/sources.list.d" "etc/apt/trusted.gpg.d"; do
	[ -d "$R/$p" ] && for f in "$R/$p"/*; do
		[ -e "$f" ] || continue
		case "$(basename "$f")" in
			phantomos*) LEAK+=("$p/$(basename "$f")") ;;
		esac
	done
done
[ -e "$R${POOL}" ] && LEAK+=("${POOL} (inside the image)")
grep -q "squashfs-root${POOL}" "$WORK/paths.txt" && LEAK+=("${POOL} (listed in the squashfs)")
grep -q 'squashfs-root/var/cache/apt/archives/phantomos_.*\.deb' "$WORK/paths.txt" && LEAK+=("phantomos_*.deb in the image's apt cache")

# Build-tree state, reported and never fatal — the reason is the stage order above.
TREE_LEFT=()
[ -e "$CHROOT${POOL}" ] && TREE_LEFT+=("chroot${POOL}")
[ -e "$CHROOT/etc/apt/sources.list.d/phantomos.list" ] && TREE_LEFT+=("chroot/etc/apt/sources.list.d/phantomos.list")
mapfile -t MOUNTED < <(awk -v d="$CHROOT" 'index($2, d) == 1 && $2 ~ /phantomos/ { print $2 }' /proc/mounts)
for m in ${MOUNTED[@]+"${MOUNTED[@]}"}; do TREE_LEFT+=("still mounted: $m"); done

echo "=== the image's own records (from binary/live/filesystem.squashfs) ==="
echo "installed:                 $(wc -l < "$OUT/M1-image-installed.txt") packages"
echo "  manual selections:       $(wc -l < "$OUT/M1-image-selections.txt")"
echo "  dependency closure:      $(wc -l < "$OUT/M1-image-auto.txt") (apt Auto-Installed: 1)"
echo "expected selections:       $(wc -l < "$OUT/M1-expected-selections.txt")"
echo "  of which bootstrap:      $(wc -l < "$WORK/bootstrap.txt") (cache/packages.bootstrap)"
echo "  of which §5/live/ours:   $(wc -l < "$WORK/named.txt") ($(comm -12 "$WORK/named.txt" "$WORK/bootstrap.txt" | wc -l) of these are in both buckets)"
echo
echo "cross-check against live-build's chroot.packages.live: $(if [ -z "$CLOSURE_LIVE" ]; then echo "identical"; else echo "DIFFERENT"; fi)"
[ -z "$CLOSURE_LIVE" ] || echo "$CLOSURE_LIVE" | sed 's/^/  /'
echo
echo "=== direction 1: named by §5, not installed in the image (basis: dpkg's installed set) ==="
[ -z "$MISSING" ] && echo "(empty)" || echo "$MISSING" | sed 's/^/  MISSING /'
echo
echo "  how the $(wc -l < "$OUT/M1-expected-named.txt") names got there:"
echo "    named on an apt command line (manual selection): $(comm -12 "$OUT/M1-expected-named.txt" "$OUT/M1-image-selections.txt" | wc -l)"
echo "    arrived through a dependency edge (auto-marked): $(echo "$NAMED_AUTO" | grep -c . || true)"
[ -z "$NAMED_AUTO" ] || echo "$NAMED_AUTO" | sed 's/^/      auto  /'
echo
echo "=== direction 2: selected in the image, not named by §5 ==="
[ -z "$EXTRA" ] && echo "(empty)" || echo "$EXTRA" | sed 's/^/  EXTRA /'
echo
echo "=== guard: §5 drops present anyway ==="
[ -z "$DROPPED" ] && echo "(none)" || echo "$DROPPED" | sed 's/^/  PRESENT /'
echo
echo "=== §8 guard: the build pool inside the image ==="
if [ ${#LEAK[@]} -eq 0 ]; then
	echo "(none)"
else
	for p in "${LEAK[@]}"; do printf '  LEAKED %s\n' "$p"; done
fi
echo
echo "channels the image ships with (/etc/apt/sources.list and sources.list.d inside it):"
{ cat "$R/etc/apt/sources.list" 2>/dev/null || true
  find "$R/etc/apt/sources.list.d" -type f -exec cat {} + 2>/dev/null || true; } \
	| grep -E '^(deb|deb-src)' | sed 's/^/  /'
if [ ${#TREE_LEFT[@]} -gt 0 ]; then
	echo
	echo "build tree, not the image (left by the archives re-bind after the snapshot — see header):"
	for p in "${TREE_LEFT[@]}"; do printf '  %s\n' "$p"; done
fi

if [ -n "$MISSING" ] || [ -n "$EXTRA" ] || [ -n "$DROPPED" ]; then
	echo
	echo "M1 EXIT CRITERION: NOT MET (§5 diff not empty)"
	[ ${#LEAK[@]} -eq 0 ] || echo "§8: build pool inside the image too"
	exit 1
fi
if [ ${#LEAK[@]} -gt 0 ]; then
	echo
	echo "M1 EXIT CRITERION: met, but §8 is violated — the build pool reached the image"
	exit 1
fi
echo
echo "M1 EXIT CRITERION: MET (both directions empty, drop guard clean, no pool inside the image)"
