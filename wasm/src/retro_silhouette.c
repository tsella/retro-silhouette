//
//  retro_silhouette.c
//  RetroSilhouetteKit - WebAssembly / Portable C99 Core
//
//  Inspired by the 1992 Amiga demo "State of the Art" by Spaceballs:
//  https://www.youtube.com/watch?v=89wq5EoXy-0
//

#include <stdint.h>

#define MAX_WIDTH       384
#define MAX_HEIGHT      384
#define MAX_PIXELS      (MAX_WIDTH * MAX_HEIGHT)
#define MAX_HISTORY     96
#define MAX_TRAILS      8

#define WASM_EXPORT __attribute__((visibility("default")))

static uint8_t  g_input_rgba[MAX_PIXELS * 4];
static uint8_t  g_output_rgba[MAX_PIXELS * 4];
static uint8_t  g_history_masks[MAX_HISTORY * MAX_PIXELS];
static uint8_t  g_palette_rgb[33];

static int32_t  g_width      = 160;
static int32_t  g_height     = 160;
static int32_t  g_write_idx  = 0;

static inline uint32_t fast_block_hash(uint32_t bx, uint32_t by, uint32_t seed) {
    uint32_t h = bx * 374761393U + by * 668265263U + seed * 1442695041U;
    h = (h ^ (h >> 13U)) * 1274126177U;
    return h ^ (h >> 16U);
}

static inline uint8_t clamp_u8(int32_t v) {
    if (v < 0) return 0;
    if (v > 255) return 255;
    return (uint8_t)v;
}

WASM_EXPORT uint8_t* get_input_buffer(void)   { return g_input_rgba; }
WASM_EXPORT uint8_t* get_output_buffer(void)  { return g_output_rgba; }
WASM_EXPORT uint8_t* get_palette_buffer(void) { return g_palette_rgb; }

WASM_EXPORT void init_engine(int32_t width, int32_t height) {
    if (width < 32) width = 32;
    if (width > MAX_WIDTH) width = MAX_WIDTH;
    if (height < 32) height = 32;
    if (height > MAX_HEIGHT) height = MAX_HEIGHT;
    g_width = width;
    g_height = height;
    g_write_idx = 0;
    int32_t total = width * height * MAX_HISTORY;
    for (int32_t i = 0; i < total; ++i) g_history_masks[i] = 0;
}

WASM_EXPORT void render_frame(
    int32_t threshold,
    int32_t invert,
    int32_t trail_count,
    int32_t trail_delay,
    int32_t is_gradient,
    int32_t blocky_artifacts,
    int32_t frame_num
) {
    const int32_t w = g_width;
    const int32_t h = g_height;
    const int32_t num_pixels = w * h;

    uint8_t* current_slice = &g_history_masks[g_write_idx * num_pixels];
    for (int32_t i = 0; i < num_pixels; ++i) {
        const int32_t px = i << 2;
        const int32_t luma = (77 * g_input_rgba[px] + 150 * g_input_rgba[px + 1] + 29 * g_input_rgba[px + 2]) >> 8;
        const int32_t is_fg = invert ? (luma > threshold) : (luma < threshold);
        current_slice[i] = is_fg ? 255 : 0;
    }

    const int32_t min_dim = (w < h) ? w : h;
    int32_t block_size = min_dim / 14;
    if (block_size < 6) block_size = 6;
    const uint32_t time_seed = (uint32_t)(frame_num >> 2);

    const int32_t bg0_r = g_palette_rgb[0], bg0_g = g_palette_rgb[1], bg0_b = g_palette_rgb[2];
    const int32_t bg1_r = g_palette_rgb[3], bg1_g = g_palette_rgb[4], bg1_b = g_palette_rgb[5];
    const int32_t bg2_r = g_palette_rgb[6], bg2_g = g_palette_rgb[7], bg2_b = g_palette_rgb[8];

    for (int32_t y = 0; y < h; ++y) {
        const int32_t row_offset = y * w;
        const uint32_t by = (uint32_t)((y / block_size) * block_size);
        for (int32_t x = 0; x < w; ++x) {
            const int32_t idx = row_offset + x;
            int32_t out_r = bg0_r, out_g = bg0_g, out_b = bg0_b;

            if (is_gradient) {
                int32_t t256 = ((x * 141) / w) + ((y * 115) / h);
                if (t256 > 256) t256 = 256;
                if (t256 < 140) {
                    const int32_t lt = (t256 * 256) / 140;
                    out_r = bg0_r + (((bg1_r - bg0_r) * lt) >> 8);
                    out_g = bg0_g + (((bg1_g - bg0_g) * lt) >> 8);
                    out_b = bg0_b + (((bg1_b - bg0_b) * lt) >> 8);
                } else {
                    const int32_t lt = ((t256 - 140) * 256) / 116;
                    out_r = bg1_r + (((bg2_r - bg1_r) * lt) >> 8);
                    out_g = bg1_g + (((bg2_g - bg1_g) * lt) >> 8);
                    out_b = bg1_b + (((bg2_b - bg1_b) * lt) >> 8);
                }
                if (blocky_artifacts) {
                    const uint32_t bx = (uint32_t)((x / block_size) * block_size);
                    const int32_t delta = (fast_block_hash(bx, by, time_seed) & 1U) ? 14 : -10;
                    out_r = clamp_u8(out_r + delta);
                    out_g = clamp_u8(out_g + delta);
                    out_b = clamp_u8(out_b + delta);
                }
            }

            for (int32_t layer = 0; layer < trail_count; ++layer) {
                const int32_t steps_back = (trail_count - 1 - layer) * trail_delay;
                const int32_t slice_idx = (g_write_idx - steps_back + MAX_HISTORY) % MAX_HISTORY;
                if (g_history_masks[slice_idx * num_pixels + idx] > 0) {
                    const int32_t pal_offset = 9 + layer * 3;
                    out_r = g_palette_rgb[pal_offset + 0];
                    out_g = g_palette_rgb[pal_offset + 1];
                    out_b = g_palette_rgb[pal_offset + 2];
                }
            }

            const int32_t px = idx << 2;
            g_output_rgba[px + 0] = (uint8_t)out_r;
            g_output_rgba[px + 1] = (uint8_t)out_g;
            g_output_rgba[px + 2] = (uint8_t)out_b;
            g_output_rgba[px + 3] = 255;
        }
    }
    g_write_idx = (g_write_idx + 1) % MAX_HISTORY;
}
