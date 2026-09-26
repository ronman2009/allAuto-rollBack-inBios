#!/usr/bin/env python3
"""verify-uki.py - UKI 结构自检（构建回归防线）。
检查: PE 头合法、所有节区在 SizeOfImage 内、节区无重叠、.linux 必须最后。
"""
import struct
import sys

def main(path):
    d = open(path, "rb").read()
    e_lfanew = struct.unpack_from("<I", d, 0x3C)[0]
    assert d[e_lfanew:e_lfanew+4] == b"PE\0\0", "不是 PE 文件"
    coff = e_lfanew + 4
    _, nsec, _, _, _, opt_size, _ = struct.unpack_from("<HHIIIHH", d, coff)
    opt = coff + 20
    size_of_image = struct.unpack_from("<I", d, opt + 56)[0]
    secs = []
    for i in range(nsec):
        off = opt + opt_size + 40 * i
        name = d[off:off + 8].rstrip(b"\0").decode(errors="replace")
        vs, va = struct.unpack_from("<II", d, off + 8)
        secs.append((name, va, vs))
    srt = sorted(secs, key=lambda s: s[1])
    problems = []
    for a, b in zip(srt, srt[1:]):
        if a[1] + a[2] > b[1]:
            problems.append("节区重叠: %s 压过 %s" % (a[0], b[0]))
    for name, va, vs in secs:
        if va + vs > size_of_image:
            problems.append("%s 超出 SizeOfImage" % name)
    last = max(secs, key=lambda s: s[1])[0]
    if last != ".linux":
        problems.append("最后节区是 %s（应为 .linux）" % last)
    need = {".osrel", ".cmdline", ".initrd", ".linux"}
    have = {n for n, _, _ in secs}
    for n in need - have:
        problems.append("缺节区 %s" % n)
    if problems:
        for p in problems:
            print("!! " + p)
        sys.exit(1)
    print("* UKI 自检通过: SizeOfImage=0x%x, %d 节区, .linux 最后" % (size_of_image, nsec))

if __name__ == "__main__":
    main(sys.argv[1])
