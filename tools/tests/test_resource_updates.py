#!/usr/bin/env python3
"""Real Godot process + verified local HTTPS fixture; no publish or host config changes."""
import argparse
import functools
import hashlib
import http.server
import importlib.util
import json
import os
from pathlib import Path
import shutil
import ssl
import sys
import struct
import subprocess
import tempfile
import threading
import zipfile
import zlib

sys.dont_write_bytecode = True
PROJECT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('builder', PROJECT / 'tools/build_resource_patch.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def png():
    def chunk(kind, raw):
        return struct.pack('>I', len(raw)) + kind + raw + struct.pack('>I', zlib.crc32(kind + raw))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 2, 2, 8, 2, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(b'\x00\x20\x60\xcc\x20\x60\xcc' * 2)) + chunk(b'IEND', b''))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default='/home/ubuntu/qiangpo/tools/Godot_v4.4.1-stable_linux.x86_64')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='shotdawn-hot-update-') as tmp:
        temp = Path(tmp)
        source, output = temp / 'source', temp / 'https'
        shutil.copytree(PROJECT / 'tools/tests/fixtures/resource_patch', source)
        (source / 'textures').mkdir()
        (source / 'textures/grid.png').write_bytes(png())
        data = json.loads((source / 'maps/main.json').read_text())
        data['ground_texture'] = 'textures/grid.png'
        (source / 'maps/main.json').write_text(json.dumps(data))
        url = builder.PREFIX + 'resources-r7.zip'
        manifest = builder.build(source, output, url, 7, '1.2.2', '1.2.2', 'Test visual patch')
        first = (output / 'resources-r7.zip').read_bytes()
        builder.build(source, output, url, 7, '1.2.2', '1.2.2')
        assert first == (output / 'resources-r7.zip').read_bytes(), 'builder must be deterministic'
        print('PASS deterministic restricted ZIP builder', flush=True)
        for name in ('script', 'traversal', 'deflate', 'duplicate', 'scene', 'symlink', 'central', 'badmap', 'hugepng', 'truncated'):
            path = output / f'bad-{name}.zip'
            with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED if name == 'deflate' else zipfile.ZIP_STORED) as z:
                content = json.dumps({'schema': 1, 'script': 'evil.gd'}).encode() if name == 'badmap' else (source / 'maps/main.json').read_bytes()
                z.writestr('maps/main.json', content)
                z.writestr('textures/grid.png', png())
                if name in ('script', 'traversal', 'scene'):
                    extra = {'script': 'scripts/evil.gd', 'traversal': '../evil.png', 'scene': 'maps/main.tscn'}[name]
                    z.writestr(extra, 'evil')
                if name == 'duplicate':
                    z.writestr('maps/main.json', content)
                if name == 'symlink':
                    entry = zipfile.ZipInfo('textures/link.png')
                    entry.external_attr = 0o120777 << 16
                    z.writestr(entry, 'outside')
                if name == 'hugepng':
                    z.writestr('textures/huge.png', b'\x89PNG\r\n\x1a\n' + b'\0' * 8 + struct.pack('>II', 100000, 100000))
            if name == 'central':
                raw = bytearray(path.read_bytes())
                index = raw.index(b'PK\x01\x02')
                raw[index + 10:index + 12] = struct.pack('<H', 8)  # malicious mismatched decompression header
                path.write_bytes(raw)
            if name == 'truncated':
                path.write_bytes(path.read_bytes()[:-10])
        # Builder itself rejects script files instead of quietly ignoring them.
        (source / 'evil.gd').write_text('extends Node')
        try:
            builder.build(source, output, url, 7, '1.2.2', '1.2.2')
            raise AssertionError('builder accepted executable payload')
        except ValueError:
            print('PASS builder rejects executable payload', flush=True)
        (source / 'evil.gd').unlink()
        # Generate an ephemeral CA/server certificate in the test directory only.
        cert, key = temp / 'cert.pem', temp / 'key.pem'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                        '-keyout', str(key), '-out', str(cert), '-days', '1', '-subj', '/CN=localhost',
                        '-addext', 'subjectAltName=DNS:localhost', '-addext', 'basicConstraints=critical,CA:TRUE'],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        class FixtureHandler(http.server.SimpleHTTPRequestHandler):
            def do_GET(self):
                if self.path == '/redirect.zip':
                    self.send_response(302)
                    self.send_header('Location', 'https://attacker.invalid/evil.zip')
                    self.end_headers()
                else:
                    super().do_GET()
        handler = functools.partial(FixtureHandler, directory=str(output))
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        env = os.environ.copy()
        env.update(XDG_DATA_HOME=str(temp / 'userdata'), PATCH_TEST_DIR=str(output),
                   PATCH_TEST_CERT=str(cert), PATCH_TEST_SERVER=f'https://localhost:{server.server_port}')
        def run(mode):
            p = subprocess.run([args.godot, '--headless', '--path', str(PROJECT), '--script',
                                'res://tools/tests/resource_pipeline_test.gd', '--', mode],
                               env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
            print(p.stdout, end='', flush=True)
            assert p.returncode == 0 and 'SCRIPT ERROR' not in p.stdout and 'FAIL ' not in p.stdout, mode
        try:
            run('download')
            run('boot')
            run('negative')
            active_files = list((temp / 'userdata').rglob('active.json'))
            assert len(active_files) == 1
            root = active_files[0].parent
            (root / manifest['sha256'] / 'assets.zip').write_bytes(b'corrupt')
            run('fallback')
            # Install two more valid patches; corrupt newest to test last-good rollback.
            data.pop('ground_texture')
            (source / 'maps/main.json').write_text(json.dumps(data))
            for revision in (8, 9):
                data['label'] = f'Patch {revision}'
                (source / 'maps/main.json').write_text(json.dumps(data))
                m = builder.build(source, output, builder.PREFIX + f'resources-r{revision}.zip', revision, '1.2.2', '1.2.2')
                (output / f'manifest-r{revision}.json').write_text(json.dumps(m))
            run('install_next')
            state = json.loads(active_files[0].read_text())
            (root / state['sha256'] / 'assets.zip').write_bytes(b'corrupt')
            run('previous')
        finally:
            server.shutdown()
            server.server_close()
        print('PASS all resource update end-to-end and failure/security tests', flush=True)


if __name__ == '__main__':
    main()
