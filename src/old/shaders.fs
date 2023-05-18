: vert-header s"
#version 330 core

layout (location = 0) in vec2 _ext_vertex;
layout (location = 1) in vec2 _ext_uv;

layout (location = 2) in vec4  _ext_sb_uv;
layout (location = 3) in vec2  _ext_sb_position;
layout (location = 4) in float _ext_sb_rotation;
layout (location = 5) in vec2  _ext_sb_scale;
layout (location = 6) in vec4  _ext_sb_color;

// basic
uniform mat3 _screen;
uniform mat3 _view;
uniform mat3 _model;
uniform float _time;
uniform int _flip_uvs;

out vec2 _uv_coord;

// spritebatch
mat3 _sb_model;
out vec4 _sb_color;
out vec2 _sb_uv;

mat3 mat3_from_transform2d(float x, float y, float r, float sx, float sy) {
    mat3 ret = mat3(1.0);
    float rc = cos(r);
    float rs = sin(r);
    ret[0][0] =  rc * sx;
    ret[0][1] =  rs * sx;
    ret[1][0] = -rs * sy;
    ret[1][1] =  rc * sy;
    ret[2][0] = floor(x);
    ret[2][1] = floor(y);
    return ret;
}

void ready_spritebatch() {
    // scale main uv coords by sb_uv
    //   automatically handles flip uvs
    //   as long as this is called after flipping the uvs in main (it is)
    float uv_w = _ext_sb_uv.z - _ext_sb_uv.x;
    float uv_h = _ext_sb_uv.w - _ext_sb_uv.y;
    _sb_uv.x = _uv_coord.x * uv_w + _ext_sb_uv.x;
    _sb_uv.y = _uv_coord.y * uv_h + _ext_sb_uv.y;

    _sb_color = _ext_sb_color;
    _sb_model = mat3_from_transform2d(_ext_sb_position.x,
                                      _ext_sb_position.y,
                                      _ext_sb_rotation,
                                      _ext_sb_scale.x,
                                      _ext_sb_scale.y);
}
" ;

: vert-default-effect s"
vec3 effect() {
    // return vec3(_ext_vertex, 1.0);
    ready_spritebatch();
    return _screen * _view * _model * _sb_model * vec3(_ext_vertex, 1.0);
    // return _screen * _view * _model * vec3(_ext_vertex, 1.0);
}
" ;

: vert-footer s"
void main() {
    _uv_coord = _flip_uvs != 0 ? vec2(_ext_uv.x, 1 - _ext_uv.y) : _ext_uv;
    // _tm = _time;
    gl_Position = vec4(effect(), 1.0);
}
" ;

create vert-strings
vert-header drop ,
vert-default-effect drop ,
vert-footer drop ,

create vert-lens
vert-header nip h,
vert-default-effect nip h,
vert-footer nip h,

: frag-header s"
#version 330 core

// basic
uniform sampler2D _diffuse;
uniform vec4 _base_color;
uniform float _time;

in vec2 _uv_coord;

// spritebatch
in vec4 _sb_color;
in vec2 _sb_uv;

out vec4 _out_color;
" ;

: frag-default-effect s"
vec4 effect() {
    // return vec4(1,1,1,1);
    return _base_color * _sb_color * texture2D(_diffuse, _sb_uv);
    // return _base_color * texture2D(_diffuse, _uv_coord);
}
" ;

: frag-footer s"
void main() {
    _out_color = effect();
}
" ;

create frag-strings
frag-header drop ,
frag-default-effect drop ,
frag-footer drop ,

create frag-lens
frag-header nip h,
frag-default-effect nip h,
frag-footer nip h,

: set-effect ( str len saddr laddr -- )
  >r swap r>
  half + h!
  cell + ! ;

: make-vert-shader,effect ( estr elen -- shader t/f )
  vert-strings vert-lens set-effect
  vert-strings vert-lens 3 gl-vertex-shader make-shader ;

: make-vert-shader ( -- shader t/f )
  vert-default-effect make-vert-shader,effect ;

: make-frag-shader,effect ( estr elen -- shader t/f )
  frag-strings frag-lens set-effect
  frag-strings frag-lens 3 gl-fragment-shader make-shader ;

: make-frag-shader ( -- shader t/f )
  frag-default-effect make-frag-shader,effect ;

: shaders>program ( vert frag -- prog )
  2dup make-program -rot free-shader free-shader ;

0
cell field locs.screen
cell field locs.view
cell field locs.model
cell field locs.time
cell field locs.flip-uvs
cell field locs.diffuse
cell field locs.base-color
constant locations

: fill-location ( prog location zname -- )
  rot get-location swap ! ;

: <locations> ( prog locations -- )
  2dup locs.screen     z" _screen"     fill-location
  2dup locs.view       z" _view"       fill-location
  2dup locs.model      z" _model"      fill-location
  2dup locs.time       z" _time"       fill-location
  2dup locs.flip-uvs   z" _flip_uvs"   fill-location
  2dup locs.diffuse    z" _diffuse"    fill-location
       locs.base-color z" _base_color" fill-location ;

: program \ ( vert frag "name" -- ) name{ ( -- prog locations ) }
  make-program dup create ,
  here @ <locations> locations allot
  does> dup @ swap cell + ;

0 value current-locs

: bind-program ( prog locs -- )
  to current-locs
  use-program ;

\ ===

