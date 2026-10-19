# WebAssembly core

[← Back to the README](./README.md)

`wasm/` holds a portable C99 port of the trail engine and a browser demo. The build has no libc and no imports, so the module loads with `WebAssembly.instantiateStreaming` and needs nothing else. The compiled module is 1,998 bytes.

The engine renders a photo of a dancer at 360 × 360, then the page scales it up to 720 × 720:

![RetroSilhouetteKit running in the browser](./docs/images/wasm-render.png)

The demo page applies the same pass to a camera, a video file, or a built-in test pattern.

## Layout

```text
wasm/
├── build.sh                 # clang wasm32 build, no libc
├── index.html               # demo page: camera, video file, or test pattern
├── retro_silhouette.wasm    # prebuilt module
├── src/retro_silhouette.c   # the engine
└── test/smoke.mjs           # node smoke test
```

## Build

You need clang with the wasm32 target and `wasm-ld` (package `lld`):

```bash
cd wasm
./build.sh
```

`build.sh` picks the first clang it finds, or the one in `CC`:

```bash
CC=clang-17 ./build.sh
```

Output: `wasm/retro_silhouette.wasm`.

The build needs `-nostdlib -fno-builtin`. Without `-fno-builtin`, clang turns the buffer-clear loop into a `memset` call that a freestanding link cannot resolve.

## API

The module exports one memory and five functions:

| Export | Type | Purpose |
| --- | --- | --- |
| `memory` | `WebAssembly.Memory` | Linear memory that holds all buffers |
| `init_engine(width, height)` | `void` | Set the grid size, clear the history |
| `render_frame(threshold, invert, trails, delay, gradient, blocky, frame_num)` | `void` | Process one frame |
| `get_input_buffer()` | `uint8_t*` | RGBA8 input, `width * height * 4` bytes |
| `get_output_buffer()` | `uint8_t*` | RGBA8 output, same size |
| `get_palette_buffer()` | `uint8_t*` | 33 bytes: 3 background colours, then 8 trail colours |

`render_frame` thresholds the input luma into a mask, writes the mask into a 96-frame history ring, then draws the background gradient and the trail layers. Lower frames are drawn first, so a newer layer covers an older one.

- `threshold` – luma cutoff, 0...255. Below it is foreground.
- `invert` – 1 makes bright pixels the foreground.
- `trails` – number of echo layers, 1...8.
- `delay` – frames between echo layers, 1...12.
- `gradient` – 1 draws the three-colour background gradient.
- `blocky` – 1 adds the macroblock noise.
- `frame_num` – drives the block noise seed.

### Limits

- Maximum grid is **384 × 384** (`MAX_WIDTH` / `MAX_HEIGHT` in the C file). Larger values are clamped. History is 96 masks, so memory grows with the square of the grid.
- The engine has no zoom-cut or audio features. Those are iOS-only.
- Colours come only from the palette buffer. Set it before you render.

## Use from a page

```js
const { instance } = await WebAssembly.instantiateStreaming(
  await fetch('./retro_silhouette.wasm'), {}
);
const api = instance.exports;

const W = 160, H = 160;
api.init_engine(W, H);

// background 0, 1, 2 then eight trail colours, RGB triplets
const palette = new Uint8Array(api.memory.buffer, api.get_palette_buffer(), 33);
palette.set([248, 236, 226], 0);
// ...

api.render_frame(128, 0, 4, 4, 1, 1, 0);

const pixels = new Uint8ClampedArray(
  api.memory.buffer, api.get_output_buffer(), W * H * 4
);
ctx.putImageData(new ImageData(pixels.slice(), W, H), 0, 0);
```

Call `render_frame` once per animation frame with fresh input. The echoes come from the history ring, so a still subject gives no visible trails.

## Demo page

`index.html` fetches the module and runs it on one of three sources:

- **Camera** – `getUserMedia`, front camera.
- **Video file** – any file the browser can play, looped.
- **Test pattern** – a moving shape, for machines without a camera.

The page exposes the threshold, trail count, trail delay, source resolution, mask inversion, gradient, blocky noise, mirroring, and palette cycling.

Browsers block `fetch` for `file://` pages, so serve the folder:

```bash
cd wasm
python3 -m http.server 8000
# open http://localhost:8000/index.html
```

## Tests

```bash
cd wasm
node test/smoke.mjs
```

The smoke test loads the module in node and checks that the input and output buffers are separate, the output alpha is opaque, foreground and background pixels take the palette colours, the invert flag works, the gradient produces valid bytes, and clamped dimensions do not crash.
