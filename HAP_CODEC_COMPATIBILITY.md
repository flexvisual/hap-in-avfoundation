# Hap Codec Compatibility Audit

## Executive summary

The implementation has a connected decode-to-Metal path for the five requested Hap formats, including Hap R. Hap R is identified by the `Hap7` track subtype, decoded by the vendored Hap parser into BC7 blocks, uploaded as `MTLPixelFormatBC7_RGBAUnorm`, and sampled directly by the Metal render shader. On the audit machine (Apple M3 Pro), a native BC7 Metal texture was successfully created. The source also has a distinct Metal compute path that converts BC7 to RGBA when the framework is asked for RGB output.

This is a source and device-capability audit, not an end-to-end Hap R playback certification: the official odd-dimension fixture pack retrieved for the audit contains Hap, Hap Alpha, Hap Q, and Hap Q Alpha files, but no Hap R file, and no Hap codec integration test target was found. Consequently Hap R's AVFoundation-to-renderer wiring is verified in code, while actual Hap R video output and pixel correctness remain unverified.

The most notable out-of-scope family gap is Hap HDR (`HapH`): the asset-track helper recognizes it, but the `AVPlayerItem` track finder omits it; its CPU RGB decode path does not handle BC6; and its writer encoder is explicitly incomplete. Do not equate that partial Hap HDR plumbing with full HDR support.

No decoder rewrite, source-code change, build-setting change, or new dependency was made for this audit.

## Format support matrix

“Metal path” below means compressed-frame decode and texture display in the test app. “RGB output” means `AVPlayerItemHapDXTOutput` is configured with `outputAsRGB:YES`. The five requested formats are wired by source inspection; except for the previously validated Hap1 playback, they have not been independently played through this app during this audit.

| Format | Track subtype / Hap texture(s) | Metal path | RGB output path | Audit result |
|---|---|---|---|---|
| Hap | `Hap1` / BC1 (DXT1) | Direct compressed BC1 texture upload and shader sampling | CPU DXT-to-RGBA conversion | Implemented; Hap1 playback was previously validated. |
| Hap Alpha | `Hap5` / BC3 (DXT5) | Direct compressed BC3 texture upload and shader sampling | CPU DXT-to-RGBA conversion, preserving alpha | Implemented in source; no audit-run sample. |
| Hap Q | `HapY` / scaled YCoCg BC3 | Direct BC3 sampling and YCoCg reconstruction in the fragment shader | CPU YCoCg block reconstruction followed by RGB conversion | Implemented in source; color output needs reference-image testing. |
| Hap Q Alpha | `HapM` / YCoCg BC3 + alpha BC4 (two textures) | Two compressed textures; shader reconstructs color and takes alpha from the second texture | CPU YCoCg-to-RGB conversion, then BC4 alpha is written into the output alpha channel | Two-plane decode and composition are wired; no audit-run sample. |
| Hap R (also called Hap 7A) | `Hap7` / RGBA BC7 | Direct BC7 texture sampling on the normal Metal path | Metal compute BC7-to-RGBA conversion when RGB output is requested, then GPU output is copied to the CPU buffer | Source wiring and M3 Pro BC7 texture creation verified; no Hap R movie fixture was available for end-to-end playback validation. |
| Hap Alpha-Only | `HapA` / alpha BC4 | BC4 texture is sampleable for mask preview | CPU BC4 decode to a mask-style RGBA buffer | Recognized and decodable as an alpha-only component; it is not a standalone full-color codec. |
| Hap HDR | `HapH` / RGB BC6U or BC6S | BC6 Metal texture-format mappings exist | BC6 is not handled by the RGB conversion switch; writer encoder is marked incomplete | Partial only; missing AVPlayer track discovery and complete HDR decode/encode/output handling. |

The official format table calls Hap R “RGBA BPTC/BC7 UNORM” and assigns it FourCC `Hap7`. The local names `kHap7AlphaCodecSubType` and `AVVideoCodecHap7Alpha` are therefore not evidence that Hap R is omitted; they are the implementation’s name for that format.

## Hap R and BC7 path

The Hap R decode/render chain is connected:

