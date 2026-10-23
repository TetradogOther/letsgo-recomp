"""make_icons.py: docs/icon/icon.svg -> icon_1024.png, icon.ico (Windows, 16..256), icon.icns (macOS) and the
hicolor set (Linux, the Debian package).

Needs rsvg-convert (MSYS2: mingw-w64-ucrt-x86_64-librsvg; Debian: librsvg2-bin). Run from the repository root:
  ./.venv/Scripts/python tools/make_icons.py
"""
import os
import shutil
import struct
import subprocess

DIR = os.path.join('docs', 'icon')
SVG = os.path.join(DIR, 'icon.svg')
RSVG = shutil.which('rsvg-convert') or r'C:\msys64\ucrt64\bin\rsvg-convert.exe'
HICOLOR = os.path.join(DIR, 'hicolor')  # (the Debian package's icons: <size>x<size>/apps/letsgo-recomp.png)
HICOLOR_SIZES = [16, 24, 32, 48, 64, 128, 256, 512]


def png(size):
    return subprocess.run([RSVG, '-w', str(size), '-h', str(size), SVG], check=True, capture_output=True).stdout


def main():
    with open(os.path.join(DIR, 'icon_1024.png'), 'wb') as f:
        f.write(png(1024))
    # ICO: PNG-compressed entries (Windows Vista and later read them at every size)
    sizes = [16, 24, 32, 48, 64, 128, 256]
    images = [png(s) for s in sizes]
    head = struct.pack('<HHH', 0, 1, len(sizes))
    off = 6 + 16 * len(sizes)
    dirs = b''
    for s, data in zip(sizes, images):
        dirs += struct.pack('<BBBBHHII', s % 256, s % 256, 0, 0, 1, 32, len(data), off)
        off += len(data)
    with open(os.path.join(DIR, 'icon.ico'), 'wb') as f:
        f.write(head + dirs + b''.join(images))
    # ICNS: PNG entries ic07 (128), ic08 (256), ic09 (512), ic10 (1024 / 512@2x)
    body = b''
    for code, s in ((b'ic07', 128), (b'ic08', 256), (b'ic09', 512), (b'ic10', 1024)):
        data = png(s)
        body += code + struct.pack('>I', 8 + len(data)) + data
    with open(os.path.join(DIR, 'icon.icns'), 'wb') as f:
        f.write(b'icns' + struct.pack('>I', 8 + len(body)) + body)
    # hicolor (Linux): the sizes a desktop asks for, and the scalable one
    for s in HICOLOR_SIZES:
        d = os.path.join(HICOLOR, f'{s}x{s}', 'apps')
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, 'letsgo-recomp.png'), 'wb') as f:
            f.write(png(s))
    d = os.path.join(HICOLOR, 'scalable', 'apps')
    os.makedirs(d, exist_ok=True)
    shutil.copyfile(SVG, os.path.join(d, 'letsgo-recomp.svg'))
    print('icon_1024.png, icon.ico (%s), icon.icns, hicolor (%s) written'
          % (', '.join(map(str, sizes)), ', '.join(map(str, HICOLOR_SIZES))))


if __name__ == '__main__':
    main()
