; Player Animations -----------------------------------------------------------

; Each Animation takes 32 bytes
; The first 16 are the tile indexes (which are 16x16)
; The other 16 bytes are frame lengths, each frame is 16ms long.
; FF FD and FE are special values for frame lengths which are used to control
; the animation behavior. FF means STOP, FE means loop, FD means bounce

; Idle
DB $00, $03,$01,$03,$01, $03,$01,$03,$02, $03,$03, $ff,$ff,$ff,$ff,$ff
DB $ff, $68,$0C,$C3,$0A, $08,$0A,$C0,$2f, $38,$fe, $ff,$ff,$ff,$ff,$ff

; Walking
DB $00, $00,$01,$02,$03, $00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 
DB $fd, $04,$05,$04,$06, $fe,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 

; Sleeping
DB $00, $00,$01,$02,$03, $00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 
DB $ff, $25,$2A,$25,$2A, $fe,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 

; Wall Pushing
DB $00, $00,$01,$02,$03, $00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 
DB $fd, $0B,$0D,$0B,$0D, $fe,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 

; Jumping 
DB $00, $03,$00,$ff,$ff, $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 
DB $fd, $05,$20,$ff,$ff, $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 

; Falling / Diving down
DB $00, $02,$01,$ff,$ff, $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 
DB $fd, $02,$20,$ff,$ff, $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 

; Running Full
DB $00, $00,$01,$02,$03, $00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 
DB $fd, $02,$03,$02,$03, $fe,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 

; Swimming
DB $00, $00,$01,$02,$03, $00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 
DB $fd, $06,$0B,$06,$0B, $fe,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 
    
; Dissolving 
DB $00, $00,$01,$02,$03, $04,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff   
DB $fd, $05,$04,$03,$02, $02,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff   

; Swimming to the Surface
DB $00, $03,$00,$ff,$ff, $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 
DB $fd, $05,$20,$ff,$ff, $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 

; Wall Sliding
DB $00, $00,$00,$ff,$ff, $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 
DB $fd, $20,$ff,$ff,$ff, $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 

; Start Pound
DB $00, $00,$01,$00,$01, $02,$01,$02,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff 
DB $fd, $06,$06,$06,$06, $06,$06,$06,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 

; Stop Pound
DB $00, $02,$01,$02,$01, $00,$01,$00,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff 
DB $fd, $04,$04,$04,$04, $04,$04,$04,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 

; Player Landing
DB $00, $00,$01,$02,$03, $00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 
DB $fd, $09,$05,$04,$03, $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 

; Double Jumping 
DB $00, $02,$03,$00,$ff, $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 
DB $fd, $04,$07,$20,$ff, $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 

; Running Half
DB $00, $00,$01,$02,$03, $00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 
DB $fd, $03,$04,$03,$05, $fe,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff 

