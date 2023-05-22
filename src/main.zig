const std = @import("std");
const Allocator = std.mem.Allocator;
const Timer = std.time.Timer;

const forth = @import("untyped");
const gfx = @import("gfx.zig");
const c = @import("c.zig");

//;

// TODO grid, forth

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

const grid = struct {
    const WIDTH = 80;
    const HEIGHT = 36;

    const Cell = struct {
        glyph: u8,
        color: [4]f32,
    };

    var cells: [WIDTH * HEIGHT]Cell = undefined;

    fn init() void {
        for (&cells) |*cell| {
            cell.glyph = ' ';
            cell.color = [_]f32{ 1, 1, 1, 1 };
        }
    }

    fn draw() void {
        gfx.sb.start();

        var x: usize = 0;
        var y: usize = 0;
        while (x < WIDTH) {
            y = 0;
            while (y < HEIGHT) {
                const cell = cells[x * HEIGHT + y];
                var sp = gfx.sb.currentSprite();
                sp.uv = fontGlyphUV(
                    cell.glyph,
                    @intCast(usize, tex_font.width),
                    @intCast(usize, tex_font.height),
                );
                sp.position[0] = @intToFloat(f32, x * 9);
                sp.position[1] = @intToFloat(f32, y * 16);
                sp.rotation[0] = 0;
                sp.scale[0] = 9;
                sp.scale[1] = 16;
                sp.color = cell.color;
                gfx.sb.advanceSprite();
                y += 1;
            }
            x += 1;
        }

        gfx.sb.end();
    }

    fn getCell(x: usize, y: usize) *Cell {
        return &cells[x * HEIGHT + y];
    }
};

//;

const xts = struct {
    const Cell = forth.VM.Cell;

    var keyPress: Cell = undefined;
    var mouseMove: Cell = undefined;
    var mousePress: Cell = undefined;
    var charInput: Cell = undefined;
    var windowSize: Cell = undefined;
    var frame: Cell = undefined;

    fn init() forth.VM.Error!void {
        keyPress = try getXt("key-press");
        mouseMove = try getXt("mouse-move");
        mousePress = try getXt("mouse-press");
        charInput = try getXt("char-input");
        windowSize = try getXt("window-resize");
        frame = try getXt("frame");
    }

    fn getXt(name: []const u8) forth.VM.Error!Cell {
        try vm.pushString(name);
        try vm.find();
        _ = try vm.pop();
        const addr = try vm.pop();
        return forth.VM.wordHeaderCodeFieldAddress(addr);
    }
};

const builtins = struct {
    const Self = forth.VM;
    const Error = Self.Error;

    fn init() Error!void {
        try vm.createBuiltin("put", 0, &putGlyph);
    }

    fn putGlyph(self: *Self) Error!void {
        const gly = try self.pop();
        const y = try self.pop();
        const x = try self.pop();
        grid.getCell(x, y).glyph = @intCast(u8, gly);
    }
};

//;

const heap_alloc = std.heap.c_allocator;
var vm: forth.VM = undefined;
var tex_font: gfx.texture.Result = undefined;

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
    tex_font = try gfx.texture.initFromFileMemory(font);

    var time: f32 = 0;

    grid.init();

    try builtins.init();

    {
        var forth_main = try readFile(heap_alloc, "src/main.fth");
        defer heap_alloc.free(forth_main);
        vm.interpretBuffer(forth_main) catch |err| switch (err) {
            error.WordNotFound => {
                std.debug.print("word not found: {s}\n", .{vm.word_not_found});
                return;
            },
            else => return err,
        };
    }

    try xts.init();

    while (c.glfwWindowShouldClose(gfx.window) == c.GLFW_FALSE) {
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

        const dt = tm.step();
        const dt32 = @floatCast(f32, dt);
        time += dt32;

        gfx.bindProgram(&prog);
        gfx.setScreen(&m3_screen);
        gfx.setView(&m3_view);
        gfx.setModel(&m3_model);
        gfx.setBaseColor([4]f32{ 1, 1, 1, 1 });
        gfx.setDiffuse(tex_font.texture);
        gfx.setTime(time);

        gfx.setUseSpritebatch(true);
        grid.draw();

        try vm.fpush(dt32);
        try vm.execute(xts.frame);

        c.glfwSwapBuffers(gfx.window);
        c.glfwPollEvents();
        _ = c.usleep(16000);
    }
}
