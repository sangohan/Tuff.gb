SECTION "MapLogic",ROM0


; Map -------------------------------------------------------------------------
map_init: ; a = base value for background tiles

    sub     128; add offset for tile buffer at $8800
    ld      hl,mapRoomTileBuffer
    ld      bc,512
    call    core_mem_set

    ; clear both screen buffers
    ld      hl,$9800
    ld      bc,1024
    call    core_mem_set

    ld      hl,$9c00
    ld      bc,1024
    call    core_mem_set

    ret


; Scrolling -------------------------------------------------------------------
map_scroll_left:
    ld      bc,$FF00
    jr      _map_scroll

map_scroll_right:
    ld      bc,$0100
    jr      _map_scroll

map_scroll_down:
    ld      bc,$0001
    jr      _map_scroll

map_scroll_up:
    ld      bc,$00FF

_map_scroll:
    ld      a,[mapRoomX]
    ld      [mapRoomLastX],a
    add     b
    ld      b,a
    ld      a,[mapRoomY]
    ld      [mapRoomLastY],a
    add     c
    ld      c,a

    ; trigger room exit scripts
    ld      a,SCRIPT_TRIGGER_ROOM_LEAVE
    call    script_execute

    ; store entity state
    push    bc
    call    entity_store
    pop     bc

    call    map_load_room
    ret


; Map -------------------------------------------------------------------------
map_load_room: ; b = x, c = y

    push    hl
    push    de
    push    bc

    ; store new room coordinates
    ld      a,b
    ld      [mapRoomX],a
    ld      a,c
    ld      [mapRoomY],a

    ; trigger room enter scripts
    ld      a,SCRIPT_TRIGGER_ROOM_ENTER
    call    script_execute

    ; bank switch
    di
    ld      a,MAP_ROOM_DATA_BANK
    ld      [$2000],a

    ; get room pointer offset into bc
    call    _map_load_room_pointer
    inc     hl; skip length byte

    ; store room flags here for later use
    ld      a,[hli]
    ld      [mapRoomHeaderFlags],a

    call    _map_load_animations
    call    _map_load_tile_map
    call    _map_load_effects
    call    _map_load_entities

    ; unpack the tile data
    ld      de,mapRoomBlockBuffer
    ld      bc,mapRoomBlockBuffer + MAP_ROOM_SIZE
    ld      a,b
    ld      [coreDecodeAddress],a
    ld      a,c
    ld      [coreDecodeAddress + 1],a
    call    core_decode_eom

    ; bank switch
    ld      a,$01
    ld      [$2000],a

    ; setup block definitions
    call    _map_load_block_definitions

    ; unload entities
    call    entity_reset

    ; unload effects
    call    effect_reset

    ; force sprite unloads
    call    sprite_update

    ; load effects from map
    call    _map_create_effects

    ; load room data into vram
    call    _map_load_room_data

    ; reset animation delays to keep everything in sync
    ld      hl,mapAnimationDelay
    xor     a
    ld      [mapCollisionFlag],a
    ld      bc,TILE_ANIMATION_COUNT
    call    core_mem_set

    ; update all sprites
    call    sprite_update
    ei

    pop     bc
    pop     de
    pop     hl

    ret


