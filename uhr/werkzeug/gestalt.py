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
GERAETE = {'resources': 466, 'resources-fenix9pro47mm': 454, 'resources-fenix9pro43mm': 416}
MIP = 'resources-fenix9prosolar51mm'
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
G6, G6T = grotesk(600, False), grotesk(600, True)
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

MIP_APP = {
    'Kopf': (MONO5, 17, 1, VOLL, True),
    'Mono': (MONO5, 18, 0, VOLL, False),
    'Klein': (G5, 21, 0, VOLL, True),
    'Text': (G5, 25, 0, VOLL, False),
    'Haupt': (G6, 28, 0, VOLL, True),
    'Gross': (G6, 32, 0, VOLL, False),
    'Titel': (G6, 42, 0, VOLL, False),
    'Zahl': (G6T, 44, 0, ZIFFERN + ' ', True),
    'Zahl2': (G6T, 76, -1, ZIFFERN, False),
    'Zahl1': (G6T, 100, -2, ZIFFERN, False),
    'Koppel': (G6, 64, 0, '0123456789 ', False),
    'Buch': (IS, 36, 0, VOLL, False),
    'Gruss': (ISR, 40, 0, VOLL, False),
}

MIP_ZIFFERBLATT = {
    'Uhr': (ISR, 92, 0, '0123456789:', False),
    'Mono': (MONO4, 11, 2, GROSS + '?', False),
    'MonoKlein': (MONO4, 10, 1.8, GROSS, False),
}

MIP_TRAIL = {
    'Marke': (MONO5, 16, 1, GROSS + 'm', False),
    'Zeit': (G6T, 36, 0, ZIFFERN, False),
    'Gross': (G6T, 64, -1, ZIFFERN, False),
    'Mittel': (G6T, 52, -1, ZIFFERN, False),
    'Wert': (G6T, 32, 0, ZIFFERN, False),
    'Navi': (G6, 18, 0, ZIFFERN + ' kmNOCH', False),
}


def schnitt(daten, zeichen, px):
    for quelle in [daten] + ERSATZ:
        roh = quelle if isinstance(quelle, bytes) else quelle.read_bytes()
        if ord(zeichen) in TTFont(io.BytesIO(roh), fontNumber=0).getBestCmap():
            return ImageFont.truetype(io.BytesIO(roh), px)
    return None


def kante(wert):
    return max(0, min(255, round((wert - 64) * 2)))


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
        stift.text((1 - links, 1 - oben), z, font=f, fill=255, anchor='ls')
        if scharf:
            bild = bild.point(kante)
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
            bild.putpixel((x, y), tuple(round(c) for c in farbe))
    return bild


def liste(ziel, schriften, scharf, mitBlick):
    zeilen = ['<resources>', '    <fonts>']
    for name, (daten, px, sperrung, zeichen, blick) in schriften.items():
        schrift(name, daten, px, sperrung, zeichen, ziel, scharf)
        umfang = ' scope="glance"' if blick and mitBlick else ''
        zeilen.append(f'        <font id="{name}" filename="{name}.fnt" antialias="true"{umfang}/>')
    return zeilen + ['    </fonts>']


def gestalt(projekt, schriften, mip, mitHintergrund, mitBlick):
    for ordner, breite in GERAETE.items():
        s = breite / ENTWURF
        ziel = projekt / ordner / 'gestalt'
        ziel.mkdir(parents=True, exist_ok=True)
        skaliert = {n: (d, px * s, sp * s, z, b) for n, (d, px, sp, z, b) in schriften.items()}
        zeilen = liste(ziel, skaliert, False, True)
        lichtpunkt(14 * s).save(ziel / 'lichtpunkt.png')
        umfang = ' scope="glance"' if mitBlick else ''
        zeilen += ['    <drawables>', f'        <bitmap id="Lichtpunkt" filename="lichtpunkt.png"{umfang}/>']
        if mitHintergrund:
            hintergrund(breite).save(ziel / 'hintergrund.png')
            zeilen.append(f'        <bitmap id="Hintergrund" filename="hintergrund.png"/>')
        zeilen += ['    </drawables>', '</resources>', '']
        (ziel / 'gestalt.xml').write_text('\n'.join(zeilen))
    ziel = projekt / MIP / 'gestalt'
    for alt in ziel.glob('*'):
        alt.unlink()
    ziel.mkdir(parents=True, exist_ok=True)
    (ziel / 'gestalt.xml').write_text('\n'.join(liste(ziel, mip, True, mitBlick) + ['</resources>', '']))


gestalt(UHR, SCHRIFTEN, MIP_APP, False, True)
gestalt(UHR / 'zifferblatt', ZIFFERBLATT, MIP_ZIFFERBLATT, True, False)
gestalt(UHR / 'trail', TRAIL, MIP_TRAIL, False, False)
