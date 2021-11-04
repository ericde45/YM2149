;---------------------------------------------------------
;
;	LZ4 block 68k depacker
;	converted to ARM 2
;	68K version written by Arnaud Carré ( @leonard_coder )
;	https://github.com/arnaud-carre/lz4-68k
;
;	LZ4 technology by Yann Collet ( https://lz4.github.io/lz4/ )
;
;---------------------------------------------------------

; Normal version
;
; input: a0.l : packed buffer 							=> R8
;		 a1.l : output buffer							=> R9
;		 d0.l : LZ4 packed block size (in bytes)		=> R0
;
; output: none
;
; R0-R4 : used
; R5 = tmp
; R13 = heap/pile

lz4_depack:
			add		R12,R8,R0		; packed buffer end
			
			mov		R0,#0
			mov		R2,#0
			mov		R3,#0
			mov		R4,#15
			b		lz4_depack_tokenLoop

lz4_depack_lenOffset:
			ldrb	R1,[R8],#1
			ldrb	R5,[R8],#1			; a tester en réel, voir le sens de la recup depuis la mémoire
			orr		R3,R3,R5 lsl #8		; R3 = .w / voir si il faut inverser
			mov		R11,R9
			subs	R11,R11,R3
			mov		R1,#0b1111
			and		R1,R1,R0
			cmp		R1,R4
			bne		lz4_depack_small

lz4_depack_readLen0:
			ldrb	R2,[R10],#1
			add		R1,R1,R2
			not		R2					; !!!!!!!
			cmp		R2,#0
			beq		lz4_depack_readLen0
			
			add		R1,R1,#4
lz4_depack_copy:
			ldrb	R5,[R11],#1
			strb	R5,[R9],#1
			subs	R1,R1,#1
			bne		lz4_depack_copy
			b		lz4_depack_tokenLoop

lz4_depack_small:
			mov		R1,R1,lsl #3		; * 8
			neg		R1					;  !!!!!!
			adr		R6,lz4_depack_copys
			add		R6,R6,R1
			mov		pc,R6


			.rept		15
				ldrb	R5,[R11],#1			; 4 octets
				strb	R5,[R9],#1			; +4 octets
			.endr
			
lz4_depack_copys:
			ldrb	R5,[R11],#1			
			strb	R5,[R9],#1			
			ldrb	R5,[R11],#1			
			strb	R5,[R9],#1			
			ldrb	R5,[R11],#1			
			strb	R5,[R9],#1			
			ldrb	R5,[R11],#1			
			strb	R5,[R9],#1			

lz4_depack_tokenLoop:
			ldrb	R0,[R8],#1
			movs	R1,R0,lsr #4
			beq		lz4_depack_lenOffset
			cmp		R1,R4
			beq		lz4_depack_readLen1

lz4_depack_litcopys:
			mov		R1,R1,lsl #3		; * 8
			neg		R1					;  !!!!!!
			adr		R6,lz4_depack_copys2
			add		R6,R6,R1
			mov		pc,R6

			.rept		15
				ldrb	R5,[R8],#1			; 4 octets
				strb	R5,[R9],#1			; +4 octets
			.endr

lz4_depack_copys2:
			cmp		R12,R8
			bne		lz4_depack_lenOffset
			mov		pc,lr					; retour
			
lz4_depack_readLen1:
			ldrb	R2,[R8],#1
			adds	R1,R1,R2
			not		R2					; !!!!!!!
			cmp		R2,#0
			beq		lz4_depack_readLen1
			
lz4_depack_litcopy:
			ldrb	R5,[R8],#1
			strb	R5,[R9],#1
			subs	R1,R1,#1
			bne		lz4_depack_litcopy
			
			; end test is always done just after literals
			cmp		R12,R8
			bne		lz4_depack_lenOffset

lz4_depack_over:
			mov		pc,lr				; retour
			
			
			
			
			