1. `Hap7` is recognized by `AVPlayerItem.hapTrack` and `AVAssetTrack.isHapTrack` ([AVPlayerItemAdditions.m](HapInAVFoundation/AVPlayerItemAdditions.m#L19), [AVAssetAdditions.m](HapInAVFoundation/AVAssetAdditions.m#L50)).
2. The decoder reads the texture count and per-texture format from the Hap frame, allocates a suitably sized compressed plane, and calls `HapDecode` ([HapDecoderFrame.m](HapInAVFoundation/HapDecoderFrame.m#L110), [HapDecoderFrame.m](HapInAVFoundation/HapDecoderFrame.m#L145), [AVPlayerItemHapDXTOutput.m](HapInAVFoundation/AVPlayerItemHapDXTOutput.m#L625)).
3. The upstream Hap format table recognizes the BC7 texture format (`kHapFormatRGBABPTC` to `HapTextureFormat_RGBA_BPTC_UNORM`) ([hap.c](../hap/source/hap.c#L49), [hap.c](../hap/source/hap.c#L227)).
4. The test app maps that decoded format to `MTLPixelFormatBC7_RGBAUnorm`, uploads the compressed bytes, and the general sampleable shader samples the texture ([HapMTLPixelBufferTexture.m](HapInAVF%20Test%20App/Metal/HapMTLPixelBufferTexture.m#L67), [HapMTLPixelBufferTexture.m](HapInAVF%20Test%20App/Metal/HapMTLPixelBufferTexture.m#L206), [HapMTKViewShader.metal](HapInAVF%20Test%20App/Metal/HapMTKViewShader.metal#L49)).
5. On the audit machine, a runtime Metal probe created an `MTLPixelFormatBC7_RGBAUnorm` texture successfully on **Apple M3 Pro**. This verifies device support for native BC7 textures; it is not a Hap R sample-playback test.

Therefore the normal Metal path uses native Metal BC7 texture sampling, not `HapMetalBC7toRGBA`. The custom compute conversion is a separate RGB-output fallback: it creates a BC7 texture, dispatches `HapMetalBC7toRGBA`, waits for the GPU command buffer, and copies to the supplied RGB buffer if it could not use that buffer directly ([AVPlayerItemHapDXTOutput.m](HapInAVFoundation/AVPlayerItemHapDXTOutput.m#L704), [HapMetalDXTDecoder.m](source/DXT/HapMetalDXTDecoder.m#L37), [HapMetalDXTDecoder.m](source/DXT/HapMetalDXTDecoder.m#L87), [AVPlayerItemHapDXTOutput.m](HapInAVFoundation/AVPlayerItemHapDXTOutput.m#L751)). The conversion shader gathers BC7-decoded samples and bounds-checks output writes ([HapMetalBC7toRGBA.metal](source/DXT/HapMetalBC7toRGBA.metal#L18), [HapMetalBC7toRGBA.metal](source/DXT/HapMetalBC7toRGBA.metal#L35)).

The BC7 encoder is connected for Hap7 export through the pinned `bc7enc_rdo` block-encoding API. The adapter handles RGBA/BGRA input, padded row strides, and partial edge blocks ([ATEBC7Encoder.c](source/DXT/ATEBC7Encoder.c#L35), [BC7EncoderAdapter.cpp](source/DXT/BC7EncoderAdapter.cpp#L17), [BC7EncoderAdapter.cpp](source/DXT/BC7EncoderAdapter.cpp#L48), [AVAssetWriterHapInput.m](HapInAVFoundation/AVAssetWriterHapInput.m#L179), [AVAssetWriterHapInput.m](HapInAVFoundation/AVAssetWriterHapInput.m#L1018)). It does not currently run the library's frame-level RDO optimizer.

## YCoCg and separate alpha

Hap Q uses one BC3 plane. The renderer identifies `HapY` as YCoCg and reconstructs RGB in the fragment shader: it recenters Co/Cg, derives the scale factor, then applies the YCoCg-to-RGB equations ([HapMTKView.m](HapInAVF%20Test%20App/Metal/HapMTKView.m#L312), [HapMTKViewShader.metal](HapInAVF%20Test%20App/Metal/HapMTKViewShader.metal#L54)). This is consistent with the bundled YCoCg encoder's stored scale and chroma representation ([YCoCgDXT.cpp](source/DXT/YCoCgDXT.cpp#L233), [YCoCgDXT.cpp](source/DXT/YCoCgDXT.cpp#L248)).

Hap Q Alpha uses the spec-permitted YCoCg BC3 + alpha BC4 two-image combination. The decoder queries and decodes texture indices 0 and 1, the frame holds two plane pointers/sizes, and the Metal wrapper creates/uploads a second texture where present ([hap.h](../hap/source/hap.h#L78), [HapDecoderFrame.h](HapInAVFoundation/HapDecoderFrame.h#L23), [AVPlayerItemHapDXTOutput.m](HapInAVFoundation/AVPlayerItemHapDXTOutput.m#L637), [HapMTLPixelBufferTexture.m](HapInAVF%20Test%20App/Metal/HapMTLPixelBufferTexture.m#L180)). The YCoCgA shader reconstructs RGB from plane A and takes alpha from the red component of plane B ([HapMTKView.m](HapInAVF%20Test%20App/Metal/HapMTKView.m#L316), [HapMTKViewShader.metal](HapInAVF%20Test%20App/Metal/HapMTKViewShader.metal#L67)). The CPU fallback's RGTC1 write helper updates only the output alpha byte, leaving converted RGB intact ([SquishRGTC1Decoder.c](source/SquishRGTC1Decoder.c#L73), [AVPlayerItemHapDXTOutput.m](HapInAVFoundation/AVPlayerItemHapDXTOutput.m#L787)).

These are source-level confirmations only. A visual/reference comparison is still needed for YCoCg colors, alpha edges, and alpha-plane alignment.

## Chunking and dimensions

- The Hap format parser recognizes BC1, BC3, scaled YCoCg, BC4, BC7, BC6U, and BC6S texture IDs ([hap.c](../hap/source/hap.c#L49), [hap.c](../hap/source/hap.c#L227)).
- For complex/chunked sections, it reads per-chunk compressor and size tables, calculates output offsets, checks the output capacity, then invokes the supplied callback across chunks ([hap.c](../hap/source/hap.c#L734), [hap.c](../hap/source/hap.c#L813), [hap.c](../hap/source/hap.c#L861)). The AVFoundation callback dispatches chunk work with `dispatch_apply` ([AVPlayerItemHapDXTOutput.m](HapInAVFoundation/AVPlayerItemHapDXTOutput.m#L22)).
- The public Hap API permits one or two textures and documents the YCoCg + alpha combination; chunk counts are per texture ([hap.h](../hap/source/hap.h#L70), [hap.h](../hap/source/hap.h#L78), [hap.h](../hap/source/hap.h#L91)).
- Decoder dimensions are rounded up to a multiple of four for block storage, while the actual video dimensions are retained separately ([Utility.c](source/Utility.c#L68), [HapDecoderFrame.m](HapInAVFoundation/HapDecoderFrame.m#L145)). The Metal textures are sized to the padded dimensions and the displayed image uses the actual image size ([HapMTLPixelBufferTexture.m](HapInAVF%20Test%20App/Metal/HapMTLPixelBufferTexture.m#L171), [HapMTLPixelBufferTexture.m](HapInAVF%20Test%20App/Metal/HapMTLPixelBufferTexture.m#L237), [HapMTKView.m](HapInAVF%20Test%20App/Metal/HapMTKView.m#L221)). The BC7 compute fallback also bounds writes to the actual destination dimensions.

This is structurally compatible with non-multiple-of-four dimensions. Runtime odd-dimension rendering still needs coverage for all supported formats, especially Hap Q Alpha's paired planes and Hap R's BC7 compute fallback.

## Fixtures and missing tests

The repository contains no Hap codec integration test target or Hap-format fixture suite. The existing Snappy/Squish tests do not exercise container parsing, AVFoundation track discovery, texture upload, Metal color reconstruction, or end-to-end playback.

The official [VIDVOX Odd Dimensions pack](https://d3omao0uy1rjjh.cloudfront.net/hap/Hap_Test_Odd_Dimensions.zip) was retrieved during the audit (1,587,302-byte archive; unpacked contents total 8,246,112 bytes). Its files are:

- `Hap_973x734.mov`
- `Hap_Alpha_973x734.mov`
- `Hap_Q_973x734.mov`
- `Hap_Q_Alpha_973x734.mov`

This is useful for existing four-format odd-size testing, but it predates Hap R and contains no BC7 sample. VIDVOX's [Hap repository](https://github.com/Vidvox/hap) also links [16K samples](https://d3omao0uy1rjjh.cloudfront.net/hap/Hap_Test_16K.zip) for large-dimension testing. The [Hap R benchmark article](https://vdmx.vidvox.net/blog/hap-r-benchmarks) says Hap R supports alpha and chunking. The [official HapInAVFoundation releases](https://github.com/Vidvox/hap-in-avfoundation/releases) identify AVF Batch Exporter 1.6.9.4 as supporting HapR/7A, making that exporter a suitable source for creating a small Hap R fixture if no distributable reference clip is available.

A playback smoke-test attempt with the Hap Q Alpha odd-dimension clip did not reach rendering: the app launched from its `/tmp` build bundle reported that access to the bundle was not permitted and could not load `default.metallib`. The successful app build and BC7 device probe are not substitutes for that playback test, so the four clips remain unvalidated at runtime in this audit.

Recommended integration fixtures/tests:

1. Run each odd-dimension movie above through Metal and RGB output; compare dimensions and decoded RGB/alpha against a trusted decode or reference frames.
2. Create and check in (or download as a test asset) an odd-sized, alpha-bearing Hap R/`Hap7` movie and test both direct BC7 Metal sampling and `outputAsRGB:YES` compute conversion against the same reference frames.
3. Exercise multichunk Hap1, Hap Q, Hap Q Alpha, and Hap R frames, including separate chunk tables for each Hap Q Alpha plane.
4. Run a 16K sample through decode/upload and verify allocation sizes, row bytes, and GPU support boundaries.
5. Add a Hap HDR negative/unsupported test until Hap HDR output is deliberately completed.

## Minimal recommended corrections

1. **Add Hap R end-to-end fixtures and tests first.** The Hap R source path and M3 Pro BC7 capability are present, so there is not enough evidence to justify rewriting or replacing the BC7 renderer. Validate direct sampling and the `HapMetalDXTDecoder` fallback with an official-exporter-generated sample before making code changes.
2. **Update stale public comments.** `HapDecoderFrame.h` still lists only older subtypes and formats in its property documentation ([HapDecoderFrame.h](HapInAVFoundation/HapDecoderFrame.h#L57), [HapDecoderFrame.h](HapInAVFoundation/HapDecoderFrame.h#L70)); document `Hap7`/BC7 and Hap HDR accurately.
3. **If “complete Hap family” includes Hap HDR, treat it as a separate feature.** Add `HapH` to the `AVPlayerItem` track finder ([AVPlayerItemAdditions.m](HapInAVFoundation/AVPlayerItemAdditions.m#L19)), define an explicit HDR display/RGB-output policy including BC6U/BC6S, and complete or reject the writer path rather than accepting settings that later report “incomplete” ([AVPlayerItemHapDXTOutput.m](HapInAVFoundation/AVPlayerItemHapDXTOutput.m#L704), [AVAssetWriterHapInput.m](HapInAVFoundation/AVAssetWriterHapInput.m#L1021)). Keep this out of a Hap R-only fix.
4. **Do not change block sizing or chunk decode speculatively.** The implementation's four-pixel padding, plane sizes, and chunk callback structure match the formats encoded in the current VIDVOX specification; validate with the fixtures above before altering them.

## References

- [VIDVOX Hap specification and reference source](https://github.com/vidvox/hap), including [HapVideoDRAFT.md](https://github.com/Vidvox/hap/blob/master/documentation/HapVideoDRAFT.md) and official sample-material links.
- [VIDVOX Hap R Benchmarks](https://vdmx.vidvox.net/blog/hap-r-benchmarks), published August 7, 2025.
- [VIDVOX HapInAVFoundation](https://github.com/Vidvox/hap-in-avfoundation), including [releases](https://github.com/Vidvox/hap-in-avfoundation/releases).
