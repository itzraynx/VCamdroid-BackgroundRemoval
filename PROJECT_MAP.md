# Project Map: Background Removal & Filters in VCamdroid

## Architecture Overview

**Goal**: Inject MediaPipe Selfie Segmentation into VCamdroid's RTSP pipeline to replace/blur background — plus standalone Chroma Key filter — all on-device with no cloud.

**Flow (Android)**:
```
Camera → [BackgroundRemovalFilterRender] → [other effects/corrections] → RTSP Server → PC Client
           ↑                         ↑
   SelfieSegmenterHelper       chroma key shader
   (MediaPipe CPU)             (pure GL, no ML)
```

**Flow (iOS)**:
```
Camera → CPU compositing (vImage + pixels) → VideoToolbox encode → RTSP Server → PC Client
           ↑                        ↑
   SelfieSegmenterHelper      ChromaKeyFilter
   (MediaPipe CPU)            (CPU pixel loop)
```

Key insight: All three new features share the same 256×256 downscale + inference pipeline (for MediaPipe filters) or a pure pixel-loop (for Chroma Key).

## Files — Android

### Modified

| File | What changed |
|------|-------------|
| `BackgroundRemovalFilterRender.kt` | Added `mode` property (`MODE_REMOVE` / `MODE_BLUR`). Shader now has `uMode` + `uPixelSize` uniforms. Mode 0 = black, Mode 1 = 5×5 box blur on background. |
| `FilterRepository.kt` | `FilterInfo` gains optional `configure` lambda. Added 2 entries: `Background Blur` (same class, mode=BLUR) and `Chroma Key` (new class). `create()` calls `configure()` after reflection. |
| `Streamer.kt` | Removed auto-apply of background removal in `applyOptionsToStream()`. Removed orphan imports `BackgroundRemovalFilterRender`, `SelfieSegmenterHelper`. |
| `StreamOptions.kt` | Removed `backgroundRemovalApplied: Boolean` field (no longer needed — toggle happens via the effect filter system). `deserialize()` unchanged (uses defaults for removed field). |

### New

| File | Purpose |
|------|---------|
| `ChromaKeyFilterRender.kt` | Standalone `BaseFilterRender`. Fragment shader does Euclidean distance `color.rgb - keyColor`. If `dist < tolerance`, pixel → #000000. Default key = green (0,1,0), tolerance=0.3. Tunable via `keyColorR/G/B` + `tolerance` fields. |

## Files — iOS

### Modified

| File | What changed |
|------|-------------|
| `BackgroundRemovalFilter.swift` | Added `enum Mode { remove, blur }` + `var mode`. `composite()` now does 5×5 box blur on background pixels when mode == `.blur`. |
| `StreamManager.swift` | Added `enum FilterType` with cases `none`, `backgroundRemoval`, `backgroundBlur`, `chromaKey`. `processFrame()` dispatches to the selected filter. No forced bg removal. Background removal is now opt-in. |
| `ControlsView.swift` | Added segmented `Picker` bound to `activeFilter`. Filter changes take effect on next stream start. |

### New

| File | Purpose |
|------|---------|
| `ChromaKeyFilter.swift` | CPU pixel-loop: for each pixel, compute Euclidean distance from key color (default green). Within tolerance → black. Outside → original. |

### Unchanged

`Shaders.metal`, `PixelBufferRenderer.swift`, `RTSPServer.swift`, `RTPPacketizer.swift`, `VideoEncoder.swift`, `SelfieSegmenterHelper.swift`, `ConnectionManager.swift`, `Logger.swift`

## Key Design Decisions

1. **Same class, configure lambda** — `BackgroundRemovalFilterRender` serves both "Remove" and "Blur" modes. The `FilterInfo.configure` lambda sets the mode after reflection-construction. No code duplication.
2. **5×5 box blur in fragment shader** — single-pass, no extra FBO writes. ~25 samples per background pixel. Acceptable perf (background is typically <50% of frame).
3. **No auto-apply** — background filters are now regular effect filters. Client chooses "None" to disable, "Background Removal" or "Background Blur" to enable. Chroma Key is a separate effect filter entry.
4. **Chroma Key in pure GLSL** (Android) / **CPU pixels** (iOS) — no MediaPipe dependency. Simple Euclidean distance in RGB space. Fast and predictable.
5. **`uPixelSize` uniform** — passed as `1/width, 1/height` from `drawFilter()` to allow the shader to compute accurate neighbor offsets for the blur kernel.

## Constraints

- Background processing (both Remove and Blur) requires MediaPipe (selfie model). Chroma Key does not.
- Both modes share the same inference pipeline — only the compositing step differs.
- Chroma Key runs on every frame (no inference rate-limiting).
- All filters are on-device, no cloud.

## Toggle / Filter Selection

- **Android**: The client sends "Apply Effect: Background Removal" / "Background Blur" / "Chroma Key" / "None" via the existing effect filter protocol. The `Streamer.applyEffectFilter()` method handles removal+addition atomically.
- **iOS**: SwiftUI segmented picker sets `StreamManager.activeFilter`. The filter is applied in `processFrame()` before encoding. Changes take effect on the next stream start.

## [ORPHANS_AND_PENDING]

| Item | Status |
|------|--------|
| Support `client.py` multiple-URL deserialization | Not started — PC client code not in scope |
| Android: Chroma Key color/tolerance from client | Not wired — client protocol doesn't support filter parameter passing yet |
| iOS: Filtered preview | Preview shows raw camera; encoder gets filtered output |
| iOS: Metal-based blur/chroma shaders | CPU fallback works; Metal path would be faster |

## Verification

1. **Build**: `./gradlew assembleDebug` — all filter classes compile, no orphan imports.
2. **Toggle**: Send "None" → no background processing. Send "Background Removal" → mask composite. Send "Background Blur" → blur composite. Send "Chroma Key" → green screen removal.
3. **No regression**: Existing effects (Grey Scale, Sepia, etc.) and corrections (Brightness, Contrast) still work — only `FilterInfo` constructor signature changed (backward-compatible default parameter).
