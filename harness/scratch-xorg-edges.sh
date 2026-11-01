set -u
export LC_ALL=C
REPO=/mnt/c/Users/INFINITY/OneDrive/Desktop/phantomOS

echo "=== clock ==="; date -u +%Y-%m-%dT%H:%M:%SZ
sort -u "$REPO/logs/M1-image-installed.txt" > /tmp/installed
echo "image packages: $(wc -l < /tmp/installed)"

echo
echo "############ 1. reverse-Depends of the three X-server names, inside the image only ############"
for target in xserver-xorg-core xserver-xorg xorg; do
  echo "--- who in the image hard-Depends on $target ?"
  for f in /var/lib/apt/lists/*Packages; do
    [ -f "$f" ] || continue
    awk -v T="$target" 'BEGIN{RS=""}
      { n=split($0,L,"\n"); pkg=""; dep=""
        for(i=1;i<=n;i++){
          if(L[i] ~ /^Package: /) pkg=substr(L[i],10)
          if(L[i] ~ /^Depends: /) dep=substr(L[i],10)
        }
        if(pkg=="") next
        re="(^| )" T "( |,|\\||$)"
        if(dep ~ re) print pkg
      }' "$f"
  done | sort -u > /tmp/rd
  echo "    archive-wide: $(wc -l < /tmp/rd)   in-image: $(comm -12 /tmp/rd /tmp/installed | wc -l)"
  comm -12 /tmp/rd /tmp/installed | sed 's/^/      in image: /'
done

echo
echo "############ 2. the xterm alternative, resolved ############"
echo "    xorg Depends on: xterm | x-terminal-emulator"
echo "    xterm in image:        $(grep -cx 'xterm' /tmp/installed)"
echo "    x-terminal-emulator:   $(grep -cx 'x-terminal-emulator' /tmp/installed)  (virtual)"
echo "    who provides x-terminal-emulator in the image:"
for f in /var/lib/apt/lists/*Packages; do
  awk 'BEGIN{RS=""}
    { n=split($0,L,"\n"); pkg=""; prov=""
      for(i=1;i<=n;i++){
        if(L[i] ~ /^Package: /)  pkg=substr(L[i],10)
        if(L[i] ~ /^Provides: /) prov=substr(L[i],11)
      }
      if(prov ~ /(^| |,)x-terminal-emulator( |,|$)/) print pkg
    }' "$f"
done | sort -u > /tmp/prov
comm -12 /tmp/prov /tmp/installed | sed 's/^/      /'

echo
echo "############ 3. versions, for §3.1 ############"
for p in xorg xserver-xorg xserver-xorg-core lightdm light-locker xinit x11-common xfce4; do
  v=$(apt-cache show "$p" 2>/dev/null | sed -n '1,/^$/p' | sed -n 's/^Version: //p' | head -1)
  printf '    %-22s %s\n' "$p" "${v:-?}"
done
echo "    -- as run M actually unpacked them (its log's Unpacking lines):"
grep -o 'Unpacking \(xorg\|xserver-xorg-core\|xserver-xorg\|lightdm\|xinit\|x11-common\) ([^)]*)' \
  "$REPO/logs/M1-lb-build-runM.log" | sort -u | sed 's/^/      /'

echo
echo "############ 4. §5's own text: the line xorg is missing from ############"
grep -n 'lightdm, light-locker' "$REPO/docs/SPEC.md" | cut -c1-200 | sed 's/^/    /'
echo "    -- any X-server token anywhere in §5 (SPEC lines 142-342):"
sed -n '142,342p' "$REPO/docs/SPEC.md" \
  | grep -niE 'xorg|xserver|x11|x server|display server' | cut -c1-160 | sed 's/^/      /' \
  || echo "      (none)"

echo
echo "=== hygiene ==="
echo "mounts matching phantomos: $(grep -c phantomos /proc/mounts)"
echo "wrapper: $(pgrep -af 'build-iso.running' | head -1)"
NL=$(ls -t /root/phantomos-m1/logs/lb-build-*.log | head -1)
echo "run N: $(wc -l < "$NL") lines, $(grep -c '^E:' "$NL" || true) E: lines, last stage: $(grep '^\[20.*\] lb ' "$NL" | tail -1 | cut -c1-70)"
