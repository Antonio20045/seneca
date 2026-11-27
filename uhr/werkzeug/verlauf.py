# Seneca-Zifferblatt 1.4.0 (fenix 9 Pro Solar, MIP): Farbverlauf Weiss -> Navy als Streifen.
# Eine Quelle fuer Entwurf und Uhr: `python3 verlauf.py <ordner>` schreibt die 12 Scheiben (280x32, Bayer 8x8)
# und verlauf.xml. Die Uhr schiebt den Streifen mit dem Tag (GesichtMip.mc, gleiche Formel fuer die Schriftfarben).
import math
W = 280
L = 340          # Laenge des Verlaufs (Streifen-Pixel) von Weiss bis Navy
BOGEN = 60       # rechts oben reicht das Licht weiter herab (App-Aufhellung)
BOGEN_X, BOGEN_B = 213, 110
H = 384          # Streifenhoehe (12 Scheiben a 32)
SCHEIBE = 32
BAYER = [[0, 32, 8, 40, 2, 34, 10, 42], [48, 16, 56, 24, 50, 18, 58, 26], [12, 44, 4, 36, 14, 46, 6, 38],
         [60, 28, 52, 20, 62, 30, 54, 22], [3, 35, 11, 43, 1, 33, 9, 41], [51, 19, 59, 27, 49, 17, 57, 25],
         [15, 47, 7, 39, 13, 45, 5, 37], [63, 31, 55, 23, 61, 29, 53, 21]]
KETTE = [0x000055, 0x5555AA, 0xAAAAFF, 0xFFFFFF]

def bogen(x):
    d = (x - BOGEN_X) / BOGEN_B
    return BOGEN * math.exp(-d * d)

def stufe(x, u, kette=KETTE):
    t = 1.0 - (u - bogen(x)) / L
    t = 0.0 if t < 0 else 1.0 if t > 1 else t
    return (len(kette) - 1) * (0.6 * t + 0.4 * t * t * (3 - 2 * t))

def farbe_px(x, u, kette=KETTE):
    v = stufe(x, u, kette)
    i = int(v)
    if i >= len(kette) - 1: return kette[-1]
    q = int((v - i) * 64)
    return kette[i + 1] if BAYER[u % 8][x % 8] < q else kette[i]

def rgb(c): return ((c >> 16) & 255, (c >> 8) & 255, c & 255)

def grund(off, kette=KETTE):
    from PIL import Image
    im = Image.new('RGB', (W, W)); px = im.load()
    for y in range(W):
        u = y + off
        for x in range(W):
            px[x, y] = rgb(kette[-1] if u < 0 else kette[0] if u >= H else farbe_px(x, u, kette))
    return im

LIN = {0: 0.0, 0x55: 0.0908, 0xAA: 0.402, 0xFF: 1.0}
def lum(c):
    r, g, b = rgb(c); return 0.2126 * LIN[r] + 0.7152 * LIN[g] + 0.0722 * LIN[b]
def kontrast(a, b):
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
def paar(x, u):
    if u < 0: return KETTE[-1], KETTE[-1], 0.0
    if u >= H: return KETTE[0], KETTE[0], 0.0
    v = stufe(x, u); i = int(v)
    if i >= len(KETTE) - 1: return KETTE[-1], KETTE[-1], 0.0
    return KETTE[i], KETTE[i + 1], v - i
# Rollen: (Kandidaten auf hellem Grund, Kandidaten auf dunklem Grund, Mindestkontrast)
ROLLEN = {
    'TINTE': ([0x000055], [0xFFFFFF], 1.0),
    'LEISE': ([0x555555, 0x000055], [0xAAAAAA, 0xFFFFFF], 7.0),
    'LINIE': ([0xAAAAAA, 0x5555AA, 0x000055], [0x0055AA, 0xAAAAFF, 0xFFFFFF], 1.6),
    'WARNUNG': ([0xAA5500, 0x550000], [0xFFAA00], 3.0),
    'a': ([0x0055AA, 0x0000AA, 0x000055], [0x55AAFF, 0xAAFFFF], 2.2),
    't': ([0x55AA55, 0x005500], [0xAAFFAA], 2.2),
    's': ([0xAA5555, 0xAA0000, 0x550000], [0xFFAAAA], 2.2),
}
def boden(x, y, off):
    a, b, f = paar(int(x), int(y) + off)
    return lum(a) * (1 - f) + lum(b) * f, a, b, f
def farbe(rolle, x, y, off):
    g, a, b, f = boden(x, y, off)
    hell = kontrast(lum(0x000055), g) >= kontrast(lum(0xFFFFFF), g)
    liste = ROLLEN[rolle][0 if hell else 1]
    for c in liste:
        if kontrast(lum(c), g) >= ROLLEN[rolle][2]: return c
    return liste[-1]
def hof(x, y, off):
    g, a, b, f = boden(x, y, off)
    hell = kontrast(lum(0x000055), g) >= kontrast(lum(0xFFFFFF), g)
    return None if f == 0 else (b if hell else a)

if __name__ == '__main__':
    import sys, os
    from PIL import Image
    aus = sys.argv[1]; os.makedirs(aus, exist_ok=True)
    teile = ['<resources>', '    <bitmaps>']
    for k in range(H // SCHEIBE):
        im = Image.new('RGB', (W, SCHEIBE)); px = im.load()
        for y in range(SCHEIBE):
            for x in range(W):
                px[x, y] = rgb(farbe_px(x, k * SCHEIBE + y))
        im.save(os.path.join(aus, 'verlauf%d.png' % k))
        teile.append('        <bitmap id="Verlauf%d" filename="verlauf%d.png" dithering="none"><palette disableTransparency="true">%s</palette></bitmap>'
                     % (k, k, ''.join('<color>%06X</color>' % c for c in KETTE)))
    teile += ['    </bitmaps>', '</resources>', '']
    open(os.path.join(aus, 'verlauf.xml'), 'w').write('\n'.join(teile))
