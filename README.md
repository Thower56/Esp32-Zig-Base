# Zig ESP32 Base Template

A minimal, working Zig project template for ESP32 microcontrollers.

## Quick Start

```bash
# Setup ESP-IDF environment
. ~/esp/esp-idf/export.sh

# Build
idf.py build

# Flash to ESP32
idf.py flash
```

## Project Structure

```
.
├── build.zig              # Zig build configuration
├── build.zig.zon         # Zig project metadata
├── CMakeLists.txt        # Root ESP-IDF config
├── cmake/                # Build system integration
├── imports/              # Zig API wrappers for ESP-IDF (~40 files)
├── include/              # C header stubs
├── main/
│   ├── app.zig          # YOUR CODE HERE
│   ├── CMakeLists.txt   # Component config
│   ├── idf_component.yml
│   └── placeholder.c
└── patches/             # Version compatibility fixes
```

## Editing Your Code

Edit `main/app.zig` to write your application:

```zig
const std = @import("std");
const esp = @import("imports/esp.zig");

pub fn main() void {
    // Your code here
}
```

## Requirements

- Zig 0.13.0+ (with Xtensa support)
- ESP-IDF (set via `export.sh`)
- LLD linker: `sudo apt-get install -y lld`
- CMake 3.12+

## Key Files

| File | Purpose | Modify? |
|------|---------|---------|
| `main/app.zig` | Your application | ✅ YES |
| `build.zig` | Zig build config | ❌ NO |
| `main/CMakeLists.txt` | Component config | ❌ NO |
| `cmake/*` | Build system | ❌ NO |
| `imports/*` | ESP-IDF API wrappers | ❌ NO |

## Troubleshooting

**Error: "failed to link with LLD: FileNotFound"**
```bash
sudo apt-get install -y lld
```

**Error: "IDF_PATH environment not set"**
```bash
. ~/esp/esp-idf/export.sh
```

**Clean rebuild**
```bash
idf.py fullclean
idf.py build
```

## More Information

- [Zig Language](https://ziglang.org/)
- [ESP-IDF Documentation](https://docs.espressif.com/projects/esp-idf/en/latest/)
- [ESP32 Specifications](https://www.espressif.com/en/products/microcontrollers/esp32/overview)
