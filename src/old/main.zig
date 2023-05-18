const std = @import("std");
const Allocator = std.mem.Allocator;
const Timer = std.time.Timer;

const forth = @import("untyped");
usingnamespace forth.VM;

const json = std.json;

//;

usingnamespace @cImport({
    @cInclude("epoxy/gl.h");
    @cInclude("GLFW/glfw3.h");
    @cInclude("stb_image.h");
});

const c = @cImport({
    @cInclude("unistd.h");
});

//;

fn readFile(allocator: *Allocator, filename: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(filename, .{ .read = true });
    defer file.close();
    return file.readToEndAlloc(allocator, std.math.maxInt(usize));
}

fn cintToCell(val: c_int) Cell {
    return @bitCast(Cell, @intCast(i64, val));
}

fn cellToLocation(val: Cell) GLint {
    const sval = @bitCast(SCell, val);
    return if (sval == -1) -1 else @intCast(GLint, sval);
}

fn vmGetValue(comptime T: type, name: []const u8) Error!T {
    try vm.interpretBuffer(name);
    return @intCast(T, try vm.pop());
}

//;

const m3 = struct {
    const Self = [9]Float;

    // column major
    // m3[x * 3 + y]
    const m_00 = 0 * 3 + 0;
    const m_01 = 0 * 3 + 1;
    const m_02 = 0 * 3 + 2;
    const m_10 = 1 * 3 + 0;
    const m_11 = 1 * 3 + 1;
    const m_12 = 1 * 3 + 2;
    const m_20 = 2 * 3 + 0;
    const m_21 = 2 * 3 + 1;
    const m_22 = 2 * 3 + 2;

    fn zero(self: *Self) void {
        for (self) |*f| {
            f.* = 0;
        }
    }

    fn identity(self: *Self) void {
        zero(self);
        self[m_00] = 1;
        self[m_11] = 1;
        self[m_22] = 1;
    }

    fn translation(self: *Self, x: Float, y: Float) void {
        identity(self);
        self[m_20] = x;
        self[m_21] = y;
    }

    fn rotation(self: *Self, rads: Float) void {
        identity(self);
        const rc = std.math.cos(rads);
        const rs = std.math.sin(rads);
        self[m_00] = rc;
        self[m_01] = rs;
        self[m_10] = -rs;
        self[m_11] = rc;
    }

    fn scaling(self: *Self, x: Float, y: Float) void {
        identity(self);
        self[m_00] = x;
        self[m_11] = y;
    }

    fn shearing(self: *Self, x: Float, y: Float) void {
        identity(self);
        self[m_10] = x;
        self[m_01] = y;
    }

    fn orthoScreen(self: *Self, width: Cell, height: Cell) void {
        identity(self);
        // scale
        self[m_00] = 2 / @intToFloat(Float, width);
        self[m_11] = -2 / @intToFloat(Float, height);
        // translate
        self[m_20] = -1;
        self[m_21] = 1;
    }

    // writes into first arg
    fn mult(s: *Self, o: *Self) void {
        var temp: Self = undefined;
        temp[m_00] = s[m_00] * o[m_00] + s[m_01] * o[m_10] + s[m_02] * o[m_20];
        temp[m_01] = s[m_00] * o[m_01] + s[m_01] * o[m_11] + s[m_02] * o[m_21];
        temp[m_02] = s[m_00] * o[m_02] + s[m_01] * o[m_12] + s[m_02] * o[m_22];
        temp[m_10] = s[m_10] * o[m_00] + s[m_11] * o[m_10] + s[m_12] * o[m_20];
        temp[m_11] = s[m_10] * o[m_01] + s[m_11] * o[m_11] + s[m_12] * o[m_21];
        temp[m_12] = s[m_10] * o[m_02] + s[m_11] * o[m_12] + s[m_12] * o[m_22];
        temp[m_20] = s[m_20] * o[m_00] + s[m_21] * o[m_10] + s[m_22] * o[m_20];
        temp[m_21] = s[m_20] * o[m_01] + s[m_21] * o[m_11] + s[m_22] * o[m_21];
        temp[m_22] = s[m_20] * o[m_02] + s[m_21] * o[m_12] + s[m_22] * o[m_22];
        for (temp) |f, i| {
            s[i] = f;
        }
    }
};

// TODO
pub const Mat3 = struct {
    pub fn fromTransform2d(t2d: Transform2d) Self {
        var ret = Self.identity();
        const sx = t2d.scale.x;
        const sy = t2d.scale.y;
        const rc = std.math.cos(t2d.rotation);
        const rs = std.math.sin(t2d.rotation);
        ret.data[0][0] = rc * sx;
        ret.data[0][1] = rs * sx;
        ret.data[1][0] = -rs * sy;
        ret.data[1][1] = rc * sy;
        ret.data[2][0] = t2d.position.x;
        ret.data[2][1] = t2d.position.y;
        return ret;
    }
};

