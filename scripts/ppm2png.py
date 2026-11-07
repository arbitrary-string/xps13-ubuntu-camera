# SPDX-License-Identifier: GPL-2.0-or-later
import sys, zlib, struct
d=open(sys.argv[1],'rb').read()
p=d.split(b'\n',3); w,h=map(int,p[1].split()); px=p[3]
st=int(sys.argv[3]) if len(sys.argv)>3 else 2
W,H=w//st,h//st; rows=bytearray()
for y in range(H):
    rows.append(0); r=px[(y*st)*w*3:(y*st)*w*3+w*3]
    for x in range(W): rows+=r[x*st*3:x*st*3+3]
def ch(t,b): return struct.pack('>I',len(b))+t+b+struct.pack('>I',zlib.crc32(t+b)&0xffffffff)
open(sys.argv[2],'wb').write(b'\x89PNG\r\n\x1a\n'+ch(b'IHDR',struct.pack('>IIBBBBB',W,H,8,2,0,0,0))+ch(b'IDAT',zlib.compress(bytes(rows)))+ch(b'IEND',b''))
