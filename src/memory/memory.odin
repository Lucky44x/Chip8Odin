package memory

import "core:mem"
import "core:fmt"
import "core:os"
import "core:math"

FONT : [80]u8 = {
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80  // F
}

FONT_START :: 0x100
FONT_END :: 0x150

Memory :: struct {
    ram: [^]u8,
    frameBuffer: [^]u8
}

init :: proc(
    ctx: ^Memory
) {
    ctx.ram = make([^]u8, 4096) // 4 KiB of RAM
    cpy_arr(ctx, FONT[:], FONT_START)
    ctx.frameBuffer = make([^]u8, 2048)
}

deinit :: proc(
    ctx: ^Memory
) {
    free(ctx.frameBuffer)
    free(ctx.ram)
}

load_prog :: proc(
    ctx: ^Memory,
    rom: os.Handle
) -> bool {
    dst := mem.ptr_offset(ctx.ram, 0x200)
    romSize, err := os.file_size(rom)
    if err != nil { fmt.eprintfln("Could not load rom-file\n-> %e", err); return false }

    _, err1 := os.read_ptr(rom, dst, cast(int)romSize)
    if err1 != nil { fmt.eprintfln("Could not load rom to memory\n-> %e", err1); return false }

    return true
}

clear_vbank :: proc(
    ctx: ^Memory
) {
    mem.set(ctx.frameBuffer, 0x00, 2048)
}

get_vbank :: proc(
    ctx: ^Memory,
    offset: int = 0
) -> u8 {
    return mem.reinterpret_copy(u8, mem.ptr_offset(ctx.frameBuffer, offset))
}

set_vbank :: proc(
    ctx: ^Memory,
    val: u8,
    offset: int = 0
) {
    dst := mem.ptr_offset(ctx.frameBuffer, offset)
    value: u8 = val
    _ = mem.copy(dst, &value, size_of(u8))
}

vbank_blit :: proc(
    ctx: ^Memory,
    x, y: u8
) -> bool {

    addr := u16(x) + (u16(y)*64)
    cur := get_vbank(ctx, int(addr))
    collision := cur == 0xFF
    cur ~= 0xFF
    set_vbank(ctx, cur, int(addr))
    return collision
}

get :: proc(
    ctx: ^Memory,
    $T: typeid,
    offset: int = 0
) -> T {
    when T == u8 do return mem.reinterpret_copy(u8, mem.ptr_offset(ctx.ram, offset))
    when T == u16 {
        b0 := get(ctx, u8, offset)
        b1 := get(ctx, u8, offset + 1)
        return T((u16(b0) << 8) | u16(b1))
    }
    return mem.reinterpret_copy(T, mem.ptr_offset(ctx.ram, offset))
}

put :: proc(
    ctx: ^Memory,
    val: $T,
    offset: int = 0
) {
    dst := mem.ptr_offset(ctx.ram, offset)
    value: T = val
    _ = mem.copy(dst, &value, size_of(T))
}

cpy_arr :: proc(
    ctx: ^Memory,
    val: []$T,
    offset: int = 0
) {
    dst := mem.ptr_offset(ctx.ram, offset)
    len := len(val)
    _ = mem.copy(dst, raw_data(val), len * size_of(T))
}

cpy_put :: proc(
    ctx: ^Memory,
    val: rawptr,
    len: int,
    offset: u16 = 0
) {
    dst := mem.ptr_offset(ctx.ram, offset)
    _ = mem.copy(dst, val, len)
}

cpy_get :: proc(
    ctx: ^Memory,
    out: rawptr,
    len: int,
    offset: u16 = 0
) {
    src := mem.ptr_offset(ctx.ram, offset)
    _ = mem.copy(out, src, len)
}