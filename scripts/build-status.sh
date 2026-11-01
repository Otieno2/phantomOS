#!/bin/bash
# build-status.sh — answer "is a build running right now?" from evidence, not from memory.
#
# This exists because a second session working in the same tree can corrupt a running build in
# ways that are invisible until the build is already lost. The four that matter, all measured and
# written into §9.1:
#
#   * `lb build` on the same $WORK a second time races the first one over live/chroot,
#     live/binary and the .build/ stamps that tell live-build a stage is done.
#   * `rsync --delete` from the repo against a *configured* tree tears the configuration down,
#     because `lb config` generates most of live/config/ and the repo commits only a few files
#     under it (bootstrap, common, binary, chroot, source, includes*, hooks/, packages*, local/bin).
#   * a recursive `chmod 0644` over $WORK hits live/chroot on a resumed tree and strips the exec
#     bit from everything in the bootstrapped system; the chroot is then unrecoverable, because
#     cache/bootstrap.tar caches the damage.
#   * `rm -rf` through a stale bind mount deletes the *source*, which is how the package pool was
#     eaten once during a test run.
#
# Scripts/build-iso.sh calls this and refuses to start when it says busy. Run it by hand before
# touching $WORK, /opt/phantomos-build/pool, or the signing key.
#
# Why not just a lock file: a lock only holds against people who take it. `lb build` run directly,
# a stale tree, or a session that forgot all refuse nothing, so the answer here is read from the
# host's own state and a lock would only ever be a fifth, weaker signal on top of that.
#
# Usage: scripts/build-status.sh [--work DIR] [--exclude-pid PID] [--quiet]
#   --work         live-build tree to inspect (default $PHANTOMOS_WORK or /root/phantomos-m1).
#                  A tree that verifiably does not exist answers idle with a note — build-iso.sh
#                  probes before its `mkdir -p "$WORK"`, so "absent" must not be a refusal. Only
#                  an existence that cannot be checked (unsearchable $WORK or parent) is a 2.
#   --exclude-pid  a build process to ignore, plus its ancestors AND its whole descendant tree —
#                  so build-iso.sh, which re-execs itself and captures this probe in a command
#                  substitution whose fork it cannot tell apart from itself, does not count its
#                  own run as somebody else's
#   --quiet        exit status only, no output
# Exit: 0 idle   1 busy   2 cannot tell (host unreachable, every signal unreadable, or bad usage)
#
# Reading live/.lock needs root when $WORK is under /root, which is where it normally lives. Run
# without it and the lock check is reported as unreadable rather than as absent — a missing signal
# must never be read as "idle" by accident. The same rule, applied per signal after the 2026-11-01
# test pass (scripts/build-status-test.sh): a live/ that exists but cannot be searched, a $WORK
# that can be read but not searched, and a ps that fails or returns nothing are all unreadable
# signals too. None of them may answer idle.

set -uo pipefail

WORK="${PHANTOMOS_WORK:-/root/phantomos-m1}"
EXCLUDE=""
QUIET=0

while [ $# -gt 0 ]; do
	case "$1" in
		--work|--exclude-pid)
			# A missing value used to reach `$2` under `set -u`, which dies with a bash
			# "unbound variable" and exit 1 — and exit 1 is this script's BUSY code, so a
			# typoed call told its caller "a build is running". Usage errors are 2.
			[ $# -ge 2 ] || { echo "E: $1 needs an argument" >&2; exit 2; }
			if [ "$1" = --work ]; then WORK="$2"; else EXCLUDE="$2"; fi
			shift 2 ;;
		--quiet) QUIET=1; shift ;;
		*) echo "E: unknown argument: $1" >&2; exit 2 ;;
	esac
done

# A non-numeric --exclude-pid yields an empty ignore set, which makes the caller's own re-exec
# count as somebody else's build: a refusal that names the caller's own pid. Bad input is
# "cannot tell", not a false "busy" and not an accidental "idle".
if [ -n "$EXCLUDE" ] && [ "${EXCLUDE//[0-9]/}" ]; then
	echo "E: --exclude-pid is not a number: $EXCLUDE" >&2
	exit 2
