#!/bin/bash
# boot-test.sh — headless QEMU boot test for a built image, with photographed evidence.
#
# This is M0's throwaway run scripts (logs/§9 runs A, E, F, G, H, I, J) turned into one
# reusable harness. Everything non-obvious in here is a lesson that cost a run:
#
#   -monitor, not -qmp:              the runs used the human monitor; commands are plain
#                                    strings. `info accelerators` is NOT a valid command —
#                                    `info kvm` is (§9).
#   -display none + screendump:      there is no X here. Frames come out as PPM and are
#                                    converted with pnmtopng. A frame that is missing is
#                                    logged as MISSING rather than silently skipped.
#   sendkey ret, not enter:          "enter" is not a keysym.
#   the keysym table below:          "/", ".", "-", "=", " " and capitals have no direct
#                                    keysym and must be spelled (shift-X, spc, slash…).
#                                    Any character that is not in the table is REPORTED,
#                                    not dropped: run G typed into a blank console and run
#                                    J turned `fw_platform_size` into `fwuplatformsize`,
#                                    and in both cases nothing complained (§9).
#   four bugs this file had, all found by running it (2026-11-01, its first real run) — and a
#                                    fifth, found 2026-11-01T18:32Z while testing the overwrite
#                                    guard below, which is also what proved the fourth's fix had
#                                    never executed:
#                                    the backslash pattern was written `"\")`, where the
#                                    escaped quote never closes the string, so bash consumed
#                                    `)   key="` as part of it and the file did not parse at
#                                    all — `bash -n` is the check, and it is now clean. It is
#                                    `"\\")`. And `*` was absent from the table, which
#                                    harness/commands/M1.txt types in `regulatory.db*`; the
#                                    pre-flight that walks every distinct character in the
#                                    command file against this table is what caught it, which
#                                    is the reporting above working as designed rather than
#                                    the run silently losing a glob as run J lost underscores.
#                                    The third is in qemu_base below and outlived both checks.
#                                    The fourth is in shot(): the screendump file is written
#                                    asynchronously, and converting it the instant the monitor
#                                    command returns produced twelve empty PNGs and two
#                                    MISSING frames in one run. shot() now waits for the size
#                                    to settle and checks the converter's exit status — but that
#                                    fix did not run when it was written. It declared
#                                    `local label="$1" ppm="…-$label…"` in one statement, and
#                                    bash expands every word of a `local` before assigning any
#                                    of them, so shot() died on its own first line under this
#                                    file's `set -u`. Every frame in logs/evidence/M1-boot-* was
#                                    therefore taken by the pre-fix body, which is consistent
#                                    with run M's log having 2 MISSING and no settle behaviour.
#                                    Split into two `local`s and re-run 2026-11-01T18:36Z: two
#                                    correctly-named frames, md5 and dims logged, exit 0. The
#                                    settle loop has still never met a truncated 3 MB frame, so
#                                    the bug it targets is not yet shown fixed.
#   --run names the evidence, so    this file used to `rm -rf "$OUTROOT/$RUN"` unconditionally,
#   it must not be reused:          and --run is also the filename prefix of every frame. Reusing
#                                    a name deleted that run's photographs and said nothing about
#                                    it. Run M's 74 frames are the evidence behind
#                                    logs/M1-no-live-user.txt, and logs/evidence/ holds them under
#                                    the same fixed names — so a second `--run M1-boot` would
#                                    destroy them on the host and then overwrite the repo's copies
#                                    with different pictures under the names older write-ups cite.
#                                    It now refuses a non-empty run directory unless
#                                    PHANTOMOS_ALLOW_RUN_OVERWRITE=1. All three branches were run,
#                                    the destructive one against a copy: see
#                                    logs/M1-boot-overwrite-guard.txt.
#   a blank frame is not a hang:     run G was read as a hang and was not. Look at the
#                                    PNGs; a changing hash proves nothing about the guest.
#   boot waits are generous:         240 s to a live shell on a 2 vCPU i5-6200U under KVM.
#   serial mode needs direct kernel boot: a live ISO puts no getty on ttyS0 by itself;
#                                    the runs that used a serial transcript booted
#                                    vmlinuz+initrd with -append console=ttyS0,115200n8.
#
# Usage:
#   harness/boot-test.sh --iso IMAGE --mode bios|uefi|serial --run NAME [--out DIR]
#                        [--wait SECS] [--commands FILE] [--kernel VMLINUZ] [--initrd INITRD]
#                        [--cmdline "boot=live components …"]
#
# Output: $RUN_DIR/<run>-<label>.png + $RUN_DIR/<run>-<label>.ppm, a .log of every frame
# with its hash and dimensions, and for serial mode a transcript.txt.

