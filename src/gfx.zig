const std = @import("std");
const c = @import("c.zig");

const heap_alloc = std.heap.c_allocator;

//;

// math
pub const M3 = [9]f32;

pub const m3 = struct {
    // column major
    // m3[x * 3 + y]
    pub const m_00 = 0 * 3 + 0;
    pub const m_01 = 0 * 3 + 1;
    pub const m_02 = 0 * 3 + 2;
    pub const m_10 = 1 * 3 + 0;
    pub const m_11 = 1 * 3 + 1;
    pub const m_12 = 1 * 3 + 2;
    pub const m_20 = 2 * 3 + 0;
    pub const m_21 = 2 * 3 + 1;
    pub const m_22 = 2 * 3 + 2;

    pub fn zero(self: *M3) void {
        for (self) |*f| {
            f.* = 0;
        }
    }

    pub fn identity(self: *M3) void {
        zero(self);
        self[m_00] = 1;
        self[m_11] = 1;
        self[m_22] = 1;
    }

    pub fn translation(self: *M3, x: f32, y: f32) void {
        identity(self);
        self[m_20] = x;
        self[m_21] = y;
    }

    pub fn rotation(self: *M3, rads: f32) void {
        identity(self);
        const rc = std.math.cos(rads);
        const rs = std.math.sin(rads);
        self[m_00] = rc;
        self[m_01] = rs;
        self[m_10] = -rs;
        self[m_11] = rc;
    }

    pub fn scaling(self: *M3, x: f32, y: f32) void {
        identity(self);
        self[m_00] = x;
        self[m_11] = y;
    }

    pub fn shearing(self: *M3, x: f32, y: f32) void {
        identity(self);
        self[m_10] = x;
        self[m_01] = y;
    }

    pub fn orthoScreen(self: *M3, width: isize, height: isize) void {
        identity(self);
        // scale
        self[m_00] = 2 / @intToFloat(f32, width);
        self[m_11] = -2 / @intToFloat(f32, height);
        // translate
        self[m_20] = -1;
        self[m_21] = 1;
    }

    // writes into first arg
    pub fn mult(s: *M3, o: *M3) void {
        var temp: M3 = undefined;
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

//;

pub const texture = struct {
    const Result = struct {
        texture: c.GLuint,
        width: c_int,
        height: c_int,
    };

    pub fn initFromMemory(buf: [*]const u8, width: u32, height: u32) c.GLuint {
        var tex: c.GLuint = undefined;
        c.glGenTextures(1, &tex);
        c.glBindTexture(c.GL_TEXTURE_2D, tex);

        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_RGBA,
            @intCast(c.GLint, width),
            @intCast(c.GLint, height),
            0,
            c.GL_RGBA,
            c.GL_UNSIGNED_BYTE,
            buf,
        );

        c.glGenerateMipmap(c.GL_TEXTURE_2D);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);

        c.glBindTexture(c.GL_TEXTURE_2D, 0);

        return tex;
    }

    pub fn initFromFileMemory(buf: []u8) !Result {
        var w: c_int = undefined;
        var h: c_int = undefined;
        const raw_data = c.stbi_load_from_memory(
            buf.ptr,
            @intCast(c_int, buf.len),
            &w,
            &h,
            null,
            4,
        ) orelse return error.Load;
        defer c.stbi_image_free(raw_data);
        return Result{
            .texture = initFromMemory(
                raw_data,
                @intCast(u32, w),
                @intCast(u32, h),
            ),
            .width = w,
            .height = h,
        };
    }
};