fi

REASONS=()
UNREADABLE=()

# Whether $WORK is verifiably absent. `[ -e $WORK ]` being false is only evidence of absence when
# the parent directory can be searched; under a parent we cannot enter (/root, mode 700, is the
# usual case) the same test returns false for a tree that exists and is busy, and that must stay
# a 2. Before this function existed, a first run — build-iso.sh probes before its mkdir — hit
# exactly the false arm and the guard refused to start a build on an empty disk.
work_is_absent ()
{
	local P
	P=$(dirname -- "$WORK" 2>/dev/null) || return 1
	[ -n "$P" ] && [ -x "$P" ] || return 1
	[ ! -e "$WORK" ]
}

# Ancestors AND descendants of $EXCLUDE, so neither the wrapper a build is waiting on nor the
# caller's own process tree is ever counted as somebody else's build.
#
# Descendants are load-bearing: build-iso.sh captures this probe with `BUILD_STATE=$(… )`, and
# the subshell bash forks for that capture keeps the parent's argv while it waits — so the probe
# sees a second live process whose cmdline is the wrapper's own, under a pid that is neither
# $$ nor an ancestor of it. Measured 2026-11-01 in /tmp/arttest-runout.txt (pass 1 named pid
# 100884, pass 2 named pid 100919, both identical to their parent's argv) and reproduced in
# scripts/build-status-test.sh: without this walk, build-iso.sh's guard refuses every start on a
# genuinely idle host, because its own command substitution looks like a concurrent build.
#
# $PPID is the special variable and must not be walked — it always names the *current* parent.
# For ancestors, /proc/PID/stat is `pid (comm) state ppid …` and comm is arbitrary bytes: it can
# contain spaces, so the parent is the first field after the LAST ") " minus the state letter,
# not field 4 — field 4 is the state letter whenever comm contains a space (measured 2026-11-01
# with a binary literally named `bu ild`: the walk stopped at the child and its matching parent
# was reported as somebody's build). A pid that vanishes mid-walk ends it: fewer pids ignored,
# which can only make the answer more busy, never more idle.
ignored_pids ()
{
	[ -n "$EXCLUDE" ] || return 0
	[ -r "/proc/$EXCLUDE/stat" ] || return 0   # a dead EXCLUDE ignores nothing, as before

	local P S N
	P="$EXCLUDE"
	N=0
	while [ -n "$P" ] && [ "$P" != 0 ] && [ "$N" -lt 64 ]; do
		N=$((N + 1))
		S=$(cat "/proc/$P/stat" 2>/dev/null) || break
		echo "$P"
		# The tail after the LAST ") " is `state ppid …` — the ppid is the field after the
		# state letter, not the first field of the tail.
		S="${S##*) }"
		S="${S#* }"
		P="${S%% *}"
		case "$P" in ''|*[!0-9]*) break ;; esac
	done

	# Down: breadth-first through /proc/PID/task/PID/children (kernel-truth, so pid reuse cannot
	# sneak an unrelated build into the set). Bounded: a login shell's subtree is shallow and a
	# runaway bound here can only under-ignore, i.e. answer more busy.
	local I Q=("$EXCLUDE") C
	N=0
	while [ ${#Q[@]} -gt 0 ] && [ "$N" -lt 512 ]; do
		I="${Q[0]}"
		Q=("${Q[@]:1}")
		N=$((N + 1))
		for C in $(cat "/proc/$I/task/$I/children" 2>/dev/null); do
			case " ${Q[*]-} " in *" $C "*) continue ;; esac
			Q+=("$C")
			echo "$C"
		done
	done
}

# A process whose pid is in the ignore set is us. Everything else is somebody's build.
matches_our_own_run ()
{
	case " $IGNORED " in
		*" $1 "*) return 0 ;;
		*)       return 1 ;;
	esac
}

