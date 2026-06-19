#!/usr/bin/env bash
# Renders the Macda mascot app icon and builds bundle/Macda.icns.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/icon.swift" <<'SWIFT'
import AppKit

let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let cx = size/2

func col(_ r: Double,_ g: Double,_ b: Double) -> CGColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: 1).cgColor
}

// Ears (drawn first so they peek above the squircle)
let earR = 118.0
for sx in [-1.0, 1.0] {
    ctx.setFillColor(col(0.72, 0.36, 0.22))
    ctx.fillEllipse(in: CGRect(x: cx + sx*168 - earR, y: 700 - earR + 140, width: earR*2, height: earR*2))
}

// Body squircle with a soft vertical gradient
let inset = 104.0
let rect = CGRect(x: inset, y: inset, width: size-2*inset, height: size-2*inset)
let radius = (size-2*inset)*0.235
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.saveGState(); ctx.addPath(path); ctx.clip()
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [col(0.80, 0.45, 0.30), col(0.62, 0.30, 0.18)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
// glossy highlight
ctx.setFillColor(NSColor(white: 1, alpha: 0.10).cgColor)
ctx.fillEllipse(in: CGRect(x: cx-300, y: 560, width: 380, height: 200))
ctx.restoreGState()

// Eyes
for sx in [-1.0, 1.0] {
    let ex = cx + sx*150
    ctx.setFillColor(col(1, 1, 1))
    ctx.fillEllipse(in: CGRect(x: ex-78, y: 470, width: 156, height: 188))
    ctx.setFillColor(col(0.16, 0.10, 0.07))
    ctx.fillEllipse(in: CGRect(x: ex-42 + sx*6, y: 488, width: 84, height: 84))
}

// Smile
ctx.setStrokeColor(col(1, 1, 1)); ctx.setLineWidth(26); ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: cx-95, y: 410))
ctx.addQuadCurve(to: CGPoint(x: cx+95, y: 410), control: CGPoint(x: cx, y: 330))
ctx.strokePath()

img.unlockFocus()
if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
SWIFT

echo "▶︎ Rendering icon…"
swift "$TMP/icon.swift" "$TMP/icon_1024.png"

echo "▶︎ Building iconset…"
ICONSET="$TMP/Macda.iconset"; mkdir -p "$ICONSET"
for s in 16 32 64 128 256 512 1024; do
  sips -z $s $s "$TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
done
# Retina (@2x) variants
cp "$ICONSET/icon_32x32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$ICONSET/icon_64x64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$ICONSET/icon_256x256.png" "$ICONSET/icon_128x128@2x.png"
cp "$ICONSET/icon_512x512.png" "$ICONSET/icon_256x256@2x.png"
cp "$ICONSET/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"
rm -f "$ICONSET/icon_64x64.png" "$ICONSET/icon_1024x1024.png"

iconutil -c icns "$ICONSET" -o "$ROOT/bundle/Macda.icns"
echo "✓ Wrote bundle/Macda.icns"
