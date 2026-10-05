# Mira como estan armados los efectos de Heroes of the Storm (orbes, proyectiles):
# cuanta malla tienen, cuantos emisores de particulas, cintas y luces, y que texturas usan.
# Sirve de referencia para los efectos de GGmon. Uso: py -3.12 hots_fx.py
import os
import sys

HOTS = r'M:\proyectos\rtcw-freeze\hots'
sys.path.insert(0, HOTS)
import m3mesh  # noqa: E402
from hots_study import A, fetch, RAW  # noqa: E402

EFFECTS = [
    'effects/storm_effect_regenglobeblue/storm_effect_regenglobeblue.m3',
    'effects/storm_effect_regenglobeblue_missile/storm_effect_regenglobeblue_missile.m3',
    'effects/storm_fx_d3wizardf_base_arcaneorb_aoe/storm_fx_d3wizardf_base_arcaneorb_aoe.m3',
    'effects/storm_fx_alexstrasza_base_dragon_cast/storm_fx_alexstrasza_base_dragon_cast.m3',
    'effects/storm_fx_maiev_base_orbshadowstrike_missile/storm_fx_maiev_base_orbshadowstrike_missile.m3',
]

if __name__ == '__main__':
    os.makedirs(RAW, exist_ok=True)
    for path in EFFECTS:
        local = fetch(A + path, os.path.basename(path))
        if not local:
            print('no se pudo extraer', path)
            continue
        model = m3mesh.m3.loadModel(local)
        print(os.path.basename(path))
        counts = {}
        for attr in dir(model):
            if attr.startswith('_'):
                continue
            val = getattr(model, attr)
            if isinstance(val, list) and len(val) and attr not in ('vertices', 'boneLookup', 'bones', 'absoluteInverseBoneRestPositions', 'boneRests'):
                counts[attr] = len(val)
        print('  ', {k: v for k, v in counts.items() if not k.startswith('unknown')})
        div = model.divisions[0] if model.divisions else None
        if div:
            print('   malla: %d regiones, %d indices' % (len(div.regions), len(div.faces)))
        texs = set()
        for mats in ('standardMaterials', 'displacementMaterials', 'compositeMaterials'):
            for mat in getattr(model, mats, []):
                for attr in dir(mat):
                    if attr.endswith('Layer'):
                        val = getattr(mat, attr)
                        layer = val[0] if val else None
                        p = getattr(layer, 'imagePath', None) if layer is not None else None
                        if p:
                            texs.add(os.path.basename(p))
        print('   texturas:', sorted(texs)[:12])
        for ps in getattr(model, 'particles', [])[:4]:
            fields = {}
            for f in ('emissionRate', 'lifespan1', 'lifespan2', 'partEmit', 'emissionSpeed1'):
                v = getattr(ps, f, None)
                if v is not None:
                    fields[f] = getattr(v, 'initValue', v)
            print('   particulas:', fields)
