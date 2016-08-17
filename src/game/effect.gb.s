SECTION "EffectLogic",ROM0

; TODO remove this test code
effect_init:
    ld      a,0
    ld      b,120
    ld      c,24
    call    effect_create

    ;ld      a,1
    ;ld      b,64
    ;ld      c,96
    ;call    effect_create

    ;ld      a,1
    ;ld      b,64
    ;ld      c,122
    ;call    effect_create
    ret


; Update all active Effects ---------------------------------------------------
effect_update:
    ld      l,0

_effect_update: ; l = reset

    ; effect state pointer
    ld      de,effectScreenState
    ld      h,0

.loop:
    ; check active flag
    ld      a,[de]
    and     %1000_0000
    cp      0
    jr      z,.next; not active skip

    ; check if in reset mode
    ld      a,l
    cp      1
    jr      z,.reset

    ; update sprite
    push    hl
    push    de
    call    _update_effect_sprite
    pop     de
    pop     hl

    ; check if still active
    jr      c,.next

.reset:
    push    de
    call    _effect_reset
    pop     de

    ; clear active flag
    ld      a,[de]
    and     %0111_1111
    ld      [de],a

.next:
    ld      a,e
    add     EFFECT_BYTES
    ld      e,a

    inc     h
    ld      a,e
    cp      (effectScreenState + EFFECT_MAX_COUNT * EFFECT_BYTES) & $ff
    jr      nz,.loop
    ret


; Create a new Effect ---------------------------------------------------------
effect_create:; a = effect type, b = ypos, c = xpos

    ; get free animation slot
    ld      de,effectScreenState

    ; effect index
    ld      h,0

    ; store effect type
    ld      l,a

.loop:
    ; load type / active
    ld      a,[de]
    cp      0
    jr      nz,.skip; active, skip
    ld      a,l; restore effect index
    call     _effect_create
    ret

.skip:
    ld      a,e
    add     EFFECT_BYTES
    ld      e,a

.next:
    inc     h
    ld      a,e
    cp      (effectScreenState + EFFECT_MAX_COUNT * EFFECT_BYTES) & $ff
    jr      nz,.loop
    ret


; Reset all active Effects ----------------------------------------------------
effect_reset:
    ld      l,1
    call    _effect_update
    ret



_effect_create:; a = effect index, de = effect data pointer, b = ypos, c = xpos

    ; multiply effect animation index by 8
    add     a
    add     a
    add     a

    ; setup effect data index
    ld      hl,DataEffectAnimation
    add     l
    ld      l,a

    ; load effect animation row
    ld      a,[hli]
    inc     a; offset animation row by 1
    push    hl
    push    de
    push    bc
    call    _effect_get_animation_quad
    ld      [coreTmp],a; store animation quad
    pop     bc
    pop     de
    pop     hl

    ; return early if we could not load the effect animation quad
    cp      $ff
    ret     z
    
    ; load flags
    ld      a,[hli]
    or      %1000_0000     
    ld      [de],a
    inc     e

    ; load dy from effect animation
    ld      a,[hli]
    ld      [de],a
    inc     e

    ; store ypos
    ld      a,b
    ld      [de],a
    inc     e

    ; store xpos
    ld      a,c
    ld      [de],a
    inc     e

    ; reset animation delay offset
    xor     a
    ld      [de],a
    inc     e

    ; load animation delay 
    ld      a,[hli]
    ld      [de],a
    inc     e

    ; load animation loop count
    ld      a,[hli]
    ld      [de],a
    inc     e

    ; reset effect animation index
    xor     a
    ld      [de],a
    inc     e

    ; store effect animation tile offset
    ld      a,[coreTmp]; multiply by 8
    ld      [de],a

    ret


_update_effect_sprite:; h = effect index, de = effect data pointer

    ; store effect sprite index
    ld      a,h
    add     a ; effect index * 4 
    add     a

    ; load sprite oam address
    ld      l,a
    ld      h,spriteOam >> 8

    ; load effect flags
    ld      a,[de]
    and     %0111_1111; mask of active bit
    ld      b,a; store flags
    inc     e

    ; check fore- / background flag and update hardware sprite  index
    and     %0001_0000
    jr      nz,.background
    ld      a,l
    add     EFFECT_FG_SPRITE_INDEX * 4
    ld      l,a
    jr      .update

.background:
    ld      a,l
    add     EFFECT_BG_SPRITE_INDEX * 4
    ld      l,a

.update:

    ; load dy
    ld      a,[de]
    inc     e
    cp      0
    jr      z,.no_move
    sub     $80
    ld      c,a; store dy
    jr      c,.add_y

.sub_y:
    ; only move every specified frame
    ld      a,[coreLoopCounter]
    sub     c
    jr      c,.no_move
    ld      a,[de]
    dec     a
    jr      .update_y

.add_y:

    ; only move every specified frame
    ld      a,[coreLoopCounter]
    sub     c
    jr      c,.no_move
    ld      a,[de]
    inc     a
    jr      .update_y

.no_move:
    ld      a,[de]

