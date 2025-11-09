package main

import "core:flags"
import rl "vendor:raylib"
import "core:os"

import "cpu"
import "memory"

SCALE :: 20

EmuArgs :: struct {
    rom: os.Handle `args:"pos=0,required,file=r" usage:"Rom file."`,
}

EmuContext :: struct {
    args: EmuArgs,
    chipCpu: cpu.CPU,
    chipMem: memory.Memory
}

ctx: EmuContext

main :: proc() {
    make_emu_context(&ctx)
    defer delete_emu_context(&ctx)

    if !memory.load_prog(&ctx.chipMem, ctx.args.rom) {
        panic("Could not load rom")
    }
    // Set first instruction address
    ctx.chipCpu.PC = 0x200

    rl.InitWindow(64 * SCALE, 32 * SCALE, "OdinChip8")
    defer rl.CloseWindow()

    // Load Texture etc
    img: rl.Image
    img.data = ctx.chipMem.frameBuffer
    img.width = 64
    img.height = 32
    img.mipmaps = 1
    img.format = .UNCOMPRESSED_GRAYSCALE
    tex := rl.LoadTextureFromImage(img)
    defer rl.UnloadTexture(tex)

    rl.SetTextureFilter(tex, .POINT)

    rl.SetTargetFPS(60)

    // Setup other stuff
    for !rl.WindowShouldClose() {
        // Run timer tick once per frame -> 60Hz
        cpu.tick_timers(&ctx.chipCpu)
        // Run 12 instructions per frame -> ~700 Hz
        for i in 0..<12 do cpu.tick(&ctx.chipCpu, &ctx.chipMem)
        rl.UpdateTexture(tex, ctx.chipMem.frameBuffer)

        rl.BeginDrawing()
        rl.DrawTexturePro(tex, {0,0,64,32}, {0,0,64*SCALE,32*SCALE}, {0,0}, 0, rl.WHITE)

        rl.EndDrawing()
    }
}

make_emu_context :: proc(
    ctx: ^EmuContext
) {
    flags.parse_or_exit(&ctx.args, os.args)

    memory.init(&ctx.chipMem)
    cpu.init(&ctx.chipCpu)
}

delete_emu_context :: proc(
    ctx: ^EmuContext
) {
    memory.deinit(&ctx.chipMem)
    cpu.deinit(ctx.chipCpu)
}