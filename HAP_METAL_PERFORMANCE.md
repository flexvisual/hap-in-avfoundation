# Hap Metal Playback Validation

## Summary

The red bands were the Metal render pass's clear color, not corrupted Hap pixels. The Hap1 frame is 3840x1080 (3.556:1) and is correctly aspect-fit into a 640x480 (4:3) Metal drawable. That produces a 640x180 image with 150-pixel bands above and below it. The Metal drawable now clears those bands to transparent, allowing the content behind the view to show through. The viewport uses the drawable's actual size, and the full image rectangle is used for pixel-coordinate texture sampling.

The Metal Hap1 path uploads compressed BC1/DXT1 data to an `MTLPixelFormatBC1_RGBA` texture and samples it in the Metal fragment shader. It does not CPU-decompress BC1 to RGBA first. On the measured Apple Silicon system, it sustained approximately 30 Hap frames/sec with about 15% of one CPU core in use. The NSImage diagnostic path, which enables CPU DXT-to-RGBA conversion, produced about 15.6 frames/sec and used about 120% of one CPU core.

No decoder rewrite, build-setting change, or new dependency was introduced.

## Test setup

- **Input:** `RibbonnobbiR.mov`, Hap1, 3840x1080, nominal 30 FPS, 58.27 seconds.
- **System:** MacBook Pro with M3 Pro; macOS 27.2.
- **Comparison:** Separate 30-second Metal and NSImage runs on the same file, plus a Metal pause/seek/restart test followed by sustained playback.
- **Instrumentation:** App counters for frame rate, estimated drops, process CPU, texture reuse, GPU execution, and presented drawables; signposts for decode, conversion, upload, rendering, and presentation. Instrumented stage timings were collected with Time Profiler and Points of Interest.
- The test app can run without UI automation using `HAP_PERFORMANCE_TEST_FILE`, `HAP_PERFORMANCE_TEST_PATH` (`Metal` or `NSImage`), and `HAP_PERFORMANCE_TEST_DURATION`. Set `HAP_PLAYBACK_CONTROL_TEST=1` to exercise playback controls.

## Playback measurements

| Path / run | Hap FPS | Estimated dropped frames | Process CPU | Presentation | Resource observations |
|---|---:|---:|---:|---:|---|
| Metal, 30 seconds | 29.99 | 0 | 15.3% of one core | 59.95 presented FPS | 2 texture wrapper objects created, 898 reuses, 2 Metal textures created |
| NSImage, 30 seconds | 15.56 | 433 | 119.5% of one core | Not applicable | Native AVFoundation output: 0 FPS |
| Metal after pause/seek/restart | 30.03 | 0 | 15.2% of one core | Approximately 60 presented FPS | Sustained playback completed |

The drop count is an estimate: nominal source FPS multiplied by elapsed time minus newly delivered Hap frames. It is not a PTS-gap or display-scanout counter. CPU percentages are process user-plus-system CPU time normalized to elapsed wall time, so 119.5% is approximately 1.195 continuously occupied cores. The display-link refresh rate is reported separately from the source-frame rate.

## Instrumented stage timings

These are averages from the captured signpost intervals, not timings inferred from FPS:

| Stage | Samples | Average | P95 | Maximum | Notes |
|---|---:|---:|---:|---:|---|
| Hap/Snappy decode, Metal run | 749 | 3.961 ms | 5.011 ms | 6.788 ms | CPU decode of the Hap/Snappy-compressed input into DXT blocks |
| Hap/Snappy decode, NSImage run | 439 | 3.777 ms | 4.266 ms | 7.619 ms | Same decode stage |
| CPU DXT-to-RGBA conversion, NSImage run | 438 | 57.701 ms | 58.288 ms | 67.179 ms | CPU `HapCodecSquishDecodePortable` conversion |
| Compressed texture upload, CPU call | 748 | 0.220 ms | 0.232 ms | 0.449 ms | `replaceRegion` upload call |
| Upload/synchronization command-buffer GPU time | 748 | 0.0004 ms | Not reported | 0.0012 ms | Does not represent a standalone bandwidth measurement |
| Metal render GPU execution | 1,497 | 0.0542 ms | 0.0976 ms | 0.386 ms | Full measured render command-buffer GPU time, including texture sampling |
| Metal frame CPU encoding | 1,497 | 0.0363 ms | 0.0765 ms | 0.124 ms | CPU-side render command encoding |

The app's independent 30-second Metal run measured 0.054 ms average GPU execution, 0.194 ms maximum, and estimated GPU busy time of 0.32% of the interval. Signpost sample counts are from the profiler capture and should not be treated as delivered frame counts; profiling and capture coverage can affect sample totals. The fragment sampler's BC1 decompression is not separately timed from the rest of GPU rendering. Presentation timestamps and presented-frame counts are recorded, but compositor/scan-out latency was not isolated as a millisecond duration.

The roughly 57.7 ms CPU conversion time is the principal measured difference: it exceeds the 33.3 ms interval of a 30 FPS source and accounts for the NSImage path's lower frame rate and higher CPU use. In contrast, the Metal path's measured decode and upload work fit comfortably within that interval.

## Renderer and BC1 path findings

