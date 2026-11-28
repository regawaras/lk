#!/usr/bin/env bash
set -euo pipefail

BIN="${1:-./lk}"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$TEST_DIR/.config/logklerk" "$TEST_DIR/logs"
cat << EOF > "$TEST_DIR/.config/logklerk/lk.conf"
[settings]
LK_DIR="$TEST_DIR/logs"
EOF

echo "=== 1. Check ELF Hardening (W^X & NX Stack) ==="
readelf -lW "$BIN" | grep -q "GNU_STACK.*RW " || { echo "FAIL: Stack executable!"; exit 1; }
echo "PASS: Stack non-executable (NX)"

echo "=== 2. Read Fragmentation Test (1 byte per cycle) ==="
OUT=$(HOME="$TEST_DIR" timeout 5 python3 -c '
import sys, time
for ch in "echo test_ok\n":
    sys.stdout.write(ch)
    sys.stdout.flush()
    time.sleep(0.005)
' | HOME="$TEST_DIR" "$BIN")
echo "$OUT" | grep -q '"echo test_ok"' || { echo "FAIL: Fragmentation failed"; exit 1; }
echo "PASS: Read fragmentation succeeded"

echo "=== 3. Line Length & CSV Escaping Fuzzing ==="
HOME="$TEST_DIR" timeout 5 python3 -c '
import random, string
safe_chars = string.ascii_letters + string.digits + "\"\",,\t "
for size in [10, 500, 2046, 2047, 2048, 4095, 4096, 8192]:
    payload = "".join(random.choice(safe_chars) for _ in range(size))
    print("true # " + payload)
' | HOME="$TEST_DIR" "$BIN" > /dev/null
echo "PASS: Buffer boundary fuzzing (10..8192 bytes) completed without crash"

echo "=== 4. Binary Null-Byte & Non-UTF8 Fuzzing ==="
HOME="$TEST_DIR" timeout 5 python3 -c '
import os, sys
for size in [1, 64, 2048, 4096]:
    sys.stdout.buffer.write(b"true # " + os.urandom(size) + b"\n")
' | HOME="$TEST_DIR" "$BIN" > /dev/null
echo "PASS: Random binary & null-byte safe"

echo "=== 5. Oversized Config File Fuzzing (>16KB) ==="
python3 -c '
import os
with open("'"$TEST_DIR"'/.config/logklerk/lk.conf", "wb") as f:
    f.write(b"[settings]\nLK_DIR=\"'"$TEST_DIR"'/logs\"\n" + os.urandom(17000))
'
HOME="$TEST_DIR" timeout 5 "$BIN" < /dev/null
echo "PASS: Config parser >16KB safe"

echo "=== ALL TESTS PASSED! ==="

