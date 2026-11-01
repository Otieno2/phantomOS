#!/bin/bash
# build-iso-artifact-test.sh — does scripts/build-iso.sh keep the artifact it produces?
#
# Registered by scripts/run-tests.sh (§11: a defined-but-unregistered test counts as not done).
#
# What it covers, and why each case is a measured failure rather than a hypothetical:
#
#   a stray ISO left in $WORK/live by a run that died after xorriso   run K's rsync --delete removed
#     the 910,163,968-byte ISO the 2026-10-30T20:44:33Z build had produced, because live/*.iso is
#     not one of the scratch paths the rsync excludes. Its size and SHA256 survived only in a
#     hand-written log (logs/M1-shipped-squashfs.txt §1).
#   a second invocation                                              must not reach the first run's
#     archive at all.
#   a failing lb build                                               must not print an artifact as
#     though the run had succeeded, and must exit non-zero.
#
# It runs the real build-iso.sh against copies — a throwaway tree under /tmp and a throwaway work
# directory — with `lb` stubbed on PATH and the two helper scripts stubbed inside the copied tree.
# The helpers are stubbed because the real ones rebuild the pool at /opt/phantomos-build/pool, which
# a build running at the same time is bind-mounted to. Nothing here touches that pool, and the work
# directory may only ever be under /tmp, so this cannot be pointed at a live build tree by accident.
# The idle guard does still see a live build, because it reads the whole process table; `run()` below
# overrides it deliberately and says why.
#
# Assertions are taken immediately after the run they describe: run 3 resets artifacts/ on purpose
# (it needs a clean slate to prove a failed run invents nothing), which destroys run 1's and run 2's
# archives, so anything about those two has to have been measured already.
#
# Usage: scripts/build-iso-artifact-test.sh [repo-root]
# Exit: 0 if every assertion holds.

set -u

REPO="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
TR=/tmp/repo-arttest
TW=/tmp/arttest
STUB=/tmp/artstub