const m4 = struct {
    const Self = [16]Float;

    const m_00 = 0 * 4 + 0;
    const m_01 = 0 * 4 + 1;
    const m_02 = 0 * 4 + 2;
    const m_03 = 0 * 4 + 3;
    const m_10 = 1 * 4 + 0;
    const m_11 = 1 * 4 + 1;
    const m_12 = 1 * 4 + 2;
    const m_13 = 1 * 4 + 3;
    const m_20 = 2 * 4 + 0;
    const m_21 = 2 * 4 + 1;
    const m_22 = 2 * 4 + 2;
    const m_23 = 2 * 4 + 3;
    const m_30 = 3 * 4 + 0;
    const m_31 = 3 * 4 + 1;
    const m_32 = 3 * 4 + 2;
    const m_33 = 3 * 4 + 3;

    fn zero(self: *Self) void {
        for (self) |*f| {
            f.* = 0;
        }
    }

    fn identity(self: *Self) void {
        zero(self);
        self[m_00] = 1;
        self[m_11] = 1;
        self[m_22] = 1;
        self[m_33] = 1;
    }

    fn translation(self: *Self, x: Float, y: Float, z: Float) void {
        identity(self);
        self[m_30] = x;
        self[m_31] = y;
        self[m_32] = z;
    }

    fn perspective(self: *Self, right: Float, top: Float, near: Float, far: Float) void {
        zero(self);
        self[m_00] = near / right;
        self[m_11] = near / top;
        self[m_22] = -(far + near) / (far - near);
        self[m_23] = -1;
        self[m_32] = (-2 * far * near) / (far - near);
    }

    fn perspectiveFov(self: *Self, y_fov: Float, aspect: Float, near: Float, far: Float) void {
        zero(self);
        const a = 1 / std.math.tan(y_fov / 2);
        self[m_00] = a / aspect;
        self[m_11] = a;
        self[m_22] = -(far + near) / (far - near);
        self[m_23] = -1;
        self[m_32] = (-2 * far * near) / (far - near);
    }

    fn mult(s: *Self, o: *Self) void {
        var temp: Self = undefined;
        temp[m_00] = s[m_00] * o[m_00] + s[m_01] * o[m_10] + s[m_02] * o[m_20] + s[m_03] * o[m_30];
        temp[m_01] = s[m_00] * o[m_01] + s[m_01] * o[m_11] + s[m_02] * o[m_21] + s[m_03] * o[m_31];
        temp[m_02] = s[m_00] * o[m_02] + s[m_01] * o[m_12] + s[m_02] * o[m_22] + s[m_03] * o[m_32];
        temp[m_03] = s[m_00] * o[m_03] + s[m_01] * o[m_13] + s[m_02] * o[m_23] + s[m_03] * o[m_33];
        temp[m_10] = s[m_10] * o[m_00] + s[m_11] * o[m_10] + s[m_12] * o[m_20] + s[m_13] * o[m_30];
        temp[m_11] = s[m_10] * o[m_01] + s[m_11] * o[m_11] + s[m_12] * o[m_21] + s[m_13] * o[m_31];
        temp[m_12] = s[m_10] * o[m_02] + s[m_11] * o[m_12] + s[m_12] * o[m_22] + s[m_13] * o[m_32];
        temp[m_13] = s[m_10] * o[m_03] + s[m_11] * o[m_13] + s[m_12] * o[m_23] + s[m_13] * o[m_33];
        temp[m_20] = s[m_20] * o[m_00] + s[m_21] * o[m_10] + s[m_22] * o[m_20] + s[m_23] * o[m_30];
        temp[m_21] = s[m_20] * o[m_01] + s[m_21] * o[m_11] + s[m_22] * o[m_21] + s[m_23] * o[m_31];
        temp[m_22] = s[m_20] * o[m_02] + s[m_21] * o[m_12] + s[m_22] * o[m_22] + s[m_23] * o[m_32];
        temp[m_23] = s[m_20] * o[m_03] + s[m_21] * o[m_13] + s[m_22] * o[m_23] + s[m_23] * o[m_33];
        temp[m_30] = s[m_30] * o[m_00] + s[m_31] * o[m_10] + s[m_32] * o[m_20] + s[m_33] * o[m_30];
        temp[m_31] = s[m_30] * o[m_01] + s[m_31] * o[m_11] + s[m_32] * o[m_21] + s[m_33] * o[m_31];
        temp[m_32] = s[m_30] * o[m_02] + s[m_31] * o[m_12] + s[m_32] * o[m_22] + s[m_33] * o[m_32];
        temp[m_33] = s[m_30] * o[m_03] + s[m_31] * o[m_13] + s[m_32] * o[m_23] + s[m_33] * o[m_33];
        for (temp) |f, i| {
            s[i] = f;
        }
    }
};

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

