import io
import math
import sys
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from PIL import Image, ImageDraw, ImageFont

UHR = Path(__file__).resolve().parent.parent
QUELLE = Path(sys.argv[1])
ENTWURF = 466
GERAETE = {'resources': 466, 'resources-fenix9pro47mm': 454, 'resources-fenix9pro43mm': 416, 'resources-fenix9prosolar51mm': 280}
MIP = {280: 10}
SCHARF = 20
BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
ERSATZ = [Path('/System/Library/Fonts/Menlo.ttc'), Path('/System/Library/Fonts/Apple Symbols.ttf')]

GROSS = ' ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜß0123456789·:%●Ø/.,–-+'
VOLL = ''.join(chr(c) for c in range(32, 127)) + 'ÄÖÜäöüß·×–—…„“”‘’°♥●○→éÉ± '
ZIFFERN = '0123456789:–-,.'
WERTE = ZIFFERN + '\u202f%'
DATUM = ' ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜ0123456789.'


def grotesk(gewicht, tabellarisch):
    schrift = instancer.instantiateVariableFont(TTFont(QUELLE / 'SpaceGrotesk[wght].ttf'), {'wght': gewicht})
    if tabellarisch:
        tausch = {}
        gsub = schrift['GSUB'].table
        for eintrag in gsub.FeatureList.FeatureRecord:
            if eintrag.FeatureTag == 'tnum':
                for nummer in eintrag.Feature.LookupListIndex:
                    for teil in gsub.LookupList.Lookup[nummer].SubTable:
                        tausch.update(getattr(teil, 'mapping', {}))
        for tabelle in schrift['cmap'].tables:
            for zeichen, glyphe in list(tabelle.cmap.items()):
                tabelle.cmap[zeichen] = tausch.get(glyphe, glyphe)
    puffer = io.BytesIO()
    schrift.save(puffer)
    return puffer.getvalue()


MONO5, MONO4 = (QUELLE / 'IBMPlexMono-Medium.ttf').read_bytes(), (QUELLE / 'IBMPlexMono-Regular.ttf').read_bytes()
G5T, G5, G4, G4T = grotesk(500, True), grotesk(500, False), grotesk(400, False), grotesk(400, True)
IS, ISR = (QUELLE / 'InstrumentSerif-Italic.ttf').read_bytes(), (QUELLE / 'InstrumentSerif-Regular.ttf').read_bytes()

SCHRIFTEN = {
    'M5_16': (MONO5, 16, 1.5, GROSS, True),
    'M5_17': (MONO5, 17, 1.5, GROSS, False),
    'M5_15': (MONO5, 15, 1.5, GROSS, False),
    'M5_14': (MONO5, 14, 0.5, VOLL, False),
    'M5_14W': (MONO5, 14, 1.2, GROSS, False),
    'M4_20': (MONO4, 20, 0, 'kgWdhMin ', False),
    'M4_15': (MONO4, 15, 0, VOLL, False),
    'M4_15W': (MONO4, 15, 1, GROSS, False),
    'M4_14': (MONO4, 14, 0, VOLL, False),
    'M4_13': (MONO4, 13, 0, VOLL, False),
    'M4_13W': (MONO4, 13, 1, GROSS, False),
    'M5_13W': (MONO5, 13, 1, GROSS, False),
    'M5_22W': (MONO5, 22, 1.4, GROSS, False),
    'G5_120': (G5T, 120, -3, ZIFFERN, False),
    'G5_96': (G5T, 96, -2, ZIFFERN, False),
    'G5_80': (G5, 80, 0, '0123456789 ', False),
    'G5_72': (G5T, 72, -1, ZIFFERN, False),
    'G5_64': (G5, 64, 0, ZIFFERN, True),
    'G5_40': (G5T, 40, 0, VOLL, False),
    'G5_38': (G5T, 38, 0, VOLL, False),
    'G5_36': (G5, 36, 0, 'Min ', False),
    'G5_34': (G5, 34, 0, VOLL, True),
    'G5_32': (G5, 32, 0, VOLL, False),
    'G5_30': (G5, 30, 0, VOLL, False),
    'G5_26': (G5, 26, 0, VOLL, False),
    'G5_22': (G5, 22, 0, VOLL, False),
    'G5_20': (G5, 20, 0, VOLL, False),
    'G5_18': (G5, 18, 0, VOLL, False),
    'G5_15': (G5, 15, 0, VOLL, False),
    'G4_26': (G4, 26, 0, VOLL, False),
    'G4_24': (G4, 24, 0, VOLL, False),
    'G4_22': (G4, 22, 0, VOLL, True),
    'G4_21': (G4, 21, 0, VOLL, False),
    'G4_20': (G4, 20, 0, VOLL, True),
    'G4_19': (G4, 19, 0, VOLL, False),
    'G4_18': (G4, 18, 0, VOLL, False),
    'G4_17': (G4, 17, 0, VOLL, False),
    'G4_15': (G4, 15, 0, VOLL, False),
    'I_48': (IS, 48, 0, VOLL, False),
    'IR_42': (ISR, 42, 0, VOLL, False),
    'I_34': (IS, 34, 0, VOLL, False),
    'I_26': (IS, 26, 0, VOLL, False),
}


