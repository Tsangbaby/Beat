import os, sys, struct, io, tarfile, lzma, gzip, bz2

def parse_ar(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'!<arch>\n', data[:8]
    off = 8
    members = []
    while off + 60 <= len(data):
        hdr = data[off:off+60]
        name = hdr[0:16].decode('utf-8', 'replace').rstrip()
        size = int(hdr[48:58].decode('utf-8', 'replace').strip())
        body_off = off + 60
        # BSD long name
        if name.startswith('#1/'):
            nlen = int(name[3:])
            real = data[body_off:body_off+nlen].decode('utf-8','replace').rstrip('\x00')
            body = data[body_off+nlen:body_off+size]
            name = real
        else:
            body = data[body_off:body_off+size]
            name = name.rstrip('/')
        members.append((name, body))
        off = body_off + size
        if size % 2: off += 1
    return members

def extract_tar(body, name, outdir):
    if body[:3] == b'\xfd7zXZ' or name.endswith('.xz'):
        raw = lzma.decompress(body)
    elif body[:2] == b'\x1f\x8b':
        raw = gzip.decompress(body)
    elif body[:3] == b'BZh':
        raw = bz2.decompress(body)
    elif body[:4] == b'\x28\xb5\x2f\xfd':
        import zstandard as zstd
        raw = zstd.ZstdDecompressor().decompress(body, max_output_size=200*1024*1024)
    else:
        raw = body
    tf = tarfile.open(fileobj=io.BytesIO(raw))
    os.makedirs(outdir, exist_ok=True)
    names = []
    for m in tf.getmembers():
        tf.extract(m, outdir)
        names.append((m.name, m.size))
    return names

if __name__ == '__main__':
    pkg = sys.argv[1]
    out = sys.argv[2]
    for name, body in parse_ar(pkg):
        print(f'member: {name} size={len(body)}')
        if name.startswith('data.tar') or name.startswith('control.tar'):
            d = os.path.join(out, name.split('.')[0])
            for n, s in extract_tar(body, name, d):
                print(f'   {n} {s}')
        elif name == 'debian-binary':
            print('   content:', body)
