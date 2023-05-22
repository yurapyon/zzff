const std = @import("std");
const Allocator = std.mem.Allocator;
const Timer = std.time.Timer;

const forth = @import("untyped");
const gfx = @import("gfx.zig");
const c = @import("c.zig");

//;

fn readFile(allocator: Allocator, filename: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
    defer file.close();
    return file.readToEndAlloc(allocator, std.math.maxInt(usize));
}

//;

const Region = [4]usize;
const UVRegion = [4]f32;

fn fontGlyphRegion(glyph: u8, glyph_w: usize, glyph_h: usize) Region {
    const y = @divTrunc(glyph, 0x20);
    const x = glyph - y * 0x20;
    return [_]usize{
        x * glyph_w,
        y * glyph_h,
        (x + 1) * glyph_w,
        (y + 1) * glyph_h,
    };
}

fn fontGlyphUV(glyph: u8, tex_w: usize, tex_h: usize) UVRegion {
    const glyph_w = @divTrunc(tex_w, 32);
    const glyph_h = @divTrunc(tex_h, 8);
    const region = fontGlyphRegion(glyph, glyph_w, glyph_h);
    return [_]f32{
        @intToFloat(f32, region[0]) / @intToFloat(f32, tex_w),
        @intToFloat(f32, region[1]) / @intToFloat(f32, tex_h),
        @intToFloat(f32, region[2]) / @intToFloat(f32, tex_w),
        @intToFloat(f32, region[3]) / @intToFloat(f32, tex_h),
    };
}

//;

const FrameTimer = struct {
    const Self = @This();

    tm: Timer,
    last_now: u64,
    last_delta: f64,

    fn start() Timer.Error!Self {
        var ret = Self{
            .tm = try Timer.start(),
            .last_now = 0,
            .last_delta = 0,
        };
        _ = ret.step();
        _ = ret.step();
        return ret;
    }

    fn step(self: *Self) f64 {
        const now = self.tm.read();
        self.last_delta = @intToFloat(f64, now - self.last_now) / 1000000000;
        self.last_now = now;
        return self.last_delta;
    }
};

//;

const heap_alloc = std.heap.c_allocator;
var vm: forth.VM = undefined;

pub fn main() !void {
    vm = try forth.VM.init(heap_alloc);
    defer vm.deinit();

    try gfx.init();
    defer gfx.deinit();

    var tm = try FrameTimer.start();

    const vert = try gfx.Program.makeDefaultVertShader();
    const frag = try gfx.Program.makeDefaultFragShader();
    const prog = try gfx.Program.init(&[_]c.GLuint{ vert, frag });

    var m3_screen: gfx.M3 = undefined;
    var m3_view: gfx.M3 = undefined;
    var m3_model: gfx.M3 = undefined;
    gfx.m3.orthoScreen(&m3_screen, 800, 600);
    gfx.m3.identity(&m3_view);
    gfx.m3.identity(&m3_model);

    const white = [_]u8{ 255, 255, 255, 255 };
    const tex_white = gfx.texture.initFromMemory(&white, 1, 1);
    _ = tex_white;

    const font = try readFile(heap_alloc, "content/Codepage437.png");
    const tex_font = try gfx.texture.initFromFileMemory(font);

    std.debug.print("{any} {any}\n", .{
        tex_font.width,
        tex_font.height,
    });

    while (c.glfwWindowShouldClose(gfx.window) == c.GLFW_FALSE) {
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

        const dt = tm.step();
        _ = dt;

        gfx.bindProgram(&prog);
        gfx.setScreen(&m3_screen);
        gfx.setView(&m3_view);
        gfx.setModel(&m3_model);
        gfx.setBaseColor([4]f32{ 1, 1, 0, 1 });
        gfx.setDiffuse(tex_font.texture);

        gfx.setUseSpritebatch(true);
        gfx.sb.start();
        var i: f32 = 0;
        while (i < 10) {
            var sp = gfx.sb.currentSprite();
            // sp.uv[0] = 0;
            // sp.uv[1] = 0;
            // sp.uv[2] = 1;
            // sp.uv[3] = 1;

            sp.uv = fontGlyphUV(
                @floatToInt(u8, i) + 0x40,
                @intCast(usize, tex_font.width),
                @intCast(usize, tex_font.height),
            );

            sp.position[0] = i * 11;
            sp.position[1] = 20;
            sp.rotation[0] = 0;
            sp.scale[0] = 9;
            sp.scale[1] = 16;
            sp.color[0] = 1;
            sp.color[1] = i / 10;
            sp.color[2] = 1;
            sp.color[3] = 1;
            gfx.sb.advanceSprite();
            i += 1;
        }
        gfx.sb.end();

        gfx.setUseSpritebatch(false);
        gfx.sb.drawOne();

        c.glfwSwapBuffers(gfx.window);
        c.glfwPollEvents();
        _ = c.usleep(100);
    }
}
