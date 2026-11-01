#!/bin/bash
# init-signing-key.sh — create or reuse the local GPG key that signs the build pool,
# and export its public half into the repo.
#
# What this key is: a BUILD key. It signs the pool of our own metapackages on this
# machine. It is created without a passphrase because it is not the key §8 describes;
# §8's offline master, its custody procedure and rotation plan belong to M5, together
# with the hosting decision in §12 item 3 that decides where a published repo lives at
# all. Nothing published to a friend is signed by this key, and no claim in this repo
# says otherwise.
#
# The private half stays outside the tree at $PHANTOMOS_KEYDIR (default
# /root/phantomos-key). Only the armored public key is committed, at
# live/config/archives/phantomos.key.chroot: live-build installs that into the build
# chroot so apt can verify the pool, and scripts/build-packages.sh dearmors the same
# file into phantomos-release's /usr/share/keyrings. One key, one source, no drift.
#
# Usage: scripts/init-signing-key.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEYDIR="${PHANTOMOS_KEYDIR:-/root/phantomos-key}"
UID_NAME="PhantomOS Archive Signing Key"
UID_COMMENT="build key, not the release key"
UID_EMAIL="root@localhost"
PUBOUT="$ROOT/live/config/archives/phantomos.key.chroot"

mkdir -p "$KEYDIR"
chmod 700 "$KEYDIR"

if GNUPGHOME="$KEYDIR" gpg --batch --list-secret-keys "$UID_NAME" 2>/dev/null | grep -q '^sec'; then
	echo "reusing existing build key in $KEYDIR"
else
	echo "creating build key in $KEYDIR (no passphrase — see the header of this script)"
	GNUPGHOME="$KEYDIR" gpg --batch --gen-key - <<EOF
Key-Type: RSA
Key-Length: 3072
Key-Usage: sign
Name-Real: $UID_NAME
Name-Comment: $UID_COMMENT
Name-Email: $UID_EMAIL
Expire-Date: 0
%no-protection
%commit
EOF
fi

mkdir -p "$(dirname "$PUBOUT")"
GNUPGHOME="$KEYDIR" gpg --batch --armor --export "$UID_NAME" > "$PUBOUT"
echo "public key exported -> $PUBOUT"
GNUPGHOME="$KEYDIR" gpg --batch --list-keys --with-colons "$UID_NAME" | awk -F: '/^fpr/ {print "fingerprint: " $10; exit}'
