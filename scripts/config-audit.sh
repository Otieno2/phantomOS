#!/bin/bash
# config-audit.sh — prove that live/auto/config still produces the config the last
# audited toolchain produced, and that no live-build default moved underneath us.
#
# Why this exists: live-build's defaults are a property of the package installed on
# the build host, not of this repo (§11). Without this check, a `live-build` upgrade
# can change the artifact while every committed file stays identical.
#
# Usage:
#   scripts/config-audit.sh dump <tree>      normalized LB_* assignments for an existing tree
#   scripts/config-audit.sh verify [baseline]
#       runs `lb config` on a throwaway copy of live/, then diffs it against the
#       baseline (default: logs/M0-effective-config.txt, i.e. the M0 stock invocation).
#
# The baseline is a raw capture of live-build's own generated config files, so this
# script normalizes both sides the same way before comparing: keep only LB_*="..."
# assignments, drop comments, blank lines and the version banner.

set -u

normalize() {
	# reads a raw `cat config/{common,bootstrap,chroot,binary,source}` stream on stdin,
	# writes the LB_* assignments it contains, sorted
	sed -n 's/^\(LB_[A-Z0-9_]*\)=\(.*\)$/\1=\2/p' | sort
}

dump_tree() {
	local tree="$1"
	cat "$tree"/config/common "$tree"/config/bootstrap "$tree"/config/chroot \
	    "$tree"/config/binary "$tree"/config/source 2>/dev/null | normalize
}

case "${1:-}" in
	dump)
		[ -d "${2:-}" ] || { echo "E: no such tree: $2" >&2; exit 2; }
		dump_tree "$2"
		;;

	verify)
		BASELINE="${2:-logs/M0-effective-config.txt}"
		[ -f "$BASELINE" ] || { echo "E: no baseline: $BASELINE" >&2; exit 2; }
		[ -x live/auto/config ] || chmod +x live/auto/config

		WORK="$(mktemp -d /tmp/config-audit.XXXXXX)"
		trap 'rm -rf "$WORK"' EXIT
		cp -a live/. "$WORK/"
		rm -rf "$WORK/config"
		( cd "$WORK" && lb config >lb-config.log 2>&1 ) || {
			echo "E: lb config failed:"; tail -20 "$WORK/lb-config.log"; exit 1
		}

		dump_tree "$WORK" > "$WORK/new.txt"
		normalize < "$BASELINE" > "$WORK/base.txt"

		echo "baseline: $BASELINE ($(wc -l < "$WORK/base.txt") assignments)"
		echo "current : live/auto/config ($(wc -l < "$WORK/new.txt") assignments)"
		echo
		echo "=== differences (< baseline / M0, > committed auto/config) ==="
		if diff -u "$WORK/base.txt" "$WORK/new.txt" | grep -E '^[-+][^-+]' ; then
			:
		else
			echo "(none — the committed config reproduces the baseline exactly)"
		fi
		echo
		echo "=== lb config stderr (must be empty) ==="
		grep -E '^(E|W):' "$WORK/lb-config.log" || echo "(clean)"
		;;

	*)
		sed -n '1,20p' "$0"
		exit 2
		;;
esac
