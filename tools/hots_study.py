# Estudia modelos de Heroes of the Storm como referencia de diseño para las criaturas de GGmon.
# No copia nada al juego: mide cada modelo (poligonos, huesos, materiales, animaciones,
# proporciones) y guarda laminas de referencia en tools/ref/.
# Reutiliza el extractor del mod de Wolfenstein (M:\proyectos\rtcw-freeze\hots).
# Uso: py -3.12 hots_study.py [nombre ...]
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image

HOTS = r'M:\proyectos\rtcw-freeze\hots'
sys.path.insert(0, HOTS)
import m3anim  # noqa: E402
import m3mesh  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.join(HERE, 'ref')
RAW = os.path.join(REF, 'raw')
GAME = 'M:/Heroes of the Storm'
BASE = 'mods\\heroes.stormmod\\base.stormassets\\'
A = BASE + 'assets\\'

# nombre: (modelo, animaciones o None si vienen adentro)
MODELS = {
    'raptor': ('units/mounts/storm_mount_raptor_rank17/storm_mount_raptor_rank17_00.m3',
               'units/mounts/storm_mount_raptor_requiredanims/storm_mount_raptor_requiredanims.m3a'),
    'triceratops': ('units/mounts/storm_mount_battlebeast_triceratops/storm_mount_battlebeast_triceratops_00.m3',
                    'units/mounts/storm_mount_battlebeast_triceratops_requiredanims/storm_mount_battlebeast_triceratops_requiredanims.m3a'),
    'dehaka': ('units/heroes/storm_hero_dehaka_base/storm_hero_dehaka_base.m3',
               'units/heroes/storm_hero_dehaka_requiredanims/storm_hero_dehaka_requiredanims.m3a'),
    'dragon': ('units/heroes/storm_morph_alexstraszadragon_base/storm_morph_alexstraszadragon_base.m3',
               'units/heroes/storm_morph_alexstraszadragon_requiredanims/storm_morph_alexstraszadragon_requiredanims.m3a'),
    'brightwing': ('units/heroes/storm_hero_brightwing_base/storm_hero_brightwing_base.m3',
                   'units/heroes/storm_hero_brightwing_requiredanims/storm_hero_brightwing_requiredanims.m3a'),
    'beetle': ('units/pets/storm_pet_anubarakcarrionbeetle_base/storm_pet_anubarakcarrionbeetle_base.m3', None),
    'anubarak': ('units/heroes/storm_hero_anubarak_base/storm_hero_anubarak_base.m3',
                 'units/heroes/storm_hero_anubarak_requiredanims/storm_hero_anubarak_requiredanims.m3a'),
    'murky': ('units/heroes/storm_hero_murky_base/storm_hero_murky_base.m3',
              'units/heroes/storm_hero_murky_requiredanims/storm_hero_murky_requiredanims.m3a'),
}