pub const Program = struct {
    const Self = @This();

    const vert_header =
        \\ #version 330 core
        \\
        \\ layout (location = 0) in vec2 _ext_vertex;
        \\ layout (location = 1) in vec2 _ext_uv;
        \\
        \\ layout (location = 2) in vec4  _ext_sb_uv;
        \\ layout (location = 3) in vec2  _ext_sb_position;
        \\ layout (location = 4) in float _ext_sb_rotation;
        \\ layout (location = 5) in vec2  _ext_sb_scale;
        \\ layout (location = 6) in vec4  _ext_sb_color;
        \\
        \\ // basic
        \\ uniform mat3 _screen;
        \\ uniform mat3 _view;
        \\ uniform mat3 _model;
        \\ uniform float _time;
        \\ uniform int _flip_uvs;
        \\ uniform vec2 _vertex_offset;
        \\ uniform int _use_spritebatch;
        \\ out vec2 _uv_coord;
        \\
        \\ // spritebatch
        \\ mat3 _sb_model;
        \\ out vec4 _sb_color;
        \\ out vec2 _sb_uv;
        \\
        \\ mat3 mat3_from_transform2d(float x, float y, float r, float sx, float sy) {
        \\     mat3 ret = mat3(1.0);
        \\     float rc = cos(r);
        \\     float rs = sin(r);
        \\     ret[0][0] =  rc * sx;
        \\     ret[0][1] =  rs * sx;
        \\     ret[1][0] = -rs * sy;
        \\     ret[1][1] =  rc * sy;
        \\     ret[2][0] = floor(x);
        \\     ret[2][1] = floor(y);
        \\     return ret;
        \\ }
        \\
        \\ void ready_spritebatch() {
        \\ // scale main uv coords by sb_uv
        \\ //   automatically handles flip uvs
        \\ //   as long as this is called after flipping the uvs in main (it is)
        \\     float uv_w = _ext_sb_uv.z - _ext_sb_uv.x;
        \\     float uv_h = _ext_sb_uv.w - _ext_sb_uv.y;
        \\     _sb_uv.x = _uv_coord.x * uv_w + _ext_sb_uv.x;
        \\     _sb_uv.y = _uv_coord.y * uv_h + _ext_sb_uv.y;
        \\
        \\     _sb_color = _ext_sb_color;
        \\     _sb_model = mat3_from_transform2d(_ext_sb_position.x,
        \\                                       _ext_sb_position.y,
        \\                                       _ext_sb_rotation,
        \\                                       _ext_sb_scale.x,
        \\                                       _ext_sb_scale.y);
        \\ }
    ;

    const vert_default_effect =
        \\ vec3 effect() {
        \\     if (_use_spritebatch != 0) {
        \\         ready_spritebatch();
        \\     } else {
        \\         _sb_color = vec4(1, 1, 1, 1);
        \\         _sb_model = mat3(1);
        \\     }
        \\     return _screen * _view * _model * _sb_model * vec3(_ext_vertex + _vertex_offset, 1.0);
        \\ }
    ;

    const vert_footer =
        \\ void main() {
        \\    _uv_coord = _flip_uvs != 0 ? vec2(_ext_uv.x, 1 - _ext_uv.y) : _ext_uv;
        \\    gl_Position = vec4(effect(), 1.0);
        \\ }
    ;

    const frag_header =
        \\ #version 330 core
        \\
        \\ // basic
        \\ uniform sampler2D _diffuse;
        \\ uniform vec4 _base_color;
        \\ uniform float _time;
        \\
        \\ in vec2 _uv_coord;
        \\
        \\ // spritebatch
        \\ in vec4 _sb_color;
        \\ in vec2 _sb_uv;
        \\
        \\ out vec4 _out_color;
    ;

    const frag_default_effect =
        \\ vec4 effect() {
        \\     return _base_color * _sb_color * texture2D(_diffuse, _sb_uv);
        \\ }
    ;

    const frag_footer =
        \\ void main() {
        \\    _out_color = effect();
        \\ }
    ;

    prog: c.GLuint,
    locations: Locations,

    pub fn init(shaders: []const c.GLuint) !Self {
        var ret: Self = undefined;
        ret.prog = try makeProgram(shaders);
        ret.locations.fill(ret.prog);
        return ret;
    }

    // TODO deinit, deinit shaders?

    //;

    pub fn makeShader(ty: c.GLenum, sources: []const [*:0]const u8) !c.GLuint {
        const shader = c.glCreateShader(ty);
        errdefer c.glDeleteShader(shader);
        if (shader == 0) {
            return error.ShaderAllocError;
        }

        c.glShaderSource(shader, @intCast(c_int, sources.len), sources.ptr, null);
        c.glCompileShader(shader);

        var info_len: c_int = 0;
        c.glGetShaderiv(shader, c.GL_INFO_LOG_LENGTH, &info_len);
        if (info_len != 0) {
            var buf = try heap_alloc.alloc(u8, @intCast(usize, info_len));
            c.glGetShaderInfoLog(shader, info_len, null, buf.ptr);
            std.debug.print("shader info:\n{s}", .{buf});
            heap_alloc.free(buf);
        }

        var success: c_int = undefined;
        c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &success);
        if (success != c.GL_TRUE) {
            return error.ShaderCompileError;
        }

        return shader;
    }

    pub fn makeDefaultVertShader() !c.GLuint {
        const sources = [_][*:0]const u8{ vert_header, vert_default_effect, vert_footer };
        return try makeShader(c.GL_VERTEX_SHADER, &sources);
    }

    pub fn makeDefaultFragShader() !c.GLuint {
        const sources = [_][*:0]const u8{ frag_header, frag_default_effect, frag_footer };
        return try makeShader(c.GL_FRAGMENT_SHADER, &sources);
    }

    pub fn makeProgram(shaders: []const c.GLuint) !c.GLuint {
        const program = c.glCreateProgram();
        errdefer c.glDeleteProgram(program);
        if (program == 0) {
            return error.ProgramAllocError;
        }

        for (shaders) |shader| {
            c.glAttachShader(program, @intCast(c.GLuint, shader));
        }

        c.glLinkProgram(program);

        var info_len: c_int = 0;
        c.glGetProgramiv(program, c.GL_INFO_LOG_LENGTH, &info_len);
        if (info_len != 0) {
            var buf = try heap_alloc.alloc(u8, @intCast(usize, info_len));
            c.glGetProgramInfoLog(program, info_len, null, buf.ptr);
            std.debug.print("program info:\n{s}", .{buf});
            heap_alloc.free(buf);
        }

        var success: c_int = undefined;
        c.glGetProgramiv(program, c.GL_LINK_STATUS, &success);
        if (success != c.GL_TRUE) {
            return error.ProgramCompileError;
        }

        return program;
    }
};