# Snapshot the process table and the ancestor chain exactly once, before any probe reads either.
# Two `ps` calls a minute apart disagree, and an answer that mixed them could ignore one line of
# a build and report its parent as somebody else's in the same breath.
PS_TABLE=$(ps -eo pid=,etime=,args= 2>/dev/null)
PS_RC=$?
if [ "$PS_RC" -ne 0 ]; then
	UNREADABLE+=("cannot read the process table: ps exited $PS_RC")
elif [ -z "$PS_TABLE" ]; then
	# A real ps lists at least pid 1. Empty means the tool or procfs was unusable — this file
	# used to reason "ps is never empty" and treat an empty table as no evidence to report;
	# measured 2026-11-01: a ps that fails *is* empty, and the answer came out IDLE.
	UNREADABLE+=("the process table came back empty — ps produced no rows, which is not evidence of idle")
fi
# Newline-separated ancestors flattened to a space-separated word list: matches_our_own_run
# tests membership on words, and " 91030\n" is not " 91030 ".
IGNORED=$(ignored_pids | tr '\n' ' ')

# Signals 2-5 are process-table lookups against the snapshot. A single pattern per signal, so a
# busy answer always names what matched rather than just asserting it.
probe_procs ()
{
	local LABEL="$1" PATTERN="$2" HITS PID LINE ARGS

	[ -n "$PS_TABLE" ] || return 0

	# ps -eo on a procps host lists every user's processes without needing root, which is what
	# makes this usable from a non-root shell — unlike live/.lock below.
	HITS=$(printf '%s\n' "$PS_TABLE" | grep -E "$PATTERN" || true)

	[ -n "$HITS" ] || return 0
	while read -r PID LINE; do
		[ -n "$PID" ] || continue
		# This probe's own machinery, judged by the COMMAND WORD and by whole words only. The
		# previous `grep -vE 'build-status\.sh|grep -E'` filtered substrings of the whole line
		# before the exclusion logic ever ran, so a genuinely busy process was silenced whenever
		# its path merely contained either string: a wrapper run from
		# /tmp/build-status.sh.d/scripts/build-iso.sh, or a stage helper with "grep -E" anywhere
		# in its argv, answered IDLE (both measured 2026-11-01). Silencing the probe's own greps
		# needs the command to *be* grep; nothing else is this script.
		ARGS="${LINE#* }"
		[ "${ARGS%% *}" = grep ] && continue
		case " $ARGS " in
			*build-status.sh[[:space:]]*) continue ;;
		esac
		if matches_our_own_run "$PID"; then
			[ "$QUIET" = 1 ] || echo "  (ignoring pid $PID: this run's own tree)"
			continue
		fi
		REASONS+=("$LABEL: pid $PID up ${LINE%% *}: $ARGS")
	done <<< "$HITS"
}

probe_procs "live-iso wrapper" '\.build-iso\.running\.sh|scripts/build-iso\.sh'
# live-build's own stage helpers and the ISO/squashfs packers, which outlive the `lb build` shell.
probe_procs "live-build stage" '/usr/lib/live/build/|/usr/sbin/debootstrap|/usr/bin/lb |mksquashfs|xorriso'
# A boot test is not a build, but it holds KVM and CPU and its ISO may be the one being rebuilt,
# so it belongs in the answer. Reported as its own reason; a caller that only cares about builds
# can grep it out.
probe_procs "qemu boot test" 'qemu-system-x86_64'

