#!/bin/bash
# build.sh - Build KiwiRecorder backend for multiple architectures
set -euo pipefail

DIR=$(dirname "$(realpath "$0")")

echo "⬜ Detecting host architecture..."
HOST_ARCH=$(uname -m)
echo "   → Host architecture: $HOST_ARCH"

# Function to build for a specific Rust target
build_target() {
    local target=$1
    echo "⬜ Building for target: $target"
    cargo build --release --target "$target"
    echo "✅ Build complete: target/$target/release/backend"
}

# Check Rust toolchain
if ! command -v cargo &>/dev/null; then
    echo "❌ Cargo not found. Please install Rust before running this script."
    exit 1
fi

cd "$DIR"

# Ensure necessary targets are installed
echo "⬜ Ensuring Rust targets are installed..."
rustup target add x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu armv7-unknown-linux-gnueabihf

# Install cross-compilers for ARM if missing
case "$HOST_ARCH" in
    x86_64)
        echo "⬜ Installing cross-compilers for ARM..."
        sudo apt update -qq
        sudo apt install -y -qq gcc-aarch64-linux-gnu gcc-arm-linux-gnueabihf
        ;;
    *)
        echo "ℹ️ Host is not x86_64, assuming ARM cross-compiler not needed."
        ;;
esac

# Build binaries for all targets
build_target x86_64-unknown-linux-gnu
build_target aarch64-unknown-linux-gnu
build_target armv7-unknown-linux-gnueabihf

echo "✅ All binaries built successfully."
echo "   x86_64 → target/x86_64-unknown-linux-gnu/release/backend"
echo "   aarch64 → target/aarch64-unknown-linux-gnu/release/backend"
echo "   armv7 → target/armv7-unknown-linux-gnueabihf/release/backend"
