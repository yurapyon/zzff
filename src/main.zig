const std = @import("std");
const Allocator = std.mem.Allocator;
const Timer = std.time.Timer;

const forth = @import("untyped");
const gfx = @import("gfx.zig");
const c = @import("c.zig");

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

    std.debug.print("{} {} {}", .{ vert, frag, prog });

    while (c.glfwWindowShouldClose(gfx.window) == c.GLFW_FALSE) {
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

        const dt = tm.step();
        _ = dt;

        c.glfwSwapBuffers(gfx.window);
        c.glfwPollEvents();
        _ = c.usleep(100);
    }
}
