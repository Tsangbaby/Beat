"""把指定函数导出为带注释的反汇编文本，便于逐条阅读"""
import sys, os
from dx import DX

COND = ('bl','b','cbz','cbnz','tbz','tbnz','cmp','cmn','tst','ret','brk','braa','retab')

def dump(dx, addr, out, count=None, stop_ret=False):
    """按函数边界截断；只保留"有语义"的指令，便于阅读"""
    import bisect
    i = bisect.bisect_right(dx.funcs, addr)
    end = dx.funcs[i] if i < len(dx.funcs) else addr + 0x4000
    n = max(1, (end - addr)//4)
    lines = []
    insns = dx.disas(addr, count=n, stop_ret=stop_ret)
    for ins in insns:
        note = getattr(ins, '_note', '')
        keep = bool(note) or ins.mnemonic in COND
        if not keep:
            continue
        if note:
            lines.append(f'{ins.address:#08x}  {ins.mnemonic:10s} {ins.op_str:46s} ; {note}')
        else:
            lines.append(f'{ins.address:#08x}  {ins.mnemonic:10s} {ins.op_str}')
    open(out, 'w', encoding='utf-8').write('\n'.join(lines))
    return len(lines)

if __name__ == '__main__':
    path = sys.argv[1]
    outdir = sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    dx = DX(path)
    targets = {
        0x74c54: 'deactivation_filter',
        0x73d84: 'gesture_manager',
        0x66c98: 'frame_math',
        0x2c430: 'app_workspace',
        0x428c4: 'app_enum',
        0x2b784: 'orientation',
        0x10058: 'window_setup',
        0x5acc0: 'statusbar_notify',
        0x5a6d0: 'notification_observer',
        0x5cbe8: 'touch_handling',
        0x5b2f8: 'gesture_state_machine',
        0x16ef0: 'license',
        0x14704: 'keyboard_layer',
        0x2ab20: 'switcher_storyboard',
    }
    for addr, name in targets.items():
        n = dump(dx, addr, os.path.join(outdir, f'{addr:05x}_{name}.txt'))
        print(f'{addr:#07x} {name:24s} {n} lines')
