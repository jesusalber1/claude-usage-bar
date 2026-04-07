#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ClaudeUsageBar"
ICONSET_DIR="$SCRIPT_DIR/$APP_NAME.iconset"
PNG_SOURCE="$SCRIPT_DIR/icon_1024.png"

# Generate a simple icon using Python if no source PNG exists
if [ ! -f "$PNG_SOURCE" ]; then
    echo "Generating app icon..."
    python3 -c "
import struct, zlib

def create_png(width, height):
    def make_pixel(x, y):
        # Circle-based bar chart icon with orange/amber theme
        cx, cy = width / 2, height / 2
        r = min(width, height) * 0.42
        dx, dy = x - cx, y - cy
        dist = (dx*dx + dy*dy) ** 0.5

        # Background circle
        if dist <= r:
            # Dark background
            bg_r, bg_g, bg_b = 45, 45, 50

            # Draw three vertical bars
            bar_width = r * 0.18
            gap = r * 0.28
            bars = [
                (-gap, 0.75),  # left bar, 75% height
                (0, 0.50),     # middle bar, 50%
                (gap, 0.90),   # right bar, 90%
            ]

            bar_bottom = cy + r * 0.30
            for bx_offset, bar_pct in bars:
                bx = cx + bx_offset
                bar_top = bar_bottom - r * 0.7 * bar_pct
                half_w = bar_width / 2

                if bx - half_w <= x <= bx + half_w and bar_top <= y <= bar_bottom:
                    # Orange/amber gradient
                    t = (y - bar_top) / (bar_bottom - bar_top)
                    return (int(230 - t * 30), int(140 - t * 40), int(50 + t * 10), 255)

            return (bg_r, bg_g, bg_b, 255)

        # Slight shadow
        if dist <= r + 3:
            alpha = int(40 * (1 - (dist - r) / 3))
            return (0, 0, 0, alpha)

        return (0, 0, 0, 0)

    raw_data = b''
    for y in range(height):
        raw_data += b'\x00'  # filter byte
        for x in range(width):
            r, g, b, a = make_pixel(x, y)
            raw_data += struct.pack('BBBB', r, g, b, a)

    # PNG file structure
    def chunk(chunk_type, data):
        c = chunk_type + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)

    ihdr = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    compressed = zlib.compress(raw_data, 9)

    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', ihdr)
    png += chunk(b'IDAT', compressed)
    png += chunk(b'IEND', b'')
    return png

png_data = create_png(1024, 1024)
with open('$PNG_SOURCE', 'wb') as f:
    f.write(png_data)
print('Generated icon_1024.png')
"
fi

if [ ! -f "$PNG_SOURCE" ]; then
    echo "Warning: Could not generate icon, skipping .icns creation"
    exit 0
fi

# Create iconset
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

for size in 16 32 64 128 256 512 1024; do
    sips -z $size $size "$PNG_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}.png" > /dev/null 2>&1
done

# Create @2x variants
cp "$ICONSET_DIR/icon_32x32.png" "$ICONSET_DIR/icon_16x16@2x.png"
cp "$ICONSET_DIR/icon_64x64.png" "$ICONSET_DIR/icon_32x32@2x.png"
cp "$ICONSET_DIR/icon_256x256.png" "$ICONSET_DIR/icon_128x128@2x.png"
cp "$ICONSET_DIR/icon_512x512.png" "$ICONSET_DIR/icon_256x256@2x.png"
cp "$ICONSET_DIR/icon_1024x1024.png" "$ICONSET_DIR/icon_512x512@2x.png"
rm -f "$ICONSET_DIR/icon_64x64.png" "$ICONSET_DIR/icon_1024x1024.png"

# Generate .icns
iconutil -c icns "$ICONSET_DIR" -o "$SCRIPT_DIR/$APP_NAME.icns" 2>/dev/null || echo "Warning: iconutil failed, continuing without .icns"

# Cleanup
rm -rf "$ICONSET_DIR"

echo "Icon generated: $APP_NAME.icns"
