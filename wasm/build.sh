#!/usr/bin/env bash
# Build the WebAssembly core. Produces wasm/retro_silhouette.wasm.
#
# Needs clang with the wasm32 target and wasm-ld (package: lld).
# No libc, no imports: the module exposes its own linear memory and four
# functions, so the host page only needs WebAssembly.instantiateStreaming.
set -euo pipefail

cd "$(dirname "$0")"

OUT=retro_silhouette.wasm
SRC=src/retro_silhouette.c

# Pick the first compiler that can target wasm32.
CC_BIN=${CC:-}
if [ -z "$CC_BIN" ]; then
  for candidate in clang clang-20 clang-19 clang-18 clang-17 clang-16 clang-15; do
    if command -v "$candidate" >/dev/null 2>&1; then
      CC_BIN=$candidate
      break
    fi
  done
fi
if [ -z "$CC_BIN" ]; then
  echo "error: no clang found. Install clang and lld." >&2
  exit 1
fi

# wasm-ld is named after the LLVM version clang was built against, so clang
# looks for e.g. wasm-ld-17 even when plain wasm-ld is installed.
if ! command -v wasm-ld >/dev/null 2>&1 && ! command -v "wasm-ld-${CC_BIN#clang-}" >/dev/null 2>&1; then
  echo "error: wasm-ld not found. Install lld (apt: lld)." >&2
  exit 1
fi

echo "Building $OUT with $CC_BIN..."
# -fno-builtin keeps clang from lowering the buffer-clear loop into a memset
# call, which a freestanding link cannot resolve.
"$CC_BIN" --target=wasm32 -O3 -nostdlib -fno-builtin \
  -Wl,--no-entry \
  -Wl,--export=get_input_buffer \
  -Wl,--export=get_output_buffer \
  -Wl,--export=get_palette_buffer \
  -Wl,--export=init_engine \
  -Wl,--export=render_frame \
  -Wl,--export-memory \
  -o "$OUT" "$SRC"

echo "Built $(pwd)/$OUT ($(wc -c <"$OUT") bytes)"
