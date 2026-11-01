#!/bin/bash
# s5-coverage.sh — the check §10's M1 exit criterion has a hole in.
#
# §10: "M1 — package sets. `phantomos-base` and `phantomos-desktop` metapackages defined,
# §5 inventory complete with a justification per entry. Exit: `dpkg -l` from the built image
# diffed against §5 comes back empty, in both directions."
#
# scripts/m1-diff.sh does the diff half, but its expected side is the *manifest*, and its
# header says so at line 37: "manifests/base.pkgs, manifests/desktop.pkgs — §5's inventory.
# This is what the exit criterion actually means." That is a bridge the diff asserts and never
# checks. A name in a manifest that §5 does not contain is invisible to both directions at
# once: direction 1 finds it installed, direction 2 finds it expected. This script is the
# other half — manifest against §5's actual text.
#
# It exists because `xorg` sat in manifests/desktop.pkgs with no §5 basis for an unknown
# length of time while the diff stayed green, and it turned out to be load-bearing: it is a
# hard Depends of phantomos-desktop and the only route to an X server in the image, every
# other route being a Recommends that --apt-recommends false turns off
# (logs/M1-xorg-ownership.txt). §5 names it as of the 2026-11-01 amendment.
#
# Matching is by token, not by substring and not by grep -w. grep -w treats '-' as a
# boundary, so `grep -wF xorg` matches "xserver-xorg" and would have passed for exactly the
# wrong reason after §5's amendment quoted that Recommends field. The delimiter class below
# is everything that is not [A-Za-z0-9_.+-].
#
# Known limits, stated rather than papered over:
#   * §5 mentions some names in order to *drop* them ("Dropped, 19 of them: `xfburn` ...").
#     A name that is only in that sentence counts as covered here. The cheap guard against
#     the worst version of that is the drops.pkgs cross-check below: a name in both a
#     selection manifest and the drop guard is a hard failure, because it is a contradiction
#     no reader should have to resolve.
#   * manifests/live.pkgs is exempt. Its own header: "§5's inventory is about the latter, so
#     nothing here is justified by §5, and the M1 diff treats this file as its own bucket."
#   * This does not check the reverse direction (a package §5 names that no manifest
#     carries). §5 is prose and names things in groups — "fonts (§5 tail)", "the kernel" —
#     so the reverse needs a human reading, which is what the amendments record.
#
# Usage: scripts/s5-coverage.sh [repo-root]
# Exit: 0 only if every base.pkgs and desktop.pkgs name is covered by §5, and no name is in
#       both a selection manifest and manifests/drops.pkgs.

set -uo pipefail
export LC_ALL=C

REPO="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SPEC="$REPO/docs/SPEC.md"

[ -f "$SPEC" ] || { echo "E: $SPEC not found" >&2; exit 2; }
for m in base.pkgs desktop.pkgs live.pkgs drops.pkgs; do
	[ -f "$REPO/manifests/$m" ] || { echo "E: manifests/$m not found" >&2; exit 2; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---- §5's extent, found not assumed ----
S=$(grep -n '^## 5\. ' "$SPEC" | head -1 | cut -d: -f1)
[ -n "$S" ] || { echo "E: no '## 5.' heading in $SPEC" >&2; exit 2; }
E=$(awk -v s="$S" 'NR > s && /^## /{print NR; exit}' "$SPEC")
[ -n "$E" ] || { echo "E: §5 is the last section? no '## ' heading after line $S" >&2; exit 2; }
sed -n "${S},$((E - 1))p" "$SPEC" > "$WORK/s5.txt"

# The same parser scripts/build-packages.sh:127 and scripts/m1-diff.sh:146 use, so this test
# reads the manifests the way the build does and cannot disagree with it about what a name is.
sel() { sed -e 's/#.*//' "$REPO/manifests/$1" | awk 'NF' | sed -e 's/[[:space:]]*$//'; }

# Token match inside §5. A package name can only contain [a-z0-9.+-], so '.' and '+' are the
# only ERE metacharacters that can appear in one and the only two that need escaping. (An
# earlier version escaped a longer class written as '[.+*?()\[\]{}|^$\\]', where the '\]'
# closes the bracket early in POSIX and leaves garbage after it — the short class is both
# correct and enough.)
#
# The §5-relative line the name was first found on. Printed for every name, including the
# ones that pass, because "a justification per entry" is a claim a human has to be able to
# check: §5 is prose, and a name can be covered by the inventory line, by an amendment that
# explains a substitution, or by a sentence that merely mentions it. The check cannot tell
# those apart, so it reports the line and lets the reader tell them apart. Line numbers are
# relative to §5's start; add $S-1 for the file.
s5_line() {
	local pat
	pat=$(printf '%s' "$1" | sed -e 's/[.+]/\\&/g')
	grep -nE "(^|[^A-Za-z0-9_.+-])${pat}([^A-Za-z0-9_.+-]|\$)" "$WORK/s5.txt" \
		| head -1 | cut -d: -f1
}

echo "=== §5 coverage of the selection manifests ==="
echo "spec:      $SPEC"
echo "§5 extent: lines $S-$((E - 1)) ($((E - S)) lines)"
echo

FAIL=0
for m in base.pkgs desktop.pkgs; do
	sel "$m" | sort -u > "$WORK/$m.names"
	total=$(wc -l < "$WORK/$m.names")
	hit=0; miss=""
	while IFS= read -r p; do
		[ -n "$p" ] || continue
		if ln=$(s5_line "$p") && [ -n "$ln" ]; then
			hit=$((hit + 1))
			printf '  %-24s §5+%s\n' "$p" "$ln"
		else
			miss="$miss $p"
			FAIL=$((FAIL + 1))
		fi
	done < "$WORK/$m.names"
	printf '%-16s %s names: %s covered by §5, %s not covered\n' \
		"$m" "$total" "$hit" "$(echo $miss | wc -w)"
	for p in $miss; do
		echo "    NOT IN §5: $p"
		echo "      either §5 gains a justification for it, or it comes out of manifests/$m."
		echo "      A name with no §5 basis is invisible to scripts/m1-diff.sh in both directions."
	done
	echo
done

# ---- live.pkgs, exempt, and the exemption has to keep being stated ----
sel live.pkgs | sort -u > "$WORK/live.pkgs.names"
echo "live.pkgs        $(wc -l < "$WORK/live.pkgs.names") names: exempt by design, not covered by §5"
echo "                 \"§5's inventory is about the latter, so nothing here is justified by §5,"
echo "                 and the M1 diff treats this file as its own bucket\" — its own header,"
echo "                 and scripts/m1-diff.sh:39-41 carries the same rule."
echo

# ---- the drop-guard cross-check ----
sel drops.pkgs | sort -u > "$WORK/drops.names"
echo "drops.pkgs       $(wc -l < "$WORK/drops.names") names in the drop guard"
for m in base.pkgs desktop.pkgs live.pkgs; do
	bad=$(comm -12 "$WORK/$m.names" "$WORK/drops.names")
	if [ -n "$bad" ]; then
		echo "$bad" | while IFS= read -r p; do
			echo "    CONTRADICTION: $p is in manifests/$m and in manifests/drops.pkgs"
		done
		FAIL=$((FAIL + $(echo "$bad" | wc -l)))
	fi
done
echo

if [ "$FAIL" -eq 0 ]; then
	echo "S5 COVERAGE: COMPLETE — every base.pkgs and desktop.pkgs name has a §5 justification, and no name is both selected and dropped"
else
	echo "S5 COVERAGE: INCOMPLETE — $FAIL name(s) to resolve" >&2
fi
exit $((FAIL > 0 ? 1 : 0))
