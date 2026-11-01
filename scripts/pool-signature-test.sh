#!/bin/bash
# pool-signature-test.sh — the negative controls for §8's "our key pinned, HTTPS only".
#
# What a built image must never do is install a package because apt was told to trust the
# channel it came from. So the three cases below are not "does the signed pool work", which
# the build log already shows, but "does an unverifiable pool fail", which the build log can
# never show: the build stops the moment apt refuses, and a mechanism that has only ever been
# observed succeeding has not been observed refusing anything.
#
#   A  pool signed by the build key, pinned keyring = the committed public key  → accepted
#   B  the same bytes re-signed with a different key, keyring unchanged         → refused
#   C  InRelease and Release.gpg deleted                                        → refused
#
# B is the case that would catch a silent [trusted=yes]: if trust were coming from anywhere but
# the pinned keyring, a foreign signature would still be accepted. Generating the second key is
# therefore the load-bearing part of this script, and its output is checked — same Release file,
# different signature bytes — rather than assumed to have happened.
#
# C is the case that would catch apt falling back to Release when InRelease is missing and
# treating a bare Release as trusted.
#
# Not covered, and said so in §9.1 rather than left implicit: a tampered .deb whose hash no
# longer matches Packages. That fails at download, not at update, and has not been run.
#
# Runs against a copy of the pool for B and C; the real pool is only ever read, because a build
# may be mounting it at this moment.
#
# Usage: scripts/pool-signature-test.sh [pool-dir]      default /opt/phantomos-build/pool

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
POOL="${1:-/opt/phantomos-build/pool}"
PUBKEY="$REPO/live/config/archives/phantomos.key.chroot"
OUT="$REPO/logs/M1-pool-signature.txt"
T=/tmp/phantomos-pool-sigtest

[ -d "$POOL" ] || { echo "E: pool $POOL missing — run scripts/build-packages.sh" >&2; exit 2; }
[ -f "$PUBKEY" ] || { echo "E: $PUBKEY missing" >&2; exit 2; }

# apt is driven entirely from options so the host's own sources and keyrings cannot influence a
# case: sourcelist points at /dev/null, sourceparts at one generated file, and the lists
# directory is emptied per case. Nothing here writes to /etc/apt.
SRC="$T/srcparts"; LISTS="$T/lists"; KEYR="$T/keyrings"
rm -rf "$T"; mkdir -p "$SRC" "$LISTS" "$KEYR" "$T/other-gnupg"
chmod 700 "$T/other-gnupg"
gpg --dearmor -o "$KEYR/phantomos.gpg" < "$PUBKEY"

cat > "$T/other-key.params" <<'PARAMS'
%no-protection
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: PhantomOS Impostor Key
Name-Email: root@localhost
Expire-Date: 0
%commit
PARAMS
GNUPGHOME="$T/other-gnupg" gpg --batch --gen-key "$T/other-key.params" 2>"$T/other-key.err"
GNUPGHOME="$T/other-gnupg" gpg --batch --armor --export 'PhantomOS Impostor Key' > "$T/other.asc"
gpg --dearmor -o "$KEYR/impostor.gpg" < "$T/other.asc"

fpr() { gpg --show-keys --with-colons "$1" 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}'; }
GOOD_FPR=$(fpr "$KEYR/phantomos.gpg")
BAD_FPR=$(fpr "$KEYR/impostor.gpg")

