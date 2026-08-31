# OverlayTweak v2.0 - CPM Image-to-Vinyl Automation

## Overview

OverlayTweak v2.0 is an iOS floating image overlay tweak that has been extended into a fully automated, AI-driven **Image-to-Vinyl Automation Tool** for the game **"Car Parking Multiplayer" (CPM)**.

This extended version builds upon the original OverlayTweak's floating overlay capabilities and adds 5 core modules for automated car vinyl creation:

1. **Floating Overlay UI & ROI Selector** - Extended overlay with region-of-interest selection
2. **Image Vectorization & Shape Decomposer** - CV engine to decompose images into CPM-compatible primitives
3. **CPM UI Layout Mapper & Calibration Engine** - JSON-based UI coordinate mapping
4. **Touch Injection & Macro Automation System** - IOHIDEvent touch synthesis for CPM vinyl editor
5. **Execution Controller & Safety System** - Thread-safe execution with emergency stop

## Project Structure

```
OverlayTweak/
├── Core/
│   ├── CPMVinylShape.h/.m         # CPM-compatible vinyl shape data model
│   ├── CPMShapeDecomposer.h/.m    # Image→shapes engine (K-Means + contour detection)
│   ├── CPMTouchInjector.h/.m      # IOHIDEvent touch synthesis engine
│   ├── CPMExecutionController.h/.m # Threaded execution + safety system
│   └── CPMUICalibration.h/.m      # UI calibration manager (JSON anchors)
├── UI/
│   ├── CPMAutoDrawViewController.h/.m  # Control panel UI
│   └── CPMROIOverlayView.h/.m         # ROI selector overlay
├── Resources/
│   └── cpm_ui_anchors.json         # Default UI calibration data
├── Makefile (updated for CPM modules)
├── OverlayCommon.h (extended with CPM constants)
├── OverlayEntry.m (extended)
├── OverlayManager.h/.m (extended with CPM automation APIs)
├── OverlayView.h/.m (extended with ROI selection)
├── SettingsViewController.h/.m (extended)
└── README.md
```

## Features

### Core OverlayTweak (Preserved)
- Scene-attached overlay window (iOS 13+), doesn't steal host key window
- Passthrough hit-testing when locked
- PHPicker image import + clipboard paste
- Overlay frame follows photo aspect ratio
- Card-based settings panel (v1.6)
- Opacity, scale, rotation, flip H/V, crop, warp, perspective, color pick
- Lock mode, hide/show overlay, edge tab
- Images saved as JPEG on disk

### New CPM Automation Features

#### 1. ROI Selector
- Interactive bounding box/region-of-interest selector for defining drawing area on the target car
- Drag to select, double-tap to clear
- Visual overlay with guide lines and center crosshair

#### 2. Shape Decomposer (CV Engine)
- **K-Means Color Quantization** (Accelerate framework) - reduces image to 6-12 key colors
- **Sobel Edge Detection** - finds edges in the ROI
- **8-Connected Contour Tracing** - extracts shape boundaries
- **Douglas-Peucker Simplification** - simplifies contours to essential points
- **Shape Classification** - identifies circles, rectangles, triangles, lines, polygons
- **Ear Clipping Triangulation** - breaks complex polygons into triangles
- Configurable max shapes (50-300, matching CPM layer limits)
- Progress callbacks during processing

#### 3. UI Calibration
- JSON-based anchor file (`cpm_ui_anchors.json`) mapping CPM vinyl editor UI elements:
  - Add Shape button
  - Shape Selector menu
  - Color Picker
  - RGB Sliders (Red, Green, Blue)
  - Scale/Rotate sliders
  - Move Joystick
  - Confirm/Cancel buttons
  - Layer List view
  - Zoom control
- Configurable per device screen size and orientation
- Save/load from UserDefaults for persistence

#### 4. Touch Injection Engine
- IOHIDEvent-based touch synthesis (for jailbreak/entitled environments)
- Supports tap, drag, long-press, slider-drag gestures
- Configurable touch delay (5-100ms) to match CPM UI processing speed
- Sequence execution with completion callbacks
- Emergency stop capability

#### 5. Execution Controller
- Background thread execution (NSOperationQueue)
- Real-time progress tracking (0.0-1.0)
- Layer count tracking (placed/total)
- Pause/Resume functionality
- Emergency stop with immediate halt
- Delegate/callback pattern for UI updates
- State machine: Idle → Loading → Decomposing → Placing → Completed/Paused/Stopped/Failed

#### 6. Control Panel UI
- Load Reference Image button
- Select ROI Region button
- Layer Limit slider (50-300)
- Touch Delay slider (5-100ms)
- Progress bar
- Status text
- Layer count display
- Start/Pause/Stop buttons
- Emergency stop via long-press on overlay

## Build Instructions

### Prerequisites
- macOS with Xcode installed
- iOS SDK (via `xcode-select`)
- For touch injection: jailbreak device or appropriate entitlements

### Building

```bash
chmod +x build_macos.sh
./build_macos.sh
```

Or using make:

```bash
make
```

### Injecting into an IPA

Requires `insert_dylib`:

```bash
mkdir -p tools
git clone https://github.com/tyilo/insert_dylib.git /tmp/insert_dylib
cc /tmp/insert_dylib/insert_dylib/main.c -o tools/insert_dylib

make inject IPA_PATH=/path/to/CPM.ipa
```

