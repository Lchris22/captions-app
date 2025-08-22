Software Solution Reference Document
1. Project Overview

Project Title: CaptionsApp — Mobile caption editor & renderer (Preview → Native Export)

Objective
Build a mobile app that lets creators import a video + SRT, preview subtitle animations live (WYSIWYG), tweak styling/timing, and produce a final MP4 with pixel-perfect captions. The final render must match the preview exactly (“Preview == Final Output”).

2. Initial Plan
Scope and Main Features

Import/Preview

Import video files from device.

Import SRT subtitle files (manual import; auto-detect later).

Live video preview (top half of screen) with caption overlay (CustomPainter).

Scrollable timeline and caption list (bottom half) for editing / font/size/animation selection.

Caption styling & animations (MVP)

Font family, size, color, outline/shadow, alignment.

Word-by-word “pop” animation: each word appears sequentially, stays, then all words exit together.

Multi-line wrapping that fits portrait and landscape.

Export

Native encoder pipeline for final render (Android: MediaCodec/MediaMuxer; iOS: AVAssetWriter).

Export to Downloads/CaptionsApp/ with user-granted storage permission.

Keep audio (passthrough) in final MP4.

Developer tools / utilities

SRT parser and canonical Subtitle model.

Reusable CaptionPainter used for both Preview and Export to guarantee parity.

Flutter UI + Kotlin/Swift native encoder plugin bridged via MethodChannel & EventChannel.

Selected technologies / frameworks

Frontend: Flutter (Dart) — single codebase for Android/iOS.

Native Encoding: Android (Kotlin) using MediaCodec/MediaMuxer; iOS (Swift) using AVAssetWriter.

Packages: video_player, file_picker, permission_handler, path_provider.

Dev Tools: Git, Flutter toolchain, Android Studio for native debugging.

Intended user base

Mobile content creators who add stylized captions to short videos for social platforms.

Internal testing users and early adopters; later: general public release.

Timeline (example phases)

Prototype (short loop): UI, SRT import, live preview with simple painter.

MVP (local): Editor UI, word-by-word animation in preview, native Android exporter (beta).

Polish: iOS encoder, performance/quality tuning, onboarding + permission UX, sharing.

Later: Auto-captions (STT), cloud render option, font library, templates.

3. Later Changes and Updates
Modifications after Initial Planning (log of major decisions)

Switched from in-container ffmpeg-only workflow → hybrid approach
Why: Needed WYSIWYG preview in Flutter and performant native final render.
Result: CustomPainter preview + native encoder plugin (Kotlin/Swift) that accepts PNG overlays per frame.

Dropped ffmpeg_kit_flutter dependency
Why: Packaging and ABI issues + discontinued variant caused build problems. Native MediaCodec/MediaMuxer is lighter and better controlled.

Changed overlay delivery approach
Initial: On-demand: native requests overlay per-frame during encode.
Update: Pre-render overlays (per-subtitle timestamps) before starting encoding to avoid synchronous waits and jitter. Keep on-demand listener as fallback.

Storage & Permissions flow updated
Why: Android 11+ scoped storage changed rules.
Result: Use permission_handler to request MANAGE_EXTERNAL_STORAGE on Android 11+, fall back to storage on older versions. Save outputs to Downloads/CaptionsApp.

Kotlin plugin migration to V2 Flutter embedding
Why: Old plugin API caused runtime errors. Rewrote plugin to implement FlutterPlugin, MethodChannel, EventChannel.

Robust YUV→Bitmap conversion
Why: Early naive conversion caused BufferUnderflowException and buffer is inaccessible crashes. Implemented safe copying and fallback for corrupted buffers.

Technology / Process Adjustments

CI / build: Moved away from reliance on prebuilt ffmpeg images; CI will run Flutter builds + run unit tests. (Planned)

Testing approach: Add device-specific testing to validate MediaCodec compatibility across devices.

4. Key Assumptions and Constraints
Assumptions

Device hardware supports H.264 encoding via MediaCodec (most modern Android phones).

Users are willing to grant storage permission to save to Downloads.

Captions timing from SRT is accurate enough for word-by-word pop timing.

Preview rendering using Flutter CustomPainter can be rasterized to PNGs for overlays without significant visual difference.

Constraints

Android permission model (scoped storage / MANAGE_EXTERNAL_STORAGE) — may require manual settings if permanently denied.

Performance: Converting Image (YUV) → Bitmap and encoding in software is CPU-heavy; high resolution may be slow on older devices.

Device variability: MediaCodec/encoder capabilities differ between vendors; need fallbacks.

Licensing: Fonts included must be licensed for redistribution (embed only licensed fonts).

Memory: Pre-rendering many PNG overlays increases memory/disk usage temporarily.

5. Current Status and Outstanding Items
What’s done

Flutter UI: import video + SRT, video preview, caption timeline, basic editing UI — working.

CaptionPainter implemented and used in preview.

Kotlin native encoder plugin implemented (MediaCodec + MediaMuxer) for Android with EventChannel/MethodChannel handshake.

Export workflow implemented: pre-render overlays, native plugin composes video + overlay, export saved to Downloads/CaptionsApp.

