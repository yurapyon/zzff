: 3dvert s"
#version 330 core

layout (location = 0) in vec3 _ext_vertex;
layout (location = 1) in vec3 _ext_normal;
layout (location = 2) in vec2 _ext_uv;

uniform mat4 _screen;
uniform mat4 _view;
uniform mat4 _model;
uniform float _time;
uniform int _flip_uvs;

out vec2 _uv_coord;

vec4 effect() {
    return _screen * _view * _model * vec4(_ext_vertex, 1);
}

void main() {
    _uv_coord = _ext_uv;
    gl_Position = effect();
}
" ;

create 3dvert-strings
3dvert drop ,

create 3dvert-lens
3dvert nip h,

: 3dfrag s"
#version 330 core

uniform sampler2D _diffuse;
uniform float _time;

in vec2 _uv_coord;

out vec4 _out_color;

vec4 effect() {
    return texture2D(_diffuse, _uv_coord);
}

void main() {
    _out_color = effect();
}
" ;

create 3dfrag-strings
3dfrag drop ,

create 3dfrag-lens
3dfrag nip h,

: make-3d-shaders
  3dvert-strings 3dvert-lens 1 gl-vertex-shader make-shader
  3dfrag-strings 3dfrag-lens 1 gl-fragment-shader make-shader
  ;

0 value gltf-str
0 value gltf-str-len
0 value gltf-bin
0 value gltf-bin-sz
0 value gltf-json

: free-gltf ( -- )
  gltf-json free-json 0 to gltf-json ;

: maybe-free-gltf ( -- )
  gltf-json if free-gltf then ;

: set-gltf ( json json-len bin bin-len -- )
  maybe-free-gltf
  to gltf-bin-sz to gltf-bin
  2dup to gltf-str-len to gltf-str
       parse-json to gltf-json ;

: node.name ( node -- addr len )
  s" name" rot jv>object.get jv>string ;

: get-node ( name nlen -- jnode/0 )
  s" nodes" gltf-json jv>object.get ( name nlen nodes )
  dup jv>array.len 0 ?do
    3dup
    i swap jv>array.at ( name nlen nodes name nlen nodes[i] )
    node.name string= if
      i swap jv>array.at -rot 2drop unloop exit
    then
  loop
  3drop 0 ;

: node.mesh
  s" mesh" rot jv>object.get jv>int ;

: get-mesh ( id -- jmesh )
  s" meshes" gltf-json jv>object.get jv>array.at ;

: get-accessor ( id -- jmesh )
  s" accessors" gltf-json jv>object.get jv>array.at ;

: get-buffer-view ( id -- jmesh )
  s" bufferViews" gltf-json jv>object.get jv>array.at ;

: gltf-mesh.primitives
  s" primitives" rot jv>object.get 0 swap jv>array.at ;

: gltf-mesh.indices
  gltf-mesh.primitives
  s" indices" rot jv>object.get jv>int ;

: gltf-mesh.attributes
  gltf-mesh.primitives
  s" attributes" rot jv>object.get ;

: attributes.position
  s" POSITION" rot jv>object.get jv>int ;

: attributes.normal
  s" NORMAL" rot jv>object.get jv>int ;

: attributes.uv
  s" TEXCOORD_0" rot jv>object.get jv>int ;

: buffer-view.byte-offset
  s" byteOffset" rot jv>object.get jv>int ;

: accessor.buffer-view
  s" bufferView" rot jv>object.get jv>int ;

: accessor.count
  s" count" rot jv>object.get jv>int ;

: accessor.byte-offset
  accessor.buffer-view get-buffer-view buffer-view.byte-offset ;

: attribute.byte-offset
  get-accessor accessor.byte-offset ;

: position-offset
  attributes.position attribute.byte-offset ;

: normal-offset
  attributes.normal attribute.byte-offset ;

: uv-offset
  attributes.uv attribute.byte-offset ;

0
cell field mesh.vao
cell field mesh.vbo
cell field mesh.elements-ct
cell field mesh.elements-offset
constant mesh

: <mesh> ( mesh -- )
  make-vertex-array over mesh.vao !
  make-buffer swap mesh.vbo ! ;

: mesh.bind-vao ( mesh -- )
  mesh.vao @ bind-vertex-array ;

: mesh.bind-vbo ( to mesh -- )
  mesh.vbo @ bind-buffer ;

: draw-mesh ( mesh -- )
  dup mesh.bind-vao
  >r
  gl-triangles r@ mesh.elements-ct @ gl-unsigned-short r> mesh.elements-offset @
  draw-elements
  0 bind-vertex-array ;

: <mesh>,gltf ( node-name nnlen mesh -- )
  dup <mesh> -rot
  get-node node.mesh get-mesh ( mesh gltf-mesh )
  over mesh.bind-vao
  over gl-array-buffer swap mesh.bind-vbo
  gl-array-buffer gltf-bin gltf-bin-sz gl-static-draw buffer-data
  over gl-element-array-buffer swap mesh.bind-vbo
  dup gltf-mesh.attributes
      dup position-offset >r
          3 gl-float false 0 r> 0 0 enable-attribute
      dup normal-offset >r
          3 gl-float false 0 r> 0 1 enable-attribute
          uv-offset >r
          2 gl-float false 0 r> 0 2 enable-attribute
  0 bind-vertex-array
  gltf-mesh.indices get-accessor
  2dup accessor.count swap mesh.elements-ct !
       accessor.byte-offset swap mesh.elements-offset !
  ;

: mesh.free
  \ todo
  ;
