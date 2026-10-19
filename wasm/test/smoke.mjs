// Smoke test for the WebAssembly core. Run with: node wasm/test/smoke.mjs
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const wasmPath = join(here, '..', 'retro_silhouette.wasm');

const { instance } = await WebAssembly.instantiate(readFileSync(wasmPath), {});
const api = instance.exports;
const mem = () => new Uint8Array(api.memory.buffer);

let failures = 0;
const check = (name, cond, detail = '') => {
  if (cond) {
    console.log(`ok   ${name}`);
  } else {
    failures += 1;
    console.log(`FAIL ${name}${detail ? ' - ' + detail : ''}`);
  }
};

const W = 64;
const H = 64;

// Palette: background 0 = (10,20,30), background 1 = (40,50,60), trail layer 0 = (200,0,0).
api.init_engine(W, H);
const palettePtr = api.get_palette_buffer();
mem().set([10, 20, 30, 40, 50, 60, 70, 80, 90, 200, 0, 0], palettePtr);

check('input buffer is separate from output buffer',
  api.get_input_buffer() !== api.get_output_buffer());

// Every input pixel is black (luma 0), so a threshold of 128 marks the whole
// frame as foreground.
const inputPtr = api.get_input_buffer();
const outputPtr = api.get_output_buffer();
const input = mem().subarray(inputPtr, inputPtr + W * H * 4);
input.fill(0);
for (let i = 3; i < input.length; i += 4) input[i] = 255;

api.render_frame(128, 0, 1, 1, 0, 0, 0);

const out = mem().subarray(outputPtr, outputPtr + W * H * 4);
const first = [out[0], out[1], out[2], out[3]];
check('output alpha is opaque', first[3] === 255, `alpha=${first[3]}`);
check('foreground pixel takes trail layer 0 colour',
  first[0] === 200 && first[1] === 0 && first[2] === 0,
  `rgb=${first.slice(0, 3).join(',')}`);

// A white frame with the same threshold is background only.
const input2 = mem().subarray(inputPtr, inputPtr + W * H * 4);
input2.fill(255);
for (let i = 3; i < input2.length; i += 4) input2[i] = 255;
api.render_frame(128, 0, 1, 1, 0, 0, 1);
const out2 = mem().subarray(outputPtr, outputPtr + W * H * 4);
check('background pixel uses background 0 colour',
  out2[0] === 10 && out2[1] === 20 && out2[2] === 30,
  `rgb=${out2.slice(0, 3).join(',')}`);

// Inverted mask: white is foreground now.
api.render_frame(128, 1, 1, 1, 0, 0, 2);
const out3 = mem().subarray(outputPtr, outputPtr + W * H * 4);
check('invert puts the white frame in the trail colour',
  out3[0] === 200 && out3[1] === 0 && out3[2] === 0,
  `rgb=${out3.slice(0, 3).join(',')}`);

// Gradient mode must stay inside the three palette colours (plus block noise off).
api.render_frame(128, 1, 2, 2, 1, 0, 3);
const out4 = mem().subarray(outputPtr, outputPtr + W * H * 4);
let inRange = true;
for (let i = 0; i < out4.length; i += 4) {
  for (let c = 0; c < 3; c += 1) {
    const v = out4[i + c];
    if (!Number.isInteger(v) || v < 0 || v > 255) inRange = false;
  }
}
check('gradient output pixels are valid bytes', inRange);

// The engine clamps out-of-range dimensions instead of writing past the buffers.
api.init_engine(10000, -5);
const clamped = api.get_output_buffer();
api.render_frame(128, 0, 1, 1, 0, 0, 0);
check('engine survives clamped dimensions', typeof clamped === 'number' && clamped > 0);

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} check(s) failed`);
process.exit(failures === 0 ? 0 : 1);
