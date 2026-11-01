#!/bin/bash
# build-status-test.sh — does scripts/build-status.sh answer busy/idle/cannot-tell soundly?
#
# Registered by scripts/run-tests.sh (§11: a defined-but-unregistered test counts as not done).
#
# The contract under test: exit 0 idle, 1 busy, 2 cannot-tell, and the rule the whole gate exists
# for — *absence of evidence is never reported as idle*. build-iso.sh refuses to start on 1 and on
# 2, so every wrong answer is either a destroyed build (false idle) or a build that cannot start
# (false busy / false cannot-tell).
#
# Every case below is a measured defect or a measured guarantee, from the 2026-11-01 attack pass:
#
#   A  --work on a nonexistent tree (parent visible)        answered CANNOT TELL 2; build-iso.sh
#     ----------------------------------------------------   probes before its `mkdir -p $WORK`, so a
#      (was: IDLE 0 after fix)                               first-ever build could never start.
#   B  a .lock under a live/ the caller cannot search       answered IDLE 0 — the exact violation
#     ----------------------------------------------------   the file's own header forbids.
#   C  $WORK readable but not searchable (mode 400)         answered IDLE 0 with a "no live/ tree"
#                                                            note that had not been observable.
#   D  a busy wrapper launched from a path containing       the old `grep -vE 'build-status\.sh|
#     ----------------------------------------------------    grep -E'` silenced it before the
#      "build-status.sh" or with "grep -E" in its argv      exclusion logic ran: IDLE 0. The fixed
#                                                            filter judges command words, not
#                                                            substrings.
#   E  the probe's own `ps` failing or returning nothing   was reasoned impossible ("ps is never
#     ----------------------------------------------------   empty") and answered IDLE 0; a failing
#      or a broken procfs                                    ps *is* empty. Now an unreadable
#                                                            signal: 2.
#   F  --exclude-pid of a process whose /proc comm         awk field 4 is the state letter when
#     ----------------------------------------------------   comm contains a space; the walk stopped
#      contains a space (a binary literally named "bu il")  at the child and its matching parent
#                                                            was reported as somebody's build.
#   G  --work / --exclude-pid with a missing value          `$2` under `set -u` died with exit 1 —
#     ----------------------------------------------------   which the caller reads as BUSY. Now a
#      and a non-numeric --exclude-pid                      usage error exits 2.
#   H  the caller's own command-substitution fork           build-iso.sh captures this probe with
#     ----------------------------------------------------   `BUILD_STATE=$(…)`; the subshell bash
#      made the guard refuse a genuinely idle host           forks keeps the parent's argv while it
#                                                            waits, was matched as a second live
#                                                            wrapper, and the guard refused its own
#                                                            start (measured 2026-11-01 in both
#                                                            passes of /tmp/arttest-runout.txt:
#                                                            "ignoring pid 100883" beside "busy
#                                                            pid 100884, same cmdline"). The ignore
#                                                            set now walks descendants too.
#   The design guarantees that must NOT regress: an     rc 2 with no idle claim, as any user;
#     ----------------------------------------------------   lock under /root, unreadable to the
#      default WSL user; busy-with-reasons; quiet/verbose agreement; an unrelated qemu counts
#      as busy (documented design: a boot test holds KVM and CPU and its ISO may be the one
#      being rebuilt — see the probe header).
#
# Safety while a build is running — this suite never touches /root/phantomos-m1 in any case that
# could damage it, and never touches the pool:
#   * every process-table case runs the probe against a STUB ps that replays a fixture table from
#     /tmp (the model is build-iso-artifact-test.sh stubbing `lb`); the live build's processes can
#     therefore neither influence nor be influenced by the verdicts under test;
#   * tree cases use throwaway /tmp trees, plus two real background fixture processes this script
#     spawns and kills (a `sleep`-copy and its wrapper) so --exclude-pid walks real /proc data;
#   * the one probe of the real tree is `build-status.sh --work <real>` with the real ps — pure
#     reads — and it asserts self-consistency (quiet exit == verbose label), not a specific busy/
#     idle answer, so this suite passes with a build running AND after the milestone closes.
#
# Permission cases run the probe under an identity the fixtures block: `nobody` when this suite is
# run as root (which scripts/run-tests.sh is), directly as the caller when it is not (a regular
# user's own chmod 000 directory blocks even its owner).
#
# Usage: scripts/build-status-test.sh [repo-root]
# Exit: 0 if every assertion holds.