set -u

ISO="" MODE="" RUN="" OUTROOT="${PHANTOMOS_TESTDIR:-/root/phantomos-tests}"
WAIT=240 KERNEL="" INITRD="" CMDEDIT="" CMDLINE="boot=live components quiet splash console=ttyS0,115200n8"
: > /tmp/boot-test-cmds.$$ ; CMDS="/tmp/boot-test-cmds.$$"

while [ $# -gt 0 ]; do
	case "$1" in
		--iso) ISO="$2"; shift 2 ;;
		--mode) MODE="$2"; shift 2 ;;
		--run) RUN="$2"; shift 2 ;;
		--out) OUTROOT="$2"; shift 2 ;;
		--wait) WAIT="$2"; shift 2 ;;
		--kernel) KERNEL="$2"; shift 2 ;;
		--initrd) INITRD="$2"; shift 2 ;;
		--cmdline) CMDEDIT="$2"; shift 2 ;;
		--commands) CMDS="$2"; shift 2 ;;
		*) echo "E: unknown argument: $1" >&2; exit 2 ;;
	esac
done
[ -n "$CMDEDIT" ] && CMDLINE="$CMDEDIT"

for need in "$ISO"; do [ -f "$need" ] || { echo "E: missing file: $need" >&2; exit 2; }; done
case "$MODE" in bios|uefi|serial) ;; *) echo "E: --mode must be bios, uefi or serial" >&2; exit 2 ;; esac
if [ "$MODE" = serial ]; then
	[ -f "$KERNEL" ] && [ -f "$INITRD" ] || { echo "E: serial mode needs --kernel and --initrd" >&2; exit 2; }
fi

W="$OUTROOT/$RUN"
# Refuse to replace a run directory that already has contents. `--run` is caller-supplied and is
# also the filename prefix of every frame this writes ($RUN-<label>.png), so reusing a name does
# not just collide — it deletes the previous run's photographs before taking new ones. This is the
# same fixed-name defect §11 now has a rule about, and the loss here is worse than a wrong
# citation: /root/phantomos-tests/M1-boot holds run M's 74 frames, the only photographs of the
# no-login defect (logs/M1-no-live-user.txt), and logs/evidence/ carries the same fixed names, so a
# second `--run M1-boot` destroys them on the host and then overwrites them in the repo when the
# new frames are copied in. Give each run its own name. Measured 2026-11-01T18:35Z:
# logs/M1-boot-overwrite-guard.txt.
if [ -d "$W" ] && [ -n "$(ls -A "$W" 2>/dev/null)" ]; then
	if [ "${PHANTOMOS_ALLOW_RUN_OVERWRITE:-0}" != 1 ]; then
		echo "E: refusing to start — $W exists and holds $(ls -A "$W" | wc -l) entries." >&2
		echo "   --run is the filename prefix for every frame this writes, so reusing the name" >&2
		echo "   replaces that run's evidence. Pick a name nobody has used, or set" >&2
		echo "   PHANTOMOS_ALLOW_RUN_OVERWRITE=1 to re-shoot this one deliberately." >&2
		exit 2
	fi
	echo "W: PHANTOMOS_ALLOW_RUN_OVERWRITE=1 — replacing $(ls -A "$W" | wc -l) entries in $W." >&2
	rm -rf "$W"
fi
mkdir -p "$W"
SOCK="$W/monitor.sock"
LOG="$W/$RUN.log"
PIDF="$W/qemu.pid"
MON() { printf '%s\n' "$1" | timeout 15 socat - "UNIX-CONNECT:$SOCK" 2>/dev/null | tr -d '\r'; }