Robust YUV→Bitmap conversion and safe threading improvements applied.

Ongoing / Pending

Performance tuning: reduce jitter, guarantee original FPS in final output for high-res videos.

Audio muxing robustness: ensure AAC passthrough for all codecs and container compatibility.

iOS encoder: AVAssetWriter implementation to reach parity with Android.

Edge-case tests: multiple devices, different frame rates, rotated videos, variable subtitle density.

User permission UX: better flows when manageExternalStorage is permanently denied (in-app guidance).

Memory management: ensure pre-render PNGs are paged/saved efficiently to avoid OOM.

Automated tests: unit tests for SRT parser, integration tests for preview/export parity.

CI integration and release packaging.

Open questions / required decisions

Font licensing: which font(s) to ship by default (Montserrat used in prototype — confirm licensing).

Export options: allow user to choose bitrate/resolution (scaling?) or always export at source resolution?

Should we provide a cloud render fallback for low-end devices?

6. Native Encoder API Contracts (finalize)

These are the agreed Flutter ↔ Native contracts used by the app.

MethodChannel: native_encoder (method names & arguments)

start

Args (map)

inputVideoPath (string) — absolute path to source video.

outputPath (string) — absolute path where native will write MP4 (or empty if native decides location).

width (int) — output width (pixels).

height (int) — output height (pixels).

fps (double/int) — target frames-per-second.

keepAudio (bool) — whether to copy audio track.

Returns: null (immediate) or throws error. Native begins encoding on background thread. Final completion signaled via result of finish call.

deliverOverlay

Args (map)

tMs (int) — timestamp in milliseconds the overlay corresponds to.

png (Uint8List) — PNG bytes representing overlay at tMs sized to output resolution.

Returns: null on success.

finish

Args: none

Returns: String — path to final MP4 (or error).

cancel

Args: none

Returns: null

EventChannel: native_encoder/events

Events emitted by native -> Flutter:

{ "type": "requestOverlay", "tMs": <int> }

Native asks Flutter to produce an overlay for timestamp tMs. Ideally the overlay is already pre-delivered; event is fallback/optional.

{ "type": "progress", "percent": <double> } (optional enhancement)

{ "type": "done", "path": "<outputPath>" } (optional enhancement if you want push notifications)

Behavior expectations

Flutter should pre-render overlays for subtitle timestamps and call deliverOverlay for each tMs prior to start to avoid runtime stalls.

Native plugin must call event channel on the main thread (UI thread). Native will wait a bounded time (e.g., 5s) for overlay; if none delivered, behave gracefully (use blank overlay / reuse last).

7. Testing Workflow to Verify Preview == Final
Automated & Manual tests

Unit tests

SRT parser: timing parsing, multi-line, commas/edge cases.

CaptionPainter layout tests using golden images (Dart test with flutter_test + golden_tool).

Integration tests

Small test videos with known FPS & SRT to compare frames:

Render preview at sample timestamps and rasterize painter to PNG.

Trigger native export for same timestamps and extract corresponding frames from exported MP4 (with ffprobe / MediaExtractor).

Pixel-diff frames (tolerance for encoding compression); failure if beyond threshold.

Manual device matrix tests

Devices: low / mid / high-end Android devices (various chipsets), and iOS models.

Test cases:

SRT with dense captions (many words per line).

Long subtitles that need wrapping (portrait).

High-resolution source (1080p/4K) to test performance.

Source with/without audio.

Device rotated or different aspect ratios.

Performance tests

Measure CPU, memory, and time to export for sample file sizes.

Confirm exported FPS ≈ source FPS (within small margin).

Test start-to-finish timings before and after pre-render optimization.

Acceptance criteria to confirm Preview == Final

Visual parity: for 95% of sampled frames across test set, SSIM/PSNR-based comparison between preview-generated PNGs and exported frames above threshold.

No dropped frames beyond an acceptable threshold for target device class.

Audio-sync: audio remains aligned to video within ±20 ms.

Exports are playable in mainstream players (Gallery, VLC, Google Photos).

8. Risks & Mitigations

Permission friction: Users may not grant MANAGE_EXTERNAL_STORAGE.
Mitigation: Provide clear prompt + in-app tutorial and fallback to internal storage or cloud export.

Device encoder variability: Some devices have buggy encoders.
Mitigation: Detect failures and fallback to alternative encoding strategies (software encode or different MIME).

Memory & CPU spikes: Pre-rendering for very long videos can OOM.
Mitigation: Stream overlays to disk temporarily and pre-render in batches; allow lower export resolution.

Legal/licensing: Bundled fonts or third-party assets.
Mitigation: Confirm font license before bundling; optionally download at runtime.

9. Next Actions / Roadmap (short term)

Finalize and harden native encoder plugin:

Ensure robust audio passthrough (AAC), finalize muxer handling.

Implement pipelined overlay delivery + backpressure handling.

Implement iOS native encoder (AVAssetWriter) to achieve feature parity.

Add automated integration tests to validate frame equality.

Add UI for export options (bitrate, scale, share-on-complete).

Prepare app store privacy & permission docs (storage access).

