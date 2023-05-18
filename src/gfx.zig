const std = @import("std");
const c = @import("c.zig");

const heap_alloc = std.heap.c_allocator;

//;

pub const texture = struct {
    const Result = struct {
        texture: c.GLuint,
        width: c_int,
        height: c_int,
    };

    pub fn initFromMemory(buf: [*]u8, width: u32, height: u32) c.GLuint {
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
        \\     _ext_sb_position.y,
        \\     _ext_sb_rotation,
        \\     _ext_sb_scale.x,
        \\     _ext_sb_scale.y);
        \\ }
    ;

    const vert_default_effect =
        \\ vec3 effect() {
        \\    // return vec3(_ext_vertex, 1.0);
        \\    ready_spritebatch();
        \\    return _screen * _view * _model * _sb_model * vec3(_ext_vertex, 1.0);
        \\    // return _screen * _view * _model * vec3(_ext_vertex, 1.0);
        \\ }
    ;

    const vert_footer =
        \\ void main() {
        \\    _uv_coord = _flip_uvs != 0 ? vec2(_ext_uv.x, 1 - _ext_uv.y) : _ext_uv;
        \\    // _tm = _time;
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
        \\     // return vec4(1,1,1,1);
        \\     return _base_color * _sb_color * texture2D(_diffuse, _sb_uv);
        \\     // return _base_color * texture2D(_diffuse, _uv_coord);
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
    diffuse: c.GLint,
    base_color: c.GLint,

    pub fn fill(self: *Self, prog: c.GLuint) void {
        self.screen = c.glGetUniformLocation(prog, "_screen");
        self.view = c.glGetUniformLocation(prog, "_view");
        self.model = c.glGetUniformLocation(prog, "_model");
        self.time = c.glGetUniformLocation(prog, "_time");
        self.flip_uvs = c.glGetUniformLocation(prog, "_flip_uvs");
        self.diffuse = c.glGetUniformLocation(prog, "_diffuse");
        self.base_color = c.glGetUniformLocation(prog, "_base_color");
    }
};

var current_locations: *const Locations = undefined;

pub fn bindProgram(prog: *const Program) void {
    c.useProgram(prog.prog);
    current_locations = &prog.locations;
}

pub fn setBaseColor(color: [4]f32) void {
    c.uniform4fv(current_locations.base_color, color);
}

// TODO set time sceen view model, etc etc

var quad_vbo: c.GLuint = undefined;
var quad_vao: c.GLuint = undefined;
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

    const quad_verts = [16]f32{
        1.0, 1.0, 1.0, 1.0,
        0.0, 1.0, 0.0, 1.0,
        1.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 0.0,
    };

    c.glGenBuffers(1, &quad_vbo);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, quad_vbo);
    c.glBufferData(
        c.GL_ARRAY_BUFFER,
        @sizeOf(@TypeOf(quad_verts)),
        &quad_verts,
        c.GL_STATIC_DRAW,
    );
    c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);

    c.glGenVertexArrays(1, &quad_vao);
    c.glBindVertexArray(quad_vao);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, quad_vbo);
    c.glEnableVertexAttribArray(0);
    c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, 0, null);
    c.glEnableVertexAttribArray(1);
    c.glVertexAttribPointer(
        1,
        2,
        c.GL_FLOAT,
        c.GL_FALSE,
        0,
        @intToPtr(*allowzero const anyopaque, 2 * @sizeOf(f32)),
    );
    c.glBindVertexArray(0);

    //
}

pub fn deinit() void {
    c.glfwDestroyWindow(window);
    c.glfwTerminate();
}

pub fn drawQuad() void {
    c.glBindVertexArray(quad_vao);
    c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
    c.glBindVertexArray(0);
}

pub fn initSpritebatch() void {}

pub fn deinitSpritebatch() void {}