case "$TW" in
	/tmp/*) ;;
	*) echo "E: work directory $TW is not under /tmp; refusing to run against a build tree" >&2; exit 2 ;;
esac

rm -rf "$TR" "$TW" "$STUB"; mkdir -p "$TR" "$TW" "$STUB" "$TR/logs" "$TW/live"
for need in live manifests scripts; do
	[ -d "$REPO/$need" ] || { echo "E: $REPO/$need missing — wrong repo root?" >&2; exit 2; }
	cp -a "$REPO/$need" "$TR/"
done

# build-iso.sh calls these by absolute path inside the work tree (lines 110, 111, 115), so PATH
# cannot intercept them. seed-binary-cache.sh joined the list when it was added to the pipeline
# after this test was written: left unstubbed it ran for real and did a 3862 kB `apt-get download`
# per invocation, which made a test about artifact bookkeeping take two minutes per run and depend
# on the network being up — the exact dependency run L died of.
for h in gen-package-lists.sh build-packages.sh seed-binary-cache.sh; do
	printf '#!/bin/bash\nexit 0\n' > "$TR/scripts/$h"; chmod +x "$TR/scripts/$h"
done
printf '#!/bin/bash\nfor i in 1 2 3 4 5; do echo "LB_TEST_$i=1"; done\n' > "$TR/scripts/config-audit.sh"
chmod +x "$TR/scripts/config-audit.sh"

# `lb config` is a no-op; `lb build` fabricates a 4096-byte ISO in the current directory, which is
# $WORK/live because that is where build-iso.sh cd's to. ARTTEST_FAIL makes it exit 1 afterwards.
cat > "$STUB/lb" <<'EOS'
#!/bin/bash
if [ "$1" = "build" ]; then
	head -c 4096 /dev/zero | tr '\0' 'A' > live-image-amd64.hybrid.iso
	[ -n "${ARTTEST_FAIL:-}" ] && exit 1
fi
exit 0
EOS
chmod +x "$STUB/lb"

pass=0 fail=0
chk() { # chk <label> <shell condition>
	if eval "$2"; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
	else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi
}
RUNOUT=/tmp/arttest-runout.txt
run() { # run <NAME=value ...> — full output in $RUNOUT, exit code in $RC
	# Call this OUTSIDE any pipeline and outside $( ). Both put a function in a subshell, so the
	# RC it sets dies with the subshell and the parent sees it unset — which under `set -u` is
	# "RC: unbound variable" at the first reference. This test had that bug at all three call
	# sites and was never caught because it had never been run; scripts/run-tests.sh caught it on
	# its first execution.
	#
	# PHANTOMOS_ALLOW_CONCURRENT_BUILD=1 is set because build-iso.sh's idle guard is global, not
	# per-$WORK: scripts/build-status.sh scans the whole process table (build-status.sh:85), so a
	# real build anywhere on the host makes this test's /tmp work directory read BUSY and every
	# run here exits 1 before doing anything. Measured 2026-11-01T17:47Z with run N live in
	# /root/phantomos-m1: 6 passed, 10 failed, and the captured output was the guard's own
	# "E: refusing to start — /tmp/arttest is not idle" naming run N's pid. Overriding is what the
	# guard's message asks a caller to do *deliberately*, and here the reason is not a guess: `lb`
	# is a stub that writes 4096 bytes, both helpers that touch /opt/phantomos-build/pool are
	# stubs, and $WORK is under /tmp — so this is provably not a build and cannot reach the tree,
	# the pool or the signing key the live run is using. The same run is also the first positive
	# evidence that the guard fires against a real concurrent build at all.
	PATH="$STUB:$PATH" env PHANTOMOS_WORK="$TW" PHANTOMOS_ALLOW_CONCURRENT_BUILD=1 \
		"$@" bash "$TR/scripts/build-iso.sh" "$TR" > "$RUNOUT" 2>&1
	RC=$?
}
show() { grep -E "$1" "$RUNOUT" | sed 's/^/  /'; }   # runs grep, so it clobbers $? — capture RC first
records() { ls "$TR"/logs/M1-artifact-*.txt 2>/dev/null | wc -l; }

echo "=== seed: a stray ISO from a run that died, plus a previous archive and a previous log ==="
printf 'STRAY-ISO-CONTENT-FROM-A-RUN-WHICH-DIED-AFTER-XORRISO\n' > "$TW/live/live-image-amd64.hybrid.iso"
mkdir -p "$TW/artifacts/2026-01-01T000000Z" "$TW/logs"
printf 'ARCHIVE-PREVIOUS-RUN\n' > "$TW/artifacts/2026-01-01T000000Z/live-image-amd64.hybrid.iso"
printf 'LOG-PREVIOUS-RUN\n' > "$TW/logs/lb-build-2026-01-01T000000Z.log"
PREV=$(sha256sum "$TW/artifacts/2026-01-01T000000Z/live-image-amd64.hybrid.iso" | cut -d' ' -f1)
echo "  previous archive sha256 = $PREV"
echo

echo "=== run 1 ==="
N0=$(records)
run PHANTOMOS_LOG=artifact-test.log
RC1=$RC
show '^artifact|^  (size|sha256|recorded)|lb build exit'
echo "  exit=$RC1"
REC1=$(ls -t "$TR"/logs/M1-artifact-*.txt 2>/dev/null | head -1)
chk "run 1 exits 0" '[ "$RC1" = 0 ]'
chk "the stray ISO was moved out of live/, not deleted with it" \
	"grep -rq 'STRAY-ISO-CONTENT-FROM-A-RUN-WHICH-DIED' \"$TW/artifacts\""
chk "the previous run's archive survived the rsync --delete" \
	'[ "$(sha256sum "$TW/artifacts/2026-01-01T000000Z/live-image-amd64.hybrid.iso" 2>/dev/null | cut -d" " -f1)" = "$PREV" ]'
chk "the previous run's log in \$WORK/logs survived" '[ -f "$TW/logs/lb-build-2026-01-01T000000Z.log" ]'
chk "run 1 archived its ISO under artifacts/<START>/" \
	'[ -n "$REC1" ] && [ -f "$(grep "^path: " "$REC1" | cut -d" " -f2)" ]'
chk "live/ is left with no ISO for the next run to trip over" \
	'[ -z "$(ls "$TW"/live/*.iso 2>/dev/null)" ]'
chk "one artifact record was written into logs/" '[ "$(records)" -eq "$((N0 + 1))" ]'
chk "the record's size line matches the archived file" \
	'grep -q "^size: $(stat -c %s "$(grep "^path: " "$REC1" | cut -d" " -f2)") bytes" "$REC1"'
chk "the record's sha256 matches the archived file" \
	'[ "$(grep "^sha256: " "$REC1" | cut -d" " -f2)" = "$(sha256sum "$(grep "^path: " "$REC1" | cut -d" " -f2)" | cut -d" " -f1)" ]'
echo

echo "=== run 2 — the second invocation must not reach run 1's archive ==="
N1=$(records)
FIRST1=$(grep '^path: ' "$REC1" | cut -d' ' -f2)
FIRSTSHA=$(sha256sum "$FIRST1" | cut -d' ' -f1)
run PHANTOMOS_LOG=artifact-test.log
RC2=$RC
show '^artifact|lb build exit'
echo "  exit=$RC2"
chk "run 2 exits 0" '[ "$RC2" = 0 ]'
chk "run 1's archived ISO is byte-identical after run 2" \
	'[ "$(sha256sum "$FIRST1" | cut -d" " -f1)" = "$FIRSTSHA" ]'
chk "run 2 wrote its own record, so two runs are two artifacts" '[ "$(records)" -eq "$((N1 + 1))" ]'
chk "two archives exist side by side" \
	'[ "$(ls -d "$TW"/artifacts/2026-1*T*Z 2>/dev/null | wc -l)" -ge 2 ]'
echo

echo "=== run 3 — lb build fails; a failed run must not look like a success ==="
rm -rf "$TW/artifacts"; mkdir -p "$TW/artifacts"
N2=$(records)
ARTTEST_FAIL=1 run PHANTOMOS_LOG=artifact-test-fail.log
RC3=$RC
show '^artifact|lb build exit'
echo "  exit=$RC3"
REC3=$(ls -t "$TR"/logs/M1-artifact-*.txt 2>/dev/null | head -1)
chk "run 3 exits non-zero, i.e. the failure is not swallowed" '[ "$RC3" != 0 ]'
if [ "$(records)" -gt "$N2" ]; then
	chk "the record run 3 wrote says the build failed" 'grep -q "exit 1" "$REC3"'
else
	chk "run 3 wrote no artifact record" '[ "$(records)" -eq "$N2" ]'
fi
chk "no record anywhere claims exit 0 for the failed run" \
	'! grep -l "exit 0" "$TR"/logs/M1-artifact-*.txt 2>/dev/null | xargs -r grep -q "$(date -u +%Y-%m-%dT%H%M)Z"'
echo
echo "=== every file the three runs left in artifacts/ ==="
find "$TW/artifacts" -type f -printf '%10s %p\n' 2>/dev/null | sort
printf 'RESULT: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
