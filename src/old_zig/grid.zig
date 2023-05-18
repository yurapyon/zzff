const std = @import("std");
const ArrayList = std.ArrayList;

pub const Event = struct {};

pub const Canvas = struct {};

// regions are used by processes to know where to draw
// and used by zig to know where to send events or change focus
// may have a text buffer the size of w*h
// may have a canvas with dimensions (w*grid_w,h*grid_h)
pub const Region = struct {
    x: isize,
    y: isize,
    w: usize,
    h: usize,
    buffer: ?[]u8,
    canvas: ?Canvas,
};

// view are offsets used for showing the grid at certain points
pub const View = struct {
    pub const ZoomLevel = enum {
        half,
        none,
        twice,
    };

    x: isize,
    y: isize,
    zoom: ZoomLevel,
};

// pub const Process = struct {
// pub const Type = enum {
// forth_script,
// shader_script,
// vm_info,
// notes,
// lyza,
// tracker,
// externals_editor,
// image_file,
// audio_file,
// audio_node,
// game_screen,
// };
// };

pub const TextEdit = struct {
    pub const Type = enum {
        forth,
        shader,
        notes,
    };

    ty: Type,
    region: *Region,
    buffer: []u8,
};

pub var current_view: *View = undefined;
pub var focused_region: *Region = undefined;
pub var regions: ArrayList(Region) = undefined;
pub var views: ArrayList(View) = undefined;