set -uo pipefail

REPO="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
S="$REPO/scripts/build-status.sh"
# per-uid: this suite is run both as root (scripts/run-tests.sh) and by hand as the default user
# to exercise the non-root identity branch; a shared directory leaves root-owned fixtures that
# the next identity cannot write (measured 2026-11-01: three false failures in section 4 from
# exactly that).
T=/tmp/phantomos-bs-test.$(id -u)
REALWORK="${PHANTOMOS_WORK:-/root/phantomos-m1}"

case "$T" in
	/tmp/*) ;;
	*) echo "E: fixture directory $T is not under /tmp; refusing to run" >&2; exit 2 ;;
esac
[ -f "$S" ] || { echo "E: $S missing — wrong repo root?" >&2; exit 2; }

PSBIN="$(command -v ps)"   # the real ps, captured before the stub shadows the PATH
EUID_NOW="$(id -u)"

rm -rf "$T"
mkdir -p "$T/bin" "$T/idle/live" "$T/locktree/live" "$T/stamptree/live/.build"
touch "$T/locktree/live/.lock"
# stamp names exercise the display path, epoch- and colon-named files included.
touch "$T/stamptree/live/.lock" "$T/stamptree/live/.build/config" \
	"$T/stamptree/live/.build/1730480847_bootstrap" "$T/stamptree/live/.build/2026-11-01T17:07:27Z_stage"

# the stub ps: replays $QA_PS_TABLE, or simulates a broken procfs.
cat > "$T/bin/ps" <<'EOS'
#!/bin/bash
[ "${QA_PS_FAIL:-0}" = 1 ] && { echo "stub ps: simulated procps failure" >&2; exit 1; }
[ "${QA_PS_EMPTY:-0}" = 1 ] && exit 0
cat "${QA_PS_TABLE:-/dev/null}"
EOS
chmod 755 "$T/bin" "$T/bin/ps"

# a single unrelated line, so "idle" cases have a usable (non-empty) process table;
# an EMPTY table is itself signal-unreadable under the fixed contract (case E).
printf '1 01:02:03 /sbin/init\n' > "$T/tbl_idle"

# permission fixtures: a lock nobody can see, a $WORK that cannot be searched at all, a $WORK
# readable but not searchable (mode 444 — the probe can list the name but not stat children),
# and a parent directory the caller cannot enter. $PRIV is the block-everything mode for the
# probing identity: 700 root-owned blocks `nobody` (root probes as nobody), 000 blocks the owner
# itself, which is who probes when the suite runs as a regular user (no CAP_DAC_OVERRIDE).
mkdir -p "$T/hide/live" "$T/nostat" "$T/ronly/live" "$T/pblock/hidden/live"
touch "$T/hide/live/.lock" "$T/nostat/placeholder" "$T/ronly/live/.lock" "$T/pblock/hidden/live/.lock"
chmod 755 "$T" "$T/hide"
if [ "$EUID_NOW" = 0 ]; then
	PRIV=700
	chown -R root:root "$T/hide" "$T/nostat" "$T/ronly" "$T/pblock"
else
	PRIV=000
	# a regular user cannot make a root-owned invisible-parent fixture; /root (mode 700) is
	# the real one, and supplies the "absent under an invisible parent" case directly.
	BLOCKED_ABSENT="/root/qa-absent-under-root-$$"
fi
chmod "$PRIV" "$T/hide/live" "$T/nostat" "$T/pblock" "$T/pblock/hidden"
chmod 444 "$T/ronly"

pass=0 fail=0
chk() { # chk <label> <shell condition>
	if eval "$2"; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
	else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi
}

OUT=""
RC=0
probe() { # probe <table-file-or-empty-flag> -- extra args... ; sets OUT and RC
	# Called outside pipelines, exactly like build-iso-artifact-test.sh's run(): a pipeline
	# would put this function in a subshell and the RC it sets would die there.
	local tbl="$1"; shift
	if [ "$tbl" = "FAILPS" ]; then
		OUT=$(env QA_PS_FAIL=1 PATH="$T/bin:$PATH" bash "$S" "$@" 2>&1); RC=$?
	elif [ "$tbl" = "EMPTYPS" ]; then
		OUT=$(env QA_PS_EMPTY=1 PATH="$T/bin:$PATH" bash "$S" "$@" 2>&1); RC=$?
	else
		OUT=$(env QA_PS_TABLE="$tbl" PATH="$T/bin:$PATH" bash "$S" "$@" 2>&1); RC=$?
	fi
}

probe_unpriv() { # same, but as an identity the fixtures block; args must contain no spaces
	local tbl="$1"; shift
	if [ "$EUID_NOW" = 0 ]; then
		OUT=$(su -s /bin/bash nobody -c \
			"export PATH=$T/bin:/usr/bin:/bin QA_PS_TABLE=$tbl; bash $S $*" 2>&1); RC=$?
	else
		probe "$tbl" "$@"
	fi
}

label_rc() { # map a probe's verbose first word onto the exit code it must have produced
	case "$1" in
		"BUSY"*)          echo 1 ;;
		"CANNOT TELL"*)   echo 2 ;;
		"IDLE"*)          echo 0 ;;
		*)                echo x ;;
	esac
}

# ---------------------------------------------------------------- tree classification
echo "=== 1. tree signals (process table stubbed to one unrelated line) ==="
probe "$T/tbl_idle" --work "$T/idle";                     echo "  idle tree: rc=$RC"; chk "a readable tree with live/ and no .lock is IDLE 0" '[ "$RC" = 0 ] && grep -q "^IDLE" <<< "$OUT"'
probe "$T/tbl_idle" --work "$T/locktree";                 echo "  lock tree: rc=$RC"; chk "a present live/.lock is BUSY 1 naming the lock" '[ "$RC" = 1 ] && grep -q "live-build lock" <<< "$OUT"'
probe "$T/tbl_idle" --work "$T/stamptree";                                    chk "busy output lists the .build stage stamps"            'grep -q "stage stamps: .*config" <<< "$OUT"'
                                                                                        chk "epoch- and colon-named stamps survive the listing"    'grep -q "1730480847_bootstrap" <<< "$OUT" && grep -q "2026-11-01T17:07:27Z_stage" <<< "$OUT"'
probe "$T/tbl_idle" --work "$T/absent-does-not-exist";   echo "  absent tree: rc=$RC"; chk "definitely-absent --work is IDLE 0 with a first-run note (defect A)" '[ "$RC" = 0 ] && grep -q "first run" <<< "$OUT"'
probe_unpriv "$T/tbl_idle" --work "$T/hide";              echo "  hidden lock: rc=$RC"; chk "a .lock under an unsearchable live/ is never IDLE (defect B)" '[ "$RC" = 2 ] && grep -q "^CANNOT TELL" <<< "$OUT"'
probe_unpriv "$T/tbl_idle" --work "$T/ronly";             echo "  WORK 444: rc=$RC"; chk "a WORK that can be read but not searched is never IDLE (defect C)" '[ "$RC" = 2 ] && ! grep -q "no live/ tree" <<< "$OUT"'
probe_unpriv "$T/tbl_idle" --work "$T/nostat";            echo "  unreadable WORK: rc=$RC"; chk "an unreadable WORK is CANNOT TELL 2" '[ "$RC" = 2 ]'
probe_unpriv "$T/tbl_idle" --work "$T/pblock/hidden";     echo "  invisible WORK: rc=$RC"; chk "a WORK the caller cannot stat (parent blocks) is CANNOT TELL 2" '[ "$RC" = 2 ]'
probe_unpriv "$T/tbl_idle" --work "$T/pblock/nothing"; echo "  absent under invisible parent: rc=$RC"; chk "absence the caller cannot verify is NOT claimed as idle (defect A kept honest)" '[ "$RC" = 2 ]'
if [ -n "${BLOCKED_ABSENT:-}" ]; then
	probe "$T/tbl_idle" --work "$BLOCKED_ABSENT";         echo "  absent under /root: rc=$RC"; chk "non-root: absent under mode-700 /root is CANNOT TELL 2" '[ "$RC" = 2 ]'
fi

echo "=== 2. quiet and verbose never disagree ==="
for pair in "0 idle" "1 locktree" "0 absent-does-not-exist" "2 nostat" "2 hide" "2 ronly"; do
	want="${pair%% *}"; dir="${pair#* }"
	probe_unpriv "$T/tbl_idle" --work "$T/$dir"
	vrc="$RC"; vlabel="${OUT%%$'\n'*}"
	probe_unpriv "$T/tbl_idle" --quiet --work "$T/$dir"
	qrc="$RC"
	echo "  $dir: verbose=$vrc ($vlabel), quiet=$qrc"
	chk "$dir: verbose exit is $( [ "$want" = 0 ] && echo idle || { [ "$want" = 1 ] && echo busy || echo cannot-tell; } ) and the label says the same" '[ "$vrc" = "$want" ] && [ "$vrc" = "$(label_rc "$vlabel")" ]'
	chk "$dir: --quiet exit equals the verbose exit" '[ "$qrc" = "$vrc" ]'
done

# ---------------------------------------------------------------- process table
echo "=== 3. process-table signals (stub ps replays fixture lines) ==="
printf '999901 00:01 bash /root/somewhere/.build-iso.running.sh /repo\n' > "$T/tbl_wrapper"
printf '999902 00:02 /bin/sh /usr/lib/live/build/build\n' > "$T/tbl_stage"
printf '999903 00:03 mksquashfs live/binary foo.iso -comp zstd\n' >> "$T/tbl_stage"
printf '999904 00:04 qemu-system-x86_64 -enable-kvm -cdrom some-other.iso\n' > "$T/tbl_qemu"
printf '999905 00:05 bash /tmp/build-status.sh.d/scripts/build-iso.sh /tmp/build-status.sh.d\n' > "$T/tbl_bsname"
printf '999906 00:06 /usr/lib/live/build/build grep -E some-pattern /tmp/f\n' > "$T/tbl_grepargv"
printf '999907 00:07 grep -E /usr/lib/live/build/|mksquashfs\n' > "$T/tbl_selfgrep"
printf '999908 00:08 bash /repo/scripts/build-status.sh --work /tmp/x/.build-iso.running.sh\n' > "$T/tbl_selfrun"

probe "$T/tbl_wrapper" --work "$T/idle";                 echo "  wrapper: rc=$RC"; chk "a wrapper line is BUSY 1 naming pid and wrapper" '[ "$RC" = 1 ] && grep -q "live-iso wrapper: pid 999901" <<< "$OUT"'
probe "$T/tbl_stage"   --work "$T/idle";                 echo "  stages: rc=$RC";  chk "stage helpers and mksquashfs are BUSY 1" '[ "$RC" = 1 ] && grep -q "live-build stage: pid 999902" <<< "$OUT" && grep -q "live-build stage: pid 999903" <<< "$OUT"'
probe "$T/tbl_qemu"    --work "$T/idle";                 echo "  qemu: rc=$RC";    chk "an unrelated qemu is BUSY 1 as its own reason (documented design, not a defect)" '[ "$RC" = 1 ] && grep -q "qemu boot test" <<< "$OUT"'
probe "$T/tbl_bsname"  --work "$T/idle";                 echo "  path-similarity: rc=$RC"; chk "busy process under a path containing build-status.sh is NOT silenced (defect D)" '[ "$RC" = 1 ] && grep -q "pid 999905" <<< "$OUT"'
probe "$T/tbl_grepargv" --work "$T/idle";                echo "  argv-grep: rc=$RC"; chk "helper with grep -E in its argv is NOT silenced (defect D)" '[ "$RC" = 1 ] && grep -q "pid 999906" <<< "$OUT"'
probe "$T/tbl_selfgrep" --work "$T/idle";                echo "  own grep: rc=$RC"; chk "the probe command grep is not counted busy" '[ "$RC" = 0 ]'
probe "$T/tbl_selfrun"  --work "$T/idle";                echo "  own run: rc=$RC";  chk "an invocation of build-status.sh itself is not counted busy" '[ "$RC" = 0 ]'
probe FAILPS           --work "$T/idle";                 echo "  ps exit 1: rc=$RC"; chk "a failing ps is an unreadable signal, not IDLE (defect E)" '[ "$RC" = 2 ] && grep -q "process table" <<< "$OUT"'
probe EMPTYPS          --work "$T/idle";                 echo "  ps empty: rc=$RC";  chk "an empty process table is not evidence of idle (defect E)" '[ "$RC" = 2 ]'
probe "$T/tbl_idle"    --work "$T/locktree" --quiet;     echo "  lock quiet: rc=$RC"; chk "--quiet reports busy for a lock (exit 1)" '[ "$RC" = 1 ]'

# ---------------------------------------------------------------- exclude-pid, on real /proc
echo "=== 4. --exclude-pid walks a real ancestor chain (fixtures are two live processes) ==="
cp /bin/sleep "$T/bu ild"                       # a comm containing a space — defect F's trigger
mkdir -p "$T/wtree"
cat > "$T/wtree/.build-iso.running.sh" <<EOS
#!/bin/bash
"$T/bu ild" 900 &
echo \$! > "$T/bpid"
sleep 900
EOS
chmod +x "$T/wtree/.build-iso.running.sh" "$T/bu ild"
bash "$T/wtree/.build-iso.running.sh" & APID=$!
trap 'kill "${APID:-}" "${BPID:-}" 2>/dev/null' EXIT
for _ in $(seq 50); do [ -s "$T/bpid" ] && break; sleep 0.1; done
BPID="$(cat "$T/bpid" 2>/dev/null || echo "")"
[ -n "$BPID" ] || { echo "  FAIL  fixture child never started"; fail=$((fail+1)); }
REAL_LINE="$($PSBIN -eo pid=,etime=,args= | grep "^ *$APID " || true)"
[ -n "$REAL_LINE" ] || REAL_LINE="$APID       00:01 bash $T/wtree/.build-iso.running.sh"
printf '%s\n' "$REAL_LINE" > "$T/tbl_real"

probe "$T/tbl_real" --work "$T/idle" --exclude-pid 999999; echo "  dead pid: rc=$RC"; chk "excluding a dead pid neither crashes nor hides the live ancestor" '[ "$RC" = 1 ] && grep -q "pid $APID" <<< "$OUT"'
probe "$T/tbl_real" --work "$T/idle" --exclude-pid "$BPID"; echo "  exclude child: rc=$RC"; chk "excluding a pid ignores its ancestors despite a space in comm (defect F)" '[ "$RC" = 0 ] && grep -q "(ignoring pid $APID" <<< "$OUT"'
probe "$T/tbl_real" --work "$T/idle" --exclude-pid "$APID"; chk "excluding the wrapper itself is idle" '[ "$RC" = 0 ]'
kill "$APID" "$BPID" 2>/dev/null; wait 2>/dev/null

probe "$T/tbl_idle" --work "$T/idle" --exclude-pid "1 2";  echo "  bad pid: rc=$RC"; chk "a non-numeric --exclude-pid is a usage error (2), not a silent empty ignore set (defect G)" '[ "$RC" = 2 ] && grep -q "^E:" <<< "$OUT"'

echo "=== 4b. a build-iso.sh-shaped guard must not refuse an idle host over its own fork (defect H) ==="
mkdir -p "$T/bin2" "$T/selfguard" "$T/tree/live"
printf '#!/bin/bash\n"%s" -eo pid=,etime=,args= | grep selfguard\n' "$PSBIN" > "$T/bin2/ps"
chmod 755 "$T/bin2" "$T/bin2/ps"
# the same capture form as build-iso.sh:65; only the fixture subtree reaches the probe's table,
# so the real build cannot influence this — and this cannot touch the real build.
cat > "$T/selfguard/.build-iso.running.sh" <<EOS
#!/bin/bash
if ! BUILD_STATE=\$(bash "$S" --work "$T/tree" --exclude-pid \$\$ 2>&1); then
	printf '%s\n' "\$BUILD_STATE"
	echo GUARD-REFUSED
else
	echo GUARD-PROCEEDED
fi
EOS
SGOUT="$(env PATH="$T/bin2:/usr/bin:/bin" bash "$T/selfguard/.build-iso.running.sh" 2>&1)"
echo "  guard said: $(echo "$SGOUT" | tail -1)"
chk "build-iso.sh's own subshell fork is ignored: the guard proceeds over a truly idle tree" 'grep -q "GUARD-PROCEEDED" <<< "$SGOUT"'

# ---------------------------------------------------------------- usage
echo "=== 5. argument handling ==="
probe "$T/tbl_idle" --work;                                echo "  --work bare: rc=$RC"; chk "--work without a value exits 2, not a set -u crash exiting 1 (defect G)" '[ "$RC" = 2 ] && grep -q "^E:" <<< "$OUT"'
probe "$T/tbl_idle" --exclude-pid;                         echo "  --exclude-pid bare: rc=$RC"; chk "--exclude-pid without a value exits 2 (defect G)" '[ "$RC" = 2 ] && grep -q "^E:" <<< "$OUT"'
probe "$T/tbl_idle" --bogus;                               chk "an unknown argument exits 2" '[ "$RC" = 2 ] && grep -q "^E: unknown" <<< "$OUT"'

# ---------------------------------------------------------------- the real tree, read-only
echo "=== 6. the real work tree (read-only, real ps, whatever state the build is in) ==="
OUT=$(bash "$S" --work "$REALWORK" 2>&1); RC=$?
VLABEL="${OUT%%$'\n'*}"; VRC="$RC"
QRC=$(bash "$S" --quiet --work "$REALWORK" >/dev/null 2>&1; echo $?)
# two calls can straddle a real state change; on disagreement re-take the pair once.
if [ "$VRC" != "$QRC" ]; then
	sleep 2
	OUT=$(bash "$S" --work "$REALWORK" 2>&1); VRC=$?; VLABEL="${OUT%%$'\n'*}"
	QRC=$(bash "$S" --quiet --work "$REALWORK" >/dev/null 2>&1; echo $?)
fi
echo "  verbose says: $VLABEL (exit $VRC); quiet exit $QRC"
if [ "$VRC" = 1 ]; then printf '%s\n' "$OUT" | sed -n '2,6p;s/^/  | /'; fi
chk "the real tree answers 0, 1 or 2 only" '[ "$VRC" = 0 ] || [ "$VRC" = 1 ] || [ "$VRC" = 2 ]'
chk "quiet and verbose agree on the real tree" '[ "$VRC" = "$QRC" ] && [ "$VRC" = "$(label_rc "$VLABEL")" ]'
if [ -e "$REALWORK/live/.lock" ]; then
	chk "a .lock visible to this identity is never answered IDLE" '[ "$VRC" != 0 ]'
else
	echo "  (no .lock readable by this identity right now — the lock-vs-idle invariant was checked on the /tmp fixture instead)"
fi

echo
printf 'RESULT: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
