#!/usr/bin/env python3
"""Generate original, self-contained Godot PackedScenes; no imported model/texture inputs."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / 'scenes' / 'primitives'


def scene(name, parts, colors):
    resources, nodes = [], [f'[node name="{name}" type="Node3D"]']
    for key, color in colors.items():
        resources.append(f'[sub_resource type="StandardMaterial3D" id="Mat_{key}"]\nalbedo_color = Color({color})\nroughness = 0.8')
    for index, (label, kind, dims, pos, color, rotation) in enumerate(parts):
        mesh = f'Mesh_{index}'
        if kind == 'BoxMesh':
            props = f'size = Vector3({dims})'
        elif kind == 'CapsuleMesh':
            radius, height = dims
            props = f'radius = {radius}\nheight = {height}\nradial_segments = 12\nrings = 4'
        else:
            radius, height = dims
            props = f'top_radius = {radius}\nbottom_radius = {radius}\nheight = {height}\nradial_segments = 12'
        resources.append(f'[sub_resource type="{kind}" id="{mesh}"]\n{props}')
        nodes.append(f'[node name="{label}" type="MeshInstance3D" parent="."]\nposition = Vector3({pos})\nrotation = Vector3({rotation})\nmesh = SubResource("{mesh}")\nmaterial_override = SubResource("Mat_{color}")')
    return f'[gd_scene load_steps={len(resources)+1} format=3]\n\n' + '\n\n'.join(resources + nodes) + '\n'


def generate():
    ROOT.mkdir(parents=True, exist_ok=True)
    colors = {'armor': '0.23, 0.38, 0.56, 1', 'enemy': '0.72, 0.20, 0.18, 1', 'dark': '0.08, 0.10, 0.14, 1', 'visor': '0.20, 0.78, 0.88, 1'}
    for name, color in [('player_body', 'armor'), ('enemy_body', 'enemy')]:
        parts = [
            ('Torso', 'BoxMesh', '0.62, 0.68, 0.34', '0, 1.06, 0', color, '0, 0, 0'),
            ('Helmet', 'CapsuleMesh', (0.22, 0.43), '0, 1.60, 0', color, '0, 0, 0'),
            ('Visor', 'BoxMesh', '0.32, 0.10, 0.04', '0, 1.62, -0.21', 'visor', '0, 0, 0'),
            ('LeftLeg', 'CapsuleMesh', (0.12, 0.74), '-0.17, 0.38, 0', 'dark', '0, 0, 0'),
            ('RightLeg', 'CapsuleMesh', (0.12, 0.74), '0.17, 0.38, 0', 'dark', '0, 0, 0'),
            ('LeftArm', 'CapsuleMesh', (0.10, 0.62), '-0.40, 1.04, 0', color, '0, 0, 0.1'),
            ('RightArm', 'CapsuleMesh', (0.10, 0.62), '0.40, 1.04, 0', color, '0, 0, -0.1')]
        (ROOT / f'{name}.tscn').write_text(scene(name, parts, colors))
    weapons = [('ak47', .70, '0.66, 0.34, 0.13, 1', False), ('m4', .64, '0.17, 0.31, 0.38, 1', False), ('dragunov', .92, '0.32, 0.38, 0.20, 1', True), ('mosin9130', .96, '0.52, 0.29, 0.17, 1', False), ('l85', .52, '0.24, 0.45, 0.27, 1', False), ('g3a3', .78, '0.30, 0.28, 0.47, 1', False), ('m1911', .28, '0.57, 0.58, 0.62, 1', False)]
    for name, length, accent, scope in weapons:
        pistol = name == 'm1911'
        receiver = .20 if pistol else .34
        parts = [
            ('Receiver', 'BoxMesh', f'0.10, 0.10, {receiver}', '0, 0, -0.10', 'dark', '0, 0, 0'),
            ('Barrel', 'CylinderMesh', (.024, length * .55), f'0, 0.01, {-receiver/2-length*.275}', 'metal', '1.5707963, 0, 0'),
            ('Grip', 'BoxMesh', '0.075, 0.16, 0.09', '0, -0.11, 0', 'accent', '-0.20, 0, 0'),
            ('TopSight', 'BoxMesh', '0.025, 0.035, 0.035', f'0, 0.067, {-receiver*.7}', 'accent', '0, 0, 0')]
        if not pistol:
            parts += [('Stock', 'BoxMesh', '0.085, 0.11, 0.20', '0, -0.025, 0.16', 'accent', '0, 0, 0'), ('Magazine', 'BoxMesh', '0.07, 0.18, 0.10', '0, -0.13, -0.16', 'accent', '0.10, 0, 0'), ('Foregrip', 'BoxMesh', '0.09, 0.09, 0.18', f'0, -0.015, {-receiver/2-.08}', 'accent', '0, 0, 0')]
        if scope:
            parts.append(('Scope', 'CylinderMesh', (.043, .22), '0, 0.12, -0.12', 'accent', '1.5707963, 0, 0'))
        (ROOT / f'{name}.tscn').write_text(scene(name, parts, {'dark': '0.10, 0.12, 0.16, 1', 'metal': '0.32, 0.36, 0.40, 1', 'accent': accent}))


if __name__ == '__main__':
    generate()