This produces `CPM_injected.ipa` which can be installed via TrollStore.

## Usage

### Basic Workflow

1. **Launch CPM** with the injected OverlayTweak dylib
2. **Tap the gear icon (⚙️)** to open settings or the new auto-draw panel
3. **Load Reference Image** - Pick an image from Photos or paste from clipboard
4. **Select ROI Region** - Drag to define the drawing area on the car body
5. **Configure Settings**:
   - Set max layer limit (default 200, max 300)
   - Adjust touch delay if needed (default 15ms)
6. **Start Auto-Draw** - The automation begins:
   - Image decomposition (K-Means + contour detection)
   - Shape placement via touch injection into CPM editor
7. **Monitor Progress** - Watch the progress bar and layer count
8. **Pause/Resume/Stop** as needed via control panel buttons

### Emergency Stop

- **Long-press** anywhere on the overlay to trigger emergency stop
- Or tap the red **Stop** button in the control panel

### Calibrating UI Anchors

The default `cpm_ui_anchors.json` provides baseline coordinates for iPhone 14 Pro (portrait). To calibrate for your device:

1. Open CPM vinyl editor
2. Note the screen positions of each UI element
3. Edit `cpm_ui_anchors.json` with your coordinates
4. Rebuild and reinject

Or use the calibration save/load functions in `CPMUICalibration` to persist custom anchors to UserDefaults.

## Technical Implementation

### Shape Decomposition Pipeline

```
Input Image (ROI) → Grayscale → Sobel Edge Detection → Binary Threshold → 
Contour Tracing → Douglas-Peucker Simplification → 
Shape Classification → Primitive Decomposition → CPMVinylShape Output
```

### Touch Injection Flow

```
For each CPMVinylShape:
  1. Tap "Add Shape" button
  2. Select primitive type (if not square)
  3. Drag move joystick to position
  4. Adjust R/G/B sliders for color
  5. Adjust scale slider
  6. Adjust rotation slider
  7. Tap "Confirm" button
  → Next shape
```

Each step includes the configured touch delay (default 15ms) to allow CPM UI to process inputs.

### Color Quantization

Uses K-Means clustering (Accelerate framework) to reduce the image colors to a configurable palette (default 8 colors). Colors are sorted by luminance for consistency.

For more detailed logos, Median Cut quantization is available as an alternative.

### Memory Safety

- High-resolution images are downscaled to max 2048px before processing
- Pixel data is processed in the configured ROI only
- ARC handles Objective-C object lifecycle
- Core Graphics objects are properly released

## Configuration

### UserDefaults Keys (CPM-specific)

| Key | Description |
|-----|-------------|
| `cpm_ui_anchors` | Serialized UI calibration data |
| `cpm_autodraw_active` | Whether auto-draw is currently running |
| `cpm_autodraw_paused` | Whether auto-draw is paused |
| `cpm_layer_limit` | Maximum layer count |
| `cpm_touch_delay_ms` | Delay between touch events (ms) |
| `cpm_reference_image` | Saved reference image (legacy) |
| `cpm_roi_rect` | Last used ROI rectangle |
| `cpm_calibration_version` | Calibration version for compatibility |
| `cpm_last_session_shapes` | Last session's shapes (debug) |
| `cpm_emergency_stop` | Emergency stop state |

### CPM Shape Primitive Types

- `CPMShapeTypeSquare` - Rectangle/square
- `CPMShapeTypeCircle` - Circle/ellipse
- `CPMShapeTypeTriangle` - Triangle (or polygon with 3 vertices)
- `CPMShapeTypeLine` - Line segment
- `CPMShapeTypePolygon` - Custom polygon (with vertex array)

## Limitations & Considerations

### Touch Injection
- IOHIDEvent-based injection requires jailbreak or special entitlements
- On non-jailbroken devices, touch injection may not work as intended
- Consider using companion app with CGEvent for non-jailbreak scenarios
- Always test touch sequences on your specific device/CPU

### Performance
- Shape decomposition is CPU-intensive; large images take time
- Progress callbacks allow UI to remain responsive
- Background queue prevents UI freezing

### Layer Limits
- CPM typically supports up to 300 layers
- Default max is 200 to stay safe
- Configurable up to 300 for advanced users

### Non-Destructive
- This tool does NOT modify the CPM binary
- All interactions are via touch emulation and overlay interfaces
- Safe for use without worrying about game updates breaking things

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Build fails | Ensure Xcode iOS SDK is selected via `xcode-select` |
| Overlay never appears | Check Console for `[OverlayTweak]` logs; verify dylib is injected |
| Touches blocked | Enable lock mode, or check if overlay has focus |
| Photo picker blank | Ensure PHPicker is presented on overlay window |
| Stutter during automation | Increase touch delay (slider in control panel) |
| Poor shape quality | Use higher resolution reference image; adjust color count and min shape area |
| CPM not recognizing touches | Verify touch injection is working; check if JP requires jailbreak |
| Wrong UI anchors | Recalibrate `cpm_ui_anchors.json` for your device screen size |

## License

Original OverlayTweak: MIT License
CPM Automation Extension: MIT License

## Credits

- **OverlayTweak** base: StrongBomber
- **CPM Image-to-Vinyl Automation**: Arena.ai Agent Mode
- **IOKit/IOHID** touch injection concepts: Various jailbreak community resources
