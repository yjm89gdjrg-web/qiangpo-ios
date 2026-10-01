#!/usr/bin/env python3
"""Build a deterministic, non-executable ShotDawn resource ZIP + manifest (no upload)."""
import argparse
import hashlib
import os
import json
import math
import re
import struct
import zipfile
from pathlib import Path

PREFIX = 'https://raw.githubusercontent.com/ftyhgddjhfd-jpg/qiangpo-ios/master/update/'
# Release owner may point delivery at an owned valid-certificate HTTPS path.
# Ends with '/' and is set explicitly when publishing, never widened at runtime.
EXTRA_PREFIX = os.environ.get('SHOTDAWN_UPDATE_PREFIX', '')
MAX_FILE = 8 * 1024 * 1024


def vector(value, count, low, high):
    return isinstance(value, list) and len(value) == count and all(
        type(v) in (int, float) and math.isfinite(v) and low <= v <= high for v in value)


def validate_map(data, names):
    allowed = {'schema', 'label', 'ground_color', 'wall_color', 'cover_color',
               'site_color', 'ground_texture', 'boxes'}
    if not isinstance(data, dict) or data.get('schema') != 1 or set(data) - allowed:
        raise ValueError('invalid map schema/fields')
    if not isinstance(data.get('label', ''), str) or len(data.get('label', '')) > 80:
        raise ValueError('invalid label')
    for key in ('ground_color', 'wall_color', 'cover_color', 'site_color'):
        if key in data and not vector(data[key], 4, 0, 1):
            raise ValueError('invalid color')
    if 'ground_texture' in data and (data['ground_texture'] not in names or not
                                    data['ground_texture'].startswith('textures/')):
        raise ValueError('missing texture')
    boxes = data.get('boxes', [])
    if not isinstance(boxes, list) or len(boxes) > 64:
        raise ValueError('too many boxes')
    for box in boxes:
        if (not isinstance(box, dict) or set(box) != {'position', 'size', 'color'} or
                not vector(box['position'], 3, -55, 55) or
                not vector(box['size'], 3, .1, 20) or not vector(box['color'], 4, 0, 1)):
            raise ValueError('invalid box')


def build(source, output, url, revision, min_app, max_app, notes=''):
    trusted = [PREFIX] + ([EXTRA_PREFIX] if EXTRA_PREFIX else [])
    if not any(url.startswith(p) for p in trusted) or any(c in url for c in ('..', '\\', '@', '%', '#', '?')):
        raise ValueError('URL must be the trusted repository raw HTTPS update path')
    def version(s):
        if not re.fullmatch(r'\d{1,3}\.\d{1,3}\.\d{1,3}', s):
            raise ValueError('invalid app version')
        return tuple(map(int, s.split('.')))
    if revision < 1 or version(min_app) > version(max_app):
        raise ValueError('invalid revision/version bounds')
    source, output = Path(source), Path(output)
    files = {}
    for file in sorted(source.rglob('*')):
        if file.is_symlink():
            raise ValueError('symlinks forbidden')
        if file.is_dir():
            continue
        name = file.relative_to(source).as_posix()
        if name != 'maps/main.json' and not re.fullmatch(r'textures/[a-z0-9_-]{1,80}\.png', name):
            raise ValueError('forbidden path: ' + name)
        raw = file.read_bytes()
        if not 0 < len(raw) <= MAX_FILE:
            raise ValueError('invalid file size: ' + name)
        if name.endswith('.png'):
            if len(raw) < 24 or raw[:8] != b'\x89PNG\r\n\x1a\n':
                raise ValueError('invalid PNG')
            width, height = struct.unpack('>II', raw[16:24])
            if not 1 <= width <= 2048 or not 1 <= height <= 2048:
                raise ValueError('PNG dimensions exceed limit')
        files[name] = raw
    if 'maps/main.json' not in files or len(files) > 65 or sum(map(len, files.values())) > 48 * 1024 * 1024:
        raise ValueError('invalid file list')
    validate_map(json.loads(files['maps/main.json']), files)
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f'resources-r{revision}.zip'
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_STORED) as z:
        for name, raw in sorted(files.items()):
            entry = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_STORED
            entry.external_attr = 0o100644 << 16
            z.writestr(entry, raw)
    size = archive.stat().st_size
    if size > 32 * 1024 * 1024:
        raise ValueError('archive exceeds 32 MiB')
    manifest = dict(schema=1, format='shotdawn-assets-zip-v1', revision=revision,
                    min_app=min_app, max_app=max_app, url=url, size=size,
                    sha256=hashlib.sha256(archive.read_bytes()).hexdigest(), notes=notes)
    (output / 'resources.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    return manifest


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', required=True)
    p.add_argument('--output', required=True)
    p.add_argument('--url', required=True)
    p.add_argument('--revision', type=int, required=True)
    p.add_argument('--min-app', default='1.2.2')
    p.add_argument('--max-app', default='1.2.2')
    p.add_argument('--notes', default='')
    a = p.parse_args()
    try:
        print(json.dumps(build(a.source, a.output, a.url, a.revision,
                               a.min_app, a.max_app, a.notes), ensure_ascii=False, indent=2))
    except (ValueError, OSError, json.JSONDecodeError) as e:
        p.error(str(e))