const xts = struct {
    var keyPress: Cell = undefined;
    var mouseMove: Cell = undefined;
    var mousePress: Cell = undefined;
    var charInput: Cell = undefined;
    var windowSize: Cell = undefined;
    var frame: Cell = undefined;

    fn init() Error!void {
        keyPress = try getXt("key-press");
        mouseMove = try getXt("mouse-move");
        mousePress = try getXt("mouse-press");
        charInput = try getXt("char-input");
        windowSize = try getXt("window-resize");
        frame = try getXt("frame");
    }

    fn getXt(name: []const u8) Error!Cell {
        try vm.pushString(name);
        try vm.find();
        _ = try vm.pop();
        const addr = try vm.pop();
        return wordHeaderCodeFieldAddress(addr);
    }
};

const builtins = struct {
    const Self = forth.VM;

    fn init() Error!void {
        try vm.createBuiltin("make-shader", 0, &makeShader);
        try vm.createBuiltin("free-shader", 0, &freeShader);

        try vm.createBuiltin("make-program", 0, &makeProgram);
        try vm.createBuiltin("free-program", 0, &freeProgram);
        try vm.createBuiltin("use-program", 0, &useProgram);
        try vm.createBuiltin("get-location", 0, &getLocation);
        try vm.createBuiltin("uniform1i", 0, &uniform1i);
        try vm.createBuiltin("uniform1f", 0, &uniform1f);
        try vm.createBuiltin("uniform4fv", 0, &uniform4fv);
        try vm.createBuiltin("uniformMatrix3fv", 0, &uniformMatrix3fv);
        try vm.createBuiltin("uniformMatrix4fv", 0, &uniformMatrix4fv);

        try vm.createBuiltin("make-texture", 0, &makeTexture);
        try vm.createBuiltin("free-texture", 0, &freeTexture);
        try vm.createBuiltin("bind-texture", 0, &bindTexture);
        try vm.createBuiltin("active-texture", 0, &activeTexture);

        try vm.createBuiltin("make-buffer", 0, &makeBuffer);
        try vm.createBuiltin("free-buffer", 0, &freeBuffer);
        try vm.createBuiltin("bind-buffer", 0, &bindBuffer);
        try vm.createBuiltin("buffer-sub-data", 0, &bufferSubData);
        try vm.createBuiltin("buffer-data", 0, &bufferData);

        try vm.createBuiltin("make-vertex-array", 0, &makeVertexArray);
        try vm.createBuiltin("free-vertex-array", 0, &freeVertexArray);
        try vm.createBuiltin("bind-vertex-array", 0, &bindVertexArray);
        try vm.createBuiltin("enable-attribute", 0, &enableAttribute);
        try vm.createBuiltin("draw-arrays", 0, &drawArrays);
        try vm.createBuiltin("draw-arrays,instanced", 0, &drawArraysInstanced);
        try vm.createBuiltin("draw-elements", 0, &drawElements);

        try vm.createBuiltin("gl-enable", 0, &gl_enable);
        try vm.createBuiltin("gl-disable", 0, &gl_disable);

        try vm.createBuiltin("<m3>,zero", 0, &m3zero);
        try vm.createBuiltin("<m3>,identity", 0, &m3identity);
        try vm.createBuiltin("<m3>,translation", 0, &m3translation);
        try vm.createBuiltin("<m3>,rotation", 0, &m3rotation);
        try vm.createBuiltin("<m3>,scaling", 0, &m3scaling);
        try vm.createBuiltin("<m3>,shearing", 0, &m3shearing);
        try vm.createBuiltin("<m3>,screen", 0, &m3screen);
        try vm.createBuiltin("m3*!", 0, &m3mult);

        try vm.createBuiltin("<m4>,zero", 0, &m4zero);
        try vm.createBuiltin("<m4>,identity", 0, &m4identity);
        try vm.createBuiltin("<m4>,translation", 0, &m4translation);
        try vm.createBuiltin("<m4>,perspective", 0, &m4perspective);
        try vm.createBuiltin("<m4>,perspectiveFov", 0, &m4perspectiveFov);
        try vm.createBuiltin("m4*!", 0, &m4mult);

        try vm.createBuiltin("<t2d>,rectangle", 0, &t2dRectangle);
        try vm.createBuiltin("<t2d>,urectangle", 0, &t2dUrectangle);

        try vm.createBuiltin("<rect>,normalized", 0, &rectNormalized);

        try vm.createBuiltin("parse-json", 0, &parseJson);
        try vm.createBuiltin("free-json", 0, &freeJson);
        try vm.createBuiltin("jv>int", 0, &jsonInteger);
        try vm.createBuiltin("jv>float", 0, &jsonFloat);
        try vm.createBuiltin("jv>bool", 0, &jsonBoolean);
        try vm.createBuiltin("jv>string", 0, &jsonString);
        try vm.createBuiltin("jv>object.get", 0, &jsonObjectGet);
        try vm.createBuiltin("jv>array.at", 0, &jsonArrayAt);
        try vm.createBuiltin("jv>array.len", 0, &jsonArrayLen);
    }

    fn makeShader(self: *Self) Error!void {
        const ty = try self.pop();
        const n = try self.pop();
        const lens = try self.pop();
        const strings = try self.pop();

        const shader = glCreateShader(@intCast(GLuint, ty));
        if (shader == 0) {
            try self.push(0);
            return;
        }

        glShaderSource(
            shader,
            @intCast(GLint, n),
            @intToPtr(**const u8, strings),
            @intToPtr(*c_int, lens),
        );
        glCompileShader(shader);

        var info_len: c_int = 0;
        glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &info_len);
        if (info_len != 0) {
            var buf = try heap_alloc.alloc(u8, @intCast(usize, info_len));
            glGetShaderInfoLog(shader, info_len, null, buf.ptr);
            std.debug.print("shader info:\n{s}", .{buf});
            heap_alloc.free(buf);
        }

        var success: c_int = undefined;
        glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
        if (success != GL_TRUE) {
            try self.push(0);
            return;
        }

        try self.push(shader);
    }

    fn freeShader(self: *Self) Error!void {
        const shader = try self.pop();
        glDeleteShader(@intCast(GLuint, shader));
    }

    fn makeProgram(self: *Self) Error!void {
        const frag_cell = try self.pop();
        const vert_cell = try self.pop();
        const vert = @intCast(GLuint, vert_cell);
        const frag = @intCast(GLuint, frag_cell);
        const shaders = [_]GLuint{
            vert,
            frag,
        };
        const program = glCreateProgram();
        errdefer glDeleteProgram(program);
        if (program == 0) {
            try self.push(0);
            return;
        }

        for (shaders) |shader| {
            glAttachShader(program, @intCast(GLuint, shader));
        }

        glLinkProgram(program);

        var info_len: c_int = 0;
        glGetProgramiv(program, GL_INFO_LOG_LENGTH, &info_len);
        if (info_len != 0) {
            var buf = try heap_alloc.alloc(u8, @intCast(usize, info_len));
            glGetProgramInfoLog(program, info_len, null, buf.ptr);
            std.debug.print("program info:\n{s}", .{buf});
            heap_alloc.free(buf);
        }

        var success: c_int = undefined;
        glGetProgramiv(program, GL_LINK_STATUS, &success);
        if (success != GL_TRUE) {
            try self.push(0);
            return;
        }

        try self.push(program);
    }

    fn freeProgram(self: *Self) Error!void {
        const program = try self.pop();
        glDeleteProgram(@intCast(GLuint, program));
    }

    fn useProgram(self: *Self) Error!void {
        const program = try self.pop();
        glUseProgram(@intCast(GLuint, program));
    }

    fn getLocation(self: *Self) Error!void {
        const program = try self.pop();
        const zstr = try self.pop();
        const loc = glGetUniformLocation(
            @intCast(GLuint, program),
            @intToPtr(*const u8, zstr),
        );
        try self.push(@bitCast(Cell, @intCast(SCell, loc)));
    }

    fn uniform1i(self: *Self) Error!void {
        const loc = try self.pop();
        const i = try self.pop();
        glUniform1i(cellToLocation(loc), @intCast(GLint, i));
    }

    fn uniform1f(self: *Self) Error!void {
        const loc = try self.pop();
        const f = try self.fpop();
        glUniform1f(cellToLocation(loc), f);
    }

    fn uniform4fv(self: *Self) Error!void {
        const loc = try self.pop();
        const addr = try self.pop();
        glUniform4fv(
            cellToLocation(loc),
            1,
            @intToPtr(*const GLfloat, addr),
        );
    }

    fn uniformMatrix3fv(self: *Self) Error!void {
        const loc = try self.pop();
        const addr = try self.pop();
        glUniformMatrix3fv(
            cellToLocation(loc),
            1,
            GL_FALSE,
            @intToPtr(*const GLfloat, addr),
        );
    }

    fn uniformMatrix4fv(self: *Self) Error!void {
        const loc = try self.pop();
        const addr = try self.pop();
        glUniformMatrix4fv(
            cellToLocation(loc),
            1,
            GL_FALSE,
            @intToPtr(*const GLfloat, addr),
        );
    }

    fn makeTexture(self: *Self) Error!void {
        const buf_len = try self.pop();
        const buf_addr = try self.pop();
        const buf = arrayAt(u8, buf_addr, buf_len);
        const res = texture.initFromFileMemory(buf) catch |err| switch (err) {
            error.Load => {
                try self.push(0);
                try self.push(0);
                try self.push(0);
                return;
            },
        };
        try self.push(res.texture);
        try self.push(res.width);
        try self.push(res.height);
    }

    fn freeTexture(self: *Self) Error!void {
        const tex = try self.pop();
        glDeleteTextures(1, &@intCast(GLuint, tex));
    }

    fn bindTexture(self: *Self) Error!void {
        const tex = try self.pop();
        const target = try self.pop();
        glBindTexture(
            @intCast(GLenum, target),
            @intCast(GLuint, tex),
        );
    }

    fn activeTexture(self: *Self) Error!void {
        const num = try self.pop();
        glActiveTexture(@intCast(GLenum, num));
    }

    fn makeBuffer(self: *Self) Error!void {
        var buffer: GLuint = undefined;
        glGenBuffers(1, &buffer);
        try self.push(buffer);
    }

    fn freeBuffer(self: *Self) Error!void {
        const buffer = try self.pop();
        glDeleteBuffers(1, &@intCast(GLuint, buffer));
    }

    fn bindBuffer(self: *Self) Error!void {
        const buffer = try self.pop();
        const target = try self.pop();
        glBindBuffer(
            @intCast(GLenum, target),
            @intCast(GLuint, buffer),
        );
    }

    fn bufferSubData(self: *Self) Error!void {
        const data_addr = try self.pop();
        const size = try self.pop();
        const offset = try self.pop();
        const target = try self.pop();
        glBufferSubData(
            @intCast(GLenum, target),
            @intCast(GLintptr, offset),
            @intCast(GLsizeiptr, size),
            @intToPtr(*allowzero const c_void, data_addr),
        );
    }

    fn bufferData(self: *Self) Error!void {
        const draw_type = try self.pop();
        const len = try self.pop();
        const addr = try self.pop();
        const target = try self.pop();
        const buf = arrayAt(u8, addr, len);
        glBufferData(
            @intCast(GLenum, target),
            @intCast(GLsizeiptr, buf.len),
            buf.ptr,
            @intCast(GLenum, draw_type),
        );
    }

    fn makeVertexArray(self: *Self) Error!void {
        var vao: GLuint = undefined;
        glGenVertexArrays(1, &vao);
        try self.push(vao);
    }

    fn freeVertexArray(self: *Self) Error!void {
        const vao = try self.pop();
        glDeleteVertexArrays(1, &@intCast(GLuint, vao));
    }

    fn bindVertexArray(self: *Self) Error!void {
        const vao = try self.pop();
        glBindVertexArray(@intCast(GLuint, vao));
    }

    fn enableAttribute(self: *Self) Error!void {
        const num = try self.pop();
        const divisor = try self.pop();
        const offset = try self.pop();
        const stride = try self.pop();
        const is_normalized = try self.pop();
        const ty = try self.pop();
        const size = try self.pop();

        const gl_num = @intCast(GLuint, num);

        glEnableVertexAttribArray(gl_num);
        glVertexAttribPointer(
            gl_num,
            @intCast(GLint, size),
            @intCast(GLenum, ty),
            if (is_normalized == forth_true) GL_TRUE else GL_FALSE,
            @intCast(GLsizei, stride),
            @intToPtr(*allowzero const c_void, offset),
        );
        glVertexAttribDivisor(gl_num, @intCast(GLuint, divisor));
    }

    fn drawArrays(self: *Self) Error!void {
        const count = try self.pop();
        const first = try self.pop();
        const ty = try self.pop();
        glDrawArrays(
            @intCast(GLenum, ty),
            @intCast(GLint, first),
            @intCast(GLsizei, count),
        );
    }

    fn drawArraysInstanced(self: *Self) Error!void {
        const ict = try self.pop();
        const count = try self.pop();
        const first = try self.pop();
        const ty = try self.pop();
        glDrawArraysInstanced(
            @intCast(GLenum, ty),
            @intCast(GLint, first),
            @intCast(GLsizei, count),
            @intCast(GLsizei, ict),
        );
    }

    fn drawElements(self: *Self) Error!void {
        const offset = try self.pop();
        const index_type = try self.pop();
        const count = try self.pop();
        const ty = try self.pop();
        glDrawElements(
            @intCast(GLenum, ty),
            @intCast(GLint, count),
            @intCast(GLenum, index_type),
            @intToPtr(*allowzero const c_void, offset),
        );
    }

    fn gl_enable(self: *Self) Error!void {
        const val = try self.pop();
        glEnable(@intCast(GLenum, val));
    }

    fn gl_disable(self: *Self) Error!void {
        const val = try self.pop();
        glDisable(@intCast(GLenum, val));
    }

    fn m3zero(self: *Self) Error!void {
        const addr = try self.pop();
        const fls = arrayAt(Float, addr, 9);
        m3.zero(fls[0..9]);
    }

    fn m3identity(self: *Self) Error!void {
        const addr = try self.pop();
        const fls = arrayAt(Float, addr, 9);
        m3.identity(fls[0..9]);
    }

    fn m3translation(self: *Self) Error!void {
        const addr = try self.pop();
        const y = try self.fpop();
        const x = try self.fpop();
        const fls = arrayAt(Float, addr, 9);
        m3.translation(fls[0..9], x, y);
    }

    fn m3rotation(self: *Self) Error!void {
        const addr = try self.pop();
        const rads = try self.fpop();
        const fls = arrayAt(Float, addr, 9);
        m3.rotation(fls[0..9], rads);
    }

    fn m3scaling(self: *Self) Error!void {
        const addr = try self.pop();
        const y = try self.fpop();
        const x = try self.fpop();
        const fls = arrayAt(Float, addr, 9);
        m3.scaling(fls[0..9], x, y);
    }

    fn m3shearing(self: *Self) Error!void {
        const addr = try self.pop();
        const y = try self.fpop();
        const x = try self.fpop();
        const fls = arrayAt(Float, addr, 9);
        m3.shearing(fls[0..9], x, y);
    }

    fn m3screen(self: *Self) Error!void {
        const addr = try self.pop();
        const height = try self.pop();
        const width = try self.pop();
        const fls = arrayAt(Float, addr, 9);
        m3.orthoScreen(fls[0..9], width, height);
    }

    fn m3mult(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        const fls_a = arrayAt(Float, a, 9);
        const fls_b = arrayAt(Float, b, 9);
        m3.mult(fls_a[0..9], fls_b[0..9]);
    }

    fn m4zero(self: *Self) Error!void {
        const addr = try self.pop();
        const fls = arrayAt(Float, addr, 16);
        m4.zero(fls[0..16]);
    }

    fn m4identity(self: *Self) Error!void {
        const addr = try self.pop();
        const fls = arrayAt(Float, addr, 16);
        m4.identity(fls[0..16]);
    }

    fn m4translation(self: *Self) Error!void {
        const addr = try self.pop();
        const z = try self.fpop();
        const y = try self.fpop();
        const x = try self.fpop();
        const fls = arrayAt(Float, addr, 16);
        m4.translation(fls[0..16], x, y, z);
    }

    fn m4perspective(self: *Self) Error!void {
        const addr = try self.pop();
        const f = try self.fpop();
        const n = try self.fpop();
        const t = try self.fpop();
        const r = try self.fpop();
        const fls = arrayAt(Float, addr, 16);
        m4.perspective(fls[0..16], r, t, n, f);
    }

    fn m4perspectiveFov(self: *Self) Error!void {
        const addr = try self.pop();
        const f = try self.fpop();
        const n = try self.fpop();
        const t = try self.fpop();
        const r = try self.fpop();
        const fls = arrayAt(Float, addr, 16);
        m4.perspectiveFov(fls[0..16], r, t, n, f);
    }

    fn m4mult(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        const fls_a = arrayAt(Float, a, 16);
        const fls_b = arrayAt(Float, b, 16);
        m4.mult(fls_a[0..16], fls_b[0..16]);
    }

    fn t2dRectangle(self: *Self) Error!void {
        const addr = try self.pop();
        const y2 = try self.fpop();
        const x2 = try self.fpop();
        const y1 = try self.fpop();
        const x1 = try self.fpop();

        const t2d = arrayAt(Float, addr, 5);
        t2d[0] = (x1 + x2) / 2;
        t2d[1] = (y1 + y2) / 2;
        t2d[2] = 0;
        t2d[3] = x2 - x1;
        t2d[4] = y2 - y1;
    }

    fn t2dUrectangle(self: *Self) Error!void {
        const addr = try self.pop();
        const y2 = try self.pop();
        const x2 = try self.pop();
        const y1 = try self.pop();
        const x1 = try self.pop();

        const fx1 = @intToFloat(Float, x1);
        const fy1 = @intToFloat(Float, y1);
        const fx2 = @intToFloat(Float, x2);
        const fy2 = @intToFloat(Float, y2);

        const t2d = arrayAt(Float, addr, 5);
        t2d[0] = (fx1 + fx2) / 2;
        t2d[1] = (fy1 + fy2) / 2;
        t2d[2] = 0;
        t2d[3] = fx2 - fx1;
        t2d[4] = fy2 - fy1;
    }

    fn rectNormalized(self: *Self) Error!void {
        const addr = try self.pop();
        const h = try self.pop();
        const w = try self.pop();
        const ur_addr = try self.pop();

        const rect = arrayAt(Float, addr, 4);
        const urect = arrayAt(Cell, ur_addr, 4);
        const ux1 = @intToFloat(Float, urect[0]);
        const uy1 = @intToFloat(Float, urect[1]);
        const ux2 = @intToFloat(Float, urect[2]);
        const uy2 = @intToFloat(Float, urect[3]);
        const fw = @intToFloat(Float, w);
        const fh = @intToFloat(Float, h);
        rect[0] = ux1 / fw;
        rect[1] = uy1 / fh;
        rect[2] = ux2 / fw;
        rect[3] = uy2 / fh;
    }

    fn parseJson(self: *Self) Error!void {
        const len = try self.pop();
        const addr = try self.pop();
        const str = arrayAt(u8, addr, len);
        var j = try self.allocator.create(json.ValueTree);
        json_parser.reset();
        j.* = json_parser.parse(str) catch |err| {
            std.debug.print("json parse error: {} -- \"{s}\"\n", .{ err, str });
            try self.push(0);
            return;
        };
        try self.push(@ptrToInt(&j.root));
    }

    fn freeJson(self: *Self) Error!void {
        const addr = try self.pop();
        const j = @fieldParentPtr(json.ValueTree, "root", @intToPtr(*json.Value, addr));
        j.deinit();
        self.allocator.destroy(j);
    }

    fn jsonInteger(self: *Self) Error!void {
        const addr = try self.pop();
        const jv = @intToPtr(*json.Value, addr);
        try self.push(@intCast(Cell, jv.Integer));
    }

    fn jsonFloat(self: *Self) Error!void {
        const addr = try self.pop();
        const jv = @intToPtr(*json.Value, addr);
        try self.fpush(@floatCast(Float, jv.Float));
    }

    fn jsonBoolean(self: *Self) Error!void {
        const addr = try self.pop();
        const jv = @intToPtr(*json.Value, addr);
        try self.push(if (jv.Bool) forth_true else forth_false);
    }

    fn jsonString(self: *Self) Error!void {
        const addr = try self.pop();
        const jv = @intToPtr(*json.Value, addr);
        const str = jv.String;

        try self.push(@ptrToInt(str.ptr));
        try self.push(str.len);
    }

    fn jsonObjectGet(self: *Self) Error!void {
        const addr = try self.pop();
        const len = try self.pop();
        const str = try self.pop();
        const jv = @intToPtr(*json.Value, addr);
        const entry = jv.Object.getEntry(arrayAt(u8, str, len));
        if (entry) |e| {
            try self.push(@ptrToInt(e.value_ptr));
        } else {
            try self.push(0);
        }
    }

    fn jsonArrayAt(self: *Self) Error!void {
        const addr = try self.pop();
        const idx = try self.pop();
        const jv = @intToPtr(*json.Value, addr);
        const slc = jv.Array.items;
        if (idx < slc.len) {
            try self.push(@ptrToInt(&slc[idx]));
        } else {
            try self.push(0);
        }
    }

    fn jsonArrayLen(self: *Self) Error!void {
        const addr = try self.pop();
        const jv = @intToPtr(*json.Value, addr);
        const slc = jv.Array.items;
        try self.push(slc.len);
    }
};

