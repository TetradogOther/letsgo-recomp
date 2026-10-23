// PNG reading and writing (runtime/png.h): stb_image and stb_image_write, the copies in third_party/stb.
// The implementation of both headers lives here: they define their functions in the file that asks for it, so a
// second one (the icon, the screenshots, the 2x interface's textures) would define them again: link error.
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_NO_STDIO_WARNINGS
#include "../third_party/stb/stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "../third_party/stb/stb_image_write.h"

#include "png.h"

uint8_t *rt_png_load(const char *path, int *w, int *h, int req_channels, int *channels) {
    int n = 0;
    unsigned char *px = stbi_load(path, w, h, &n, req_channels);
    if (!px) return NULL;
    if (channels) *channels = n;
    return px;
}

bool rt_png_write(const char *path, const void *pixels, int w, int h, int channels) {
    return stbi_write_png(path, w, h, channels, pixels, w * channels) != 0;
}

void rt_png_free(void *pixels) { stbi_image_free(pixels); }