- The render pass clears to black at [HapMTKView.m](HapInAVF%20Test%20App/Metal/HapMTKView.m#L272). The aspect-fit calculation centers the image and leaves letterbox space when source and drawable aspect ratios differ at [HapMTKView.m](HapInAVF%20Test%20App/Metal/HapMTKView.m#L280). For this 32:9 source in a 4:3 viewport, top and bottom bands are expected.
- The drawable size is used as the viewport at [HapMTKView.m](HapInAVF%20Test%20App/Metal/HapMTKView.m#L466). Image coordinates cover the image rectangle at [HapMTKView.m](HapInAVF%20Test%20App/Metal/HapMTKView.m#L221), and the fragment sampler uses pixel coordinates at [HapMTKViewShader.metal](HapInAVF%20Test%20App/Metal/HapMTKViewShader.metal#L45). These calculations and coordinates are consistent with the measured aspect-fit output.
- Hap RGB DXT1 maps directly to `MTLPixelFormatBC1_RGBA` at [HapMTLPixelBufferTexture.m](HapInAVF%20Test%20App/Metal/HapMTLPixelBufferTexture.m#L67). Compressed DXT bytes are passed directly to the Metal texture's `replaceRegion` at [HapMTLPixelBufferTexture.m](HapInAVF%20Test%20App/Metal/HapMTLPixelBufferTexture.m#L206); the fragment shader samples that texture at [HapMTKViewShader.metal](HapInAVF%20Test%20App/Metal/HapMTKViewShader.metal#L51). Metal's BC1 texture sampling performs the decompression; there is no intervening CPU RGBA conversion in this path.
- Hap/Snappy decompression itself remains CPU-side: the decoder invokes `HapDecode` on its decode queue at [AVPlayerItemHapDXTOutput.m](HapInAVFoundation/AVPlayerItemHapDXTOutput.m#L625), and Snappy decompression is performed in [hap.c](../hap/source/hap.c#L612). The optional CPU conversion is `HapCodecSquishDecodePortable` at [AVPlayerItemHapDXTOutput.m](HapInAVFoundation/AVPlayerItemHapDXTOutput.m#L689), enabled for the NSImage tab.

## Reuse, copies, and threading

- The Metal texture pool reuses wrapper objects and their compatible textures; the measured run created two wrapper objects and two actual Metal textures, then reused wrappers 898 times. Pool reuse is implemented at [HapMTLPixelBufferTexture.m](HapInAVF%20Test%20App/Metal/HapMTLPixelBufferTexture.m#L264). The measured allocation counts confirm that Hap1 playback did not allocate a new Metal texture per frame.
- The MVP `MTLBuffer` is retained across frames at [HapMTKView.m](HapInAVF%20Test%20App/Metal/HapMTKView.m#L209), and small per-frame vertex data is supplied with `setVertexBytes` at [HapMTKView.m](HapInAVF%20Test%20App/Metal/HapMTKView.m#L306). Hap1 does not allocate a new explicit vertex buffer each frame.
- Each decoder frame requests DXT memory through CoreMedia's allocator at [AVPlayerItemHapDXTOutput.m](HapInAVFoundation/AVPlayerItemHapDXTOutput.m#L351). The allocator may pool internally, but reuse of these backing allocations was not measured or guaranteed by the application code.
- The Metal upload necessarily transfers compressed bytes from decoder-owned CPU memory into a Metal texture using `replaceRegion`. The app does not create an intermediate RGBA image or add an explicit second CPU copy on this route. The texture is configured as managed storage and synchronized through a blit encoder at [HapMTLPixelBufferTexture.m](HapInAVF%20Test%20App/Metal/HapMTLPixelBufferTexture.m#L228); changing that storage/synchronization behavior was not attempted without a targeted validation.
- `HapDecode` work runs on a dedicated high-priority serial queue at [AVPlayerItemHapDXTOutput.m](HapInAVFoundation/AVPlayerItemHapDXTOutput.m#L75), with chunk work dispatched in parallel at [AVPlayerItemHapDXTOutput.m](HapInAVFoundation/AVPlayerItemHapDXTOutput.m#L23). Decoding is not done on the main thread. The display-link callback is installed on the main run loop at [HapInAVFTestAppDelegate.m](HapInAVF%20Test%20App/HapInAVFTestAppDelegate.m#L69); the NSImage bitmap creation/copy happens in that display callback at [HapInAVFTestAppDelegate.m](HapInAVF%20Test%20App/HapInAVFTestAppDelegate.m#L365). That UI-side work remains a potential CPU-path cost, but no additional optimization was made.

## Playback controls and remaining limits

The automated Metal control run confirmed a paused player rate of 0 after about one second, successful midpoint seek, successful restart-to-zero, and approximately 30 FPS with zero estimated drops during the following sustained 30-second run. The test implementation is at [HapInAVFTestAppDelegate.m](HapInAVF%20Test%20App/HapInAVFTestAppDelegate.m#L167).

The renderer requests a redraw after new texture data arrives at [HapMTKView.m](HapInAVF%20Test%20App/Metal/HapMTKView.m#L134), which is important because the view is not continuously redrawn while paused. The measurements support smooth Hap1 playback on this machine; they do not establish performance for other Hap subtypes, resolutions, GPUs, or displays. No speculative decoder, storage-mode, or synchronization optimization was made.