const texture = struct {
    const Result = struct {
        texture: GLuint,
        width: Cell,
        height: Cell,
    };

    fn initFromMemory(buf: [*]u8, width: u32, height: u32) GLuint {
        var tex: GLuint = undefined;
        glGenTextures(1, &tex);
        glBindTexture(GL_TEXTURE_2D, tex);

        glTexImage2D(
            GL_TEXTURE_2D,
            0,
            GL_RGBA,
            @intCast(GLint, width),
            @intCast(GLint, height),
            0,
            GL_RGBA,
            GL_UNSIGNED_BYTE,
            buf,
        );

        glGenerateMipmap(GL_TEXTURE_2D);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

        glBindTexture(GL_TEXTURE_2D, 0);

        return tex;
    }

    fn initFromFileMemory(buf: []u8) !Result {
        var w: c_int = undefined;
        var h: c_int = undefined;
        const raw_data = stbi_load_from_memory(
            buf.ptr,
            @intCast(c_int, buf.len),
            &w,
            &h,
            null,
            4,
        ) orelse return error.Load;
        defer stbi_image_free(raw_data);
        return Result{
            .texture = initFromMemory(
                raw_data,
                @intCast(u32, w),
                @intCast(u32, h),
            ),
            .width = @intCast(Cell, w),
            .height = @intCast(Cell, h),
        };
    }
};