def fetch(game_path, local):
    path = os.path.join(RAW, local)
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        subprocess.run([os.path.join(HOTS, 'hotsx.exe'), GAME, 'get', game_path.replace('/', '\\'), path],
                       stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
    return path if os.path.exists(path) and os.path.getsize(path) > 0 else None


def material_layers(model):
    """Por material: {capa: ruta de textura} para ver de que esta hecho el look."""
    out = {}
    for ref_index, ref in enumerate(model.materialReferences):
        if ref.materialType != 1:
            continue
        mat = model.standardMaterials[ref.materialIndex]
        layers = {}
        for attr in dir(mat):
            if not attr.endswith('Layer'):
                continue
            val = getattr(mat, attr)
            layer = val[0] if val else None
            path = getattr(layer, 'imagePath', None) if layer is not None else None
            if path:
                layers[attr[:-len('Layer')]] = path
        out[ref_index] = (mat.name, layers)
    return out


def study(name):
    m3_path, m3a_path = MODELS[name]
    local = fetch(A + m3_path, name + '.m3')
    if local is None:
        print('%s: no se pudo extraer %s' % (name, m3_path))
        return None
    model, regions = m3mesh.load(local)
    anim = model
    if m3a_path:
        anim_file = fetch(A + m3a_path, name + '_anims.m3a')
        if anim_file:
            loaded = m3mesh.m3.loadModel(anim_file)
            if len(loaded.sequences):
                anim = loaded
    seqs = [(s.name, s.animEndInMS - s.animStartInMS) for s in anim.sequences]

    # pose de reposo animada (Stand) para medir y dibujar como se ve en el juego
    skel = m3anim.Skeleton(model)
    stand = next((n for n, _ in seqs if n in ('Stand', 'Stand Ready', 'Stand 01')), None)
    stand = stand or next((n for n, _ in seqs if n.startswith('Stand')), None)
    pose = skel.pose(skel.tracks(anim, stand)[0], 0) if stand else skel.pose({}, 0)

    mats = material_layers(model)
    textures = {}
    for mat, (_, layers) in mats.items():
        path = layers.get('diffuse')
        if path and path.lower().endswith('.dds'):
            got = fetch((BASE if path.lower().startswith('assets') else '') + path, os.path.basename(path).lower())
            if got:
                try:
                    textures[mat] = Image.open(got).convert('RGB')
                except Exception as e:  # formato DDS que PIL no lee
                    print('  textura ilegible %s: %s' % (path, e))

    kept, total_v, total_t = [], 0, 0
    for r in regions:
        if not len(r.tris):
            continue
        xyz, _ = m3anim.deform(pose, r)
        size = np.linalg.norm(xyz.max(axis=0) - xyz.min(axis=0))
        rest = np.linalg.norm(r.xyz.max(axis=0) - r.xyz.min(axis=0))
        # la animacion esconde accesorios escalandolos a cero o hundiendolos
        if size < 0.25 * rest or xyz[:, 2].max() < 0.05:
            continue
        kept.append((r, xyz))
        total_v += len(xyz)
        total_t += len(r.tris)
    body_mat = max(kept, key=lambda k: len(k[1]))[0].material
    body = [k for k in kept if k[0].material == body_mat]
    pts = np.concatenate([xyz for _, xyz in body])
    lo, hi = pts.min(axis=0), pts.max(axis=0)
    dims = hi - lo    # x ancho, y largo (mira a -Y), z alto

    # perfil: alto y ancho del cuerpo en 16 rebanadas de la cabeza a la cola
    profile = []
    edges = np.linspace(lo[1], hi[1], 17)
    for i in range(16):
        sl = pts[(pts[:, 1] >= edges[i]) & (pts[:, 1] <= edges[i + 1])]
        if len(sl):
            profile.append([round(float(v), 2) for v in (
                (sl[:, 2].min() - lo[2]) / dims[2], (sl[:, 2].max() - lo[2]) / dims[2], (sl[:, 0].max() - sl[:, 0].min()) / dims[2])])
        else:
            profile.append(None)

    # huesos que realmente deforman el cuerpo
    used_bones = set()
    for r, _ in body:
        used_bones.update(np.unique(r.bones[r.weights > 0.01]).tolist())

    info = {
        'modelo': m3_path,
        'vertices': total_v, 'triangulos': total_t,
        'cuerpo': {'vertices': int(sum(len(x) for _, x in body)), 'triangulos': int(sum(len(r.tris) for r, _ in body))},
        'regiones': len(kept), 'huesos': len(model.bones), 'huesos_del_cuerpo': len(used_bones),
        'largo_alto_ancho': [round(float(dims[1] / dims[2]), 2), 1.0, round(float(dims[0] / dims[2]), 2)],
        'materiales': {str(k): {'nombre': n, 'capas': l} for k, (n, l) in mats.items()},
        'textura_cuerpo': list(textures[body_mat].size) if body_mat in textures else None,
        'animaciones': seqs,
        'perfil_cabeza_a_cola': profile,
    }

    # lamina: costado, frente, y la textura del cuerpo
    parts = [(xyz, r.st, r.tris, textures.get(r.material)) for r, xyz in kept]
    size = 640
    sheet = Image.new('RGB', (size * 3, size), (40, 44, 52))
    sheet.paste(m3mesh.render(parts, size, 'side'), (0, 0))
    sheet.paste(m3mesh.render(parts, size, 'front'), (size, 0))
    if body_mat in textures:
        sheet.paste(textures[body_mat].resize((size, size), Image.LANCZOS), (size * 2, 0))
    sheet.save(os.path.join(REF, name + '.png'))
    return info


if __name__ == '__main__':
    os.makedirs(RAW, exist_ok=True)
    report = {}
    for n in sys.argv[1:] or MODELS:
        print(n)
        try:
            info = study(n)
        except Exception as e:
            print('  fallo: %r' % e)
            continue
        if info:
            report[n] = info
            print('  %d tris, %d huesos (%d en el cuerpo), %d animaciones, largo/alto/ancho %s' % (
                info['triangulos'], info['huesos'], info['huesos_del_cuerpo'], len(info['animaciones']), info['largo_alto_ancho']))
    path = os.path.join(REF, 'estudio.json')
    old = json.load(open(path, encoding='utf-8')) if os.path.exists(path) else {}
    old.update(report)
    json.dump(old, open(path, 'w', encoding='utf-8'), indent=1, ensure_ascii=False)
