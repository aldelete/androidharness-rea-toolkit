#!/bin/bash
# rea-toolkit acceptance checks. Exit 0 only if every check passes.
PREFIX="${PREFIX:-/data/user/0/com.q2r.andbuld.app/files/linux}"
G="$PREFIX/opt/ghidra_12.2_PUBLIC"
J="$PREFIX/lib/jvm/java-25-openjdk"
REA="$PREFIX/lib/node_modules/rea-agents"
fail=0
ok() { echo "PASS: $1"; }
no() { echo "FAIL: $1"; fail=1; }

[ -x "$PREFIX/bin/node" ] && ok "node binary" || no "node binary"
[ -x "$J/bin/java" ] && ok "java 25" || no "java 25"
[ -x "$G/support/analyzeHeadless" ] && ok "ghidra headless" || no "ghidra headless"
[ -x "$G/Ghidra/Features/Decompiler/os/linux_arm_64/decompile" ] && ok "arm64 decompiler" || no "arm64 decompiler"
[ -s "$PREFIX/opt/jadx/jadx-headless-mcp-0.7.1-all.jar" ] && ok "jadx jar" || no "jadx jar"
[ -d "$REA/dist" ] && ok "rea dist" || no "rea dist"
grep -q 'ANDROID_CONTAINER_DEFAULTS_v1' "$REA/scripts/lib/cli-process-environment.mjs" 2>/dev/null && ok "android defaults" || no "android defaults"
grep -q 'ps shim' "$PREFIX/bin/ps" 2>/dev/null && ok "ps shim" || no "ps shim"

if [ $fail -eq 0 ]; then echo "VERIFY:OK"; else echo "VERIFY:FAIL"; fi
exit $fail
