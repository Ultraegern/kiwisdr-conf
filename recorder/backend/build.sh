#!/bin/bash

set -euo pipefail

DIR=$(dirname "$(realpath "$0")")

HOST_ARCH=$(uname -m)
echo "⬜ Host architecture: $HOST_ARCH"

# Rust targets
TARGETS=("x86_64-unknown-linux-gnu" "aarch64-unknown-linux-gnu" "armv7-unknown-linux-gnueabihf")

echo "⬜ Ensuring Rust targets are installed..."
for target in "${TARGETS[@]}"; do
    rustup target add "$target" || true
done

# Install cross-compilers if missing
echo "⬜ Installing cross-compilers for ARM..."
if ! dpkg -s gcc-aarch64-linux-gnu &>/dev/null; then
    sudo apt update
    sudo apt install -y gcc-aarch64-linux-gnu
fi
if ! dpkg -s gcc-arm-linux-gnueabihf &>/dev/null; then
    sudo apt install -y gcc-arm-linux-gnueabihf
fi
if ! dpkg -s binutils-aarch64-linux-gnu &>/dev/null; then
    sudo apt install -y binutils-aarch64-linux-gnu
fi

# Setup Cargo config for cross-linking
mkdir -p .cargo
cat > .cargo/config.toml <<EOL
[target.aarch64-unknown-linux-gnu]
linker = "aarch64-linux-gnu-gcc"

[target.armv7-unknown-linux-gnueabihf]
linker = "arm-linux-gnueabihf-gcc"
EOL

# Build function (runs in background)
build_target() {
    local target=$1
    echo "⬜ Building for target: $target"
    cargo build --release --target "$target" --manifest-path "$DIR/Cargo.toml"
    echo "✅ Build complete: target/$target/release/backend"
}

# Build all targets in parallel
pids=()
for target in "${TARGETS[@]}"; do
    build_target "$target" &
    pids+=($!)
done

# Wait for all builds to complete
for pid in "${pids[@]}"; do
    wait "$pid"
done

echo "✅ All builds completed successfully!"
sleep 5 