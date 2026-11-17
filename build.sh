#!/bin/bash
# Compile all Swift files into one binary: bin/claude-bulb
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p bin
swiftc -O Sources/*.swift -o bin/claude-bulb
echo "built: $(pwd)/bin/claude-bulb"