// ===

fn keyCallback(
    win: ?*GLFWwindow,
    key: c_int,
    scancode: c_int,
    action: c_int,
    mods: c_int,
) callconv(.C) void {
    vm.push(cintToCell(mods)) catch unreachable;
    vm.push(cintToCell(action)) catch unreachable;
    vm.push(cintToCell(scancode)) catch unreachable;
    vm.push(cintToCell(key)) catch unreachable;
    vm.execute(xts.keyPress) catch unreachable;
}

fn cursorPosCallback(
    win: ?*GLFWwindow,
    x: f64,
    y: f64,
) callconv(.C) void {
    vm.fpush(@floatCast(f32, x)) catch unreachable;
    vm.fpush(@floatCast(f32, y)) catch unreachable;
    vm.execute(xts.mouseMove) catch unreachable;
}

fn mouseButtonCallback(
    win: ?*GLFWwindow,
    button: c_int,
    action: c_int,
    mods: c_int,
) callconv(.C) void {
    vm.push(cintToCell(mods)) catch unreachable;
    vm.push(cintToCell(action)) catch unreachable;
    vm.push(cintToCell(button)) catch unreachable;
    vm.execute(xts.mousePress) catch unreachable;
}

fn charCallback(
    win: ?*GLFWwindow,
    codepoint: c_uint,
) callconv(.C) void {
    vm.push(codepoint) catch unreachable;
    vm.execute(xts.charInput) catch unreachable;
}

