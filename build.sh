#!/bin/bash
# Compile all Swift files into one binary: bin/claude-bulb
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p bin
# Build to a new file, then swap it in with mv. Overwriting the binary in place keeps the
# old inode, and macOS then kills the running or next launch with "Code Signature Invalid".
swiftc -O Sources/*.swift -o bin/claude-bulb.new
codesign --force --sign - bin/claude-bulb.new
mv -f bin/claude-bulb.new bin/claude-bulb
echo "built: $(pwd)/bin/claude-bulb"