.update_y:

    ; store updated ypos
    ld      [de],a
    ld      c,a
    inc     e

    ; TODO check for tile col value
    ; TODO how to configure water/air/blocked col handling?
    ; TODO e.g. air bubbles collide with blocked and air and should stop then


    ; check for transparency
    ld      a,b
    and     %0010_0000
    cp      %0010_0000
    jr      nz,.update_x
    
    ; move the sprite to y 0 on every other frame to emulate 50% transparency
    ld      a,[coreLoopCounter]
    and     %0000_0001
    jr      nz,.update_x
    xor     a
    ld      c,a

    ; set ypos 
.update_x:
    ld      a,c; load updated ypos
    ld      [hli],a

    ; load xpos
    ld      a,[de]
    inc     e
    ld      [hli],a

    ; load animation delay offset
    ld      a,[de]
    inc     a
    ld      [de],a
    ld      c,a
    inc     e

    ; load animation delay and compare offset
    ld      a,[de]
    cp      c
    jr      nz,.no_index_advance

    ; reset delay offset
    dec     e
    xor     a
    ld      [de],a
    inc     e; skip delay offset
    inc     e; skip delay
    inc     e; skip loops left

    ; advance frame index
    ld      a,[de]
    inc     a
    ld      c,a; store frame index
    and     %0000_0011; wrap at 4 frames
    ld      [de],a
    dec     e; back to loops left

    ; check if the animation looped
    ld      a,c
    cp      4
    jr      nz,.update_index

    ; update loops left
    ld      a,[de]
    dec     a
    cp      0; disable effect if no loops are left
    jr      z,.disable
    ld      [de],a
    jr      .update_index

.no_index_advance:
    inc     e; skip animation delay

    ; load frame index
.update_index:
    inc     e; skip loops left
    ld      a,[de]
    ld      c,a
    inc     e

    ; load animation tile offset and add current animation index
    ld      a,[de]
    add     a
    add     a
    add     a
    add     $60; add base tile offset
    add     c; add current animation index * 2
    add     c
    inc     e

    ; update animation tile
    ld      [hli],a; tile index

    ; update sprite palette
    ld      a,[coreColorEnabled]
    cp      1
    jr      z,.color

    ; adjust palette for DMG
    ld      a,b
    and     %0000_0001
    swap    a
    ld      b,a

.color:

    ; mask of unused sprite flags
    ld      a,b
    and     %0001_0111
    ld      [hl],a

    ; mark as active
    scf
    ret

.disable:
    ; mark as disable
    and     a
    ret


_effect_reset:

    push    hl
    push    de

    ; store effect index
    ld      b,h

    ; skip effect flags and dy
    inc     e
    inc     e

    ; clear ypos
    xor     a
    ld      [de],a

    ; skip effect data until animation tile 
    ld      a,e
    add     6
    ld      e,a
    
    ; decrease effect quad usage
    ld      a,[de]; load quad index
    add     a; multiply by 2
    ld      hl,effectQuadsUsed 
    add     l
    ld      l,a
    dec     [hl]; decrease usage

    ; hide hardware sprite
    ld      h,b; restore effect index
    pop     de
    call    _update_effect_sprite
    pop     hl
    ret


; Tile Quad Management --------------------------------------------------------
_effect_get_animation_quad: ; a = animation row index -> a loaded effect quad

    ; store animation row index
    ld      d,a

    ; effect quad index
    ld      b,$ff

    ; go through all available effect quads
    ld      c,EFFECT_MAX_TILE_QUADS - 1
    ld      hl,effectQuadsUsed + EFFECT_MAX_TILE_QUADS * 2 - 2

.loop:

    ; check quad animation index
    ld      a,[hld]
    cp      d
    jr      nz,.check_unused

    ; increase usage count
    inc     [hl]

    ; found already loaded quad with same animation row index
    ld      b,c
    jr      .done

.check_unused:

    ; check usage count
    ld      a,[hl]
    cp      0
    jr      nz,.next

    ; increase usage count
    inc     a
    ld      [hli],a

    ; set quad animation row index
    ld      a,d
    ld      [hl],a 

    ; load animation row into target quad
    ld      b,c; setup target quad index
    push    bc
    dec     a ; correct row offset for loading
    call    _effect_load_tiles
    pop     bc

    ; loaded new quad
    jr      .done

.next:
    dec     hl; skip usage count
    dec     c
    jr      nz,.loop

    ; return the quad
.done:
    ld      a,b
    ret


_effect_load_tiles:; a = animation row index, b = tile quad index

    ld      c,a

    ; multiply quad index
    ld      h,b
    ld      e,$80
    call    math_mul8b

    ; calculate tile ram offset
    ld      de,$8600
    add     hl,de
    ld      d,h
    ld      e,l

    ; load high byte of tile map address
    ld      hl,DataEffectImg

    ; decompress sprite row into vram
    ld      b,0 ; offset into location table
    sla     c; each table entry is two bytes
    add     hl,bc ; hl = table offset data pointer

    ; read high and low byte for the offset
    ld      a,[hli]
    ld      b,a
    ld      a,[hli]
    ld      c,a; bc = offset until row data (from current table index position)

    ; create final data pointer for tile row data
    ; the offset value is pre calcuated to be relative from the table data pointer + 2
    add     hl,bc

    ; decode with end marker in stream
    call    core_decode_eom

    ret