shot() {
	local label="$1"
	# Two `local` statements where this used to be one. `local a="$1" b="…$a…"` expands every
	# word before it assigns any of them, so `$label` was read before `label` existed. Under this
	# file's `set -u` that is `label: unbound variable` and the function dies on its first line;
	# with a global `label` in scope it is worse — it silently expands to the stale value and
	# writes the frame under the wrong name. Both measured 2026-11-01 on bash 5.2.37
	# (exit 127, and "x-STALE" from the same construct with a pre-existing global).
	#
	# The consequence is worth stating because the header above claims this body was the fix for
	# the truncated-frame bug: it was, and it could not run. Run M's 74 frames were taken by the
	# pre-fix body, which is why its log has 2 MISSING and no settle-loop behaviour in it at all.
	# Found not by a boot run but by the overwrite-guard test below, which invokes this file with
	# a fresh --run and so reaches shot() (logs/M1-boot-overwrite-guard.txt).
	local ppm="$W/$RUN-$label.ppm" png="$W/$RUN-$label.png" s1 s2 i
	MON "screendump $ppm" >/dev/null
	# QEMU writes the screendump file asynchronously: the monitor command returns before
	# the PPM is on disk in full. One run (2026-11-01) showed both faces of it — cmd-22 and
	# cmd-25 reached the MISSING branch because the file did not exist yet, and twelve
	# other frames converted a *truncated* PPM into a 0-byte PNG while their md5, taken a
	# moment later from the finished file, looked perfectly healthy. A frame whose header
	# reads fine but whose body is half-written is worse than a missing one, because the
	# log line for it lies. Wait for the size to stop changing before trusting the file.
	for i in $(seq 20); do
		if [ -s "$ppm" ]; then
			s1=$(stat -c%s "$ppm"); sleep 0.5; s2=$(stat -c%s "$ppm")
			[ "$s1" = "$s2" ] && break
		fi
		sleep 0.5
	done
	if [ ! -s "$ppm" ]; then
		printf '%s frame %s MISSING\n' "$(date -Is)" "$label" >> "$LOG"
	elif pnmtopng < "$ppm" > "$png" 2>/dev/null && [ -s "$png" ]; then
		printf '%s frame %s md5=%s dims=%s\n' "$(date -Is)" "$label" \
			"$(md5sum "$ppm" | cut -c1-8)" "$(sed -n 2p "$ppm")" >> "$LOG"
	else
		printf '%s frame %s CONVERT-FAILED (ppm present, png empty)\n' "$(date -Is)" "$label" >> "$LOG"
	fi
}

# type_line <text> — one keysym per character, then Enter. Unmappable characters are
# written to the log as UNMAPPED so a silently-vanishing keystroke cannot become evidence.
type_line() {
	local s="$1" i c key out=""
	for ((i=0; i<${#s}; i++)); do
		c="${s:i:1}"
		case "$c" in
			" ")   key="spc" ;;
			"/")   key="slash" ;;
			"-")   key="minus" ;;
			".")   key="dot" ;;
			",")   key="comma" ;;
			";")   key="semicolon" ;;
			"=")   key="equal" ;;
			"*")   key="shift-8" ;;
			"_")   key="shift-minus" ;;
			"|")   key="shift-backslash" ;;
			"\\")  key="backslash" ;;
			":")   key="shift-semicolon" ;;
			[A-Z]) key="shift-${c,,}" ;;
			[a-z0-9]) key="$c" ;;
			*) MON "sendkey $c" >/dev/null 2>&1 || true
			   printf 'UNMAPPED character %s in "%s" — sent raw, check the frame\n' "'$c'" "$s" >> "$LOG"
			   continue ;;
		esac
		MON "sendkey $key" >/dev/null
		printf '%s' "$c" >> "$W/typed.txt"
		sleep 0.15
	done
	printf '\n' >> "$W/typed.txt"
	MON "sendkey ret" >/dev/null
}

# Element 0 is the binary. It was missing until the third run (2026-11-01), so every
# invocation expanded to `-name M1-boot -m 1024 …` and bash tried to execute `-name`,
# reporting only "line 153: -name: command not found" — which reads like a broken argument
# and is a missing program. M0's runs A–J worked because they were separate throwaway
# scripts that each named qemu-system-x86_64; consolidating them dropped it. `bash -n`
# cannot see this and neither can a keysym pre-flight, so it survived two checks.
qemu_base=(qemu-system-x86_64 -name "$RUN" -m 1024 -smp 2 -accel kvm -display none
           -monitor "unix:$SOCK,server,nowait" -pidfile "$PIDF" -daemonize)

