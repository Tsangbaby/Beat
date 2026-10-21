"""LC_DYLD_CHAINED_FIXUPS 解析：arm64(fmt 2/6) 与 arm64e(fmt 1/3) 分支"""
import struct

def parse_chained_fixups(m):
    lc = None
    for cmd, sz, off, body in m.cmds:
        if cmd == 0x80000034:
            dataoff, datasize = struct.unpack_from('<II', body, 8)
            lc = (dataoff, datasize)
    if not lc:
        return {}, {}, []
    base = lc[0]
    d = m.data
    version, starts_off, imports_off, symbols_off, imports_count, imports_format, symbols_format = \
        struct.unpack_from('<7I', d, base)
    rebase = {}
    bind = {}
    imports = []

    # imports
    if imports_format == 1:
        for i in range(imports_count):
            o = base + imports_off + i*4
            v = struct.unpack_from('<I', d, o)[0]
            libord = v & 0xff
            weak = (v >> 8) & 1
            nameoff = v >> 9
            s = d.find(b'\x00', base + symbols_off + nameoff)
            name = d[base+symbols_off+nameoff:s].decode('utf-8','replace')
            imports.append(dict(lib=libord, weak=weak, name=name))
    elif imports_format == 3:
        for i in range(imports_count):
            o = base + imports_off + i*16
            v, nameoff = struct.unpack_from('<QI', d, o)
            libord = v & 0xffff; weak = (v>>16)&1
            s = d.find(b'\x00', base + symbols_off + nameoff)
            name = d[base+symbols_off+nameoff:s].decode('utf-8','replace')
            imports.append(dict(lib=libord, weak=weak, name=name))

    starts = base + starts_off
    seg_count = struct.unpack_from('<I', d, starts)[0]
    seg_info_offs = struct.unpack_from('<%dI' % seg_count, d, starts+4)
    for si in range(seg_count):
        if seg_info_offs[si] == 0: continue
        info = starts + seg_info_offs[si]
        size = struct.unpack_from('<I', d, info)[0]
        page_size = struct.unpack_from('<H', d, info+4)[0]
        ptr_format = struct.unpack_from('<H', d, info+6)[0]
        segment_offset = struct.unpack_from('<Q', d, info+8)[0]
        max_valid = struct.unpack_from('<I', d, info+16)[0]
        page_count = struct.unpack_from('<H', d, info+20)[0]
        if ptr_format in (1, 3, 4, 5, 7, 9, 10, 12):
            stride = 8
            arm64e = True
        else:
            stride = 4
            arm64e = False
        # 该段对应的 vmaddr
        vm = None
        for s in m.segs:
            if s['fileoff'] == segment_offset:
                vm = s['vmaddr']; break
        if vm is None:
            for s in m.segs:
                if s['fileoff'] <= segment_offset < s['fileoff'] + max(s['filesize'], 1):
                    vm = s['vmaddr'] + (segment_offset - s['fileoff']); break
        if vm is None:
            continue
        for pi in range(page_count):
            ps = struct.unpack_from('<H', d, info+22+pi*2)[0]
            if ps == 0xFFFF: continue
            page_file = segment_offset + pi*page_size
            page_vm = vm + pi*page_size
            o = page_file + ps
            guard = 0
            while guard < 200000:
                guard += 1
                if o + 8 > len(d): break
                e = struct.unpack_from('<Q', d, o)[0]
                addr = page_vm + (o - page_file)
                if arm64e:
                    is_auth = (e >> 63) & 1
                    is_bind = (e >> 62) & 1
                    nxt = (e >> 51) & 0x7ff
                    if is_bind:
                        ord_ = e & 0xffffff
                        bind[addr] = imports[ord_] if ord_ < len(imports) else dict(name=f'<bad ord {ord_}>', lib=0, weak=0)
                    else:
                        # arm64e auth rebase 的 target 只有 32 位（43 位是 non-auth 形态）
                        tgt = (e & 0xffffffff) if is_auth else (e & ((1 << 43) - 1))
                        if tgt:
                            rebase[addr] = tgt
                else:
                    is_bind = (e >> 63) & 1
                    nxt = (e >> 51) & 0xfff
                    if is_bind:
                        ord_ = e & 0xffffff
                        bind[addr] = imports[ord_] if ord_ < len(imports) else dict(name=f'<bad ord {ord_}>', lib=0, weak=0)
                    else:
                        tgt = e & ((1 << 36) - 1) if ptr_format == 6 else (e & ((1 << 43) - 1))
                        if tgt:
                            rebase[addr] = tgt + m.seg0_vmaddr
                if nxt == 0: break
                o += nxt * stride
    return rebase, bind, imports

def resolve(m, rebase, bind, slot_addr):
    """读某个 8 字节槽的解析值：('bind', name) 或 ('ptr', addr) 或 None"""
    if slot_addr in bind: return ('bind', bind[slot_addr]['name'])
    if slot_addr in rebase: return ('ptr', rebase[slot_addr])
    v = m.u64(slot_addr)
    return ('raw', v) if v is not None else None