ZIFFERBLATT = {
    'M5_14': (MONO5, 14, 0.5, VOLL, False),
    'M5_22D': (MONO5, 22, 2, DATUM, False),
    'M5_20D': (MONO5, 20, 2, DATUM, False),
    'M5_16L': (MONO5, 16, 1, GROSS, False),
    'M5_15L': (MONO5, 15, 1, GROSS, False),
    'IR_164': (ISR, 164, -2, ZIFFERN, False),
    'IR_152': (ISR, 152, -2, ZIFFERN, False),
    'IR_148': (ISR, 148, -2, ZIFFERN, False),
    'G4_32': (G4T, 32, 0, WERTE, False),
    'G4_30': (G4T, 30, 0, WERTE, False),
    'G4_20': (G4, 20, 0, '%', False),
    'G4_18': (G4, 18, 0, '%', False),
    'G5_22': (G5, 22, 0, VOLL, False),
    'G5_24D': (G5, 24, 3, DATUM, False),
    'G5_132': (G5T, 132, -3, ZIFFERN, False),
    'G5_124': (G5T, 124, -3, ZIFFERN, False),
    'G5_36': (G5T, 36, 0, WERTE, False),
    'G5_32': (G5T, 32, 0, WERTE, False),
    'G5_20': (G5, 20, 0, '%', False),
}

TRAIL = {
    'M5_14': (MONO5, 14, 0.5, VOLL, False),
    'M5_17W': (MONO5, 17, 1.5, GROSS + 'm', False),
    'M5_13W': (MONO5, 13, 1, GROSS, False),
    'G5_88': (G5T, 88, -2, ZIFFERN, False),
    'G5_72': (G5T, 72, -2, ZIFFERN, False),
    'G5_48': (G5T, 48, 0, ZIFFERN, False),
    'G5_40': (G5T, 40, 0, ZIFFERN, False),
    'G5_20': (G5T, 20, 0, ZIFFERN + ' km', False),
}

def schnitt(daten, zeichen, px):
    for quelle in [daten] + ERSATZ:
        roh = quelle if isinstance(quelle, bytes) else quelle.read_bytes()
        if ord(zeichen) in TTFont(io.BytesIO(roh), fontNumber=0).getBestCmap():
            return ImageFont.truetype(io.BytesIO(roh), px)
    return None


def schrift(name, daten, px, sperrung, zeichen, ziel, scharf):
    ober, unter = ImageFont.truetype(io.BytesIO(daten), px).getmetrics()
    glyphen = []
    for z in dict.fromkeys(zeichen):
        f = schnitt(daten, z, px)
        if f is None:
            continue
        links, oben, rechts, boden = f.getbbox(z, anchor='ls')
        bild = Image.new('L', (max(rechts - links, 0) + 2, max(boden - oben, 0) + 2), 0)
        stift = ImageDraw.Draw(bild)
        stift.fontmode = '1' if scharf else 'L'
        stift.text((1 - links, 1 - oben), z, font=f, fill=255, anchor='ls')
        glyphen.append((z, bild, links - 1, ober + oben - 1, round(f.getlength(z) + sperrung)))
    seite = 128
    while True:
        x = y = zeile = 0
        orte = []
        for _, bild, *_ in glyphen:
            if x + bild.width > seite:
                x, y, zeile = 0, y + zeile + 1, 0
            orte.append((x, y))
            x += bild.width + 1
            zeile = max(zeile, bild.height)
        if y + zeile <= seite:
            break
        seite *= 2
    atlas = Image.new('RGB', (seite, seite))
    zeilen = []
    for (z, bild, xo, yo, vorschub), (x, y) in zip(glyphen, orte):
        atlas.paste(Image.merge('RGB', (bild, bild, bild)), (x, y))
        zeilen.append(f'char id={ord(z)} x={x} y={y} width={bild.width} height={bild.height} xoffset={xo} yoffset={yo} xadvance={vorschub} page=0 chnl=15')
    atlas.save(ziel / f'{name}.png', optimize=True)
    (ziel / f'{name}.fnt').write_text('\n'.join([
        f'info face="{name}" size={round(px)} bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1',
        f'common lineHeight={ober + unter} base={ober} scaleW={seite} scaleH={seite} pages=1 packed=0',
        f'page id=0 file="{name}.png"', f'chars count={len(zeilen)}', *zeilen, '']))