printf '#### %s start %s mode=%s iso=%s\n' "$RUN" "$(date -Is)" "$MODE" "$ISO" >> "$LOG"
sha256sum "$ISO" | sed 's/^/#### image sha256 /' >> "$LOG"

if [ "$MODE" = serial ]; then
	SER="$W/serial.sock"
	# -append needs the kernel and initrd outside the ISO; extract them from the build
	# tree or with: xorriso -osirrox on -indev IMAGE -extract / live && cat live/initrd*
	"${qemu_base[@]}" -kernel "$KERNEL" -initrd "$INITRD" -append "$CMDLINE" \
		-cdrom "$ISO" -serial "unix:$SER,server,nowait" 2> "$W/qemu.err" || {
			cat "$W/qemu.err" >> "$LOG"; exit 1; }
	# the transcript is the evidence; the input is fed from the commands file
	( while IFS= read -r line; do
		case "$line" in KEY:*|\#*|"") continue ;; esac
		printf '%s\n' "$line" >> "$W/typed.txt"; sleep 30
	  done < "$CMDS" ) \
		| timeout $((WAIT + 240)) socat - "UNIX-CONNECT:$SER" > "$W/transcript.txt" 2> "$W/socat.err" &
	SERPID=$!
elif [ "$MODE" = uefi ]; then
	cp /usr/share/OVMF/OVMF_VARS_4M.fd "$W/OVMF_VARS.fd"
	"${qemu_base[@]}" -machine q35 \
		-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
		-drive if=pflash,format=raw,file="$W/OVMF_VARS.fd" -cdrom "$ISO" 2> "$W/qemu.err" || {
			cat "$W/qemu.err" >> "$LOG"; exit 1; }
else
	"${qemu_base[@]}" -cdrom "$ISO" 2> "$W/qemu.err" || { cat "$W/qemu.err" >> "$LOG"; exit 1; }
fi

sleep 5
printf '%s info kvm -> %s\n' "$(date -Is)" "$(MON 'info kvm' | tr '\n' ' ')" >> "$LOG"
printf '%s info status -> %s\n' "$(date -Is)" "$(MON 'info status' | tr '\n' ' ')" >> "$LOG"

# the isolinux/grub menu is dismissed with a single Enter; runs A/E/H proved that
sleep 25
MON 'sendkey ret' >/dev/null
printf '%s menu dismissed (sendkey ret)\n' "$(date -Is)" >> "$LOG"

elapsed=25
while [ "$elapsed" -lt "$WAIT" ]; do
	next=$(( elapsed + 60 )); [ "$next" -gt "$WAIT" ] && next=$WAIT
	sleep $(( next - elapsed )); elapsed=$next
	[ "$MODE" = serial ] || shot "boot-$elapsed"
done

# wake the prompt (Enter on an empty line is harmless) and run the evidence commands
MON 'sendkey ret' >/dev/null; sleep 2; MON 'sendkey ret' >/dev/null; sleep 3
[ "$MODE" = serial ] || shot "wake"
n=0
while IFS= read -r cmd; do
	[ -n "$cmd" ] || continue
	case "$cmd" in
		KEY:*)
			# raw key combo, e.g "KEY: ctrl-alt-f2" to leave the graphical VT. Not a
			# typed character, so it gets no entry in typed.txt.
			MON "sendkey ${cmd#KEY: }" >/dev/null
			printf '%s sent key %s\n' "$(date -Is)" "${cmd#KEY: }" >> "$LOG"
			continue ;;
		\#*) continue ;;
	esac
	n=$((n+1))
	[ "$MODE" = serial ] || type_line "$cmd"
	sleep 5
	[ "$MODE" = serial ] || shot "cmd-$n"
done < "$CMDS"

[ "$MODE" = serial ] || shot "end"
printf '%s commands sent: %s\n' "$(date -Is)" "$n" >> "$LOG"
MON 'quit' >/dev/null; sleep 3
[ -f "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null
[ -n "${SERPID:-}" ] && kill "$SERPID" 2>/dev/null
printf '#### %s done %s\n' "$(date -Is)" "$RUN" >> "$LOG"
( cd "$W" && sha256sum *.png transcript.txt 2>/dev/null > "$RUN.artifacts-sha256.txt" )
echo "run dir: $W"
ls "$W"