pub const Locations = struct {
    const Self = @This();

    screen: c.GLint,
    view: c.GLint,
    model: c.GLint,
    time: c.GLint,
    flip_uvs: c.GLint,
    vertex_offset: c.GLint,
    use_spritebatch: c.GLint,
    diffuse: c.GLint,
    base_color: c.GLint,

    pub fn fill(self: *Self, prog: c.GLuint) void {
        self.screen = c.glGetUniformLocation(prog, "_screen");
        self.view = c.glGetUniformLocation(prog, "_view");
        self.model = c.glGetUniformLocation(prog, "_model");
        self.time = c.glGetUniformLocation(prog, "_time");
        self.flip_uvs = c.glGetUniformLocation(prog, "_flip_uvs");
        self.vertex_offset = c.glGetUniformLocation(prog, "_vertex_offset");
        self.use_spritebatch = c.glGetUniformLocation(prog, "_use_spritebatch");
        self.diffuse = c.glGetUniformLocation(prog, "_diffuse");
        self.base_color = c.glGetUniformLocation(prog, "_base_color");
    }
};

var current_locations: *const Locations = undefined;

pub fn bindProgram(prog: *const Program) void {
    c.glUseProgram(prog.prog);
    current_locations = &prog.locations;
}

pub fn setScreen(mat3: *const [9]f32) void {
    c.glUniformMatrix3fv(current_locations.screen, 1, c.GL_FALSE, mat3);
}

pub fn setView(mat3: *const [9]f32) void {
    c.glUniformMatrix3fv(current_locations.view, 1, c.GL_FALSE, mat3);
}

pub fn setModel(mat3: *const [9]f32) void {
    c.glUniformMatrix3fv(current_locations.model, 1, c.GL_FALSE, mat3);
}

pub fn setTime(to: f32) void {
    c.glUniform1f(current_locations.time, to);
}

pub fn setFlipUvs(to: bool) void {
    c.glUniform1i(current_locations.flip_uvs, if (to) 1 else 0);
}

pub fn setVertexOffset(x: f32, y: f32) void {
    c.glUniform2f(current_locations.vertex_offset, x, y);
}

pub fn setUseSpritebatch(to: bool) void {
    c.glUniform1i(current_locations.use_spritebatch, if (to) 1 else 0);
}

pub fn setBaseColor(color: [4]f32) void {
    c.glUniform4fv(current_locations.base_color, 1, &color);
}

pub fn setDiffuse(tex: c.GLuint) void {
    c.glBindTexture(c.GL_TEXTURE_2D, tex);
    c.glActiveTexture(c.GL_TEXTURE0);
    c.glUniform1i(current_locations.diffuse, 0);
}

fn enableFloatAttrib(index: c.GLuint, size: c.GLint, stride: c.GLsizei, offset: usize) void {
    c.glEnableVertexAttribArray(index);
    c.glVertexAttribPointer(
        index,
        size,
        c.GL_FLOAT,
        c.GL_FALSE,
        stride,
        @intToPtr(*allowzero const anyopaque, offset),
    );
}

