package cpu

import rl "vendor:raylib"
import "core:math/rand"
import "../memory"
import "core:fmt"

KeyTable : [16]rl.KeyboardKey : {
    .ONE, .TWO, .THREE, .FOUR,
    .Q, .W, .E, .R,
    .A, .S, .D, .F,
    .Z, .X, .C, .V
}

CPU :: struct {
    PC: u16,                // Program Counter
    reg_I: u16,             // I - Register
    delay, sound: u8,       // Delay and Sound Timers
    registers: [^]u8,       // Variable Registers V0 - VF
    stack: [dynamic]u16,    // Stack
}

init :: proc(
    ctx: ^CPU
) {
    ctx.stack = make([dynamic]u16)
    ctx.registers = make([^]u8, 16)
}

deinit :: proc(
    ctx: CPU
) {
    delete(ctx.stack)
    free(ctx.registers)
}

push_stack :: proc(
    ctx: ^CPU,
    val: u16
) {
    append(&ctx.stack, val)
}

pop_stack :: proc(
    ctx: ^CPU
) -> u16 {
    if len(ctx.stack) == 0 do return 0x200
    val: u16 = pop(&ctx.stack)
    return val
}

tick_timers :: proc(
    ctx: ^CPU
) {
    if ctx.delay > 0 { ctx.delay -= 1 }
    if ctx.sound > 0 { ctx.sound -= 1 }
}

/*
    Run this at 700 Hz
*/
tick :: proc(
    ctx: ^CPU,
    ctx_mem: ^memory.Memory
) {
    ins: u16 = fetch(ctx, ctx_mem)
    decode(ctx, ctx_mem, ins)
}

@private
fetch_key :: proc(
    code: u8
) -> bool {
    table := KeyTable
    return rl.IsKeyDown(table[code])
}

@private 
fetch_keypress :: proc() -> (pressed: bool, key: u8) {
    table := KeyTable
    for i in 0..<16 {
        if rl.IsKeyReleased(table[i]) do return true, u8(i)
    }
    return false, 0x00
}

@(private)
fetch :: proc(
    ctx: ^CPU,
    ctx_mem: ^memory.Memory 
) -> u16 {
    ins := memory.get(ctx_mem, u16, cast(int)ctx.PC)    // Fetch current instruction
    ctx.PC += 2                                 // Roll over to next instruction 
    return ins
}