fn windowSizeCallback(
    win: ?*GLFWwindow,
    width: c_int,
    height: c_int,
) callconv(.C) void {
    vm.push(cintToCell(height)) catch unreachable;
    vm.push(cintToCell(width)) catch unreachable;
    vm.execute(xts.windowSize) catch unreachable;
}

// ===

const GfxError = error{
    GlfwInit,
    WindowInit,
};

const Settings = struct {
    const Self = @This();

    ogl_version_major: u32,
    ogl_version_minor: u32,
    window_width: u32,
    window_height: u32,
    window_name: [:0]const u8 = "float",
    is_resizable: bool = false,

    fn fromForth() Error!Self {
        // TODO name, is-resizable
        return Self{
            .ogl_version_major = try vmGetValue(u32, "version-major"),
            .ogl_version_minor = try vmGetValue(u32, "version-minor"),
            .window_width = try vmGetValue(u32, "window-width"),
            .window_height = try vmGetValue(u32, "window-height"),
        };
    }
};

var window: *GLFWwindow = undefined;

fn initGfx() !void {
    if (glfwInit() != GLFW_TRUE) {
        return error.GlfwInit;
    }
    errdefer glfwTerminate();

    const settings = try Settings.fromForth();

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, @intCast(c_int, settings.ogl_version_major));
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, @intCast(c_int, settings.ogl_version_minor));
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    glfwWindowHint(GLFW_RESIZABLE, if (settings.is_resizable) GL_TRUE else GL_FALSE);
    glfwSwapInterval(1);

    // note: window creation fails if we can't get the desired opengl version

    window = glfwCreateWindow(
        @intCast(c_int, settings.window_width),
        @intCast(c_int, settings.window_height),
        settings.window_name,
        null,
        null,
    ) orelse return error.WindowInit;
    errdefer glfwDestroyWindow(window);

    glfwMakeContextCurrent(window);

    var w: c_int = undefined;
    var h: c_int = undefined;
    glfwGetFramebufferSize(window, &w, &h);
    glViewport(0, 0, w, h);

    _ = glfwSetKeyCallback(window, keyCallback);
    _ = glfwSetCursorPosCallback(window, cursorPosCallback);
    _ = glfwSetMouseButtonCallback(window, mouseButtonCallback);
    _ = glfwSetCharCallback(window, charCallback);
    _ = glfwSetWindowSizeCallback(window, windowSizeCallback);

    glEnable(GL_BLEND);
    glBlendEquation(GL_FUNC_ADD);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glClearColor(0, 0, 0, 0);
}

