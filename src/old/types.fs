0
float ffield v2.x
float ffield v2.y
constant v2

: .v2 ( v2 -- )
  dup v2.x f?
      v2.y f? ;

: <v2> \ ( v2 -- ) f: ( x y -- )
  dup v2.y f!
      v2.x f! ;

: <v2>,zero ( v2 -- )
  0.0 0.0 <v2> ;

: <v2>,one ( v2 -- )
  1.0 1.0 <v2> ;

\ ===

9 floats constant m3

: .m3
  9 0 ?do
    dup i floats + f?
  loop ;

create m3main m3 allot
create m3temp m3 allot

: m3push! m3temp m3main m3*! ;

: m3identity m3main <m3>,identity ;
: m3screen m3main <m3>,screen ;

: m3rotate! m3temp <m3>,rotation m3push! ;
: m3scale! m3temp <m3>,scaling m3push! ;
: m3translate! m3temp <m3>,translation m3push! ;
: m3shear! m3temp <m3>,shearing m3push! ;

: m3t2d! ( x y r sx sy -- )
  m3scale!
  m3rotate!
  m3translate! ;

\ ===

0
v2 ffield vertex.position
v2 ffield vertex.uv
constant vertex

: <vertex> \ ( v -- ) f: ( x y ux uy -- )
  dup vertex.uv <v2>
      vertex.position <v2> ;

: vertex, \ ( -- ) f: ( x y ux uy -- )
  here @ <vertex> vertex allot ;

: .vertex ( v -- )
  dup vertex.position .v2
      vertex.uv .v2 ;

0
float ffield color.r
float ffield color.g
float ffield color.b
float ffield color.a
constant color

: <color> \ ( color -- ) f: ( r g b a -- )
  dup color.a f!
  dup color.b f!
  dup color.g f!
      color.r f! ;

: <color>,white ( color -- )
  1.0 1.0 1.0 1.0 <color> ;

: <color>,black ( color -- )
  0.0 0.0 0.0 1.0 <color> ;

0
float ffield rect.x1
float ffield rect.y1
float ffield rect.x2
float ffield rect.y2
constant rect

: <rect> \ ( addr -- ) f: ( x1 y1 x2 y2 -- )
  dup rect.y2 f!
  dup rect.x2 f!
  dup rect.y1 f!
      rect.x1 f! ;

: <rect>,identity ( addr -- )
  0.0 0.0 1.0 1.0 <rect> ;

: .rect ( addr -- )
  dup f?
  dup float + f?
  dup 2 floats + f?
      3 floats + f? ;

0
v2    ffield t2d.position
float ffield t2d.rotation
v2    ffield t2d.scale
constant t2d

: .t2d ( addr -- )
  dup t2d.position .v2
  dup t2d.rotation f?
      t2d.scale .v2 ;

: <t2d> \ ( addr -- ) f: ( x y r sx sy -- )
  dup t2d.scale    <v2>
  dup t2d.rotation f!
      t2d.position <v2> ;

: <t2d>,identity ( addr -- )
  0.0 0.0 0.0 1.0 1.0 <t2d> ;

0
rect  ffield sprite.uv
t2d   ffield sprite.t2d
color ffield sprite.color
constant sprite

0
cell field urect.x1
cell field urect.y1
cell field urect.x2
cell field urect.y2
constant urect

: <urect>
  dup urect.y2 !
  dup urect.x2 !
  dup urect.y1 !
      urect.x1 ! ;

\ === 3d ===

0
float ffield v3.x
float ffield v3.y
float ffield v3.z
constant v3

: .v3 ( v3 -- )
  dup .v2 v3.z f? ;

0
v3 ffield vertex3d.position
v3 ffield vertex3d.normal
v2 ffield vertex3d.uv
constant vertex3d

\ ===

16 floats constant m4

: .m4
  16 0 ?do
    dup i floats + f?
  loop ;

create m4main m4 allot
create m4temp m4 allot

: m4push! m4temp m4main m4*! ;

: m4identity m4main <m4>,identity ;
: m4perspective m4main <m4>,perspective ;
: m4perspectiveFov m4main <m4>,perspectiveFov ;

: m4translate! m4temp <m4>,translation m4push! ;