@(private)
decode :: proc(
    ctx: ^CPU,
    ctx_mem: ^memory.Memory,
    ins_val: u16
) {
    ins := ins_val

    opcode := (ins & 0xF000) >> 12
    x := (ins & 0x0F00) >> 8
    y := (ins & 0x00F0) >> 4
    n := (ins & 0x000F)
    nn := (ins & 0x00FF)
    nnn := (ins & 0x0FFF)

    switch (opcode) {
        case 0x0:
            if nn == 0xEE {                 // 0x00EE Return from Subroutine 
                prev: u16 = pop_stack(ctx)
                ctx.PC = prev
                break
            } else if nn == 0xE0 {          // 0x00E0 Clear Display
                memory.clear_vbank(ctx_mem)       
            }
            break
        case 0x1:                           // 0x1NNN Jump to NNN
            ctx.PC = nnn
            break
        case 0x2:                           // 0x2NNN Call NNN as subroutine
            push_stack(ctx, ctx.PC)
            ctx.PC = nnn
            break
        case 0x3:                           // 0x3XNN Skip next if Vx == NN
            if ctx.registers[x] == cast(u8)nn { ctx.PC += 2 }
            break
        case 0x4:                           // 0x4XNN Skip next if Vx != NN
            if ctx.registers[x] != cast(u8)nn { ctx.PC += 2 }
            break
        case 0x5:                           // 0x5XY0 Skip next if Vx == Vy
            if ctx.registers[x] == ctx.registers[y] { ctx.PC += 2 }
            break
        case 0x6:                           // 0x6XNN Set VX to NN
            ctx.registers[x] = cast(u8)nn
            break
        case 0x7:                           // 0x7XNN Add NN to Vx - NO CARRY FLAG
            ctx.registers[x] += cast(u8)nn
            break
        case 0x8:
            switch n {
                case 0x0:                       // 0x8XY0 Set Vx to Vy
                    ctx.registers[x] = ctx.registers[y]
                    break
                case 0x1:                       // 0x8XY1 Set Vx bitwise or Vy
                    ctx.registers[x] |= ctx.registers[y]
                    break
                case 0x2:                       // 0x8XY2 Set Vx bitwise and Vy
                    ctx.registers[x] &= ctx.registers[y]
                    break
                case 0x3:                       // 0x8XY3 Set Vx bitwise or Vy
                    ctx.registers[x] ~= ctx.registers[y]
                    break
                case 0x4:                       // 0x8XY4 Add Vy to Vx
                    val := u16(ctx.registers[x]) + u16(ctx.registers[y])
                    ctx.registers[x] += ctx.registers[y]
                    if val > 255 { ctx.registers[0xF] = 1 } // Set overflow
                    else { ctx.registers[0xF] = 0 }
                    break
                case 0x5:                       // 0x8XY5 Subtract Vy from Vx
                    valX,valY := ctx.registers[x], ctx.registers[y]
                    ctx.registers[x] -= ctx.registers[y]
                    if valX >= valY { ctx.registers[0xF] = 1 } // Set underflow
                    else { ctx.registers[0xF] = 0 }
                    break
                case 0x6:                       // 0x8XY6 Bitwise Rightshift and Vf = least significatn bit before shift
                    old := ctx.registers[x]
                    ctx.registers[x] = old >> 1
                    ctx.registers[0xF] = old & 0x01
                    break
                case 0x7:                       // 0x8XY7 Vx = Vy - Vx
                    valX,valY := ctx.registers[x], ctx.registers[y]
                    ctx.registers[x] = ctx.registers[y] - ctx.registers[x]
                    if valY >= valX { ctx.registers[0xF] = 1 } // Set underflow
                    else { ctx.registers[0xF] = 0 }
                    break
                case 0xE:                       // 0x8XYE  Bitwise leftshift and Vf = most significatn bit before shift
                    old := ctx.registers[x];
                    ctx.registers[x] = old << 1;
                    ctx.registers[0xF] = (old >> 7) & 0x01;
                    break
            }
            break
        case 0x9:                           // 0x9XY0 Skip next if Vx != Vy
            if ctx.registers[x] != ctx.registers[y] { ctx.PC += 2 } // skip
            break
        case 0xA:                           // 0xANNN sets I-Register to nnn
            ctx.reg_I = nnn
            break
        case 0xB:                           // 0xBNNN Jumps to NNN + V0
            ctx.PC = nnn + cast(u16)ctx.registers[0]
            break
        case 0xC:                           // 0xCXNN Sets Vx to rand() & nn
            r: u8 = u8(rand.uint32() & 0xFF)
            ctx.registers[x] = r & u8(nn)
            break
        case 0xD:                           // 0xDXYN Draws sprite at coordinate VX, VY that has a width of 8 pixels and a height of N from the I register
            //ctx.registers[0xF] = 0
            sX := ctx.registers[x] % 64
            sY := ctx.registers[y] % 32
            for sprY in 0..<u8(n) {
                if sY + sprY >= 32 do break
                spr_cur := memory.get(ctx_mem, u8, int(ctx.reg_I + u16(sprY)))
                
                for sprX in 0..<u8(8) {
                    if sX + sprX >= 64 do break

                    mask := u8(0x80 >> sprX)
                    if (spr_cur & mask) != 0 { 
                        if memory.vbank_blit(ctx_mem, sX + sprX, sY + sprY) do ctx.registers[0xF] = 0x1
                    }
                }
            }
            break
        case 0xE:
            if nn == 0x9E {                 // 0xEX9E Skip next is key Vx is Pressed
                if fetch_key(ctx.registers[x] & 0x0F) do ctx.PC += 2
            }
            else if nn == 0xA1 {            // 0xEXA1 Skip next is key Vx is Not Pressed
                if !fetch_key(ctx.registers[x] & 0x0F) do ctx.PC += 2
            }
            break
        case 0xF:
            switch nn {                     // 0xFX07 Sets Vx to Delay Timer
                case 0x07:
                    ctx.registers[x] = ctx.delay
                    break
                case 0x0A:                  // 0xFX0A Key press is awaited... blocking... and then stored in Vx
                    pressed, key := fetch_keypress()
                    if !pressed {
                        ctx.PC -= 2
                        break
                    }
                    ctx.registers[x] = key 
                    break
                case 0x15:                  // 0xFX15 Sets delay timer to Vx
                    ctx.delay = ctx.registers[x]
                    break
                case 0x18:                  // 0xFX18 Sets sound timer to Vx
                    ctx.sound = ctx.registers[x]
                    break
                case 0x1E:                  // 0xFX1E Adds Vx to I
                    ctx.reg_I += u16(ctx.registers[x])
                    break
                case 0x29:                  // 0xFX29 Sets I to font address for character X (lowest nibble)
                    char := ctx.registers[x] & 0x0F
                    ctx.reg_I = memory.FONT_START + 5*u16(char)
                    break
                case 0x33:                  // 0xFX33 Stores binary-coded decimal of Vx
                    bcd_h := u8(ctx.registers[x] / 100)
                    memory.put(ctx_mem, bcd_h, int(ctx.reg_I))
                    bcd_t := u8((ctx.registers[x] / 10) % 10)
                    memory.put(ctx_mem, bcd_t, int(ctx.reg_I + 1))
                    bcd_o := u8(ctx.registers[x] % 10)
                    memory.put(ctx_mem, bcd_o, int(ctx.reg_I + 2))
                    break
                case 0x55:                  // 0xFX55 Dumps V0..Vx into memory starting at I
                    memory.cpy_put(ctx_mem, ctx.registers, int(x) + 1, ctx.reg_I)
                    break
                case 0x65:                  // 0xFX65 Loads into V0..Vx starting from I
                    memory.cpy_get(ctx_mem, ctx.registers, int(x) + 1, ctx.reg_I)
                    break
            }
            break
    }
}