fn deinitGfx() void {
    glfwDestroyWindow(window);
    glfwTerminate();
}

// ===

var heap_alloc = std.heap.c_allocator;
var vm: forth.VM = undefined;
var json_parser: json.Parser = undefined;

pub fn main() !void {
    vm = try forth.VM.init(heap_alloc);
    defer vm.deinit();
    try builtins.init();

    json_parser = json.Parser.init(heap_alloc, false);
    defer json_parser.deinit();

    {
        var forth_cfg = try readFile(heap_alloc, "src/config.fs");
        defer heap_alloc.free(forth_cfg);
        vm.interpretBuffer(forth_cfg) catch |err| switch (err) {
            error.WordNotFound => {
                std.debug.print("word not found: {s}\n", .{vm.word_not_found});
                return;
            },
            else => return err,
        };
    }

    try initGfx();
    defer deinitGfx();

    var tm = try FrameTimer.start();

    {
        var forth_main = try readFile(heap_alloc, "src/main.fs");
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
    // TODO
    // windowSizeCallback(window, w, h);

    while (glfwWindowShouldClose(window) == GLFW_FALSE) {
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        const dt = tm.step();
        const dt32 = @floatCast(f32, dt);

        try vm.fpush(dt32);
        try vm.execute(xts.frame);

        glfwSwapBuffers(window);
        glfwPollEvents();
        _ = c.usleep(100);
    }
}