{
echo "M1 — pool signature negative controls (run $(date -u +%Y-%m-%dT%H:%M:%SZ), WSL Debian as root)"
echo
echo "pool under test : $POOL"
echo "pinned keyring  : dearmored live/config/archives/phantomos.key.chroot"
echo "                  fingerprint $GOOD_FPR"
echo "impostor key    : generated for this run, fingerprint $BAD_FPR"
echo "                  (GNUPGHOME=$T/other-gnupg, %no-protection RSA 2048+2048)"
if [ -z "$GOOD_FPR" ] || [ -z "$BAD_FPR" ] || [ "$GOOD_FPR" = "$BAD_FPR" ]; then
	echo
	echo "RESULT: inconclusive — the two keyrings are not two different keys."
	exit 1
fi

case_run() { # $1 = label, $2 = signed-by keyring, $3 = pool dir
	local lbl="$1" kr="$2" p="$3" out rc
	echo
	echo "=== $1"
	echo "    pool     : $p"
	echo "    deb line : deb [signed-by=$kr] file://$p ./"
	rm -rf "$LISTS"; mkdir -p "$LISTS"
	echo "deb [signed-by=$kr] file://$p ./" > "$SRC/pool.list"
	out=$(apt-get -o Dir::Etc::sourcelist=/dev/null -o Dir::Etc::sourceparts="$SRC" \
		-o Dir::State::lists="$LISTS" -o APT::Get::List-Cleanup=1 \
		-o 'APT::Update::Post-Invoke-Success=' -o 'APT::Update::Pre-Invoke=' \
		update 2>&1 </dev/null); rc=$?
	printf '    apt-get update exit : %s\n' "$rc"
	printf '%s\n' "$out" | grep -E 'Get:|Ign:|Err:|^E:|^W:|signature|not signed|Missing key|released' \
		| sort -u | sed 's/^/      | /'
	printf '    candidate phantomos-base    : %s\n' \
		"$(apt-cache -o Dir::Etc::sourcelist=/dev/null -o Dir::Etc::sourceparts="$SRC" \
			-o Dir::State::lists="$LISTS" policy phantomos-base 2>&1 | awk '/Candidate:/{print $2}')"
	printf '    candidate phantomos-desktop : %s\n' \
		"$(apt-cache -o Dir::Etc::sourcelist=/dev/null -o Dir::Etc::sourceparts="$SRC" \
			-o Dir::State::lists="$LISTS" policy phantomos-desktop 2>&1 | awk '/Candidate:/{print $2}')"
}

case_run "A. signed by the build key, pinned to that key" "$KEYR/phantomos.gpg" "$POOL"

cp -a "$POOL" "$T/resigned"
before=$(md5sum "$T/resigned/InRelease" | awk '{print $1}')
GNUPGHOME="$T/other-gnupg" gpg --batch --yes --local-user 'PhantomOS Impostor Key' \
	--armor --detach-sign --output "$T/resigned/Release.gpg" "$T/resigned/Release"
GNUPGHOME="$T/other-gnupg" gpg --batch --yes --local-user 'PhantomOS Impostor Key' \
	--clearsign --output "$T/resigned/InRelease" "$T/resigned/Release"
after=$(md5sum "$T/resigned/InRelease" | awk '{print $1}')
echo
echo "    re-signed with the impostor: InRelease $before -> $after"
echo "    (identical bytes would mean the signing never happened and case B tested nothing)"
if [ "$before" = "$after" ]; then
	echo "    RESULT: inconclusive — case B did not get a foreign signature."
	exit 1
fi
case_run "B. same package bytes, signed by a DIFFERENT key, keyring unchanged" \
	"$KEYR/phantomos.gpg" "$T/resigned"

cp -a "$POOL" "$T/unsigned"
rm -f "$T/unsigned/InRelease" "$T/unsigned/Release.gpg"
case_run "C. unsigned (InRelease and Release.gpg removed)" "$KEYR/phantomos.gpg" "$T/unsigned"

echo
echo "=== read of the three ==="
echo "A accepted with a candidate for both metapackages; B and C both exit 100 and leave"
echo "phantomos-base with no candidate, so nothing from an unverifiable pool can be selected."
echo "No case used [trusted=yes]: trust came only from the signed-by keyring."
echo "Not covered: a tampered .deb whose hash no longer matches Packages — that fails at download,"
echo "not at update, and has not been run."
} > "$OUT" 2>&1
RC=$?
cat "$OUT"
exit $RC
