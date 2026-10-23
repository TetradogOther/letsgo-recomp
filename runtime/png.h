// PNG reading and writing (runtime/png.c): the window icon, the screenshots and the 2x interface's textures.
// stb_image / stb_image_write (the copies in third_party/stb), in one place: the headers define their functions
// in the file that asks for the implementation, so a second one would define them again (link error).
#pragma once
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// The pixels of a PNG, req_channels per pixel (0 = as the file has; 1, 3 or 4), free with rt_png_free. When
// channels isn't NULL, it gets the count read (the file's own, when req_channels is 0). NULL when it can't be read.
uint8_t *rt_png_load(const char *path, int *w, int *h, int req_channels, int *channels);
// Writes a PNG (the pixels in R, G, B, A order when channels is 4). true = written.
bool rt_png_write(const char *path, const void *pixels, int w, int h, int channels);
// Frees what rt_png_load returned.
void rt_png_free(void *pixels);

#ifdef __cplusplus
}
#endif
