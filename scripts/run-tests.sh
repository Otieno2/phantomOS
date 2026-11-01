#!/bin/bash
# run-tests.sh — the driver §11 requires: "Feature tests must be registered in their own
# driver; a defined-but-unregistered test counts as not done."
#
# Both of the first two tests below were written and then left unregistered, which by that rule
# meant they were not done: build-iso-artifact-test.sh even named this file in its own header
# before it existed. Registering is the point of the file, so the registry is the `run_one` lines
# at the bottom and adding a test is one line — including its arguments, which are not the same
# for every test (pool-signature-test.sh takes a pool directory, build-iso-artifact-test.sh and
# build-status-test.sh take a repo root and default to neither).
#
# Deliberately NOT registered here:
#   scripts/m1-diff.sh       §10's M1 exit criterion, not a test of our code. It needs a built
#                            image, so it is run against one by hand and its output is committed
#                            to logs/ like any other run.
#   scripts/config-audit.sh  an audit tool with no pass/fail; build-iso.sh calls it directly.
#   seed-binary-cache.sh, gen-package-lists.sh, build-packages.sh, init-signing-key.sh
#                            build steps, not tests.
#
# Usage: scripts/run-tests.sh [repo-root]
#   PHANTOMOS_TEST_LOGS=…   directory for per-test output (default <repo>/logs/tests)
# Exit: 0 only if every registered test passed.
#
# Safe to run while a build is in progress — a claim that was written first and falsified once
# before it was true. pool-signature-test.sh only ever reads the real pool and copies it before
# mutating anything, so it was always safe. build-iso-artifact-test.sh runs the *real* build-iso.sh,
# whose idle guard reads the whole process table rather than just its own $WORK
# (scripts/build-status.sh:85), so a live build anywhere on the host made its /tmp work directory
# read BUSY: at 2026-11-01T17:47Z, with run N in bootstrap_debootstrap, the driver came back
# 1 passed / 1 failed and the test 6 passed / 10 failed, all three runs exiting on
# "E: refusing to start — /tmp/arttest is not idle". The test now sets
# PHANTOMOS_ALLOW_CONCURRENT_BUILD=1 at its own call site and justifies it there (stub `lb`, both
# pool-touching helpers stubbed, work directory refused unless under /tmp). Re-run at 17:51:55Z with
# the same build still live: 2 registered, 2 passed, 16 assertions, 0 failed — and that earlier
# failure is the first positive evidence the guard fires against a real concurrent build at all.
# build-status-test.sh tests the guard itself: every process-table verdict runs against a stubbed
# `ps` replaying /tmp fixtures, so a live build cannot make it flaky and it cannot reach the live
# tree; the one real-tree check is build-status.sh's own read-only probe, asserted for
# self-consistency (quiet exit == verbose verdict) rather than for a fixed busy/idle answer, so it
# passes with run N live AND after the milestone closes.

set -uo pipefail

REPO="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
LOGS="${PHANTOMOS_TEST_LOGS:-$REPO/logs/tests}"

mkdir -p "$LOGS"
STAMP=$(date -u +%Y-%m-%dT%H%M%SZ)

PASSED=""
FAILED=""
MISSING=""
REGISTERED=0

run_one ()
{
	local T="$1"
	shift
	REGISTERED=$((REGISTERED + 1))
	local NAME="${T%.sh}"
	local PATHNAME="$REPO/scripts/$T"
	local LOG="$LOGS/$NAME-$STAMP.log"

	printf '%-28s ' "$NAME"
	if [ ! -f "$PATHNAME" ]; then
		echo "MISSING (registered but not on disk)"
		MISSING="$MISSING $NAME"
		return
	fi

	local START END RC
	START=$(date -u +%s)
	bash "$PATHNAME" "$@" > "$LOG" 2>&1
	RC=$?
	END=$(date -u +%s)

	if [ $RC -eq 0 ]; then
		echo "PASS  ($((END - START))s)  -> ${LOG#"$REPO"/}"
		PASSED="$PASSED $NAME"
	else
		echo "FAIL  exit $RC ($((END - START))s)  -> ${LOG#"$REPO"/}"
		echo "  --- last 15 lines ---"
		tail -n 15 "$LOG" | sed 's/^/  /'
		FAILED="$FAILED $NAME(exit=$RC)"
	fi
}

# ---- the registry ----
run_one pool-signature-test.sh
run_one build-iso-artifact-test.sh "$REPO"
run_one build-status-test.sh "$REPO"
# ----------------------

echo
echo "registered: $REGISTERED   passed: $(echo $PASSED | wc -w)   failed: $(echo $FAILED | wc -w)   missing: $(echo $MISSING | wc -w)"
[ -n "$PASSED" ]  && echo "  passed: $PASSED"
[ -n "$FAILED" ]  && echo "  FAILED:$FAILED"
[ -n "$MISSING" ] && echo "  MISSING:$MISSING"

# A registered test that is not on disk is a failure, not a skip: the registry is the claim, and
# a silently-absent test is how "registered" stops meaning anything.
[ -z "$FAILED" ] && [ -z "$MISSING" ]
