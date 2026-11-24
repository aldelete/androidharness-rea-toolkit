#!/bin/bash
# rea-toolkit installer — runs inside the app's proot Linux container.
# Expects the release archive to be already extracted at $HERE/../payload
# (toolkit/ and payload/ siblings). Uses rename(2) where possible so the
# install is fast and keeps symlinks intact.
# Protocol: STEP:<id> / STEPOK:<id> / RESULT:OK / RESULT:FAIL:<id>:<msg>
set -uo pipefail

PREFIX="${PREFIX:-/data/user/0/com.q2r.andbuld.app/files/linux}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${SRC:-$HERE/../payload}"
VERSION="$(cat "$HERE/VERSION" 2>/dev/null || echo 0.0.0)"
BOOT_PREFIX="/data/local/tmp/androidharness/com.q2r.andbuld.app/linux"

G="$PREFIX/opt/ghidra_12.2_PUBLIC"
J="$PREFIX/lib/jvm/java-25-openjdk"
JADX="$PREFIX/opt/jadx/jadx-headless-mcp-0.7.1-all.jar"
REA="$PREFIX/lib/node_modules/rea-agents"
MARK="$PREFIX/.harness-toolkit.json"

fail() { echo "RESULT:FAIL:$1:$2"; exit 1; }
step() { echo "STEP:$1"; }
stepok() { echo "STEPOK:$1"; }

[ -d "$PREFIX" ] || fail preflight "prefix not found: $PREFIX"
[ -d "$SRC" ] || fail preflight "payload not found: $SRC"
case "$(uname -m)" in aarch64|arm64) ;; *) fail preflight "unsupported arch $(uname -m)";; esac

mkdir -p "$PREFIX/tmp" "$PREFIX/bin" "$PREFIX/opt" "$PREFIX/lib/node_modules" "$PREFIX/lib/jvm"
AVAIL_KB=$(df -Pk "$PREFIX" | awk 'NR==2{print $4}')
[ "${AVAIL_KB:-0}" -ge 400000 ] || fail preflight "not enough free space (need ~400MB after extraction, have $((AVAIL_KB/1024))MB)"

########################################
step node
cp -f "$SRC/node/bin/node" "$PREFIX/bin/node" || fail node "copy node"
[ -f "$SRC/node/bin/npx" ] && cp -f "$SRC/node/bin/npx" "$PREFIX/bin/npx"
rm -rf "$PREFIX/lib/node_modules/npm"
mv "$SRC/node/lib/node_modules/npm" "$PREFIX/lib/node_modules/npm" || fail node "move npm"
chmod 755 "$PREFIX/bin/node" "$PREFIX/bin/npx" 2>/dev/null
ln -sf ../lib/node_modules/npm/bin/npm-cli.js "$PREFIX/bin/npm"
for f in "$PREFIX/bin/npm" "$PREFIX/bin/npx" "$PREFIX/lib/node_modules/npm/bin/"*.js; do
  [ -f "$f" ] || continue
  sed -i "1s|^#!.*|#!$PREFIX/bin/node|" "$f" 2>/dev/null || true
done
stepok node

########################################
step rea
cd "$PREFIX" || fail rea "cd prefix"
"$PREFIX/bin/node" "$PREFIX/lib/node_modules/npm/bin/npm-cli.js" \
  install -g "$SRC/rea-agents-6.9.0.tgz" \
  --prefix "$PREFIX" --offline --no-audit --no-fund --loglevel=error \
  >"$PREFIX/tmp/rea-npm.log" 2>&1 || fail rea "npm install failed (see tmp/rea-npm.log)"
[ -d "$REA" ] || fail rea "rea-agents missing after install"
ln -sf ../lib/node_modules/rea-agents/scripts/rea.mjs "$PREFIX/bin/rea"
stepok rea

########################################
step overlay
rm -rf "$REA/dist"
cp -R "$SRC/rea-patch/dist" "$REA/dist" || fail overlay "copy dist"
cp -f "$SRC/rea-patch/scripts/lib/cli-process-environment.mjs" "$REA/scripts/lib/cli-process-environment.mjs" || fail overlay "copy env"
sed -i "s#^const __acb = \".*\";#const __acb = \"$PREFIX\";#" "$REA/scripts/lib/cli-process-environment.mjs" || fail overlay "rewrite __acb"
stepok overlay

########################################
step ghidra
rm -rf "$G"
mv "$SRC/ghidra" "$G" || fail ghidra "move ghidra"
chmod 755 "$G"/*.sh "$G"/support/*.sh 2>/dev/null || true
stepok ghidra

########################################
step jvm
rm -rf "$J"
mv "$SRC/jvm" "$J" || fail jvm "move jvm"
chmod 755 "$J/bin/"* 2>/dev/null || true
stepok jvm

########################################
step jadx
mkdir -p "$PREFIX/opt/jadx"
mv -f "$SRC/jadx.jar" "$JADX" || fail jadx "move jadx"
stepok jadx

########################################
step decompile
mkdir -p "$G/Ghidra/Features/Decompiler/os/linux_arm_64"
mv -f "$SRC/decompile" "$G/Ghidra/Features/Decompiler/os/linux_arm_64/decompile" || fail decompile "move decompile"
chmod 755 "$G/Ghidra/Features/Decompiler/os/linux_arm_64/decompile" || fail decompile "chmod"
stepok decompile

########################################
step ps
if [ -f "$PREFIX/bin/ps" ] && ! grep -q 'ps shim' "$PREFIX/bin/ps" 2>/dev/null; then
  mv "$PREFIX/bin/ps" "$PREFIX/bin/ps.procps"
fi
cat > "$PREFIX/bin/ps" <<EOF
#!$PREFIX/bin/bash
# ps shim: emulate "ps -axo pid=,ppid=,pgid=,uid=,stat=,command=" with Android toybox ps
/system/bin/ps -A -o pid,ppid,pgid,uid,stat,args 2>/dev/null | tail -n +2
EOF
chmod 755 "$PREFIX/bin/ps"
stepok ps

########################################
step prefix
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  case "$rel" in
    ghidra/*) t="$G/${rel#ghidra/}" ;;
    jvm/*)    t="$J/${rel#jvm/}" ;;
    node/*)   t="$PREFIX/${rel#node/}" ;;
    *)        t="$PREFIX/$rel" ;;
  esac
  [ -f "$t" ] && sed -i "s#@PREFIX@#$PREFIX#g" "$t" 2>/dev/null || true
done < "$SRC/PREFIX_FILES.txt"
grep -rIl --binary-files=without-match "$BOOT_PREFIX" "$PREFIX/bin" "$PREFIX/lib/node_modules/npm" 2>/dev/null |
  while IFS= read -r f; do sed -i "s#$BOOT_PREFIX#$PREFIX#g" "$f"; done
stepok prefix

########################################
step doctor
"$PREFIX/bin/node" "$REA/scripts/rea.mjs" doctor > "$PREFIX/tmp/rea-doctor.log" 2>&1
DOC=$?
tail -n 40 "$PREFIX/tmp/rea-doctor.log"
[ $DOC -eq 0 ] || echo "WARN:doctor exit=$DOC"
stepok doctor

########################################
step marker
cat > "$MARK" <<EOF
{"toolkit":"rea-android-toolkit","version":"$VERSION","prefix":"$PREFIX","installed_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF
stepok marker
echo "RESULT:OK"
