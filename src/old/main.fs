: fconstant
  create f, align
  does> f@ ;

\ ===

0 value kp-key
0 value kp-scancode
0 value kp-action
0 value kp-mods
0 value ci-codepoint
0 value mp-button
0 value mp-action
0 value mp-mods
0.0 fvalue mm-x
0.0 fvalue mm-y
0.0 fvalue dt
0.0 fvalue time

include src/constants.fs
include src/types.fs
include src/shaders.fs
include src/3d.fs

: kp-event? ( action key mods -- t/f )
  kp-key = swap
  kp-action = and ;

: key-press
  to kp-key to kp-scancode to kp-action to kp-mods
  cond
    action-press key-enter kp-event? if ." enter" cr else
    action-press key-a     kp-event? if
      kp-mods mod-shift and if
        ." A" cr
      else
        ." a" cr
      then
    else
    action-press key-t kp-event? if
      dt f. cr
    else
  endcond
  ;

: char-input
  to ci-codepoint
  \ ci-codepoint emit cr
  ;

: mouse-press
  to mp-button to mp-action to mp-mods
  mp-button mb-left = if
    ." left" cr
  then
  ;

: mouse-move
  fto mm-x fto mm-y
  \ mm-x f. space mm-y f. cr
  ;

: window-resize
  to window-width to window-height
  ;

\ ===

: make-texture,from-file ( filepath n -- texture )
  file>string over >r make-texture r> free ;

\ ======

s" content/Codepage437.png" make-texture,from-file
constant tex-height
constant tex-width
constant tex-font

create suz-mesh mesh allot

s" content/test.gltf" file>string
s" content/test.bin" file>string set-gltf
s" Suzanne" suz-mesh <mesh>,gltf

make-3d-shaders
program 3dprog

3dprog bind-program
0.5 4.0 3.0 f/ 0.1 100.0 m4perspectiveFov set-screen,3d
m4identity 0.0 0.0 -5.0 m4translate! set-view,3d
m4identity set-model,3d

s" content/mahou.jpg" make-texture,from-file
constant mtex-height
constant mtex-width
constant mtex

\ ===

make-vert-shader make-frag-shader
program prog

prog bind-program
window-width window-height m3screen set-screen
m3identity set-view
m3identity set-model
\ m3identity 0.0 50.0 m3translate! set-model

: frame
  fto dt
  dt f+to time

  3dprog bind-program
  m4identity
  time fsin 0.0 -5.0
  m4translate!
  set-view,3d

  gl-depth-test gl-enable
  mtex bind-diffuse
  suz-mesh draw-mesh

  gl-depth-test gl-disable

  prog bind-program
  set-time
  mtex bind-diffuse
  1.0 1.0 0.5 1.0 set-base-color

  (
  \ 500 0 ?do
    m3identity
    100.0 100.0 0.0 200.0 200.0 m3t2d!
    set-model
    draw-quad
  \ loop
  )

  start-sb
  \ 1000 0 ?do
    next-sprite
    0 0 100 100 tex-width tex-height sprite-uv!,normalized
    1.0 1.0 1.0 1.0 sprite-color!
    100 100 200 200 urectangle!
    \ 100.0 100.0 100.0 tex-width f+ 100.0 tex-height f+ rectangle!
    \ 0.0 0.0 120.0 120.0 rectangle!
  \ loop
  end-sb
  ;
