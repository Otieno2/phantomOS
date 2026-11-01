#!/bin/bash
# s5-coverage-test.sh — tests the §5 coverage check itself, against fixtures, so that a pass
# means the check can still fail.
#
# scripts/s5-coverage.sh reads docs/SPEC.md and manifests/*.pkgs out of a repo root given as
# $1, so every case below builds a throwaway root in a temp directory. The real tree is only
# ever read, never written, and case F runs the check against it for real.
#
# The cases, and why each one is here:
#   A  a consistent fixture                     -> exit 0
#   B  a manifest name §5 does not contain      -> exit 1, "NOT IN §5"
#   C  a name both selected and dropped         -> exit 1, "CONTRADICTION"
#   D  the grep -w trap                         -> exit 1
#      `grep -w xorg` matches "xserver-xorg", because '-' is not a word character. A SPEC
#      that only ever mentions xserver-xorg would then satisfy a manifest naming xorg, which
#      is the exact false pass this check exists to prevent. s5-coverage.sh uses a delimiter
#      class of everything outside [A-Za-z0-9_.+-] instead; this case is what pins that.
#   E  no '## 5.' heading at all                -> exit 2, not a silent pass
#   F  the real repository                      -> exit 0
#
# Usage: scripts/s5-coverage-test.sh [repo-root]
# Exit: 0 only if every case behaved as stated.

set -uo pipefail

REPO="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
CHECK="$REPO/scripts/s5-coverage.sh"
[ -f "$CHECK" ] || { echo "E: $CHECK not found" >&2; exit 2; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

CASES=0
FAILED=0

# fixture <name> <spec-body> <desktop-names...> ; drops/live/base are minimal and shared
make_fixture() {
	local d="$ROOT/$1"
	mkdir -p "$d/docs" "$d/manifests"
	cat > "$d/docs/SPEC.md"
	printf 'sudo\n' > "$d/manifests/base.pkgs"
	printf 'live-boot\n' > "$d/manifests/live.pkgs"
	printf 'indi-dsi\n' > "$d/manifests/drops.pkgs"
	shift
	printf '%s\n' "$@" > "$d/manifests/desktop.pkgs"
	printf '%s' "$d"
}

assert() { # <label> <want-exit> <want-substring-or-empty> <fixture-dir>
	local label="$1" want_rc="$2" want_str="$3" dir="$4" out rc
	CASES=$((CASES + 1))
	out=$(bash "$CHECK" "$dir" 2>&1)
	rc=$?
	if [ "$rc" != "$want_rc" ]; then
		printf 'FAIL  %-42s exit %s, wanted %s\n' "$label" "$rc" "$want_rc"
		echo "$out" | sed 's/^/        /'
		FAILED=$((FAILED + 1))
		return
	fi
	if [ -n "$want_str" ] && ! printf '%s' "$out" | grep -qF -- "$want_str"; then
		printf 'FAIL  %-42s exit %s, but no %s in output\n' "$label" "$rc" "'$want_str'"
		echo "$out" | sed 's/^/        /'
		FAILED=$((FAILED + 1))
		return
	fi
	printf 'ok    %-42s exit %s\n' "$label" "$rc"
}

# ---- A: consistent ----
d=$(make_fixture a <<'SPEC'
## 4. Something else

## 5. Package inventory

`phantomos-desktop`: sudo, xorg, lightdm.

## 6. Next section
SPEC
xorg lightdm)
assert "A consistent fixture" 0 "S5 COVERAGE: COMPLETE" "$d"

# ---- B: a name §5 does not contain ----
d=$(make_fixture b <<'SPEC'
## 5. Package inventory

`phantomos-desktop`: sudo, xorg, lightdm.

## 6. Next section
SPEC
xorg lightdm plank)
assert "B manifest name absent from §5" 1 "NOT IN §5: plank" "$d"

# ---- C: selected and dropped at once ----
d=$(make_fixture c <<'SPEC'
## 5. Package inventory

`phantomos-desktop`: sudo, indi-dsi.

## 6. Next section
SPEC
indi-dsi)
assert "C name both selected and dropped" 1 "CONTRADICTION: indi-dsi" "$d"

# ---- D: the grep -w trap ----
# §5 mentions only xserver-xorg. A substring match, or grep -w, would call xorg covered.
d=$(make_fixture d <<'SPEC'
## 5. Package inventory

`phantomos-desktop`: sudo, xserver-xorg, lightdm.

## 6. Next section
SPEC
xorg lightdm)
assert "D xserver-xorg must not satisfy xorg" 1 "NOT IN §5: xorg" "$d"

# ---- E: no §5 at all ----
d=$(make_fixture e <<'SPEC'
## 4. Something else

## 6. Next section
SPEC
xorg)
assert "E no '## 5.' heading" 2 "no '## 5.' heading" "$d"

# ---- F: the real repository ----
CASES=$((CASES + 1))
out=$(bash "$CHECK" "$REPO" 2>&1)
rc=$?
if [ "$rc" = 0 ]; then
	printf 'ok    %-42s exit 0\n' "F the real tree"
	printf '%s\n' "$out" | grep -E 'covered by §5|exempt|drop guard|S5 COVERAGE' | sed 's/^/        /'
else
	printf 'FAIL  %-42s exit %s\n' "F the real tree" "$rc"
	echo "$out" | sed 's/^/        /'
	FAILED=$((FAILED + 1))
fi

echo
echo "cases: $CASES   failed: $FAILED"
[ "$FAILED" -eq 0 ]