; Core Map Draw Routine -------------------------------------------------------
map_draw_room:

    ; mark as updated (disable interrupts so we don't call this during vblank)
    di

    ; load new entities
    call    entity_load

    ; switch between the two screen buffers to prevent flickering
    ld      a,[mapCurrentScreenBuffer]
    cp      0
    jr      nz,.buffer_9c

.buffer_98:
    ld      de,$9800
    jr      .copy

.buffer_9c:
    ld      de,$9C00

.copy:
    ld      hl,mapRoomTileBuffer
    ld      bc,256
    call    core_vram_cpy

    ; flip background buffer (we double buffer to avoid tear)
    ld      a,[mapCurrentScreenBuffer]
    xor     1
    ld      [mapCurrentScreenBuffer],a

    ; adjust for or mask
    xor     1
    add     a
    add     a
    add     a
    ld      b,a

    ; flip bg data used for screen
    ld      a,[rLCDC]
    and     LCDCF_BG_MASK
    or      b
    ld      [rLCDC],a

    xor     a
    ld      [mapRoomUpdateRequired],a
    ei

    ret


; Collision Detection ---------------------------------------------------------
map_get_collision: ; b = x pos, c = y pos (both without scroll offsets) -> a = 1 if collision, 0 = no collision

    ; check for the bottom end of the screen
    ; if we index into the ram beyond this area we will read invalid data
    ; so we assume that there is never any collision beyond y 128
    ld      a,c
    cp      128
    jr      nc,.off_screen ; reset collision flag and indicate no collision

    ; divide x by 8
    srl     b
    srl     b
    srl     b

    ; divide y by 8
    srl     c
    srl     c
    srl     c

    ; check type of collision
    call    map_get_tile_collision
    ld      [mapCollisionFlag],a
    cp      MAP_COLLISION_BLOCK; normal blocks
    jr      z,.collision
    cp      MAP_COLLISION_BREAKABLE; breakable
    jr      z,.collision
    cp      MAP_COLLISION_NONE; breakable
    jr      z,.no_collision
    ; store hazard flag for all other kinds of block
    ld      [mapHazardFlag],a

    ; everything that is not solid has no collision
.no_collision:
    and     a
    ret

.collision:
    scf
    ret

.off_screen:
    xor     a
    ld      [mapCollisionFlag],a
    ret


; same as the nomral collision check
; and also treat everything except for 0 as collision
map_get_collision_simple: ; b = x pos, c = y pos (both without scroll offsets) -> a = 1 if collision, 0 = no collision
    push    bc

    ; check bottom screen border
    ld      a,c
    cp      127
    jr      nc,.collision

    ; check right screen border
    ld      a,b
    cp      159
    jr      nc,.collision

    ; check top screen border
    xor     a
    cp      c
    jr      nc,.collision

    ; check left screen border
    cp      b
    jr      nc,.collision

    ; divide x by 8
    srl     b
    srl     b
    srl     b

    ; divide y by 8
    srl     c
    srl     c
    srl     c

    ; check type of collision
    call    map_get_tile_collision
    cp      0
    jr      nz,.collision
    pop     bc

    ; no collision
    and     a
    ret

.collision:
    pop     bc
    scf
    ret


; Block / Tile ----------------------------------------------------------------
map_get_block_value: ; b = x, c = y -> a block value

    push    hl
    push    de

    ; y * 10
    ld      h,10
    ld      e,c
    call    math_mul8b

    ; add x
    ld      e,b
    ld      d,0
    add     hl,de

    ; add base offset
    ld      de,mapRoomBlockBuffer
    add     hl,de
    ld      a,[hl]

    pop     de
    pop     hl

    ret


map_set_tile_value: ; b = tile x, c = tile y, a = value
    ; sets the tile value in the both the room data buffer and the screen buffer

    push    de
    push    hl

    ; convert tile into -127-128 range and store into d
    add     128
    ld      d,a ; store tile value
    ld      e,b ; store xpos

    ; calculate base offset for the tile into either buffer
    ld      h,0
    ld      l,c
    add     hl,hl ; x2
    add     hl,hl ; x4
    add     hl,hl ; x8
    add     hl,hl ; x16
    add     hl,hl ; x32

    ; set tile value in map buffer
    push    hl
    ld      a,d; temp store tile value
    ld      d,mapRoomTileBuffer >> 8; high byte, needs to be aligned at 256 bytes
    add     hl,de
    ld      [hl],a; set tile in map buffer
    pop     hl

    ; set tile value in screen buffer
    ld      d,a
    ld      a,[mapCurrentScreenBuffer]
    ; TODO optimize
    cp      0
    jr      z,.screen_9c
    ld      a,d; restore
    ld      d,$98
    jr      .set

.screen_9c:
    ld      a,d; restore
    ld      d,$9c

.set:
    add     hl,de
    ld      d,a; restore tile value

    ; wait for vram to be safe
    ld      a,[rSTAT]       ; <---+
    and     STATF_BUSY      ;     |
    jr      nz,@-4          ; ----+

    ; set tile value
    ld      [hl],d

    pop     hl
    pop     de

    ret


; Animation -------------------------------------------------------------------
map_animate_tiles:

    ; store state
    push    hl
    push    de
    push    bc

    ; loop and animate tiles
    ld      d,0
    ld      hl,mapAnimationIndexes
.animate:

    ; check if animation is used
    ld      bc,mapAnimationUseMap
    ld      a,d
    add     a,c
    ld      c,a
    adc     a,b
    sub     c
    ld      b,a
    ld      a,[bc] ; check if current tile is animated on this screen
    cp      0
    jr      z,.next

    ; load current delay count for this animation
    ld      bc,mapAnimationDelay
    ld      a,d
    add     a,c
    ld      c,a
    adc     a,b
    sub     c
    ld      b,a
    ld      a,[bc] ; delay for the current tile
    cp      0 ; if we hit zero animate the tile
    jr      nz,.delay ; if not decrease delay count by one

    ; animate the tile -------------------------------------

    ; get the default delay value
    push    bc; store delay point counter
    ld      bc,DataTileAnimation

    ; offset into tile animation data
    ld      a,d; base + d * 8 + 1
    add     a; x8
    add     a
    add     a
    inc     a

    ; add to bc
    add     a,c
    ld      c,a
    adc     a,b
    sub     c
    ld      b,a
    ld      a,[bc]
    pop     bc; restore delay count pointer

    ; set index count to default delay
    ld      [bc],a

    ; update current tile animation index
    ld      a,[hl]
    inc     a
    and     %00000011 ; modulo 4
    ld      [hl],a

    ; update tile vram -------------------------------------

    ; update vram  (hl = source, de = dest, bc = size (16))
    push    hl
    push    de

    ; store animation index value
    inc     a; offset into animation data
    inc     a
    ld      e,a

    ; get base tile value of the animation (base + d * 8)
    ld      hl,DataTileAnimation
    ld      b,0
    ld      c,d
    sla     c
    sla     c
    sla     c
    add     hl,bc
    ld      d,[hl] ; base tile value $00 - $ff

    ; get the current tile value of the animation into B (base + d * 8 + a + 2)
    ld      c,e
    add     hl,bc
    ld      b,[hl] ; store current tile value $00 - $ff

    ; get the target address in vram into DE (multiply the base tile by 16 + $8800)
    ld      h,0
    ld      l,d
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      a,h
    add     a,$88; add screen vram base offset
    ld      d,a ; store into DE
    ld      e,l

    ; get the current animation address into HL
    ; (multiply the current (tile - TILE_ANIMATION_BASE_OFFSET) by 16 + DataTileImg)
    ld      a,b; restore tile value
    ld      h,0
    ld      l,a
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      bc,mapTileAnimationBuffer
    add     hl,bc

    ; copy 16 bytes from the tile buffer into vram
    ld      b,16
    call    core_vram_cpy_low

    pop     de
    pop     hl
    jr      .next

.delay:
    dec     a
    ld      [bc],a

.next:
    ; end of vram update

    ; next animation
    inc     hl
    inc     d
    ld      a,d
    cp      TILE_ANIMATION_DATA_COUNT
    jr      nz,.animate
    ; end of loop

    ; restore state
    pop     bc
    pop     de
    pop     hl

    ret


; Fallable blocks -------------------------------------------------------------
map_check_fallable_blocks:

    ; check if there are any blocks on the current screen
    ld      a,[mapFallableBlockCount]
    cp      0
    ret     z

    ; setup loop counter
    ld      b,a

.loop:

    ; get offset
    ld      de,mapFallableBlocks
    ld      h,0
    ld      l,b
    dec     l; correct block indexing
    add     hl,hl; x 2
    add     hl,hl; x 4
    add     hl,de; get offset address

    ; check if inactive
    ld      a,[hli]
    and     %00000001
    cp      0
    jr      nz,.active

    ; skip frame
    inc     hl

    ; load block x coordinate
    ld      a,[hli]
    ld      c,a

    ; load player coordinates and convert into blocks
    ld      a,[playerX]
    swap    a
    and     $0f; divide by 16
    cp      c
    jr      z,.found_x

    ld      a,[playerX]
    add     PLAYER_HALF_WIDTH - 3
    swap    a
    and     $0f; divide by 16
    cp      c
    jr      z,.found_x

    ld      a,[playerX]
    sub     PLAYER_HALF_WIDTH - 2
    swap    a
    and     $0f; divide by 16
    cp      c
    jr      z,.found_x
    jr      .active

    ; load block y coordinate
.found_x:
    ld      c,[hl]

    ; check the block 2 pixel under the player
    ; TODO check if in upper half of block only ?
    ld      a,[playerY]
    inc     a
    swap    a
    and     $0f; divide by 16
    cp      c
    jr      nz,.active

    dec     hl
    dec     hl
    dec     hl

    ; if player is near block set active
    ld      a,[hl]
    and     %00000010; reset everything but type
    or      %00000001; type / active flag
    ld      [hl],a

    ; check player movement speed
    ld      a,[playerSpeedRight]
    ld      b,a
    ld      a,[playerSpeedLeft]
    or      b
    and     %00000010
    jr      nz,.delayed

    ; setup instant fall and play sound
    call    _map_update_falling_block
    ld      a,SOUND_EFFECT_MAP_FALLING_BLOCK
    call    sound_play_effect_two_wait

    ; prevent player from jumping over platforms
    xor     a
    ld      [playerOnGround],a
    ld      a,PLAYER_GRAVITY_MAX
    ld      [playerFallSpeed],a

    jr      .active

.delayed:
    ; setup drop delay
    ld      a,[hl]
    or      MAP_FALLABLE_BLOCK_DELAY << 4
    ld      [hl],a

    ; loop
.active:
    dec     b
    jr      nz,.loop
    ret


map_update_falling_blocks:

    ; check if there are any blocks on the current screen
    ld      a,[mapFallableBlockCount]
    cp      0
    ret     z

    ; setup loop counter
    ld      b,a

.loop:

    ; get offset
    ld      de,mapFallableBlocks
    ld      h,0
    ld      l,b
    dec     l; correct block indexing
    add     hl,hl; x 2
    add     hl,hl; x 4
    add     hl,de; get offset address

    ; check if active
    ld      a,[hl]
    and     %00000001
    cp      0
    jr      z,.inactive

    ; check for delay
    ld      a,[hl]
    swap    a
    and     %00001111
    jr      nz,.delayed

    call    _map_update_falling_block
    jr      .inactive

.delayed:
    ; decrease drop delay
    ld      a,[hl]
    swap    a
    dec     a
    swap    a
    ld      [hl],a
    and     %11110000
    jr      nz,.inactive

    ; play sound if the delay reached 0
    ld      a,SOUND_EFFECT_MAP_FALLING_BLOCK
    call    sound_play_effect_two_wait

    ; loop
.inactive:
    dec     b
    jr      nz,.loop
    ret


_map_update_falling_block: ; b = index

    ; load block type flag (dark / light)
    ld      a,[hli]
    and     %000000_1_0
    add     a; multiply by 2
    ld      e,a

    ; check animation frame index (animation has 4 frames)
    ld      a,[hl]
    cp      4
    ret     z

    ; advance to next animation frame index
    inc     [hl]

    ; store loop counter and frame pointer
    push    bc
    push    hl

    ; skip frame count
    ld      a,[hli]
    ld      d,a; store frame count

    ; load x / y coordinates
    ld      a,[hli]; load x
    ld      b,a
    ld      c,[hl]; load y
    sla     b; convert into 8x8 index
    sla     c; convert into 8x8 index

    ; load background tile base value
    ld      hl,MapFallableBlockTable
    ld      a,l
    add     e
    ld      l,a

    ; update animated tile
    ld      a,d
    cp      4
    jr      z,.done_animated

.animate:
    ld      a,[hl]
    add     d  ; add animation index
    ld      e,a; right tile
    add     4  ; left tile
    jr      .update_tiles

    ; final background tile after animation is done
.done_animated:
    inc     hl
    ld      a,[hli]; right tile
    ld      e,[hl] ; left  tile

    ; update both 8x8 background tiles
.update_tiles:
    call    map_set_tile_value
    inc     b
    ld      a,e
    call    map_set_tile_value

    ; restore frame pointer and loop counter
    pop     hl
    pop     bc

.done:
    ret

MapFallableBlockTable:
    DB     MAP_FALLING_TILE_DARK
    DB     MAP_BACKGROUND_TILE_DARK_L
    DB     MAP_BACKGROUND_TILE_DARK_R
    DB     0
    DB     MAP_FALLING_TILE_LIGHT
    DB     MAP_BACKGROUND_TILE_LIGHT
    DB     MAP_BACKGROUND_TILE_LIGHT



; Helpers ---------------------------------------------------------------------
map_get_tile_collision: ; b = tile x, c = tile y -> a = value
    push    hl

    ; get offset into collision table
    call    map_get_tile_value
    ld      h,DataTileCol >> 8; needs to be aligned at 256 bytes
    ld      l,a
    ld      a,[hl]

    pop     hl
    ret


map_get_tile_value: ; b = tile x, c = tile y -> a = value
    ; gets the tile value from the room data buffer (not VRAM!)
    ; thrashes hl and bc

    ld      a,b ; store x

    ; y * 32
    ld      h,0
    ld      l,c

    add     hl,hl ; 2
    add     hl,hl ; 4
    add     hl,hl ; 8
    add     hl,hl ; 16
    add     hl,hl ; 32

    ; + mapRoomTileBuffer + x
    ld      b,mapRoomTileBuffer >> 8; high byte, needs to be aligned at 256 bytes
    ld      c,a ; restore x
    add     hl,bc

    ; load tile value from background buffer
    ld      a,[hl]
    sub     128 ; convert into 0-255 range

    ret


; Map Loading Helpers ---------------------------------------------------------
; -----------------------------------------------------------------------------
_map_load_room_pointer:; b = x, c = y -> bc = pointer to packed room data

    ; base pointer for the map
    ld      hl,DataMapMain

    ; id = x * (y * 16)
    sla     c; x2
    sla     c; x4
    sla     c; x8
    sla     c; x16
    ld      a,c
    add     b;
    ld      b,a

.next:
    ; check if we found the room we're looking for
    ret     z; compare against the result of add b / dec b

    ; else read length byte and skip room data
    ld      a,[hli]
    add     a,l
    ld      l,a
    adc     a,h
    sub     l
    ld      h,a

    ; check next room
    dec     b
    jr      .next
    ret


_map_load_animations:
    ld      b,0; per default animations are off
    ld      a,[mapRoomHeaderFlags]
    and     %00000001
    cp      0
    jr      z,.skip_animation_byte

    ; load animation attribute byte
    ld      a,[hli]
    ld      b,a; store into b

.skip_animation_byte:

    ; set active animation data (b = animation attribute byte)
    ld      de,mapAnimationUseMap
    ld      c,TILE_ANIMATION_COUNT / 2; 8 bits to check

    ; each time we check bit 0 and flag two animations active
.next_animation_byte:
    xor     a
    bit     0,b; check if animation is active
    jr      z,.set_animation_byte; if not set, set the value to 0
    inc     a; otherwise we load a 1

.set_animation_byte:
    ld      [de],a
    inc     de
    ld      [de],a
    inc     de
    srl     b; shift to next byte of animation active table
    dec     c
    jr      nz,.next_animation_byte
    ret


_map_load_tile_map:

    ; load and setup the rooms tile block definition mapping
    ld      a,[mapRoomHeaderFlags]
    bit     1,a; check if this room has a custom tile block map
    ld      a,$0f; default mapping
    jr      z,.skip_tile_map_byte
    ld      a,[hli]

.skip_tile_map_byte:
    ld      [mapRoomTileBlockMap],a; store mapping
    ret


_map_load_block_definitions:

    ; compare with old room mapping
    ld      a,[mapRoomTileLastBlockMap]
    ld      b,a

    ; check if the mapping changed
    ld      a,[mapRoomTileBlockMap]
    cp      b
    ret     z

    ld      [mapRoomTileLastBlockMap],a
    ld      c,a
    ld      b,0

    ; now setup the tile mappings into the corresponding ram section
    xor     a
.next:
    bit     0,c
    jr      z,.not_mapped; if not set, skip this mapping

    ; load the 4 8x8 tiles for the 64 corresponding blocks
    call    _map_load_tile_block
    inc     b

.not_mapped:
    srl     c; shift to next bit

    ; we check 8 bits we do NOT expect more than 4 blocks def rows to be active
    inc     a
    cp      8
    jr      nz,.next

    ret


_map_load_tile_block: ; a = origin block, b = target block
    push    af
    push    bc

    ; setup target location
    ld      h,0
    ld      l,b
    add     hl,hl; x64
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      bc,mapBlockDefinitionBuffer
    add     hl,bc; add data location
    ld      b,h; move into bc
    ld      c,l

    ; setup origin
    ld      h,a
    ld      l,0
    ld      de,DataBlockDef
    add     hl,de; add data location

    ; copy the 256 block definition bytes for the 64, 16x16 blocks
    ld      d,64
.loop:

    ; row 1
    ld      a,[hli]
    ld      [bc],a
    inc     b

    ; row 2
    ld      a,[hli]
    ld      [bc],a
    inc     b

    ; row 3
    ld      a,[hli]
    ld      [bc],a
    inc     b

    ; row 4
    ld      a,[hli]
    ld      [bc],a

    ; back to first row
    dec     b
    dec     b
    dec     b

    ; advance column
    inc     c

.skip:
    dec     d
    jr      nz,.loop

    pop     bc
    pop     af
    ret


_map_load_effects:

    ; check number of effects used in room
    ld      a,[mapRoomHeaderFlags]
    srl     a
    srl     a
    and     %00000111

    ; copy effect data after room tile buffer and entity data buffer
    ld      [mapRoomEffectCount],a
    ld      b,0
    ld      c,a
    sla     c ; each entity has two bytes so we multiple by two here
    ld      de,mapRoomBlockBuffer + MAP_ROOM_SIZE + MAP_ENTITY_SIZE
    call    core_mem_cpy
    ret


_map_create_effects:

    ; check if we have any effects in the current room
    ld      a,[mapRoomEffectCount]
    cp      0
    ret     z

    ; setup loop
    ld      hl,mapRoomBlockBuffer + MAP_ROOM_SIZE + MAP_ENTITY_SIZE
    ld      b,a

.loop:

    ; store loop counter
    push    bc

    ; type and offsets
    ld      a,[hli]
    ld      e,a
    and     %00_111111
    ld      d,a; store type
    ld      a,e
    and     %11_000000
    ld      e,a; store 8x8 offsets

    ; load position
    ld      a,[hli]
    ld      b,a; store ypos

    ; mask xpos
    and     %0000_1111
    swap    a; multiply by 16
    add     8
    ld      c,a

    ; check for offset and add 8 pixel
    ld      a,e
    and     %1_000_0000
    jr      z,.ypos
    ld      a,c
    add     8
    ld      c,a

    ; mask ypos
.ypos:
    ld      a,b
    and     %1111_0000
    add     16; offset effect at the bottom
    ld      b,a

    ; check for offset and subtracr 8 pixel
    ld      a,e
    and     %0_100_0000
    jr      z,.create
    ld      a,b
    sub     8
    ld      b,a

.create:
    push    hl
    ld      a,d; load effect id
    add     EFFECT_MAP_DEFINITION_OFFSET - 1
    call    effect_create
    pop     hl

    ; restore loop counter
    pop     bc
    dec     b
    jr      nz,.loop
    ret


_map_load_entities:

    ; check number of entities used in room
    ld      a,[mapRoomHeaderFlags]
    swap    a
    and     %00001110
    srl     a

    ; copy entity data after room tile buffer
    ld      [mapRoomEntityCount],a
    ld      b,0
    ld      c,a
    sla     c ; each entity has two bytes so we multiple by two here
    ld      de,mapRoomBlockBuffer + MAP_ROOM_SIZE
    call    core_mem_cpy
    ret


_map_load_room_data:

    xor     a
    ld      [mapRoomUpdateRequired],a
    ld      [mapFallableBlockCount],a

    ; target is the screen buffer
    ld      hl,mapRoomTileBuffer

    ; we read from the unpacked room data
    ld      de,mapRoomBlockBuffer

    ; setup loop counts
    ld      bc,$0800; row / col

.loop_y:

    ; y loop header
    ld      a,b
    cp      0
    jr      z,.done
    dec     b

    ; y loop body
    ld      c,10

.loop_x:

    dec     c ; reduce column counter

.draw_block:

    ; draw four 8x8 tiles via the block definitions from the 16x16 block
    push    hl
    push    de

    ; drawing ------------------------------------------
    push    bc; store row / col

    ld      a,[de] ; fetch 16x16 block
    ld      c,a ; low byte index into block definitions

    ; upper left
    ld      b,mapBlockDefinitionBuffer >> 8 ; block def row 0 offset
    ld      a,[bc] ; tile value
    ld      [hli],a ;  draw + 0

    ; upper right
    ld      b,(mapBlockDefinitionBuffer >> 8) + 1 ; block def row 1 offset
    ld      a,[bc] ; tile value
    ld      [hl],a ; draw +1

    ; skip one screen buffer row
    ld      de,31
    add     hl,de

    ; lower left
    ld      b,(mapBlockDefinitionBuffer >> 8) + 2 ; block def row 2 offset
    ld      a,[bc] ; tile value
    ld      [hli],a ; draw + 32

    ; lower right
    ld      b,(mapBlockDefinitionBuffer >> 8) + 3 ; block def row 2 offset
    ld      a,[bc] ; tile value
    ld      [hl],a ; draw + 33

    ; restore 16x16 block value
    ld      a,c

    pop     bc; restore row / col

    ; check for falling blocks -------------------------
    cp      MAP_FALLABLE_BLOCK_DARK
    jr      z,.fallable_block
    cp      MAP_FALLABLE_BLOCK_LIGHT
    jr      nz,.normal_block

    ; get current index
.fallable_block:
    ld      [coreTmp],a
    ld      a,[mapFallableBlockCount]
    cp      MAP_MAX_FALLABLE_BLOCKS
    jr      z,.normal_block; maximum index reached skip

    ld      de,mapFallableBlocks
    ld      h,0
    ld      l,a
    add     hl,hl; x 2
    add     hl,hl; x 4
    add     hl,de; get offset address

    ; store tile type (dark / light) and reset active
    ld      a,[coreTmp]
    cp      MAP_FALLABLE_BLOCK_DARK
    jr      z,.dark
    ld      a,%0000_00_1_0; delay, unused, type, active flag
    jr      .set_type

.dark:
    xor     a ; delay, unused, type, active flag

.set_type:
    ld      [hli],a

    ; reset frames
    xor     a;
    ld      [hli],a

    ; store x and y coordinates
    ld      a,9
    sub     c
    ld      [hli],a; x / col
    ld      a,7
    sub     b
    ld      [hli],a; y / row

    ; next index
    ld      a,[mapFallableBlockCount]
    inc     a
    ld      [mapFallableBlockCount],a

    ; drawing ------------------------------------------
.normal_block:
    pop     de
    pop     hl

    ; goto next 16x16 block
    inc     de

    ; next x block (we skip two 8x8 tiles in the background buffer)
    inc     hl
    inc     hl

    ; x loop end
    ld      a,c
    cp      0
    jr      nz,.loop_x

    ; y loop end (skip one 16x16 screen data row)
    ld      a,44 ; 12 8x8 tiles left on this row + one full row of 32

    ; 16 bit addition a to hl
    add     a,l
    ld      l,a
    adc     a,h
    sub     l
    ld      h,a

    jr      .loop_y

.done:
    ld      a,1
    ld      [mapRoomUpdateRequired],a
    ret