pub const sb = struct {
    const SPRITE_CT = 500;

    const Sprite = extern struct {
        uv: [4]f32,
        position: [2]f32,
        rotation: [1]f32,
        scale: [2]f32,
        color: [4]f32,
    };

    const verts = [16]f32{
        1.0, 1.0, 1.0, 1.0,
        0.0, 1.0, 0.0, 1.0,
        1.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 0.0,
    };

    var vbo: c.GLuint = undefined;
    var sprites_vbo: c.GLuint = undefined;
    var vao: c.GLuint = undefined;

    var sprites_buf: [SPRITE_CT]Sprite = undefined;
    var sprites_idx: usize = 0;

    pub fn init() void {
        c.glGenBuffers(1, &vbo);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
        c.glBufferData(
            c.GL_ARRAY_BUFFER,
            @sizeOf(@TypeOf(verts)),
            &verts,
            c.GL_STATIC_DRAW,
        );
        c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);

        c.glGenBuffers(1, &sprites_vbo);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, sprites_vbo);
        c.glBufferData(
            c.GL_ARRAY_BUFFER,
            @sizeOf(@TypeOf(sprites_buf)),
            &sprites_buf,
            c.GL_STREAM_DRAW,
        );
        c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);

        const stride = 4 * @sizeOf(f32);
        const stride_sprites = @sizeOf(Sprite);

        c.glGenVertexArrays(1, &vao);

        c.glBindVertexArray(vao);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
        enableFloatAttrib(0, 2, stride, 0);
        enableFloatAttrib(1, 2, stride, 2 * @sizeOf(f32));
        c.glBindBuffer(c.GL_ARRAY_BUFFER, sprites_vbo);
        enableFloatAttrib(2, 4, stride_sprites, @offsetOf(Sprite, "uv"));
        c.glVertexAttribDivisor(2, 1);
        enableFloatAttrib(3, 2, stride_sprites, @offsetOf(Sprite, "position"));
        c.glVertexAttribDivisor(3, 1);
        enableFloatAttrib(4, 1, stride_sprites, @offsetOf(Sprite, "rotation"));
        c.glVertexAttribDivisor(4, 1);
        enableFloatAttrib(5, 2, stride_sprites, @offsetOf(Sprite, "scale"));
        c.glVertexAttribDivisor(5, 1);
        enableFloatAttrib(6, 4, stride_sprites, @offsetOf(Sprite, "color"));
        c.glVertexAttribDivisor(6, 1);
        c.glBindVertexArray(0);
    }

    pub fn start() void {
        sprites_idx = 0;
    }

    pub fn end() void {
        if (sprites_idx > 0) {
            draw();
        }
    }

    pub fn draw() void {
        c.glBindBuffer(c.GL_ARRAY_BUFFER, sprites_vbo);
        c.glBufferSubData(
            c.GL_ARRAY_BUFFER,
            0,
            @intCast(c_long, sprites_idx * @sizeOf(Sprite)),
            &sprites_buf,
        );
        c.glBindVertexArray(vao);
        c.glDrawArraysInstanced(c.GL_TRIANGLE_STRIP, 0, 4, @intCast(c_int, sprites_idx));
        c.glBindVertexArray(0);
        sprites_idx = 0;
    }

    pub fn advanceSprite() void {
        sprites_idx += 1;
        if (sprites_idx >= SPRITE_CT) {
            draw();
        }
    }

    pub fn currentSprite() *Sprite {
        return &sprites_buf[sprites_idx];
    }

    pub fn drawOne() void {
        c.glBindVertexArray(vao);
        c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
        c.glBindVertexArray(0);
    }
};

pub var window: *c.GLFWwindow = undefined;

pub fn init() !void {
    if (c.glfwInit() != c.GLFW_TRUE) {
        return error.GlfwInit;
    }
    errdefer c.glfwTerminate();

    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
    c.glfwWindowHint(c.GLFW_RESIZABLE, c.GL_FALSE);
    c.glfwSwapInterval(1);

    window = c.glfwCreateWindow(
        @intCast(c_int, 800),
        @intCast(c_int, 600),
        "float",
        null,
        null,
    ) orelse return error.WindowInit;
    errdefer c.glfwDestroyWindow(window);

    c.glfwMakeContextCurrent(window);

    var w: c_int = undefined;
    var h: c_int = undefined;
    c.glfwGetFramebufferSize(window, &w, &h);
    c.glViewport(0, 0, w, h);

    // _ = glfwSetKeyCallback(window, keyCallback);
    // _ = glfwSetCursorPosCallback(window, cursorPosCallback);
    // _ = glfwSetMouseButtonCallback(window, mouseButtonCallback);
    // _ = glfwSetCharCallback(window, charCallback);
    // _ = glfwSetWindowSizeCallback(window, windowSizeCallback);

    c.glEnable(c.GL_BLEND);
    c.glBlendEquation(c.GL_FUNC_ADD);
    c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
    c.glClearColor(0, 0, 0, 0);

    sb.init();
}

pub fn deinit() void {
    c.glfwDestroyWindow(window);
    c.glfwTerminate();
}
