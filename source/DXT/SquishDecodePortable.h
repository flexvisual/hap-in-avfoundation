#ifndef HapCodec_SquishDecodePortable_h
#define HapCodec_SquishDecodePortable_h

#include <stdint.h>

int HapCodecSquishDecodePortable(const void *src,
                                 uint32_t src_pixel_format,
                                 void *dst,
                                 uint32_t dst_pixel_format,
                                 uint32_t dst_bytes_per_row,
                                 uint32_t width,
                                 uint32_t height);

#endif
