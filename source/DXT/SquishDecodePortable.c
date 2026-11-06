#include "SquishDecodePortable.h"
#include "PixelFormats.h"
#include "squish-c.h"
#include <stddef.h>
#include <stdint.h>
#include <string.h>

int HapCodecSquishDecodePortable(const void *src,
                                 uint32_t src_pixel_format,
                                 void *dst,
                                 uint32_t dst_pixel_format,
                                 uint32_t dst_bytes_per_row,
                                 uint32_t width,
                                 uint32_t height)
{
    if (src == NULL || dst == NULL || width == 0 || height == 0 ||
        (size_t)width > SIZE_MAX / 4 ||
        dst_bytes_per_row < (size_t)width * 4)
        return 1;

    int flags;
    size_t bytes_per_block;
    if (src_pixel_format == kHapCVPixelFormat_RGB_DXT1) {
        flags = kDxt1;
        bytes_per_block = 8;
    }
    else if (src_pixel_format == kHapCVPixelFormat_RGBA_DXT5) {
        flags = kDxt5;
        bytes_per_block = 16;
    }
    else {
        return 1;
    }

    if (dst_pixel_format != 'RGBA' && dst_pixel_format != 'BGRA')
        return 1;

    const uint8_t *src_bytes = src;
    uint8_t *dst_bytes = dst;
    size_t blocks_wide = ((size_t)width + 3) / 4;

    for (uint32_t block_y = 0; block_y < height; block_y += 4) {
        for (uint32_t block_x = 0; block_x < width; block_x += 4) {
            size_t block_index = ((size_t)block_y / 4) * blocks_wide + block_x / 4;
            uint8_t decoded[16 * 4];
            SquishDecompress(decoded, src_bytes + block_index * bytes_per_block, flags);

            uint32_t rows = height - block_y < 4 ? height - block_y : 4;
            uint32_t columns = width - block_x < 4 ? width - block_x : 4;
            for (uint32_t y = 0; y < rows; ++y) {
                const uint8_t *pixel = decoded + y * 16;
                uint8_t *output = dst_bytes + (size_t)(block_y + y) * dst_bytes_per_row + (size_t)block_x * 4;
                for (uint32_t x = 0; x < columns; ++x) {
                    if (dst_pixel_format == 'BGRA') {
                        output[0] = pixel[2];
                        output[1] = pixel[1];
                        output[2] = pixel[0];
                        output[3] = pixel[3];
                    }
                    else {
                        memcpy(output, pixel, 4);
                    }
                    pixel += 4;
                    output += 4;
                }
            }
        }
    }

    return 0;
}