: set-base-color,addr ( color locs -- )
  locs.base-color @ uniform4fv ;

: set-base-color \ f: ( r g b a -- )
  fsp @ 4 floats -
  dup current-locs set-base-color,addr
  fsp ! ;

: set-time \ f: ( dt -- )
  time current-locs locs.time @ uniform1f ;

: set-screen ( -- ) m3main current-locs locs.screen @ uniformMatrix3fv ;
: set-view   ( -- ) m3main current-locs locs.view @ uniformMatrix3fv ;
: set-model  ( -- ) m3main current-locs locs.model @ uniformMatrix3fv ;

: set-screen,3d ( -- ) m4main current-locs locs.screen @ uniformMatrix4fv ;
: set-view,3d   ( -- ) m4main current-locs locs.view @ uniformMatrix4fv ;
: set-model,3d  ( -- ) m4main current-locs locs.model @ uniformMatrix4fv ;

: bind-diffuse ( tx -- )
  gl-texture-2d swap bind-texture
  gl-texture0 active-texture
  0 current-locs locs.diffuse @ uniform1i ;

\ ===

create quad-verts
1.0 1.0 1.0 1.0 vertex,
0.0 1.0 0.0 1.0 vertex,
1.0 0.0 1.0 0.0 vertex,
0.0 0.0 0.0 0.0 vertex,
here @ quad-verts - constant quad-verts-sz

make-buffer constant quad-vbo
gl-array-buffer quad-vbo bind-buffer
gl-array-buffer quad-verts quad-verts-sz gl-static-draw buffer-data
gl-array-buffer 0 bind-buffer

make-vertex-array
constant quad-vao

quad-vao bind-vertex-array
gl-array-buffer quad-vbo bind-buffer
2 gl-float false vertex 0 vertex.position 0 0 enable-attribute
2 gl-float false vertex 0 vertex.uv       0 1 enable-attribute
0 bind-vertex-array

: draw-quad
  quad-vao bind-vertex-array
  gl-triangle-strip 0 4 draw-arrays
  0 bind-vertex-array
  ;

\ ===

create smesh-verts
 0.5  0.5 1.0 1.0 vertex,
-0.5  0.5 0.0 1.0 vertex,
 0.5 -0.5 1.0 0.0 vertex,
-0.5 -0.5 0.0 0.0 vertex,
here @ smesh-verts - constant smesh-verts-sz

make-buffer constant smesh-vbo
gl-array-buffer smesh-vbo bind-buffer
gl-array-buffer smesh-verts smesh-verts-sz gl-static-draw buffer-data
gl-array-buffer 0 bind-buffer

500 constant sprite-ct
sprite-ct sprite * constant sprites-sz
create sprites-buf sprites-sz allot

make-buffer constant sprites-vbo
gl-array-buffer sprites-vbo bind-buffer
gl-array-buffer sprites-buf sprites-sz gl-stream-draw buffer-data
gl-array-buffer 0 bind-buffer

make-vertex-array
constant smesh-vao

smesh-vao bind-vertex-array
gl-array-buffer smesh-vbo bind-buffer
2 gl-float false vertex 0 vertex.position 0 0 enable-attribute
2 gl-float false vertex 0 vertex.uv       0 1 enable-attribute
gl-array-buffer sprites-vbo bind-buffer
4 gl-float false sprite 0 sprite.uv               1 2 enable-attribute
2 gl-float false sprite 0 sprite.t2d t2d.position 1 3 enable-attribute
1 gl-float false sprite 0 sprite.t2d t2d.rotation 1 4 enable-attribute
2 gl-float false sprite 0 sprite.t2d t2d.scale    1 5 enable-attribute
4 gl-float false sprite 0 sprite.color            1 6 enable-attribute
0 bind-vertex-array

0 value sprites-idx
0 value current-sprite

\ TODO make sure next-sprite logic is right

: sprites sprite * ;

: update-gl-sprites
  gl-array-buffer sprites-vbo bind-buffer
  gl-array-buffer 0 sprites-idx sprites sprites-buf buffer-sub-data
  ;

: draw-sprites ( -- )
  update-gl-sprites
  smesh-vao bind-vertex-array
  gl-triangle-strip 0 4 sprites-idx draw-arrays,instanced
  0 bind-vertex-array
  0 to sprites-idx
  sprites-buf to current-sprite
  ;

: maybe-draw-sprites
  sprites-idx sprite-ct >= if
    draw-sprites
  then ;

: next-sprite ( -- )
  1 +to sprites-idx
  sprite +to current-sprite
  maybe-draw-sprites ;

: start-sb
  0 to sprites-idx
  sprites-buf sprite - to current-sprite ;

: end-sb
  sprites-idx 0> if
    draw-sprites
  then ;

: sprite-color! \ f: ( r g b a -- )
  current-sprite sprite.color <color> ;

: sprite-uv! \ f: ( x1 y1 x2 y2 -- )
  current-sprite sprite.uv <rect> ;

: sprite-uv!,normalized \ ( x1 y1 x2 y2 w h )
  sp@ 6 cells - -rot current-sprite sprite.uv <rect>,normalized
  2drop 2drop ;

: rectangle! \ f: ( x1 y1 x2 y2 -- )
  current-sprite sprite.t2d <t2d>,rectangle ;

: urectangle! \ f: ( x1 y1 x2 y2 -- )
  current-sprite sprite.t2d <t2d>,urectangle ;

