#!/bin/bash

set -euo pipefail

case "${PLATFORM_NAME:-}" in
  iphoneos)
    rust_target="aarch64-apple-ios"
    ;;
  iphonesimulator)
    if [[ "${CURRENT_ARCH:-arm64}" == "x86_64" ]]; then
      rust_target="x86_64-apple-ios"
    else
      rust_target="aarch64-apple-ios-sim"
    fi
    ;;
  *)
    echo "Unsupported Apple platform: ${PLATFORM_NAME:-unknown}" >&2
    exit 1
    ;;
esac

export CARGO_TARGET_DIR="${DERIVED_FILE_DIR}/rust-target"
rustup target add "$rust_target"
cargo rustc \
  --manifest-path "$SRCROOT/Vendor/sdk/Cargo.toml" \
  --target "$rust_target" \
  --release \
  --features server \
  -- \
  --crate-type staticlib

source_library="$(
  find "$CARGO_TARGET_DIR/$rust_target/release" \
    -type f \
    \( -name 'libahutong_rs.a' -o -name 'libahutong_rs-*.a' \) \
    -print \
    -quit
)"
if [[ -z "$source_library" ]]; then
  echo "Rust static library was not found under $CARGO_TARGET_DIR/$rust_target/release" >&2
  find "$CARGO_TARGET_DIR/$rust_target/release" -maxdepth 2 -type f -name '*ahutong*' -print >&2
  exit 1
fi
cp "$source_library" "$BUILT_PRODUCTS_DIR/libahutong_rs.a"
