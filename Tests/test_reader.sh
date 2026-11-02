#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEMPDIR"' EXIT
python3 Tests/make_test_iso.py "$TEMPDIR/valid.iso"
swiftc BootMaker/ISO9660Reader.swift Tests/ISOReaderTest.swift -o "$TEMPDIR/test_reader"
"$TEMPDIR/test_reader" "$TEMPDIR/valid.iso"
python3 - "$TEMPDIR" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); iso=bytearray((p/'valid.iso').read_bytes())
loader=23*2048
for filename, edits in {
    'bad_pe.iso':[(loader,ord('X'))],
    'windows_exe.iso':[(loader+128+24+68,2)], # Windows GUI subsystem, not EFI application
    'wrong_arch.iso':[(loader+128+4,0x64),(loader+128+5,0xaa)], # ARM64 loader in x64 path
    'invalid_dir.iso':[(20*2048+2+68,255)]
}.items():
    data=bytearray(iso)
    for offset,value in edits: data[offset]=value
    (p/filename).write_bytes(data)
PY
for image in "$TEMPDIR"/bad_pe.iso "$TEMPDIR"/windows_exe.iso "$TEMPDIR"/wrong_arch.iso "$TEMPDIR"/invalid_dir.iso; do
  "$TEMPDIR/test_reader" "$image" --expect-failure
done
printf '✅ 5 pruebas del lector completadas.\n'
