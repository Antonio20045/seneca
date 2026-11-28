# Seneca-Zifferblatt 1.5.0 (fenix 9 Pro Solar, MIP): Farbverlauf Weiss -> Navy als Streifen, Uebergaenge als Blue-Noise-Korn.
# Eine Quelle fuer Entwurf und Uhr: `python3 verlauf.py <ordner>` schreibt die 12 Scheiben (280x32, Blue-Noise-Maske 64x64
# aus blaurauschen64.png) und verlauf.xml. Die Uhr schiebt den Streifen mit dem Tag (GesichtMip.mc, gleiche Formel fuer die Schriftfarben).
import math, os
W = 280
L = 340          # Laenge des Verlaufs (Streifen-Pixel) von Weiss bis Navy
BOGEN = 60       # rechts oben reicht das Licht weiter herab (App-Aufhellung)
BOGEN_X, BOGEN_B = 213, 110
H = 384          # Streifenhoehe (12 Scheiben a 32)
SCHEIBE = 32
RUHE = 0.6       # Anteil jeder Stufe, in dem das Korn vermittelt; sonst ruhige Flaeche
KETTE = [0x000055, 0x0055AA, 0x55AAFF, 0xAAFFFF, 0xFFFFFF]
MASKE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'blaurauschen64.png')
_maske = None

def void_cluster(n=64, sigma=1.6, seed=3):
    import numpy as np
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:n, 0:n]
    dx = np.minimum(xx, n - xx); dy = np.minimum(yy, n - yy)
    K = np.exp(-(dx * dx + dy * dy) / (2 * sigma * sigma))
    def shift(i): y, x = divmod(i, n); return np.roll(np.roll(K, y, 0), x, 1)
    P = np.zeros(n * n, bool); P[rng.choice(n * n, n * n // 10, replace=False)] = True
    def energie(P): return np.real(np.fft.ifft2(np.fft.fft2(P.reshape(n, n).astype(float)) * np.fft.fft2(K))).ravel()
    E = energie(P)
    while True:
        c = np.argmax(np.where(P, E, -1e9)); P[c] = False; E -= shift(c).ravel()
        v = np.argmin(np.where(P, 1e9, E)); P[v] = True; E += shift(v).ravel()
        if v == c: break
    rang = np.zeros(n * n, int); eins = int(P.sum())
    P1, E1 = P.copy(), E.copy()
    for r in range(eins - 1, -1, -1):
        c = np.argmax(np.where(P1, E1, -1e9)); P1[c] = False; E1 -= shift(c).ravel(); rang[c] = r
    P2, E2 = P.copy(), E.copy()
    for r in range(eins, n * n):
        v = np.argmin(np.where(P2, 1e9, E2)); P2[v] = True; E2 += shift(v).ravel(); rang[v] = r
    return rang.reshape(n, n)

def maske():
    global _maske
    if _maske is None:
        from PIL import Image
        if not os.path.exists(MASKE):
            Image.fromarray(void_cluster().astype('uint16')).save(MASKE)
        werte = list(Image.open(MASKE).getdata())
        _maske = [[(werte[y * 64 + x] + 0.5) / 4096 for x in range(64)] for y in range(64)]
    return _maske

def bogen(x):
    d = (x - BOGEN_X) / BOGEN_B
    return BOGEN * math.exp(-d * d)

def stufe(x, u, kette=KETTE):
    t = 1.0 - (u - bogen(x)) / L
    t = 0.0 if t < 0 else 1.0 if t > 1 else t
    v = (len(kette) - 1) * (0.6 * t + 0.4 * t * t * (3 - 2 * t))
    i = int(v)
    f = min(1.0, max(0.0, (v - i - (1 - RUHE) / 2) / RUHE))
    return i + f if i < len(kette) - 1 else v

def farbe_px(x, u, kette=KETTE):
    v = stufe(x, u, kette)
    i = int(v)
    if i >= len(kette) - 1: return kette[-1]
    return kette[i + 1] if v - i > maske()[u % 64][x % 64] else kette[i]

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
    'LINIE': ([0x55AAAA, 0x0055AA, 0x000055], [0x0055AA, 0x55AAFF, 0xAAFFFF], 1.6),
    'WARNUNG': ([0xAA5500, 0x550000], [0xFFAA00], 3.0),
    'a': ([0x0055AA, 0x000055], [0x55AAFF, 0xAAFFFF], 2.2),
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
