"""Generate the native app's pixel bicycle icon; stdlib, no downloaded assets."""
from pathlib import Path
import json
import struct
import zlib
root = Path(__file__).resolve().parents[1] / 'iOS/iLedBikeMobile/Assets.xcassets'
folder = root / 'AppIcon.appiconset'
folder.mkdir(parents=True, exist_ok=True)
size = 1024
pixels = bytearray(bytes([12, 17, 18]) * size * size)
def rect(x, y, w, h, color):
    row = bytes(color) * w
    for yy in range(y, y+h): pixels[(yy*size+x)*3:(yy*size+x+w)*3] = row
# A 40-cell sprite keeps the bicycle crisp even at home-screen size.
cell = 24
origin = 32
lime = [176, 245, 92]
rim = [222, 247, 240]
steel = [90, 149, 151]
def dot(x, y, color):
    rect(origin+x*cell, origin+y*cell, cell, cell, color)
def line(x0, y0, x1, y1, color):
    dx, dy = abs(x1-x0), -abs(y1-y0)
    sx, sy = (1 if x0<x1 else -1), (1 if y0<y1 else -1)
    error = dx+dy
    while True:
        dot(x0, y0, color)
        if (x0, y0) == (x1, y1): break
        doubled = 2*error
        if doubled >= dy: error += dy; x0 += sx
        if doubled <= dx: error += dx; y0 += sy
for cx in (10, 29):
    for y in range(-7, 8):
        for x in range(-7, 8):
            if 5.9**2 <= x*x+y*y <= 7.2**2:
                dot(cx+x, 25+y, rim)
    line(cx, 23, cx, 27, steel)
    line(cx-2, 25, cx+2, 25, steel)
# Two triangles, front fork, seat post, saddle and raised handlebars.
for segment in [(10,25,16,14), (16,14,22,25), (22,25,10,25),
                (16,14,27,14), (27,14,22,25), (26,10,29,25),
                (16,14,15,11)]:
    line(*segment, lime)
line(12, 10, 17, 10, rim)
line(25, 8, 29, 8, rim)
line(25, 9, 26, 10, rim)
line(29, 8, 30, 9, rim)
line(22, 25, 24, 28, steel)
line(23, 28, 26, 28, rim)
dot(10, 25, lime)
dot(29, 25, lime)
dot(22, 25, rim)
# A single amber rear light nods to the programmable bike displays.
dot(12, 12, [255, 166, 76])
def chunk(kind, data):
    return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))
raw = b''.join(b'\0'+pixels[y*size*3:(y+1)*size*3] for y in range(size))
(folder/'AppIcon.png').write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b''))
(root/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}},indent=2)+'\n')
(folder/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}},indent=2)+'\n')
print('Generated pixel bicycle app icon.')