# Signal 1: live-build's own marker. What it actually is, measured against /usr/share/live/build
# /functions/lockfile.sh on the build host rather than assumed from its name: `Acquire_lockfile` is
# called by the ~61 leaf stage helpers, each of which does `touch` and then `trap 'rm -f' EXIT HUP
# INT QUIT TERM`. The four dispatchers (build, bootstrap, chroot, binary) take no lock at all. So
# the file appears and disappears *per helper* — its mtime is the current helper's, not the run's
# start — and a SIGKILL or a WSL teardown leaves a stale one with no process behind it.
#
# That is why this signal is confirmation and never the primary answer: present ⇒ busy (correct in
# both the live and stale cases), absent ⇒ says nothing, because the whole pre-flight and the gaps
# between helpers look identical to idle. Run N's pre-flight was 13 m 35 s wide with no lock.
N_PROC=${#REASONS[@]}
NO_TREE=""
if [ -e "$WORK/live" ]; then
	if [ -e "$WORK/live/.lock" ]; then
		REASONS+=("live-build lock: $WORK/live/.lock exists (mtime $(date -Is -r "$WORK/live/.lock" 2>/dev/null || echo unknown))")
	elif [ -r "$WORK/live" ] && [ -x "$WORK/live" ]; then

		: # we could see into live/ and there is no .lock — a real absence, not a missing signal
	else
		# live/ is there but we cannot stat inside it, so the lock may exist and be invisible:
		# a .lock under a live/ the caller could not search answered IDLE (measured 2026-11-01).
		UNREADABLE+=("cannot read $WORK/live to check for .lock: needs root when the tree belongs to another user")
	fi
elif [ -r "$WORK" ] && [ -x "$WORK" ]; then
	NO_TREE="no live/ tree under $WORK yet — first run, or --work points somewhere wrong"
elif work_is_absent; then
	NO_TREE="no work tree at $WORK yet — first run, or --work points somewhere wrong"
else
	# $WORK cannot be searched (readable-but-not-executable, or a parent we cannot enter):
	# live/ may well exist — that is an unreadable signal, never a "no tree" and never idle.
	UNREADABLE+=("cannot stat $WORK/live: needs root when \$WORK is under /root")
fi

# Report which stage it is in when we can, because "busy" without a stage tells you nothing about
# how long to wait. Run M took 1 h 45 m from lb config to a signed ISO.
STAGE=""
if [ -d "$WORK/live/.build" ]; then
	STAGE=$(ls -1 "$WORK/live/.build" 2>/dev/null | tr '\n' ' ')
	[ -n "${STAGE// /}" ] || STAGE="(no completed stage stamps yet)"
fi

# Unreadable signals are handled before the idle answer, in every mode. The rule this file exists
# to enforce is that an absence of evidence is not evidence of absence: --quiet must not report
# idle to a caller that then starts a build on top of one it could not see.
if [ "$QUIET" = 1 ]; then
	[ ${#REASONS[@]} -gt 0 ] && exit 1
	[ ${#UNREADABLE[@]} -gt 0 ] && exit 2
	exit 0
fi

if [ ${#REASONS[@]} -gt 0 ]; then
	echo "BUSY — $WORK"
	printf '  %s\n' "${REASONS[@]}"
	[ -n "$STAGE" ] && echo "  stage stamps: $STAGE"
	# Lock-only busy is the case that invites a wrong override. A stale .lock left by a SIGKILL or
	# a WSL teardown is indistinguishable from a live build by existence alone, and "the guard is
	# being annoying" is exactly how guards get switched off. Name the possibility and the checks
	# that settle it, rather than leaving the reader to guess.
	if [ "$N_PROC" -eq 0 ]; then
		echo "  note: the lock is the only signal — no build process matched. A stale .lock from a"
		echo "  killed run looks like this. Do not override on this alone: read $WORK/live/.build"
		echo "  (which stages upstream thinks are done) and /proc/mounts (whether the pool is still"
		echo "  bind-mounted into a chroot) before touching the tree."
	fi
	[ ${#UNREADABLE[@]} -gt 0 ] && printf '  caveat: %s\n' "${UNREADABLE[@]}"
	[ -n "$NO_TREE" ] && echo "  note: $NO_TREE"
	exit 1
fi

if [ ${#UNREADABLE[@]} -gt 0 ]; then
	echo "CANNOT TELL — $WORK"
	printf '  %s\n' "${UNREADABLE[@]}"
	echo "  At least one signal could not be read, so idle is not a claim this script can make."
	echo "  Treat the answer as busy, or re-run with privileges that can read the signals above."
	exit 2
fi

echo "IDLE — no build, no boot test, no live-build lock"
[ -n "$NO_TREE" ] && echo "  note: $NO_TREE"
exit 0
