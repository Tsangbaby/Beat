import struct, sys, os

MH_MAGIC_64 = 0xfeedfacf
FAT_MAGIC = 0xcafebabe
FAT_MAGIC_64 = 0xcafebabf

def read_fat(path):
    data = open(path,'rb').read()
    magic = struct.unpack_from('>I', data, 0)[0]
    if magic in (FAT_MAGIC, FAT_MAGIC_64):
        nfat = struct.unpack_from('>I', data, 4)[0]
        archs = []
        for i in range(nfat):
            if magic == FAT_MAGIC:
                ct, cst, off, sz, al = struct.unpack_from('>IIIII', data, 8+i*20)
            else:
                ct, cst, off, sz, al = struct.unpack_from('>IIQQI', data, 8+i*32)
            archs.append((ct, cst, off, sz))
        return data, archs, True
    return data, [(0,0,0,len(data))], False

class MachO:
    def __init__(self, path, want_subtype=None):
        self.path = path
        full, archs, isfat = read_fat(path)
        self.isfat = isfat
        self.archs = archs
        ct, cst, off, sz = archs[0]
        for a in archs:
            if want_subtype is None or a[1] == want_subtype:
                ct, cst, off, sz = a
                if a[1] == want_subtype: break
        self.cputype, self.cpusubtype, self.base_off, self.size = ct, cst, off, sz
        data = full[off:off+sz]
        self.data = data
        magic, cputype, cpusub, ftype, ncmds, sizeofcmds, flags, res = struct.unpack_from('<IiiIIII I', data, 0)
        assert magic == MH_MAGIC_64, hex(magic)
        self.ftype = ftype
        self.ncmds = ncmds
        self.flags = flags
        self.cmds = []
        self.segs = []
        self.sects = []
        off2 = 32
        for i in range(ncmds):
            cmd, cmdsize = struct.unpack_from('<II', data, off2)
            body = data[off2:off2+cmdsize]
            self.cmds.append((cmd, cmdsize, off2, body))
            if cmd == 0x19:  # LC_SEGMENT_64
                segname = body[8:24].split(b'\x00')[0].decode()
                vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<QQQQ', body, 24)
                nsects = struct.unpack_from('<I', body, 64)[0]
                self.segs.append(dict(name=segname, vmaddr=vmaddr, vmsize=vmsize,
                                      fileoff=fileoff, filesize=filesize, nsects=nsects))
                for j in range(nsects):
                    so = 72 + j*80
                    sname = body[so:so+16].split(b'\x00')[0].decode()
                    sgname = body[so+16:so+32].split(b'\x00')[0].decode()
                    addr, ssize, offset, align, reloff, nreloc, sflags = struct.unpack_from('<QQIIIII', body, so+32)
                    self.sects.append(dict(name=sname, seg=sgname, addr=addr, size=ssize,
                                           offset=offset, flags=sflags))
            off2 += cmdsize
        self.seg0_vmaddr = self.segs[0]['vmaddr'] if self.segs else 0

    def sect(self, name, seg=None):
        for s in self.sects:
            if s['name'] == name and (seg is None or s['seg'] == seg):
                return s
        return None

    def a2o(self, addr):
        for s in self.segs:
            if s['vmaddr'] <= addr < s['vmaddr'] + s['vmsize']:
                return s['fileoff'] + (addr - s['vmaddr'])
        return None

    def read(self, addr, n):
        o = self.a2o(addr)
        if o is None: return None
        return self.data[o:o+n]

    def cstr(self, addr):
        o = self.a2o(addr)
        if o is None: return None
        e = self.data.find(b'\x00', o)
        return self.data[o:e].decode('utf-8','replace')

    def u32(self, addr):
        b = self.read(addr,4)
        return struct.unpack('<I', b)[0] if b and len(b)==4 else None
    def i32(self, addr):
        b = self.read(addr,4)
        return struct.unpack('<i', b)[0] if b and len(b)==4 else None
    def u64(self, addr):
        b = self.read(addr,8)
        return struct.unpack('<Q', b)[0] if b and len(b)==8 else None

def cmd_name(c):
    names = {0x19:'LC_SEGMENT_64',0x2:'LC_SYMTAB',0xb:'LC_DYSYMTAB',0xe:'LC_LOAD_DYLIB',
             0x1b:'LC_UUID',0x24:'LC_VERSION_MIN_IPHONEOS',0x26:'LC_FUNCTION_STARTS',
             0x1d:'LC_CODE_SIGNATURE',0x32:'LC_BUILD_VERSION',0x80000022:'LC_DYLD_INFO_ONLY',
             0x80000034:'LC_DYLD_CHAINED_FIXUPS',0x2a:'LC_SOURCE_VERSION',0xc:'LC_LOAD_DYLINKER',
             0x80000028:'LC_MAIN',0x21:'LC_ENCRYPTION_INFO',0x2c:'LC_ENCRYPTION_INFO_64',
             0x80000033:'LC_DYLD_EXPORTS_TRIE'}
    return names.get(c, hex(c))

if __name__ == '__main__':
    p = sys.argv[1]
    m = MachO(p)
    print(f'path={p}')
    print(f'fat={m.isfat} archs={m.archs}')
    print(f'cputype={m.cputype:#x} cpusubtype={m.cpusubtype:#x} ftype={m.ftype} ncmds={m.ncmds} flags={m.flags:#x}')
    print('--- load commands ---')
    for cmd, sz, off, body in m.cmds:
        extra = ''
        if cmd == 0xe:
            noff = struct.unpack_from('<I', body, 24)[0]
            extra = body[noff:].split(b'\x00')[0].decode()
        print(f'  {cmd_name(cmd):28s} size={sz} {extra}')
    print('--- segments/sections ---')
    for s in m.segs:
        print(f"  SEG {s['name']:16s} vm={s['vmaddr']:#x} vsize={s['vmsize']:#x} off={s['fileoff']:#x} fsize={s['filesize']:#x}")
        for sec in m.sects:
            if sec['seg']==s['name']:
                print(f"      {sec['name']:20s} addr={sec['addr']:#x} size={sec['size']:#x} off={sec['offset']:#x} flags={sec['flags']:#x}")
