HapInAVFoundation Framework
==========

Hap is a video codec for fast decompression on modern graphics hardware. This is the home of the HapInAVFoundation framework. For general information about Hap, see [the Hap project][1].

The HapInAVFoundation framework supports encoding and decoding Hap video. Unlike the QuickTime codec, the HapInAVFoundation framework will only decode to S3TC/DXT frames suitable for upload to graphics hardware at this time.  If requested, decoding to RGB(A) pixel formats can be added.  Encoding RGB(A) frames is supported.  For the most part, this is a port of the hap quicktime codec.

DXT1 and DXT5 encoding and the CPU fallback use libsquish. BC7 encoding uses `bc7enc_rdo`. Hap frame parsing and Snappy decompression use their upstream source. Sparkle is loaded as a local Swift Package.

Sample code for a test application ("HapInAVF Test App") that demonstrates Metal-accelerated playback is included.

Download
====

This repository is a Flexvisual, Inc fork of the original VIDVOX HapInAVFoundation project.

For the Flexvisual version, build the framework from source using the instructions below or the automated builder in [ModFrameworks](https://github.com/flexvisual/ModFrameworks).

Precompiled Flexvisual releases are not currently published. For releases of the original VIDVOX project, see [VIDVOX Releases](https://github.com/Vidvox/hap-in-avfoundation/releases).

Workspace dependencies
-------------------

This project uses third-party dependencies maintained in separate upstream repositories. These dependencies are not included in this repository.

The Xcode project currently references external dependency checkouts using relative paths. Developers building directly from this repository must arrange those dependencies accordingly or update the project references for their environment.

For automated dependency retrieval and framework packaging, see [ModFrameworks](https://github.com/flexvisual/ModFrameworks).

| Dependency | Upstream |
|---|---|
| Snappy | [google/snappy](https://github.com/google/snappy) |
| libsquish | [arves100/libsquish](https://github.com/arves100/libsquish) |
| Hap parser | [Vidvox/hap](https://github.com/Vidvox/hap) |
| BC7 block encoder | [richgel999/bc7enc_rdo](https://github.com/richgel999/bc7enc_rdo) |
| Sparkle | [sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle) |

Run `bash scripts/build.sh` from this repository to verify the sibling checkouts and build the default `HapInAVFoundation` scheme. The script does not update dependency repositories; update each checkout from its own Git repository when desired. Sparkle's Swift Package manifest is loaded from `../Sparkle` and obtains its binary artifact through Swift Package Manager. `bc7enc_rdo` is currently used through its BC7 block-encoding API; the frame-level rate-distortion optimizer is not enabled.

Using the HapInAVFoundation.framework
====

The general idea is to either download or compile the framework, add the framework to your XCode project so you may link against it, and then set up a build phase to copy the framework into your application bundle.  This is fairly important: most of the time when you link against a framework, the framework is expected to be installed on your OS.  HapInAVFoundation is different: your application will include a compiled copy of the framework.  Here's the exact procedure:

If you downloaded a compiled framework
--------------------------------------

  1.  Unzip the framework, add it to your source tree, and then drag the framework into your xcode project file's workspace.
  2.  Locate the "Build Phases" section for your project/application's target.
  3.  Add the HapInAVFoundation framework to the "Link Binary with Libraries" section.
  4.  Create a new "Copy Files" build phase, set its destination to the "Frameworks" folder, and add the HapInAVFoundation framework to this build phase- the goal is to copy the framework you need into the "Frameworks" folder inside your app package.
  5.  Switch to the "Build Settings" section of your project's target, locate the "Runpath Search Paths" settings, and make sure that the following paths exist: "@loader_path/../Frameworks" and "@executable_path/../Frameworks".

If you're compiling from source
-------------------------------  

  1.  In XCode, close the HapInAVFoundation project (if it is open), and then open your project.
  2.  In the Finder, drag "HapInAVFoundation.xcodeproj" into your project's workspace.
  3.  Switch back to XCode, and locate the "Build Phases" section for your project/application's target.
  4.  Add a dependency for the "HapInAVFoundation" framework.  This will ensure that the framework gets compiled before your project, so there won't be any missing dependencies.
  5.  Add the HapInAVFoundation framework to the "Link Binary with Libraries" section.
  6.  Create a new "Copy Files" build phase, set its destination to the "Frameworks" folder, and add the HapInAVFoundation framework to this build phase- the goal is to copy the framework you need into the "Frameworks" folder inside your app package.
  7.  Switch to the "Build Settings" section of your project's target, locate the "Runpath Search Paths" settings, and make sure that the following paths exist: "@loader_path/../Frameworks" and "@executable_path/../Frameworks".
  8.  That's it- you're done now.  You can import/include objects from the framework in your source just as you normally would.

Documentation
===

[Documentation for this framework can be found here.](http://vidvox.net/rays_oddsnends/HapInAVFoundation_doc/html/index.html)  The header files are also commented extensively, and the included sample application demonstrates the use of the framework to play back Hap video using Metal textures.

Open-Source
====

The Hap codec project is open-source, licensed under a [FreeBSD License][2], meaning you can use it in your commercial or non-commercial applications free of charge.  The hap project was originally written by [Tom Butterworth][3] and commissioned by [VIDVOX][4], 2012.

Redistribution and third-party licenses
---------------------------------------

The Xcode framework and GUI app targets copy `LICENSE` and `LICENSES/` into their built bundles. If distributing the static library or the `AVFtoHap` command-line tool, include those files alongside the binary. The YCoCg DXT compressor contains code marked LGPL-2.1-or-later; review `LICENSES/LGPL-2.1.txt` and comply with its applicable source and relinking requirements. Including the notices alone may not be sufficient for every binary distribution.

[1]: http://github.com/vidvox/hap
[2]: http://github.com/vidvox/hap-in-avfoundation/blob/master/LICENSE
[3]: http://kriss.cx/tom
[4]: http://www.vidvox.net

### Flexvisual fork and licensing

This repository contains modifications to the original VIDVOX HapInAVFoundation project. Original copyright notices and applicable third-party licenses are preserved.

The Flexvisual source modifications are publicly available in this repository. The ModFrameworks build system also records pinned dependency revisions and generates a source-compliance archive.

Some components, including the YCoCg DXT compressor, contain LGPL-2.1-or-later code. Public source availability and license notices do not, by themselves, establish compliance for every binary distribution. Distributors must review applicable source-code, modification, and relinking obligations, particularly for statically linked binaries.

The licenses of the included third-party components remain applicable independently of the licensing of ModFrameworks or ModCore.