def verlauf(stopps, t):
    if t <= stopps[0][0]:
        return stopps[0][1]
    for (a, fa), (b, fb) in zip(stopps, stopps[1:]):
        if t <= b:
            return tuple(fa[i] + (fb[i] - fa[i]) * (t - a) / (b - a) for i in range(len(fa)))
    return stopps[-1][1]


def lichtpunkt(px):
    n = max(round(px), 1)
    bild = Image.new('RGBA', (n, n))
    stopps = [(0, (255, 255, 255, 1)), (.26, (207, 228, 250, 1)), (.56, (110, 156, 224, .5)), (.76, (110, 156, 224, 0))]
    for y in range(n):
        for x in range(n):
            *farbe, a = verlauf(stopps, math.hypot(x + .5 - n / 2, y + .5 - n / 2) / (n / 2 * math.sqrt(2)))
            bild.putpixel((x, y), tuple(round(c) for c in farbe) + (round(a * 255),))
    return bild


def hintergrund(n):
    glanz = [(0, .34), (.11, .18), (.24, .06), (.36, 0)]
    oben = [(0, (0x12, 0x32, 0x64)), (.55, (0x0A, 0x1F, 0x44)), (1, (0x06, 0x16, 0x32))]
    weit = math.hypot(.74 * ENTWURF, ENTWURF - .16 * ENTWURF)
    bild = Image.new('RGB', (n, n))
    for y in range(n):
        grund = verlauf(oben, y / n)
        for x in range(n):
            a = verlauf([(t, (w,)) for t, w in glanz], math.hypot(x / n - .74, y / n - .16) * ENTWURF / weit)[0]
            farbe = [g + (h - g) * a for g, h in zip(grund, (0x8F, 0xB6, 0xE3))]
            if n in MIP:
                schwelle = (BAYER[y % 4 * 4 + x % 4] + .5) / 16
                farbe = [min(int(c / 85 + schwelle), 3) * 85 for c in farbe]
            bild.putpixel((x, y), tuple(round(c) for c in farbe))
    return bild


def gestalt(projekt, schriften, mitHintergrund, mitBlick):
    for ordner, breite in GERAETE.items():
        s = breite / ENTWURF
        ziel = projekt / ordner / 'gestalt'
        ziel.mkdir(parents=True, exist_ok=True)
        zeilen = ['<resources>', '    <fonts>']
        for name, (daten, px, sperrung, zeichen, blick) in schriften.items():
            groesse = max(px * s, MIP.get(breite, 0))
            schrift(name, daten, groesse, sperrung * s, zeichen, ziel, breite in MIP and groesse < SCHARF)
            zeilen.append(f'        <font id="{name}" filename="{name}.fnt" antialias="true"{" scope=\"glance\"" if blick else ""}/>')
        lichtpunkt(14 * s).save(ziel / 'lichtpunkt.png')
        umfang = ' scope="glance"' if mitBlick else ''
        zeilen += ['    </fonts>', '    <drawables>', f'        <bitmap id="Lichtpunkt" filename="lichtpunkt.png"{umfang}/>']
        if mitHintergrund:
            hintergrund(breite).save(ziel / 'hintergrund.png')
            zeilen.append(f'        <bitmap id="Hintergrund" filename="hintergrund.png"/>')
        zeilen += ['    </drawables>', '</resources>', '']
        (ziel / 'gestalt.xml').write_text('\n'.join(zeilen))


gestalt(UHR, SCHRIFTEN, False, True)
gestalt(UHR / 'zifferblatt', ZIFFERBLATT, True, False)
gestalt(UHR / 'trail', TRAIL, False, False)
