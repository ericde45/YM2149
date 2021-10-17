; player YM

; 4 voies : 3 voies PSG + 1 voie sample 4 bits

; - parfois il n'y a pas d'enveloppe, sur quels criteres ?
; - preconvertir le lin2log, puisque les volumes sont fixes
; - calcul tables digidrums
; - analyse lors du replay valeurs digidrums
; - mix digidrums dans enveloppe
; - gestion mémoire : mettre le next à 0
; OK - gérer YM6 / OK
; OK - gérer YM3 / OK ,YM4 / NON,YM5 / OK
; OK - intégrer le dépckaer LHa - lh5
; OK - allouer la RAM des buffers
; OK - mettre en place la conversion lineaire => log
; OK - inits
; OK - faire un double buffer pour sample
; OK - switcher les buffers
; OK - 2 voies

; routines à écrire :

; les données YM sont interlacées : toutes les datas pour reg0, toutes les datas pour reg1 ... jusqu'à toutes les datas pour reg13
; executé à chaque VBL : PSG_writeReg pour les 14 registres : de 0 à 13.
; executé pour chaque sample : PSG_calc(&ym2149);				// renvoie un int16_t signé !!



.equ		taille_totale_BSS,	256+(16*4)+(nb_octets_par_vbl*16)+16384+nb_octets_par_vbl+(4*16)+(16*86*32)+nb_octets_par_vbl+nb_octets_par_vbl+nb_octets_par_vbl+nb_octets_par_vbl
; 

.equ		DEBUG,				0								; 1=debug, pas de RM, Risc OS ON



.equ		valeur_remplissage_buffer1_default, 0
.equ		valeur_remplissage_buffer2_default, 0

.equ		frequence_replay,	20833							; 20833 / 31250 / 62500
.equ		nombre_de_voies,	1


.if frequence_replay = 20833	
	.equ		nb_octets_par_vbl,	416								; 416 : 416x50.0801282 = 20 833,333
	.equ		nb_octets_par_vbl_fois_nb_canaux,	nb_octets_par_vbl*nombre_de_voies
	.equ		ms_freq_Archi,		48								; 48 : 1 000 000 / 48 = 20 833,333
	.equ		ms_freq_Archi_div_4_pour_registre_direct,		ms_freq_Archi/4
.endif

.if frequence_replay = 31250	
	.equ		nb_octets_par_vbl,	624								; 624x50.0801282 = 31 249,9999968
	.equ		nb_octets_par_vbl_fois_nb_canaux,	nb_octets_par_vbl*nombre_de_voies
	.equ		ms_freq_Archi,		32								;  1000000/32=31250
	.equ		ms_freq_Archi_div_4_pour_registre_direct,		ms_freq_Archi/4
.endif

.if frequence_replay = 62500
	.equ		nb_octets_par_vbl,	1248							; 1248x50.0801282 = 62 499,999999936
	.equ		nb_octets_par_vbl_fois_nb_canaux,	nb_octets_par_vbl*nombre_de_voies
	.equ		ms_freq_Archi,		16								;  1000000/16=62500
	.equ		ms_freq_Archi_div_4_pour_registre_direct,		ms_freq_Archi/4
.endif

.equ		nb_octets_par_vbl_fois_16,		nb_octets_par_vbl*16	


.equ YM2149_frequence, 2000000							; 2 000 000 = Atari ST , 1 000 000 Hz = Amstrad CPC, 1 773 400 Hz = ZX spectrum 

.include "swis.h.asm"


	.org 0x8000
	

main:

	bl		allocation_memoire_buffers

	ldr		R0,LZH_pointeur_YM6packed_top
	bl		init_fichier_YM

; init du YM2149
	bl		PSG_creer_tables_volumes
	bl		PSG_creer_Noise_de_base
	bl		PSG_etendre_enveloppes

	
	bl		create_table_lin2log

	; read memc control register
	mov		R0,#0
	mov		R1,#0
	swi		0x1A
	str		R0,memc_control_register_original
; default = 0x36E0D4C
; 11 0110 1110 0000 1101 0100 1100
; page size = 11 = 32 KB
; low rom access time = 00 = 450ns
; high rom access time = 01 = 325ns
; Dram refresh control = 01 = during video fly back
; video cursor dma = 1 = enable
; Sound DMA Control = 1 = enable
; Operating System Mode = 0 = OS Mode Off

; set sound volume
	mov		R0,#127							; maxi 127
	SWI		XSound_Volume	

; allocations buffers dans la mémoire basse + calcul des adresses réelles
	bl		create_DMA_buffers
	
	
	bl		clear_dma_buffers



;
; INIT du systeme de son de l'Archi
;

; read stereos using SWI
	bl		readstereos
	
	MOV       R0,#0							;  	Channels for 8 bit sound
	MOV       R1,#0						; Samples per channel (in bytes)
	MOV       R2,#0						; Sample period (in microseconds per channel) 
	MOV       R3,#0
	MOV       R4,#0
	SWI       XSound_Configure						;"Sound_Configure"

; résultat valuers par défaut : 01,0xD0,0x30,0x01F04040,0x01815CD4
	
	adr		R5,backup_params_sons
	stmia	R5,{r0-R4}

; bug sound configure

	MOV       R0,#1							;  	Channels for 8 bit sound
	MOV       R1,#nb_octets_par_vbl_fois_nb_canaux		; Samples per channel (in bytes)
	MOV       R2,#ms_freq_Archi				; Sample period (in microseconds per channel)  = 48  / 125 pour 8000hz
	MOV       R3,#0
	MOV       R4,#0
	SWI       XSound_Configure						;"Sound_Configure"


	MOV       R0,#nombre_de_voies			;  	Channels for 8 bit sound
	MOV       R1,#0							; Samples per channel (in bytes)
	MOV       R2,#0							; Sample period (in microseconds per channel)  = 48  / 125 pour 8000hz
	MOV       R3,#0
	MOV       R4,#0
	SWI       XSound_Configure						;"Sound_Configure"

	MOV       R0,#nombre_de_voies				;  	Channels for 8 bit sound
	MOV       R1,#nb_octets_par_vbl_fois_nb_canaux		; Samples per channel (in bytes)
	MOV       R2,#ms_freq_Archi				; Sample period (in microseconds per channel)  = 48  / 125 pour 8000hz
	MOV       R3,#0
	MOV       R4,#0
	SWI       XSound_Configure						;"Sound_Configure"


	; bl		set_my_stereos_2voies


	MOV       R0,#0							;  	Channels for 8 bit sound
	MOV       R1,#0						; Samples per channel (in bytes)
	MOV       R2,#0						; Sample period (in microseconds per channel) 
	MOV       R3,#0
	MOV       R4,#0
	SWI       XSound_Configure						;"Sound_Configure"
	MUL       R0,R1,R0

	;bl		set_my_stereos_2voies

; reset de la frequence
	SWI		22
	MOVNV R0,R0            

; change bien la frequence
;sound frequency register ? 0xC0 / VIDC
	;mov		R0,#12-1
	.if		nombre_de_voies=4
		mov		R0,#ms_freq_Archi_div_4_pour_registre_direct-1
	.endif

	.if		nombre_de_voies=8
		mov		R0,#ms_freq_Archi_div_8_pour_registre_direct-1
	.endif



	mov		r1,#0x3400000               
; sound frequency VIDC
	mov		R2,#0xC0000100
	orr   	r0,r0,R2
	str   	r0,[r1]  

	teqp  r15,#0                     
	mov   r0,r0 
; reset de la frequence

	SWI		22
	MOVNV R0,R0      



; write sptr pour reset DMA
	mov		R12,#0x36C0000
	str		R12,[R12]

	teqp  r15,#0                     
	mov   r0,r0

; met le dma en place
	bl		set_dma_dma1
	bl		swap_pointeurs_dma_son	

; write memc control register, start sound

	ldr		R0,memc_control_register_original	
	orr		R0,R0,#0b100000000000
	str		R0,[R0]


	teqp  r15,#0                     
	mov   r0,r0 





;------------------------------------------------ boucle centrale

boucle:

	mov		R0,#5750
boucle_attente:
	mov		R0,R0
	subs	R0,R0,#1
	bgt		boucle_attente


	SWI		22
	MOVNV R0,R0            

	mov   r0,#0x3400000               
	mov   r1,#100
; border	
	orr   r1,r1,#0x40000000              
	str   r1,[r0]                     

	teqp  r15,#0                     
	mov   r0,r0	

; on fait tout ici

; routines en VBL

	ldr		R0,PSG_pointeur_vers_player_VBL
	adr		R14,retour_dans_boucle
	mov		pc,R0																	; lit le fichier YM, remplit les registres
	;bl		PSG_read_YMdata_to_registers_YM2									; lit le fichier YM, remplit les registres
	
	
retour_dans_boucle:
	bl		PSG_interepretation_registres
	bl		PSG_fabrication_Noise_pour_cette_VBL								; fabrique un noise avec la bonne frequence pour cette VBL
	
	
	bl		PSG_mixage_Noise_et_Tone_voie_A										; mixe onde carrée à la bonne fréquence et noise fabriqué à la bonne fréquence
	bl		PSG_mixage_Noise_et_Tone_voie_B
	bl		PSG_mixage_Noise_et_Tone_voie_C

	bl		PSG_preparation_enveloppe_pour_la_VBL								; créer une enveloppe à la bonne fréquence en fonction de la forme choisie
	
	bl		PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_A
	bl		PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_B
	bl		PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_C
	

boucle_test_digidrum_fin:
	bl		PSG_mixage_final
	

	
; on swap après
	SWI		22
	MOVNV R0,R0
	bl		set_dma_dma1
	teqp  r15,#0                     
	mov   r0,r0	
	bl		swap_pointeurs_dma_son

	SWI		22
	MOVNV R0,R0            

	mov   r0,#0x3400000               
	mov   r1,#000  
; border	
	orr   r1,r1,#0x40000000               
	str   r1,[r0]                     

	teqp  r15,#0                     
	mov   r0,r0	


	
	
; par le systeme ------------
; vsync par risc os
	mov		R0,#0x13
	swi		0x6

	;Exit if SPACE is pressed
	MOV r0, #OSByte_ReadKey
	MOV r1, #IKey_Space
	MOV r2, #0xff
	SWI OS_Byte

	CMP r1, #0xff
	CMPEQ r2, #0xff
	BEQ exit

	b	boucle



;------------------------------------------------ boucle centrale



exit:
	nop
	nop

;-----------------------
;sortie
;-----------------------


	
; clear sound system ??

	

; bug le DMA
	;mov		R0,#01								; Disable sound output 
	;SWI		XSound_Enable								; Sound_Enable

; disable hardware
	SWI		22
	MOVNV R0,R0
; write memc control register, start sound
	ldr		R0,memc_control_register_original
	ldr		R1,mask_sound_off_memc_control_register	; #0b011111111111
	and		R0,R0,R1
	str		R0,[R0]
	teqp  r15,#0                     
	mov   r0,r0 


	mov		R0,#1
	mov		R1,#0
	mov		R2,#0
	mov		R3,#0
	mov		R4,#0
	SWI       XSound_Configure


	adr		R5,backup_params_sons
	ldmia	R5,{r0-R4}
	mov		R0,#1

	SWI       XSound_Configure						;"Sound_Configure"

	bl		restore_stereos
	
	MOV r0,#22	;Set MODE
	SWI OS_WriteC
	MOV r0,#12
	SWI OS_WriteC

	mov		R0,#0
	mov		R1,#0
	mov		R2,#0
	mov		R3,#0
	mov		R4,#0
	SWI       XSound_Configure


	ldr		R1,pointeur_adresse_dma1_logical
	ldr		R1,[R1]
	ldr		R2,pointeur_adresse_dma2_logical
	ldr		R2,[R2]
	
exit_final:	
; liberer la ram
	ldr		R0,ancienne_taille_alloc_memoire_current_slot 	; New size of current slot
	mov		R1,#-1											;  	New size of next slot
	SWI		0x400EC											; Wimp_SlotSize 


; sortie
	MOV R0,#0
	SWI OS_Exit	

ancienne_taille_alloc_memoire_current_slot:		.long		0
valeur_taille_memoire:	.long		taille_totale_BSS

backup_params_sons:	
	.long		0
	.long		0
	.long		0
	.long		0
	.long		0
	.long		0

memc_control_register_original:			.long	0
LZH_pointeur_YM6packed_top:			.long		YM6packed
mask_sound_off_memc_control_register:		.long		0b011111111111
	

; --------------------------------------------------------
;
; subroutines standards
;
; --------------------------------------------------------

	

create_table_lin2log:
	ldr		R11,pointeur_table_lin2logtab

 	MOV     R1,#255
setlinlogtab:

	MOV     R0,R1,LSL#24		; R0=R1<<24 : en entrée du 8 bits donc shifté en haut, sur du 32 bits
	SWI     XSound_SoundLog		; This SWI is used to convert a signed linear sample to the 8 bit logarithmic format that’s used by the 8 bit sound system. The returned value will be scaled by the current volume (as set by Sound_Volume).
	STRB    R0,[R11,R1]			; 8 bit mu-law logarithmic sample 
	SUBS    R1,R1,#1
	BGE     setlinlogtab
	mov		pc,lr

clear_dma_buffers:
; on met à zéro les buffers DMA en superviseur

	;SWI		22
	;MOVNV R0,R0  

	ldr		R1,pointeur_adresse_dma1_logical
	ldr		R1,[R1]
	mov		R2,#nb_octets_par_vbl*2					; buffer 1 
	mov		R0,#valeur_remplissage_buffer1_default
boucle_cls_buffer_dma1:
	strb	R0,[R1],#1
	subs	R2,R2,#1
	bgt		boucle_cls_buffer_dma1

	ldr		R1,pointeur_adresse_dma2_logical
	ldr		R1,[R1]
	mov		R2,#nb_octets_par_vbl*2					; buffer 2
	mov		R0,#valeur_remplissage_buffer2_default
boucle_cls_buffer_dma2:
	strb	R0,[R1],#1
	subs	R2,R2,#1
	bgt		boucle_cls_buffer_dma2


	;teqp  r15,#0                     
	;mov   r0,r0 
	mov		pc,lr

; --------------------------------------------------------
create_DMA_buffers:
 ; Set screen size for number of buffers
	MOV 	r0, #DynArea_Screen
	SWI 	OS_ReadDynamicArea
	; r1=taille actuelle de la memoire ecran
	str		R1,taille_actuelle_memoire_ecran
	
	
	MOV r0, #DynArea_Screen
; 416 * ( 32+258+32+258+32)
	;MOV		r1, #4096				; 4Ko octets de plus pour le dma audio
	mov		R1,#16384					; assez de place pour nos buffers
	.if		DEBUG=1
	add		R1,R1,#65536
	add		R1,R1,#65536
	.endif
	
	SWI		OS_ChangeDynamicArea
	
; taille dynamic area screen = 320*256*2

	MOV		r0, #DynArea_Screen
	SWI		OS_ReadDynamicArea
	
	; r0 = pointeur debut memoire ecrans
	ldr		R10,taille_actuelle_memoire_ecran
	add		R0,R0,R10		; au bout de la mémoire video, le buffer dma
	str		R0,fin_de_la_memoire_video
	
	;add		R0,R0,#4096
	.if		DEBUG=1
	add		R0,R0,#65536
	add		R0,R0,#65536
	.endif
	
	ldr		R2,pointeur_adresse_dma1_logical
	str		R0,[R2]

	add		R1,R0,#8192

	ldr		R2,pointeur_adresse_dma2_logical
	str		R1,[R2]

		ldr		R6,pointeur_adresse_dma1_logical
		ldr		R6,[R6]
		ldr		R5,pointeur_adresse_dma2_logical
		ldr		R5,[R5]
	
		SWI       OS_ReadMemMapInfo 		;  read the page size used by the memory controller and the number of pages in use
		STR       R0,pagesize
		STR       R1,numpages

		SUB       R4,R0,#1			; R4 = pagesize - 1
		BIC       R7,R5,R4          ; page for dmabuffer2 : 
		BIC       R8,R6,R4          ; page for dmabuffer1 : and R6 & not(R4)

		SUB       R5,R5,R7          ;offset into page dma2
		SUB       R6,R6,R8          ;offset into page dma1

		ADR       R0,pagefindblk
		MOV       R1,#0
		STR       R1,[R0,#0]
		STR       R1,[R0,#8]
		MVN       R1,#0
		STR       R1,[R0,#12]
		STR       R7,[R0,#4]
		SWI       OS_FindMemMapEntries 		;not RISC OS 2 or earlier
		LDR       R1,[R0,#0]
		LDR       R4,pagesize
		MUL       R1,R4,R1
		ADD       R1,R1,R5
		ldr		R10,pointeur_adresse_dma2_memc
		STR       R1,[R10] 			;got the correct phys addr of buf2 (R7)
	

		MOV       R1,#0
		STR       R1,[R0,#0]
		STR       R1,[R0,#8]
		MVN       R1,#0
		STR       R1,[R0,#12]
		STR       R8,[R0,#4]
		SWI       OS_FindMemMapEntries ;not RISC OS 2 or earlier
		LDR       R1,[R0,#0]
		LDR       R4,pagesize
		MUL       R1,R4,R1
		ADD       R1,R1,R6
		ldr		R10,pointeur_adresse_dma1_memc
		STR       R1,[R10]			 ;got the correct phys addr of buf1 (R8)

	mov		pc,lr

pagefindblk:
		.long      0 ;0
		.long      0 ;4
		.long      0 ;8
		.long      0 ;12

page_block:
	.long		0		; Physical page number 
	.long		0		; Logical address 
	.long		0		; Physical address 



pagesize:		.long	0
numpages:		.long	0

; --------------------------------------------------------
mes_stereos_2voies:
			.byte		-79,79,-79,79,-79,79,-79,79
			.p2align	3
stockage_stereos:			.long		0,0

; steros pour 2 voies
set_my_stereos_2voies:
	MOV     R0,#1
	adr		R2,mes_stereos_2voies

set_mes_stloop_2voies:
	LDRB	R1,[R2,R0]
	MOV     R1,R1,LSL#24
	MOV     R1,R1,ASR#24
	SWI     XSound_Stereo
	ADD     R0,R0,#1
	
	CMP     R0,#8
	BLE     set_mes_stloop_2voies
	mov		pc,lr	

; --------------------------------------------------------
readstereos:
	MOV     R0,#1
	adr		R2,stockage_stereos
	
readstloop:


	MVN		R1,#127					; -128
	SWI		XSound_Stereo
	
	STRNEB  R1,[R2,R0]
	ADD     R0,R0,#1
	
	CMP     R0,#8
	BLE     readstloop
	
	mov		pc,lr

; --------------------------------------------------------
restore_stereos:
	adr		R2,stockage_stereos
	MOV     R0,#1

setstloop:
	LDRB	R1,[R2,R0]
	MOV     R1,R1,LSL#24
	MOV     R1,R1,ASR#24
	SWI     XSound_Stereo
	ADD     R0,R0,#1
	
	CMP     R0,#8
	BLE     setstloop
	mov		pc,lr	

; --------------------------------------------------------
set_dma_dma1:

	ldr		  R3,adresse_dma1_memc
	mov       R4,#nb_octets_par_vbl_fois_nb_canaux
	ADD       R4,R4,R3         ;SendN
	SUB       R4,R4,#16         ; fixit ;-)


	MOV       R3,R3,LSR#2       ;(Sstart/16) << 2
	MOV       R4,R4,LSR#2       ;(SendN/16) << 2
	MOV       R0,#0x3600000     ;memc base
	ADD       R1,R0,#0x0080000     ;Sstart
	ADD       R2,R0,#0x00A0000     ;SendN
	ORR       R1,R1,R3           ;Sstart
	ORR       R2,R2,R4           ;SendN
	STR       R2,[R2]
	STR       R1,[R1]
	mov		pc,lr

; --------------------------------------------------------	
swap_pointeurs_dma_son:

	ldr		R8,adresse_dma1_memc
	ldr		R9,adresse_dma2_memc
	str		R8,adresse_dma2_memc
	str		R9,adresse_dma1_memc
	
	ldr		R8,adresse_dma1_logical
	ldr		R9,adresse_dma2_logical
	str		R8,adresse_dma2_logical
	str		R9,adresse_dma1_logical

	mov		pc,lr	



;
; --------------------------------------------------------
;
; variables
;
; --------------------------------------------------------
pointeur_table_lin2logtab:		.long		-1
	
pointeur_adresse_dma1_logical:		.long		adresse_dma1_logical
pointeur_adresse_dma1_memc:			.long		adresse_dma1_memc
pointeur_adresse_dma2_logical:		.long		adresse_dma2_logical
pointeur_adresse_dma2_memc:			.long		adresse_dma2_memc

adresse_dma1_logical:				.long		0
adresse_dma1_memc:					.long		0

adresse_dma2_logical:				.long		0
adresse_dma2_memc:					.long		0

fin_de_la_memoire_video:	.long		0
taille_actuelle_memoire_ecran:			.long		0



; --------------------------------------------------------
;
; routines PSG
;
; --------------------------------------------------------
init_YM_pointeur_debut_fichier_packe:		.long		0
init_YM_pointeur_debut_fichier_depacke:		.long		0
init_YM_saveR14:			.long		0
pointeur_FIN_YM6packed:		.long		FIN_YM6packed
PSG_compteur_frames_restantes:		.long		0
PSG_compteur_frames:				.long		0
PSG_taille_fichier_YM:		.long		0
PSG_freq_Atari_ST:			.long		0x1E8480			; 2 000 000 hz
PSG_freq_Amstrad_CPC:		.long		0x0F4240			; 1 000 000 hz
PSG_mask_FFFE:				.long		0xFFFFFFFE
;PSG_pointeur_sample1:		.long		sample1

init_fichier_YM:
; en entrée R0=pointeur vers le fichier de musique
; OK - checker si compressé ?
; OK - si compressé : allocation mémoire + remplissage pointeur vers le YM + dépacking
; - checker la version
; - remplir 1 pointeur vers init YM, et 1 pointeur vers replay YM

	str		R0,init_YM_pointeur_debut_fichier_packe

; verif que -lh5- dans l'entete

	add		R1,R0,#2				; saute  	Size of header  + Header checksum 

; -lh5-  	8k sliding dictionary + static Huffman
	ldrb	R2,[R1],#1
	cmp		R2,#0x2D						; -
	beq		init_fichier_YM_LZH_ok1
	b		init_fichier_YM_pas_packe
init_fichier_YM_LZH_ok1:
	ldrb	R2,[R1],#1
	cmp		R2,#0x6C						; l
	beq		init_fichier_YM_LZH_ok2
	b		init_fichier_YM_pas_packe
init_fichier_YM_LZH_ok2:
	ldrb	R2,[R1],#1
	cmp		R2,#0x68						; h
	beq		init_fichier_YM_LZH_ok3
	b		init_fichier_YM_pas_packe
init_fichier_YM_LZH_ok3:
	ldrb	R2,[R1],#1
	cmp		R2,#0x35						; 5
	beq		init_fichier_YM_LZH_ok4
	b		init_fichier_YM_pas_packe
init_fichier_YM_LZH_ok4:
	ldrb	R2,[R1],#1
	cmp		R2,#0x2D						; -
	beq		init_fichier_YM_LZH_ok5
	b		init_fichier_YM_pas_packe
init_fichier_YM_LZH_ok5:

; c'est un fichier packé en LH5/LZH

	SWI		0x01
	.byte	"LZH packed file.",10,13,0
	.p2align 2

	ldr		R0,init_YM_pointeur_debut_fichier_packe
	str		R14,init_YM_saveR14
	bl		LZH_depack
	ldr		R14,init_YM_saveR14

	cmp		R0,#-1
	beq		exit_final


	b		init_fichier_YM_est_packe

init_fichier_YM_pas_packe:
	ldr		R3,pointeur_FIN_YM6packed
	ldr		R4,init_YM_pointeur_debut_fichier_packe
	subs	R1,R3,R4					; taille du fichier pas packé d'origine
		

init_fichier_YM_est_packe:
	str		R0,init_YM_pointeur_debut_fichier_depacke
	str		R1,PSG_taille_fichier_YM

; ici le fichier est dépacké, il est dispo à l'adresse init_YM_pointeur_debut_fichier_depacke

; on doit determiner le type du fichier : YM2, YM3/3b, YM6

	ldrb	R1,[R0,#2]			; numéro de version
	ldrb	R2,[R0,#3]			; "!" ou "b"

	cmp		R1,#0x36						; "6"
	bne		init_fichier_YM_LZH_pas_YM6
	
; ----------------------------------------- YM6 ---------------------------------------------------------
	SWI		0x01
	.byte	"--YM6--",10,13,0
	.p2align 2


init_fichier_YM_recolle_YM6:
	adds	R0,R0,#4						; saute "YM6!"
	adds	R0,R0,#8						; saute "LeOnArD!"
	
;  	Nb of frame in the file
	ldrb	R1,[R0],#1
	mov		R1,R1,lsl #24
	ldrb	R2,[R0],#1
	orr		R1,R1,R2,lsl #16
	ldrb	R2,[R0],#1
	orr		R1,R1,R2,lsl #8
	ldrb	R2,[R0],#1
	orr		R1,R1,R2						; R1 = Nb of frame in the file
	str		R1,PSG_compteur_frames
	str		R1,PSG_compteur_frames_restantes
	str		R1,PSG_ecart_entre_les_registres_ymdata
	
;  	Song attributes 
;        b0:     Set if Interleaved data block.
;        b1:     Set if the digi-drum samples are signed data.
;        b2:     Set if the digidrum is already in ST 4 bits format.
;        b3-b31: Not used yet, MUST BE 0.
; 
; dans STSoundLibrary
;	A_STREAMINTERLEAVED = 1,	= b0 : Set if Interleaved data block.
;	A_DRUMSIGNED = 2,			= b1 : Set if the digi-drum samples are signed data.
;	A_DRUM4BITS = 4,			= b2 : Set if the digidrum is already in ST 4 bits format.
;	A_TIMECONTROL = 8,			= b3 : set if seekable / time control possible
;	A_LOOPMODE = 16,			= b4 : inutilisé ?
	ldrb	R1,[R0],#1
	mov		R1,R1,lsl #24
	ldrb	R2,[R0],#1
	orr		R1,R1,R2,lsl #16
	ldrb	R2,[R0],#1
	orr		R1,R1,R2,lsl #8
	ldrb	R2,[R0],#1
	orr		R1,R1,R2						; R1 = Song attributes
	
	and		R2,R1,#0x1						; test interleaved
	str		R2,PSG_flag_interleaved			; 1 = interleaved / tous les reg0 de toutes les vbls, puis tous les reg1 etc
	
	cmp		R2,#1
	bne		init_fichier_YM_pas_interleaved
	SWI		0x01
	.byte	"Interleaved format",10,13,0
	.p2align 2
	b		init_fichier_YM_test_drumsigned
	
init_fichier_YM_pas_interleaved:
	.byte	"Linear format",10,13,0
	.p2align 2
	mov		R1,#1
	str		R1,PSG_ecart_entre_les_registres_ymdata
	
	
	
init_fichier_YM_test_drumsigned:
	and		R2,R1,#0x2						; test DRUMSIGNED
	str		R2,PSG_flag_DRUMSIGNED			; 1 = the digi-drum samples are signed data.
	
	cmp		R2,#1
	bne		init_fichier_YM_pas_DRUMSIGNED
	SWI		0x01
	.byte	"Digidrums are signed",10,13,0
	.p2align 2
	b		init_fichier_YM_test_drum4bits
	
init_fichier_YM_pas_DRUMSIGNED:
	SWI		0x01
	.byte	"Digidrums are NOT signed",10,13,0
	.p2align 2

init_fichier_YM_test_drum4bits:
	and		R2,R1,#0x4						; test DRUM4BITS
	str		R2,PSG_flag_DRUM4BITS			; 1 = the digidrum is already in ST 4 bits format.
	cmp		R2,#1
	bne		init_fichier_YM_pas_DRUM4BITS
	SWI		0x01
	.byte	"Digidrums are ST 4 bits",10,13,0
	.p2align 2
	b		init_fichier_YM_fin_test_attribute
	
init_fichier_YM_pas_DRUM4BITS:
	SWI		0x01
	.byte	"Digidrums are 8 bits.",10,13,0
	.p2align 2	
	
init_fichier_YM_fin_test_attribute:
	ldrb	R1,[R0],#1
	mov		R1,R1,lsl #8
	ldrb	R2,[R0],#1
	add		R1,R1,R2						; R1 =  	Nb of digidrum samples in file (can be 0)
	mov		R2,#0
	str		R1,PSG_nb_digidrums
	cmp		R1,#0
	beq		init_fichier_YM_pas_de_DG_samples
	SWI		0x01
	.byte	"There are Digidrums.",10,13,0
	.p2align 2		


	mov		R2,#1			; flag digidrums
	
init_fichier_YM_pas_de_DG_samples:
	str		R2,PSG_flag_digidrums

	
; YM master clock implementation in Hz .(ex:2000000 for ATARI-ST version, 1773400 for ZX-SPECTRUM)
	ldrb	R1,[R0],#1
	mov		R1,R1,lsl #24
	ldrb	R2,[R0],#1
	orr		R1,R1,R2,lsl #16
	ldrb	R2,[R0],#1
	orr		R1,R1,R2,lsl #8
	ldrb	R2,[R0],#1
	orr		R1,R1,R2						; R1 = YM master clock implementation in Hz
	str		R1,PSG_YM_clock

	ldr		R2,PSG_freq_Atari_ST
	cmp		R1,R2
	bne		init_fichier_YM_pas_ST
	SWI		0x01
	.byte	"YM Freq : ST",10,13,0
	.p2align 2
	b		init_fichier_YM_frame_in_hz	

init_fichier_YM_pas_ST:
	ldr		R2,PSG_freq_Amstrad_CPC
	cmp		R1,R2
	bne		init_fichier_YM_pas_CPC
	SWI		0x01
	.byte	"YM Freq : CPC",10,13,0
	.p2align 2	
	b		init_fichier_YM_frame_in_hz

init_fichier_YM_pas_CPC:
	SWI		0x01
	.byte	"YM Freq : unknown",10,13,0
	.p2align 2

init_fichier_YM_frame_in_hz:
; Original player frame in Hz (traditionnaly 50)
	ldrb	R1,[R0],#1
	mov		R1,R1,lsl #8
	ldrb	R2,[R0],#1
	add		R1,R1,R2						; R1 =  Player frequency in Hz
	str		R1,PSG_replay_frequency_HZ
	
	cmp		R1,#50
	bne		init_fichier_YM_frame_in_hz_pas50
	SWI		0x01
	.byte	"replay : 50 hz.",10,13,0
	.p2align 2
	b		init_fichier_YM_loop_frame_ym6
	
init_fichier_YM_frame_in_hz_pas50:
	SWI		0x01
	.byte	"replay NOT 50 hz.",10,13,0
	.p2align 2	
	
	
init_fichier_YM_loop_frame_ym6:
;  	Loop frame (traditionnaly 0 to loop at the beginning)
	ldrb	R1,[R0],#1
	mov		R1,R1,lsl #24
	ldrb	R2,[R0],#1
	orr		R1,R1,R2,lsl #16
	ldrb	R2,[R0],#1
	orr		R1,R1,R2,lsl #8
	ldrb	R2,[R0],#1
	orr		R1,R1,R2						; R1 =  	Loop frame (traditionnaly 0 to loop at the beginning)
	str		R1,PSG_loop_frame_YM6

;  	Size, in bytes, of futur additionnal data. You have to skip these bytes. (always 0 for the moment)
	add		R0,R0,#2


; samples
;  	Sample size 
;   Sample data (8 bits sample)
;
; il faut convertir les samples 4 bits en volumes d'enveloppe avec la table : PSG_tables_de_16_volumes

	ldr		R1,PSG_nb_digidrums
	cmp		R1,#0
	beq		init_fichier_YM_pas_de_samples_YM6
	

; PSG_table_pointeurs_digidrums
; * calculer taille totale
; * arrondir au multiple de 2 supérieur chaque longueur
; * ajouter 1784 a chaque longueur
; * allouer de la ram a partir de pointeur_FIN_DATA_actuel
; * update pointeur_FIN_DATA_actuel
; copier chaque sample en le convertissant en volume YM

	; R1=nb digidrums
	mov		R9,R0				; R9=pointeur debut digidrums
	mov		R4,#0				; R4 = taille totale des digidrums
	mov		R5,#0				; R5 = taille totale des digidrums + espace vide bouclage
	mov		R6,R1

init_fichier_YM_boucle_add_tailles_digidrums:
	ldrb	R3,[R0],#1
	mov		R3,R3,lsl #24
	ldrb	R2,[R0],#1
	orr		R3,R3,R2,lsl #16
	ldrb	R2,[R0],#1
	orr		R3,R3,R2,lsl #8
	ldrb	R2,[R0],#1
	orr		R3,R3,R2						; R3 =  taille du digidrum
	
	add		R0,R0,R3						; on saute la partie datas du sample
	
; arrondi
	add		R3,R3,#1
	and		R3,R3,#0xFFFFFFFE				; dernier bit = 0 => arrondi au multiple de 2 supérieur

	add		R4,R4,R3						; taille réelle
	
	add		R5,R5,R3
	add		R5,R5,#1784						; taille avec boucle
	
	subs	R6,R6,#1
	bgt		init_fichier_YM_boucle_add_tailles_digidrums
; R4=taille totale des digidrums
	str		R4,PSG_taille_totale_des_digidrums
	str		R5,PSG_taille_totale_des_digidrums_plus_bouclage

; allouer PSG_taille_totale_des_digidrums_plus_bouclage octets en + de pointeur_FIN_DATA_actuel
; recuperer l'allocation ram actuelle
	mov		R0,#-1				; New size of current slot
	mov		R1,#-1				;  	New size of next slot
	SWI		Wimp_SlotSize			; Wimp_SlotSize 

	add		R0,R0,R5				; current slot size + valeur_taille_memoire = New size of current slot
	mov		R1,#-1
	SWI 	Wimp_SlotSize			; Wimp_SlotSize 

; clean la mémoire allouée
	ldr		R4,pointeur_FIN_DATA_actuel
	str		R4,PSG_adresse_debut_digidrums
	
	add		R6,R4,R5				; + PSG_taille_totale_des_digidrums_plus_bouclage

; on arrondi à multiple de 4
	add		R6,R6,#3
	and		R6,R6,#0xFFFFFFFC
	str		R6,pointeur_FIN_DATA_actuel
	
	mov		R2,R5
	mov		R6,#0
init_fichier_YM_boucle_clean_memoire_digidrums:
	strb	R6,[R4],#1
	subs	R2,R2,#1
	bgt		init_fichier_YM_boucle_clean_memoire_digidrums

; remplir la table des pointeurs de digidrums : 
; R9=pointeur debut digidrums : PSG_table_pointeurs_digidrums
; convertir avec la table de volume !

	mov		R1,R9													; source des digidrums
	ldr		R2,PSG_adresse_debut_digidrums							; destination des digidrums
	ldr		R3,PSG_pointeur_table_pointeurs_digidrums				; table de pointeurs adresse digidrums + longueur
	adr		R4,PSG_tables_de_16_volumes_DG								; table des volumes 4 bits
	
	ldr		R8,PSG_flag_DRUM4BITS
	
	ldr		R7,PSG_nb_digidrums
init_fichier_YM_boucle_copie_1_DG:
	ldrb	R5,[R1],#1
	mov		R5,R5,lsl #24
	ldrb	R6,[R1],#1
	orr		R5,R5,R6,lsl #16
	ldrb	R6,[R1],#1
	orr		R5,R5,R6,lsl #8
	ldrb	R6,[R1],#1
	orr		R5,R5,R6						; R5 =  taille du digidrum

	str		R2,[R3],#4						; pointeur debut digidrum destination
	str		R5,[R3],#4						; taille digidrum 
	
	
init_fichier_YM_boucle_copie_1_DG_datas:	
	ldrb	R0,[R1],#1						; lit l'octet en 4 bits ou 8 bits
	
	cmp		R8,#1							; sample 4 bits ?
	movne	R0,R0,lsr #4					; de 8 bits à 4 bits
	
	ldrb	R0,[R4,R0]						; converti en volume YM
	strb	R0,[R2],#1						; ecrit dans la nouvelle destination
	subs	R5,R5,#1
	bgt		init_fichier_YM_boucle_copie_1_DG_datas
	
; arrondi
	add		R2,R2,#1
	and		R2,R2,#0xFFFFFFFE				; dernier bit = 0 => arrondi au multiple de 2 supérieur
		
	add		R2,R2,#1784
	subs	R7,R7,#1
	bgt		init_fichier_YM_boucle_copie_1_DG

	mov		R0,R1

; force le sample 1

	
	;ldr		R4,PSG_pointeur_sample1
	;ldr		R5,PSG_pointeur_table_pointeurs_digidrums
	;str		R4,[R5]



	b		init_fichier_YM_apres_samples_YM6

init_fichier_YM_pas_de_samples_YM6:
	SWI		0x01
	.byte	"No digidrums.",10,13,0
	.p2align 2	
	
init_fichier_YM_apres_samples_YM6:


;	Song name
	SWI		OS_WriteO
	SWI		0x01
	.byte	10,13,0
	.p2align 2	
;	Author name
	SWI		OS_WriteO
	SWI		0x01
	.byte	10,13,0
	.p2align 2	

;	Song comment 
	SWI		OS_WriteO
	SWI		0x01
	.byte	10,13,0
	.p2align 2	

; YM register data bytes. (r0,r1,r2....,r15 for each frame). Order depend on the "interleaved" bit. It takes 16*nbFrame bytes. 
; R0 = pointeur des données

	str		R0,PSG_pointeur_actuel_ymdata
	str		R0,PSG_pointeur_origine_ymdata
	
	ldr		R3,PSG_pointeur_vers_player_YM6
	str		R3,PSG_pointeur_vers_player_VBL


	b		init_fichier_YM_LZH_pas_YM2
	
init_fichier_YM_LZH_pas_YM6:
	cmp		R1,#0x35						; "5"
	bne		init_fichier_YM_LZH_pas_YM5

; ----------------------------------------- YM5 ---------------------------------------------------------
	SWI		0x01
	.byte	"--YM5--",10,13,0
	.p2align 2

	
	b		init_fichier_YM_recolle_YM6

init_fichier_YM_LZH_pas_YM5:
	cmp		R1,#0x34						; "4"
	bne		init_fichier_YM_LZH_pas_YM4

init_fichier_YM_LZH_pas_YM4:
	cmp		R1,#0x33						; "3"
	bne		init_fichier_YM_LZH_pas_YM3
	
	cmp		R2,#0x62						; "b"
	bne		init_fichier_YM_LZH_pas_YM3a
; YM3b
; bouclage a la fin du fichier don 4 octets en plus
; YM3 = idem YM2
	SWI		0x01
	.byte	"--YM3b--",10,13,0
	.p2align 2
	
	add		R0,R0,#4			; +YM3b
	str		R0,PSG_pointeur_actuel_ymdata
	str		R0,PSG_pointeur_origine_ymdata
	

	
	ldr		R3,PSG_pointeur_vers_player_YM2
	str		R3,PSG_pointeur_vers_player_VBL
	
; calcul le nombre d'etapes : /14
; PSG_ecart_entre_les_registres_ymdata

	ldr		R4,PSG_taille_fichier_YM
	subs	R4,R4,#8					; taille du fichier - 4 octets d'entete YM2! - 4 octets de loop
	ldr		R3,valeur_1_div_14
	mul		R5,R3,R4					; PSG_taille_fichier_YM * ( 1/14 *65536)
	mov		R5,R5,lsr #16				; / 65536
	str		R5,PSG_compteur_frames
	str		R5,PSG_ecart_entre_les_registres_ymdata
	str		R5,PSG_compteur_frames_restantes


; calcul de loop:
	ldr		R4,PSG_taille_fichier_YM	; taille totale du fichier YM3b
	subs	R4,R4,#8					; entete deja enlevé
	ldr		R1,PSG_pointeur_actuel_ymdata
	add		R4,R4,R1
	
	ldrb	R0,[R4],#1
	ldrb	R1,[R4],#1
	orr		R0,R0,R1,lsl #8
	ldrb	R1,[R4],#1
	orr		R0,R0,R1,lsl #16
	ldrb	R1,[R4],#1
	orr		R0,R0,R1,lsl #24
	
	ldr		R1,PSG_pointeur_actuel_ymdata
	add		R1,R1,R0				; + position repetition
	str		R1,PSG_pointeur_origine_ymdata
	
	
	b		init_fichier_YM_LZH_pas_YM2
	

init_fichier_YM_LZH_pas_YM3a:
; YM3 = idem YM2
	SWI		0x01
	.byte	"--YM3--",10,13,0
	.p2align 2

	b		init_fichier_YM_LZH_YM2
	
init_fichier_YM_LZH_pas_YM3:
	cmp		R1,#0x32
	bne		init_fichier_YM_LZH_pas_YM2

	SWI		0x01
	.byte	"--YM2--",10,13,0
	.p2align 2

init_fichier_YM_LZH_YM2:
	add		R0,R0,#4			; YM2!
	str		R0,PSG_pointeur_actuel_ymdata
	str		R0,PSG_pointeur_origine_ymdata
	

	
	ldr		R3,PSG_pointeur_vers_player_YM2
	str		R3,PSG_pointeur_vers_player_VBL
	
; calcul le nombre d'etapes : /14
; PSG_ecart_entre_les_registres_ymdata

	ldr		R4,PSG_taille_fichier_YM
	subs	R4,R4,#4					; taille du fichier - 4 octets d'entete YM2!
	ldr		R3,valeur_1_div_14
	mul		R5,R3,R4					; PSG_taille_fichier_YM * ( 1/14 *65536)
	mov		R5,R5,lsr #16				; / 65536
	str		R5,PSG_compteur_frames
	str		R5,PSG_ecart_entre_les_registres_ymdata
	str		R5,PSG_compteur_frames_restantes

init_fichier_YM_LZH_pas_YM2:



	mov		pc,lr


	
PSG_pointeur_vers_player_YM2:		.long		PSG_read_YMdata_to_registers_YM2
PSG_pointeur_vers_player_YM3:		.long		0
PSG_pointeur_vers_player_YM4:		.long		0
PSG_pointeur_vers_player_YM5:		.long		PSG_read_YMdata_to_registers_YM6
PSG_pointeur_vers_player_YM6:		.long		PSG_read_YMdata_to_registers_YM6

PSG_pointeur_vers_player_VBL:		.long		0

PSG_pointeur_registres:			.long		PSG_registres

pointeur_FIN_DATA_actuel:		.long	FIN_DATA

PSG_read_YMdata_to_registers_YM6:




; lit les valeurs de YMdata - YM6
; interlacées
; 16 octets par VBL
; et les mets dans les registes de la structure PSG

	ldr		R10,PSG_pointeur_registres
	ldr		R12,PSG_pointeur_actuel_ymdata
	mov		R13,R12
	ldr		R11,PSG_ecart_entre_les_registres_ymdata
	
	ldrb	R0,[R12],R11			; registre 0
	ldrb	R1,[R12],R11			; registre 1
	add		R0,R0,R1, lsl #8
	ldrb	R1,[R12],R11			; registre 2
	add		R0,R0,R1, lsl #16
	ldrb	R1,[R12],R11			; registre 3
	add		R0,R0,R1, lsl #24
; R0 = R3R2R1R0
	ldrb	R2,[R12],R11			; registre 4
	ldrb	R1,[R12],R11			; registre 5
	add		R2,R2,R1, lsl #8
	ldrb	R1,[R12],R11			; registre 6
	add		R2,R2,R1, lsl #16
	ldrb	R1,[R12],R11			; registre 7
	add		R2,R2,R1, lsl #24
; R2 = R7R6R5R4
	ldrb	R3,[R12],R11			; registre 8
	ldrb	R1,[R12],R11			; registre 9
	add		R3,R3,R1, lsl #8
	ldrb	R1,[R12],R11			; registre 10
	add		R3,R3,R1, lsl #16
	ldrb	R1,[R12],R11			; registre 11
	add		R3,R3,R1, lsl #24
; R3 = R7R6R5R4
	ldrb	R4,[R12],R11			; registre 12
	ldrb	R5,[R12],R11			; registre 13
	add		R4,R4,R5, lsl #8
	ldrb	R5,[R12],R11			; registre 14
	add		R4,R4,R5, lsl #16
	ldrb	R5,[R12]			; registre 15
	add		R4,R4,R5, lsl #24
; R4 = R7R6R5R4

	stmia	R10,{R0,R2-R4}



; interleaved
	ldr		R12,PSG_compteur_frames_restantes
	
	ldr		R2,PSG_flag_interleaved
	cmp		R2,#1					; interleaved ?
	beq		PSG_read_YMdata_to_registers_YM6_interleaved
; pas interleaved : on avance de 16
	add		R13,R13,#16
	b		PSG_read_YMdata_to_registers_YM6_interleaved_continue
	

PSG_read_YMdata_to_registers_YM6_interleaved:
	add		R13,R13,#1				; frame suivante
	
	
PSG_read_YMdata_to_registers_YM6_interleaved_continue:
		
	subs	R12,R12,#1
	bgt		pas_la_fin_de_ymdata_YM6
; bouclage :

	ldr		R12,PSG_compteur_frames
	ldr		R13,PSG_pointeur_origine_ymdata
	
	
pas_la_fin_de_ymdata_YM6:
	str		R12,PSG_compteur_frames_restantes
	str		R13,PSG_pointeur_actuel_ymdata

	mov		pc,lr



PSG_read_YMdata_to_registers_YM2:
; lit les valeurs de YMdata
; interlacées
; 14 octets par VBL
; et les mets dans les registes de la structure PSG

	ldr		R10,PSG_pointeur_registres
	ldr		R12,PSG_pointeur_actuel_ymdata
	mov		R13,R12
	ldr		R11,PSG_ecart_entre_les_registres_ymdata
	
	ldrb	R0,[R12],R11			; registre 0
	ldrb	R1,[R12],R11			; registre 1
	add		R0,R0,R1, lsl #8
	ldrb	R1,[R12],R11			; registre 2
	add		R0,R0,R1, lsl #16
	ldrb	R1,[R12],R11			; registre 3
	add		R0,R0,R1, lsl #24
; R0 = R3R2R1R0
	ldrb	R2,[R12],R11			; registre 4
	ldrb	R1,[R12],R11			; registre 5
	add		R2,R2,R1, lsl #8
	ldrb	R1,[R12],R11			; registre 6
	add		R2,R2,R1, lsl #16
	ldrb	R1,[R12],R11			; registre 7
	add		R2,R2,R1, lsl #24
; R2 = R7R6R5R4
	ldrb	R3,[R12],R11			; registre 8
	ldrb	R1,[R12],R11			; registre 9
	add		R3,R3,R1, lsl #8
	ldrb	R1,[R12],R11			; registre 10
	add		R3,R3,R1, lsl #16
	ldrb	R1,[R12],R11			; registre 11
	add		R3,R3,R1, lsl #24
; R3 = R7R6R5R4
	ldrb	R4,[R12],R11			; registre 12
	ldrb	R5,[R12],R11			; registre 13

; avec 16 registres , pas 14 : 	
	;ldrb	R1,[R12],R11			; registre 13
	;add		R4,R4,R1, lsl #8
	;ldrb	R1,[R12],R11			; registre 14
	;add		R4,R4,R1, lsl #16
	;ldrb	R1,[R12]			; registre 15
	;add		R4,R4,R1, lsl #24
; R4 = R7R6R5R4

	;stmia	R10,{R0,R2-R4}
	
	stmia	R10!,{R0,R2-R3}			; 12 registres
	strb	R4,[R10],#1				; reg 13
	strb	R5,[R10],#1				; reg 14
	
	

	add		R13,R13,#1				; frame suivante
	
	ldr		R12,PSG_compteur_frames_restantes
	subs	R12,R12,#1
	bgt		pas_la_fin_de_ymdata
; bouclage :

	ldr		R12,PSG_compteur_frames
	ldr		R13,PSG_pointeur_origine_ymdata
	
	
pas_la_fin_de_ymdata:
	str		R12,PSG_compteur_frames_restantes
	str		R13,PSG_pointeur_actuel_ymdata

	mov		pc,lr
PSG_pointeur_sur_table_liste_des_enveloppes_depliees:	.long	-1
PSG_pointeur_buffer_enveloppes_depliees:				.long	-1
PSG_pointeur_enveloppe_base:							.long	PSG_base_enveloppe	


PSG_pointeur_buffer_destination_mixage_Noise_channel_A:		.long		-1
PSG_pointeur_buffer_destination_mixage_Noise_channel_B:		.long		-1
PSG_pointeur_buffer_destination_mixage_Noise_channel_C:		.long		-1

PSG_pointeur_buffer_enveloppe_calculee_pour_cette_VBL:		.long		-1

PSG_pointeur_buffer_Noise_de_base:		.long		-1
PSG_pointeur_buffer_Noise_calcule_pour_cette_VBL:	.long		-1

PSG_pointeur_buffer_tables_volumes:		.long		-1
PSG_pointeur_liste_des_tables_de_volume:		.long		-1

PSG_tables_de_16_volumes:
	;.byte		0x00,6,11,17,23,28,34,40,45,51,57,62,68,74,79,85
	;.byte		0,0,1,3,6,9,14,19,24,31,38,45,54,64,74,85
	

PSG_tables_de_16_volumes_DG:
	.byte		0x00,0x00,0x00,0x00,0x01,0x02,0x02,0x04,0x05,0x08,0x0B,0x10,0x18,0x22,0x37,0x55

allocation_memoire_buffers:
	mov		R0,#-1				; New size of current slot
	mov		R1,#-1				;  	New size of next slot
	SWI		Wimp_SlotSize			; Wimp_SlotSize 
	str		R0,ancienne_taille_alloc_memoire_current_slot
	
	;R2 = taille mémoire dispo

	mov		R3,R2
	ldr		R2,valeur_taille_memoire
	cmp		R3,R2
	bge		ok_assez_de_ram

	SWI		0x01
	.byte	"Not enough memory.",10,13,0
	.p2align 2


	MOV R0,#0
	SWI OS_Exit


ok_assez_de_ram:
	add		R0,R0,R2				; current slot size + valeur_taille_memoire = New size of current slot
	mov		R1,#-1
	SWI 	Wimp_SlotSize			; Wimp_SlotSize 

; alloc mémoire
; clean la mémoire :
	ldr		R0,pointeur_FIN_DATA_actuel
	ldr		R2,valeur_taille_memoire
	add		R1,R0,R2				; de R0 à R1 à mettre à zéro
	mov		R2,#0
boucle_clean_memory_bss:
	strb	R2,[R0],#1
	cmp		R0,R1
	bne		boucle_clean_memory_bss


; lin2logtab
	ldr		R0,pointeur_FIN_DATA_actuel
	str		R0,pointeur_table_lin2logtab
	add		R0,R0,#256
	str		R0,PSG_pointeur_liste_des_tables_de_volume
	add		R0,R0,#64
	str		R0,PSG_pointeur_buffer_tables_volumes
	add		R0,R0,#nb_octets_par_vbl_fois_16
	str		R0,PSG_pointeur_buffer_Noise_de_base
	add		R0,R0,#16384
	str		R0,PSG_pointeur_buffer_Noise_calcule_pour_cette_VBL
	add		R0,R0,#nb_octets_par_vbl
	str		R0,PSG_pointeur_sur_table_liste_des_enveloppes_depliees
	add		R0,R0,#64
	str		R0,PSG_pointeur_buffer_enveloppes_depliees
	add		R0,R0,#44032
	str		R0,PSG_pointeur_buffer_destination_mixage_Noise_channel_A
	add		R0,R0,#nb_octets_par_vbl
	str		R0,PSG_pointeur_buffer_destination_mixage_Noise_channel_B
	add		R0,R0,#nb_octets_par_vbl
	str		R0,PSG_pointeur_buffer_destination_mixage_Noise_channel_C
	add		R0,R0,#nb_octets_par_vbl
	str		R0,PSG_pointeur_buffer_enveloppe_calculee_pour_cette_VBL
	add		R0,R0,#nb_octets_par_vbl
	str		R0,PSG_pointeur_buffer_destination_mixage_Digidrum_channel_A
	add		R0,R0,#nb_octets_par_vbl
	str		R0,PSG_pointeur_buffer_destination_mixage_Digidrum_channel_B
	add		R0,R0,#nb_octets_par_vbl
	str		R0,PSG_pointeur_buffer_destination_mixage_Digidrum_channel_C
	add		R0,R0,#nb_octets_par_vbl
	str		R0,pointeur_FIN_DATA_actuel

	mov		pc,lr

; --------------------------------------------------------	
; Créer les tables de volumes

PSG_creer_tables_volumes:
	adr		R0,PSG_tables_de_16_volumes			; le volume est sur 4 bits dans les registres 8,9 et 10 (A)
	ldr		R1,PSG_pointeur_buffer_tables_volumes
	ldr		R2,PSG_pointeur_liste_des_tables_de_volume

	mov		R7,#16
PSG_boucle_creer_table_volume1:	
	mov		R6,#nb_octets_par_vbl
	ldrb	R3,[R0],#1				; octet de volume
	str		R1,[R2],#4				; pointeur début de la table

PSG_boucle_creer_table_volume2:	
	strb	R3,[R1],#1
	subs	R6,R6,#1
	bgt		PSG_boucle_creer_table_volume2
	subs	R7,R7,#1
	bgt		PSG_boucle_creer_table_volume1
	mov		pc,lr

; --------------------------------------------------------	
; Créer le Noise de base


PSG_creer_Noise_de_base:

	ldr		R9,PSG_pointeur_buffer_Noise_de_base
	mov		R7,#16384
	mov		R0,#1			; D0.w partie basse
	mov		R10,#0			; D0.w partie haute
	mov		R2,#1			; D2.w partie basse
	mov		R12,#0			; D2.w partie haute
	mov		R1,#0			; D1.w partie basse
	mov		R11,#0			; D1.w partie haute
	
	mov		R6,#0xFFFF
	
PSG_boucle_fabrication_du_noise:
	mov		R1,R0			; move.w	d0,d1
	mov		R1,R1,lsr #3	; lsr.w		#3,d1
	eor		R1,R0,R1		; eor.w		d0,d1
	and		R1,R2,R1		; and.w		d2,d1
	add		R1,R1,R1		; add.w		d1,d1
	mov		R3,R1			; swap		d1
	mov		R1,R11
	mov		R11,R3
	eor		R0,R1,R0
	eor		R10,R11,R10		; eor.l 	d1,d0
	orr		R4,R0,R10,lsl #16	; R4 = R0.l
	movs	R4,R4,lsr #1	
	movcs	R3,#0xFF		; scs		d3
	movcc	R3,#0
	and		R0,R4,R6									; uniquement partie basse
	mov		R10,R4,lsr #16
	strb	R3,[R9],#1		; move.b	d3,(a1)+
	subs	R7,R7,#1
	bgt		PSG_boucle_fabrication_du_noise
	mov		pc,lr

; --------------------------------------------------------	
; Créer les enveloppes
; 
; prend les 2 temps de l'enveloppe de base
; étend le 2eme temps sur 85 fois * 32 octets
; remplit une table de pointeur

PSG_etendre_enveloppes:
	
	ldr		R5,PSG_pointeur_sur_table_liste_des_enveloppes_depliees
	ldr		R6,PSG_pointeur_buffer_enveloppes_depliees
	ldr		R10,PSG_pointeur_enveloppe_base
	mov		R7,#16								; 16 enveloppes à étendre

PSG_boucle_deplier_une_enveloppe:
	mov		R11,#8
PSG_boucle_deplier_une_enveloppe_debut:
	ldr		R0,[R10],#4
	str		R0,[R6],#4				; copie 32 octets
	subs	R11,R11,#1
	bgt		PSG_boucle_deplier_une_enveloppe_debut

	str		R6,[R5],#4				; stocke le pointeur + 32

	mov		R11,#85					; 85 fois la repetition
	ldmia	R10!,{R0,R1,R2,R3,R4,R8,R9,R12}
PSG_boucle_deplier_une_enveloppe_repetition:
	stmia	R6!,{R0,R1,R2,R3,R4,R8,R9,R12}			; 8 registres = 32 octets
	subs	R11,R11,#1
	bgt		PSG_boucle_deplier_une_enveloppe_repetition
	
	subs	R7,R7,#1
	bgt		PSG_boucle_deplier_une_enveloppe
	mov		pc,lr
	

; --------------------------------------------------------	
; interpretation des registres du PSG
;
; 	- increments de frequence des 3 voies
;	- increment de frequence de l'enveloppe
;	- increment de fréquence du Noise
;	- volumes A B C
;	- 

; à optimiser, lecture de N registres d'un bloc
; --------------------------------------------------------	


PSG_interepretation_registres:

	ldr		R13,PSG_pointeur_PSG
	ldr		R12,PSG_pointeur_table_de_frequences


; registre 0+1
; à lire en 1 fois...
	ldrb	R0,PSG_register0			; 8 bit fine tone adjustment - Frequency of channel A
	ldrb	R1,PSG_register1			; 4 bit rough tone adjustment - Frequency of channel A
	and		R1,R1,#0b1111				; on ne garde que 4 bits
	add		R0,R0,R1,lsl #8				; R0=total frequence channel A
	ldr		R0,[R12,R0,lsl #2]			; recupere l'increment de la fréquence
	str		R0,PSG_increment_frequence_tone_channel_A

; registre 2+3
; à lire en 1 fois...
	ldrb	R0,PSG_register2			; 8 bit fine tone adjustment - Frequency of channel B
	ldrb	R1,PSG_register3			; 4 bit rough tone adjustment - Frequency of channel B
	and		R1,R1,#0b1111				; on ne garde que 4 bits
	add		R0,R0,R1,lsl #8				; R0=total frequence channel A
	ldr		R0,[R12,R0,lsl #2]			; recupere l'increment de la fréquence
	str		R0,PSG_increment_frequence_tone_channel_B

; registre 4+5
; à lire en 1 fois...

	ldrb	R0,PSG_register4			; 8 bit fine tone adjustment - Frequency of channel C
	ldrb	R1,PSG_register5			; 4 bit rough tone adjustment - Frequency of channel C
	and		R1,R1,#0b1111				; on ne garde que 4 bits
	add		R0,R0,R1,lsl #8				; R0=total frequence channel A
	ldr		R0,[R12,R0,lsl #2]			; recupere l'increment de la fréquence
	str		R0,PSG_increment_frequence_tone_channel_C

; registre 6
; 5 bit noise frequency
	ldrb	R0,PSG_register6			; 5 bit noise frequency - Frequency of noise
	and		R0,R0,#0b11111				; on ne garde que 5 bits
	ldr		R0,[R12,R0,lsl #2]			; recupere l'increment de la fréquence
	str		R0,PSG_increment_frequence_Noise

; registre 7 
; 6 bits interessants
;	Noise	 Tone
;	C B A    C B A
	ldrb	R0,PSG_register7
	and		R0,R0,#0b111111
	str		R0,PSG_mixer_settings_all
	and		R1,R0,#0b111000
	moveq	R2,#0
	movne	R2,#1
	str		R2,PSG_flag_Noise				; 1 = on a du Noise
	str		R1,PSG_mixer_settings_Noise
	and		R1,R0,#0b000111
	str		R1,PSG_mixer_settings_Tone

; par défaut on utilise l'enveloppe comme table de volume ( le digidrum se met dans l'enveloppe)
	ldr		R3,PSG_pointeur_buffer_enveloppe_calculee_pour_cette_VBL					; pointe vers le buffer qui sera rempli avec l'enveloppe calculée
	str		R3,PSG_pointeur_table_volume_en_cours_channel_A
	str		R3,PSG_pointeur_table_volume_en_cours_channel_B
	str		R3,PSG_pointeur_table_volume_en_cours_channel_C

	ldrb	R1,PSG_register8
	ldrb	R2,PSG_register9
	ldrb	R3,PSG_register10
	orr		R0,R1,R2
	orr		R0,R0,R3			; cumule tous les bits des 3 registres
	tst		R0,#0b10000			; test bit 4
	movne	R0,#1
	moveq	R0,#0
	str		R0,PSG_flag_enveloppe


	ldr		R13,PSG_pointeur_liste_des_tables_de_volume
	
; test utilisation du volume channel A
	tst		R1,#0b10000			; test bit 4
	bne		PSG_utilise_enveloppe_channel_A
	and		R0,R1,#0b1111
	ldr		R4,[R13,R0,lsl #2]										; volume du channel * 4 pour lire pointeur vers la table de volume
	str		R4,PSG_pointeur_table_volume_en_cours_channel_A			; pointeur table de volume actuel pour noise canal A
PSG_utilise_enveloppe_channel_A:

; test utilisation du volume channel B
	tst		R2,#0b10000			; test bit 4
	bne		PSG_utilise_enveloppe_channel_B
	and		R0,R2,#0b1111
	ldr		R4,[R13,R0,lsl #2]										; volume du channel * 4 pour lire pointeur vers la table de volume
	str		R4,PSG_pointeur_table_volume_en_cours_channel_B			; pointeur table de volume actuel pour noise canal A
PSG_utilise_enveloppe_channel_B:

; test utilisation du volume channel C
	tst		R3,#0b10000			; test bit 4
	bne		PSG_utilise_enveloppe_channel_C
	and		R0,R3,#0b1111
;	cmp		R0,#7
;	ble		tritri
;	swi BKP
;tritri:
	ldr		R4,[R13,R0,lsl #2]										; volume du channel * 4 pour lire pointeur vers la table de volume
	str		R4,PSG_pointeur_table_volume_en_cours_channel_C			; pointeur table de volume actuel pour noise canal A
PSG_utilise_enveloppe_channel_C:

; registres 11 et 12 : frequence de l'enveloppe sur 16 bits
	mov		R4,#0													; resultat = increment frequence de l'enveloppe = 0 par défaut
	ldrb	R1,PSG_register11										; 8 bits du bas
	ldrb	R2,PSG_register12										; 8 bits du haut
	orr		R0,R1,R2,lsl #8											; R8 = frequence sur 16 bits
	mov		R3,#4095
	cmp		R0,R3													; frequence > 4095 ?
	bgt		PSG_frequence_enveloppe_trop_eleve
	ldr		R4,[R12,R0,lsl #2]										; recupere l'increment de la fréquence pour l'enveloppe

PSG_frequence_enveloppe_trop_eleve:
	str		R4,PSG_increment_frequence_enveloppe

; registre 13 : shape of envelope 
	ldrb	R1,PSG_register13
	tst		R1,#0b10000000											; test le bit 7, valeur negative avec le 68000
	bne		PSG_forme_enveloppe_negative

	orr		R1,R1,#0b10000000										; met le bit 7 sur le registre 13
	strb	R1,PSG_register13
	and		R1,R1,#0b00001111										; 4 derniers bits = Envelope shape control register
	ldr		R2,PSG_pointeur_sur_table_liste_des_enveloppes_depliees
	ldr		R1,[R2,R1,lsl #2]										; selectionne la bonne enveloppe
	str		R1,PSG_pointeur_vers_enveloppe_en_cours

	mov		R1,#0xFFE00000											; -32 pour sauter la 1ere partie non répétitive de l'enveloppe
	str		R1,PSG_offset_actuel_parcours_forme_enveloppe

PSG_forme_enveloppe_negative:


;  - INIT DG - 
; digidrums
;        r3 free bits are used to code a DD start.
;        r3 b5-b4 is a 2bits code wich means:
;        00:     No DD
;        01:     DD starts on voice A
;        10:     DD starts on voice B
;        11:     DD starts on voice C
	;mov		R4,#0
	;str		R4,PSG_flag_digidrum_voie_A
	;str		R4,PSG_flag_digidrum_voie_B
	;str		R4,PSG_flag_digidrum_voie_C


	ldrb	R1,PSG_register3
	mov		R1,R1,lsr #4
	and		R1,R1,#0b0011
	
	cmp		R1,#0
	beq		PSG_start_digidrum_no_digidrum

	cmp		R1,#1
	bne		PSG_start_digidrum_test_voie_B
; digidrum voie A
	str		R4,PSG_offset_en_cours_digidrum_A
	

	mov		R1,#1
	str		R1,PSG_flag_digidrum_voie_A

	ldrb	R1,PSG_register8						; 5 bits du bas de volume A = numero de sample
	and		R1,R1,#0b11111							; R0=numero de sample voie 
	str		R1,PSG_numero_digidrum_voie_A

;pointeur sample = 
;taille sample = PSG_longeur_sample_digidrum_voie_A
;venant de 	PSG_pointeur_table_pointeurs_digidrums

	ldr		R10,PSG_pointeur_table_pointeurs_digidrums
	add		R10,r10,R1,lsl #3
	ldr		R2,[R10],#4						; pointeur adresse sample
	ldr		R3,[R10],#4						; pointeur longeur sample
	str		R2,PSG_pointeur_sample_digidrum_voie_A
	mov		R3,R3,lsl #16					; partie entiere pour comparer à l'offset
	str		R3,PSG_longeur_sample_digidrum_voie_A


; TP for DD is stored in the 3 free bits of r8 (b7-b5)
; TC for DD is stored in the 8 bits of r15

	ldrb	R2,PSG_register8
	mov		R2,R2,lsr #5
	ldrb	R3,PSG_register15
	add		R3,R3,R2,lsl #8							; 11 bits pour la frequence
	ldr		R2,PSG_pointeur_table_MFP
	ldr		R4,[R2,R3,lsl #2]						; increment frequence en .L
	str		R4,PSG_increment_digidrum_voie_A
	b		PSG_start_digidrum_no_digidrum
	
PSG_start_digidrum_test_voie_B:
	cmp		R1,#2
	bne		PSG_start_digidrum_test_voie_C
; digidrum voie B
	str		R4,PSG_offset_en_cours_digidrum_B


	mov		R1,#1
	str		R1,PSG_flag_digidrum_voie_B

	ldrb	R1,PSG_register9						; 5 bits du bas de volume B = numero de sample
	and		R1,R1,#0b11111							; R0=numero de sample voie B
	str		R1,PSG_numero_digidrum_voie_B
	
	ldr		R10,PSG_pointeur_table_pointeurs_digidrums
	add		R10,r10,R1,lsl #3
	ldr		R2,[R10],#4						; pointeur adresse sample
	ldr		R3,[R10],#4						; pointeur longeur sample
	str		R2,PSG_pointeur_sample_digidrum_voie_B
	mov		R3,R3,lsl #16					; partie entiere pour comparer à l'offset
	str		R3,PSG_longeur_sample_digidrum_voie_B


; TP for DD is stored in the 3 free bits of r8 (b7-b5)
; TC for DD is stored in the 8 bits of r15

	ldrb	R2,PSG_register8
	mov		R2,R2,lsr #5
	ldrb	R3,PSG_register15
	add		R3,R3,R2,lsl #8							; 11 bits pour la frequence
	ldr		R2,PSG_pointeur_table_MFP
	ldr		R4,[R2,R3,lsl #2]						; increment frequence en .L
	str		R4,PSG_increment_digidrum_voie_B
	b		PSG_start_digidrum_no_digidrum
	

PSG_start_digidrum_test_voie_C:
	cmp		R1,#3
	bne		PSG_start_digidrum_no_digidrum
	
	
; digidrum voie C
	str		R4,PSG_offset_en_cours_digidrum_C

	mov		R1,#1
	str		R1,PSG_flag_digidrum_voie_C

	ldrb	R1,PSG_register10						; 5 bits du bas de volume C = numero de sample
	and		R1,R1,#0b11111							; R0=numero de sample voie C
	str		R1,PSG_numero_digidrum_voie_C

	ldr		R10,PSG_pointeur_table_pointeurs_digidrums
	add		R10,r10,R1,lsl #3
	ldr		R2,[R10],#4						; pointeur adresse sample
	ldr		R3,[R10],#4						; pointeur longeur sample
	str		R2,PSG_pointeur_sample_digidrum_voie_C
	mov		R3,R3,lsl #16					; partie entiere pour comparer à l'offset
	str		R3,PSG_longeur_sample_digidrum_voie_C

; TP for DD is stored in the 3 free bits of r8 (b7-b5)
; TC for DD is stored in the 8 bits of r15

	ldrb	R2,PSG_register8
	mov		R2,R2,lsr #5
	ldrb	R3,PSG_register15
	add		R3,R3,R2,lsl #8							; 11 bits pour la frequence
	

	ldr		R2,PSG_pointeur_table_MFP
	ldr		R4,[R2,R3,lsl #2]						; increment frequence en .L
	str		R4,PSG_increment_digidrum_voie_C

	

PSG_start_digidrum_no_digidrum:
; si digdrum en cours sur une voie, N&T=1
	ldr		R1,PSG_flag_digidrum_voie_A
	cmp		R1,#1
	bne		PSG_test_digidrum_each_VBL_voie_A_non
	ldrb	R1,PSG_register7						; force Noise = 1 et Tone = 1 / ni l'un ni l'autre. Noise et Tone OFF
	orr		R1,R1,#0b001001
	strb	R1,PSG_register7

PSG_test_digidrum_each_VBL_voie_A_non:
	ldr		R1,PSG_flag_digidrum_voie_B
	cmp		R1,#1
	bne		PSG_test_digidrum_each_VBL_voie_B_non
	ldrb	R1,PSG_register7						; force Noise = 1 et Tone = 1 / ni l'un ni l'autre. Noise et Tone OFF
	orr		R1,R1,#0b010010
	strb	R1,PSG_register7

PSG_test_digidrum_each_VBL_voie_B_non:

	ldr		R1,PSG_flag_digidrum_voie_C
	cmp		R1,#1
	bne		PSG_test_digidrum_each_VBL_voie_C_non
	ldrb	R1,PSG_register7						; force Noise = 1 et Tone = 1 / ni l'un ni l'autre. Noise et Tone OFF
	orr		R1,R1,#0b100100
	strb	R1,PSG_register7

PSG_test_digidrum_each_VBL_voie_C_non:

; retour
	mov		pc,lr

; --------------------------------------------------------
; Fabrication du Noise pour cette VBL
; en fonction du Noise prégénéré, et de la frequence de replay du Noise
; remplit un buffer de nb_octets_par_vbl octets
;
; 00c06544

PSG_fabrication_Noise_pour_cette_VBL:
	
	ldr		R0,PSG_flag_Noise
	cmp		R0,#1
	bne		PSG_pas_de_Noise_cette_VBL

	ldr		R0,PSG_increment_frequence_Noise
	ldr		R1,PSG_offset_precedent_Noise

	ldr		R10,PSG_pointeur_buffer_Noise_de_base
	ldr		R11,PSG_pointeur_buffer_Noise_calcule_pour_cette_VBL
	
	mov		R2,#0x3FFFFFF										; $3FFF << 12, pour boucler dans le parcours
; parcours du Noise
; 00c060de
	
	mov		R7,#nb_octets_par_vbl

PSG_boucle_calcul_Noise_pour_VBL:
	add		R1,R1,R0				; incremente l'offset suivant la frequence du Noise
	and		R1,R1,R2				; limite à $4000<<12
	ldrb	R3,[R10,R1,lsr #16]
	strb	R3,[R11],#1
	subs	R7,R7,#1
	bgt		PSG_boucle_calcul_Noise_pour_VBL
	
	
	str		R1,PSG_offset_precedent_Noise
PSG_pas_de_Noise_cette_VBL:
	mov		pc,lr


; --------------------------------------------------------
; mixage de Noise et onde carrée de base, suivant fréquence du channel
; 0c05c38
; a voir en ldmia/stmia
PSG_mixage_Noise_et_Tone_saveR14:		.long		0

PSG_mixage_Noise_et_Tone_voie_A:
	
	ldr		R11,PSG_pointeur_buffer_destination_mixage_Noise_channel_A
	ldr		R1,PSG_offset_actuel_parcours_onde_carree_channel_A
	ldr		R0,PSG_increment_frequence_tone_channel_A
	mov		R0,R0,lsl #16
	ldr		R12,PSG_pointeur_buffer_Noise_calcule_pour_cette_VBL
	
	mov		R7,#nb_octets_par_vbl

	ldrb	R4,PSG_register7				; R7 = mixer settings
	and		R5,R4,#0b000001					; Tone channel A						= NT / 0=Noise+Tone, 1=Noise, 2=Tone, 3=rien/$FF
	and		R6,R4,#0b001000					; Noise channel A
	orr		R5,R5,R6,lsr #2					; bits 0 & 1 = NT
	adr		R6,PSG_table_saut_routines_mixage_Noise_onde_carree
	ldr		R6,[R6,R5,lsl #2]				; * 4 pour lire la table, R6 = routine
	
	str		R14,PSG_mixage_Noise_et_Tone_saveR14
	adr		R14,PSG_mixage_Noise_et_Tone_voie_A_retour
	mov		pc,R6
	
PSG_mixage_Noise_et_Tone_voie_A_retour:

	str		R1,PSG_offset_actuel_parcours_onde_carree_channel_A
	ldr		pc,PSG_mixage_Noise_et_Tone_saveR14
	
PSG_mixage_Noise_et_Tone_voie_B:
	
	ldr		R11,PSG_pointeur_buffer_destination_mixage_Noise_channel_B
	ldr		R1,PSG_offset_actuel_parcours_onde_carree_channel_B
	ldr		R0,PSG_increment_frequence_tone_channel_B
	mov		R0,R0,lsl #16
	ldr		R12,PSG_pointeur_buffer_Noise_calcule_pour_cette_VBL
	
	mov		R7,#nb_octets_par_vbl

	ldrb	R4,PSG_register7				; R7 = mixer settings
	and		R5,R4,#0b000010					; Tone channel B
	and		R6,R4,#0b010000					; Noise channel B
	orr		R5,R5,R6,lsr #2					; bits 0 & 1 = NT
	adr		R6,PSG_table_saut_routines_mixage_Noise_onde_carree
	ldr		R6,[R6,R5,lsl #1]				; * 4 pour lire la table, R6 = routine
	
	str		R14,PSG_mixage_Noise_et_Tone_saveR14
	adr		R14,PSG_mixage_Noise_et_Tone_voie_B_retour
	mov		pc,R6
	
PSG_mixage_Noise_et_Tone_voie_B_retour:

	str		R1,PSG_offset_actuel_parcours_onde_carree_channel_B
	ldr		pc,PSG_mixage_Noise_et_Tone_saveR14


PSG_mixage_Noise_et_Tone_voie_C:

	ldr		R11,PSG_pointeur_buffer_destination_mixage_Noise_channel_C
	ldr		R1,PSG_offset_actuel_parcours_onde_carree_channel_C
	ldr		R0,PSG_increment_frequence_tone_channel_C
	mov		R0,R0,lsl #16
	ldr		R12,PSG_pointeur_buffer_Noise_calcule_pour_cette_VBL
	
	mov		R7,#nb_octets_par_vbl

	ldrb	R4,PSG_register7				; R7 = mixer settings
	and		R5,R4,#0b000100					; Tone channel C
	and		R6,R4,#0b100000					; Noise channel C
	orr		R5,R5,R6,lsr #2					; bits 0 & 1 = NT
	adr		R6,PSG_table_saut_routines_mixage_Noise_onde_carree
	ldr		R6,[R6,R5]				; * 4 pour lire la table, R6 = routine
	
	str		R14,PSG_mixage_Noise_et_Tone_saveR14
	adr		R14,PSG_mixage_Noise_et_Tone_voie_C_retour
	mov		pc,R6
	
PSG_mixage_Noise_et_Tone_voie_C_retour:

	str		R1,PSG_offset_actuel_parcours_onde_carree_channel_C
	ldr		pc,PSG_mixage_Noise_et_Tone_saveR14

	
; Faire les 4 routines
; ====================================> !!!!!!!!!!!!  attention, 0=actif, 1=coupé
; routine1 = Noise AND Tone/Note = 03
; routine2 = Noise uniquement ( pas de Note/Tone) = 02
; routine3 = Note/tone uniquement ( pas de Noise ) = 01
; routine4 = tout à $FF : ni Tone / ni Noise = 00

PSG_table_saut_routines_mixage_Noise_onde_carree:
	.long		PSG_routines_mixage_Noise_onde_carree_routine1				; Routine 1 = Noise AND Tone/Note						=0
	.long		PSG_routines_mixage_Noise_onde_carree_routine2				; Routine 2 = Noise uniquement ( pas de Note/Tone)		=1
	.long		PSG_routines_mixage_Noise_onde_carree_routine3				; routine3 = Note/tone uniquement ( pas de Noise )		=2
	.long		PSG_routines_mixage_Noise_onde_carree_routine4				; routine4 = tout à $FF : ni Tone / ni Noise => on met un mask qui accepte tout 	=3
	

PSG_routines_mixage_Noise_onde_carree_routine1:
; Routine 1 = Noise AND Tone/Note
PSG_boucle_mixage_Noise_et_Onde_carree_routine1:
; mixage Noise & Tone/Note

	adds	R1,R1,R0
	movmi	R2,#-1
	movpl	R2,#0x00
	ldrb	R3,[R12],#1				; lecture du Noise
	and		R2,R2,R3
	strb	R2,[R11],#1
	subs	R7,R7,#1
	bgt		PSG_boucle_mixage_Noise_et_Onde_carree_routine1
	mov		pc,lr

PSG_routines_mixage_Noise_onde_carree_routine2:
; Routine 2 = Noise uniquement ( pas de Note/Tone)
	mov		R7,R7,lsr #2							; divisé par 4 car str.l
	mov		R0,R0,lsl #2							; increment *4 car on fait des str.l
PSG_boucle_mixage_Noise_et_Onde_carree_routine2:
	adds	R1,R1,R0
	ldr		R3,[R12],#4								; on lit le noise
	str		R3,[R11],#4								; on le copie directement
	subs	R7,R7,#1
	bgt		PSG_boucle_mixage_Noise_et_Onde_carree_routine2
	mov		pc,lr	

PSG_routines_mixage_Noise_onde_carree_routine3:
; routine3 = Note/tone uniquement ( pas de Noise )
PSG_boucle_mixage_Noise_et_Onde_carree_routine3:
; mixage Noise & Tone/Note

	adds	R1,R1,R0
	movmi	R2,#-1
	movpl	R2,#0x00
	strb	R2,[R11],#1
	subs	R7,R7,#1
	bgt		PSG_boucle_mixage_Noise_et_Onde_carree_routine3
	mov		pc,lr

PSG_routines_mixage_Noise_onde_carree_routine4:
; routine4 = tout à $FF : ni Tone / ni Noise => on met un mask qui accepte tout
	mov		R3,#0xFFFFFFFF
	mov		R7,R7,lsr #2							; divisé par 4 car str.l
	mov		R0,R0,lsl #2							; increment *4 car on fait des str.l
PSG_boucle_mixage_Noise_et_Onde_carree_routine4:
	adds	R1,R1,R0
	str		R3,[R11],#4
	subs	R7,R7,#1
	bgt		PSG_boucle_mixage_Noise_et_Onde_carree_routine4	
	mov		pc,lr


; --------------------------------------------------------
; preparation application de l'enveloppe
; parcours l'enveloppe à la bonne frequence
; le Sync-Buzzer sera à gérer ici
; surement aussi d'autres effets : digidrum ?
; 0c05e1c
;

PSG_preparation_enveloppe_pour_la_VBL:
	ldr		R0,PSG_increment_frequence_enveloppe
	ldr		R1,PSG_offset_actuel_parcours_forme_enveloppe
; test sync buzzer ici => routine de sync buzzer - TODO -
	
	ldr		R3,PSG_flag_enveloppe
	cmp		R3,#0
	bne		PSG_preparation_enveloppe_pour_la_VBL_il_y_a_une_enveloppe
	mov		R7,#nb_octets_par_vbl
	mov		R7,R7,lsr #2				; /4

; il n'y a pas d'enveloppe, on simule juste son avancée
	mov		R2,R0,lsl #2				; R2 = increment * 4
PSG_preparation_enveloppe_pour_la_VBL_boucle_pas_d_enveloppe:
	add		R1,R1,R2
	subs	R7,R7,#1
	bgt		PSG_preparation_enveloppe_pour_la_VBL_boucle_pas_d_enveloppe
	b		PSG_preparation_enveloppe_pour_la_VBL_finalise
	

PSG_preparation_enveloppe_pour_la_VBL_il_y_a_une_enveloppe:
	
	ldr		R10,PSG_pointeur_vers_enveloppe_en_cours
	ldr		R11,PSG_pointeur_buffer_enveloppe_calculee_pour_cette_VBL
; parcours de l'enveloppe à la bonne fréquence
	mov		R7,#nb_octets_par_vbl
PSG_preparation_enveloppe_pour_la_VBL_boucle_creation_enveloppe:

	adds	R1,R1,R0				; incremente avec l'increment de frequence d'enveloppe
	ldrb	R3,[R10,R1,asr #16]		; source enveloppe en cours au rythme de la frequence
	strb	R3,[R11],#1
	
	subs	R7,R7,#1
	bgt		PSG_preparation_enveloppe_pour_la_VBL_boucle_creation_enveloppe
	
PSG_preparation_enveloppe_pour_la_VBL_finalise:
	cmp		R1,#0								; si l'offset de l'enveloppe est négatif c'est qu'il est dans la partie non répétitive
	bmi		PSG_offset_enveloppe_negatif
	ldr		R3,PSG_mask_bouclage_enveloppe
	and		R1,R3,R1							; on masque pour boucler

PSG_offset_enveloppe_negatif:
	str		R1,PSG_offset_actuel_parcours_forme_enveloppe
	mov		pc,lr

; --------------------------------------------------------
; application de l'effet digidrum ou sinus sid sur la voie A
; c064f4
; met à jour PSG_pointeur_table_volume_en_cours_channel_A pour pointer vers le buffer du digidrum mis à la bonne fréquence
PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_A:

	ldr		R0,PSG_flag_digidrum_voie_A
	cmp		R0,#0
	bne		PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_A_continue
; retour
	mov		pc,lr

PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_A_continue:
; increment frequence DG A = R0
; offset parcours DG A = R1
; pointeur debut sample DG A = R10
; buffer destination DG A = R11

	ldr		R10,PSG_pointeur_sample_digidrum_voie_A
	ldr		R1,PSG_offset_en_cours_digidrum_A
	ldr		R0,PSG_increment_digidrum_voie_A
	ldr		R11,PSG_pointeur_buffer_destination_mixage_Digidrum_channel_A
	str		R11,PSG_pointeur_table_volume_en_cours_channel_A

; - mixage
; parcours du sample DG à la bonne fréquence
	mov		R7,#nb_octets_par_vbl
PSG_preparation_DG_A_boucle:

	add		R1,R1,R0				; incremente avec l'increment de frequence d'enveloppe
	ldrb	R3,[R10,R1,lsr #16]		; source enveloppe en cours au rythme de la frequence
	strb	R3,[R11],#1
	
	subs	R7,R7,#1
	bgt		PSG_preparation_DG_A_boucle

; apres :
; si offset parcours DG A> taille DG A => flag DG A = 0
	ldr		R5,PSG_longeur_sample_digidrum_voie_A
	cmp		R1,R5
	blt		PSG_preparation_DG_A_pas_de_bouclage
	mov		R0,#0
	str		R0,PSG_flag_digidrum_voie_A			; fin du DG	
PSG_preparation_DG_A_pas_de_bouclage:
	str		R1,PSG_offset_en_cours_digidrum_A
	mov		pc,lr
	
; ----------------
PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_B:

	ldr		R0,PSG_flag_digidrum_voie_B
	cmp		R0,#0
	bne		PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_B_continue
; retour
	mov		pc,lr


PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_B_continue:
; increment frequence DG B = R0
; offset parcours DG B = R1
; pointeur debut sample DG B = R10
; buffer destination DG B = R11

	ldr		R10,PSG_pointeur_sample_digidrum_voie_B
	ldr		R1,PSG_offset_en_cours_digidrum_B
	ldr		R0,PSG_increment_digidrum_voie_B
	ldr		R11,PSG_pointeur_buffer_destination_mixage_Digidrum_channel_B
	str		R11,PSG_pointeur_table_volume_en_cours_channel_B

; - mixage
; parcours du sample DG à la bonne fréquence
	mov		R7,#nb_octets_par_vbl
PSG_preparation_DG_B_boucle:

	add		R1,R1,R0				; incremente avec l'increment de frequence d'enveloppe
	ldrb	R3,[R10,R1,lsr #16]		; source enveloppe en cours au rythme de la frequence
	strb	R3,[R11],#1
	
	subs	R7,R7,#1
	bgt		PSG_preparation_DG_B_boucle

; apres :
; si offset parcours DG B> taille DG B => flag DG B = 0
	ldr		R5,PSG_longeur_sample_digidrum_voie_B
	cmp		R1,R5
	blt		PSG_preparation_DG_B_pas_de_bouclage
	mov		R0,#0
	str		R0,PSG_flag_digidrum_voie_B			; fin du DG	
PSG_preparation_DG_B_pas_de_bouclage:
	str		R1,PSG_offset_en_cours_digidrum_B
	mov		pc,lr

; ----------------
PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_C:
	
	ldr		R0,PSG_flag_digidrum_voie_C
	cmp		R0,#0
	bne		PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_C_continue
; retour
	mov		pc,lr

PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_C_continue:
; increment frequence DG A = R0
; offset parcours DG A = R1
; pointeur debut sample DG A = R10
; buffer destination DG A = R11

	
	ldr		R10,PSG_pointeur_sample_digidrum_voie_C
	ldr		R1,PSG_offset_en_cours_digidrum_C
	ldr		R0,PSG_increment_digidrum_voie_C
	ldr		R11,PSG_pointeur_buffer_destination_mixage_Digidrum_channel_C
	str		R11,PSG_pointeur_table_volume_en_cours_channel_C

; - mixage
; parcours du sample DG à la bonne fréquence
	mov		R7,#nb_octets_par_vbl
	
PSG_preparation_DG_C_boucle:

	add		R1,R1,R0				; incremente avec l'increment de frequence d'enveloppe
	ldrb	R3,[R10,R1,lsr #16]		; source enveloppe en cours au rythme de la frequence
	strb	R3,[R11],#1
	
	subs	R7,R7,#1
	bgt		PSG_preparation_DG_C_boucle
	

; apres :
; si offset parcours DG A> taille DG A => flag DG A = 0
	ldr		R5,PSG_longeur_sample_digidrum_voie_C
	cmp		R1,R5
	blt		PSG_preparation_DG_C_pas_de_bouclage
	mov		R0,#0
	str		R0,PSG_flag_digidrum_voie_C			; fin du DG	
PSG_preparation_DG_C_pas_de_bouclage:
	str		R1,PSG_offset_en_cours_digidrum_C
	mov		pc,lr
	

; --------------------------------------------------------
; mixage final des 6 sources vers adresse_dma1_logical
; ( noise + tone voie A & table de volume A/enveloppe/enveloppe modifiée ) 
;      +
; ( noise + tone voie B & table de volume B/enveloppe/enveloppe modifiée ) 
;      +
; ( noise + tone voie C & table de volume C/enveloppe/enveloppe modifiée ) 
; 
; + normalisation
;
; + Lin to Log sur chaque octet

; maxi = 3 * $55 = 255 / $FF
;
mask_signature_sample:		.long		0x80808080
save_R14_mixage:			.long		0
PSG_mixage_final:

	str		R14,save_R14_mixage

	ldr		R13,pointeur_table_lin2logtab
	ldr		R6,adresse_dma1_logical
	
	ldr		R0,PSG_pointeur_buffer_destination_mixage_Noise_channel_A
	ldr		R1,PSG_pointeur_buffer_destination_mixage_Noise_channel_B
	ldr		R2,PSG_pointeur_buffer_destination_mixage_Noise_channel_C
	
	ldr		R3,PSG_pointeur_table_volume_en_cours_channel_A
	ldr		R4,PSG_pointeur_table_volume_en_cours_channel_B
	ldr		R5,PSG_pointeur_table_volume_en_cours_channel_C

; test flag effet dans enveloppe , si oui, remplacer R3 R4 R5 / digidrum / sinus sid

	mov		R7,#nb_octets_par_vbl
	mov		R7,R7,lsr #2				; / 4
	ldr		R8,mask_signature_sample

	
PSG_boucle_mixage_final:

	ldr		R9,[R0],#4					; R9 = noise + tone voie A
	ldr		R12,[R3],#4					; R12 = table de volume A/enveloppe/enveloppe modifiée
	and		R9,R9,R12
	
	ldr		R10,[R1],#4					; R10 = noise + tone voie B
	ldr		R12,[R4],#4					; R12 = table de volume B/enveloppe/enveloppe modifiée
	and		R10,R10,R12

	ldr		R11,[R2],#4					; R9 = noise + tone voie C
	ldr		R12,[R5],#4					; R12 = table de volume C/enveloppe/enveloppe modifiée
	and		R11,R11,R12

	add		R9,R9,R10
	add		R9,R9,R11					; somme des 3 voies
	
	eor		R9,R9,R8					; signature du sample

	
; lin2log
	and		R12,R9,#0xFF				; octet 1
	ldrb	R14,[R13,R12]				; R12=lin2log(R12.b0)

	and		R12,R9,#0xFF00				; octet 2
	ldrb	R12,[R13,R12,lsr #8]		; R12=lin2log(R12.b1)
	orr		R14,R14,R12, lsl #8

	and		R12,R9,#0xFF0000				; octet 3
	ldrb	R12,[R13,R12,lsr #16]		; R12=lin2log(R12.b1)
	orr		R14,R14,R12, lsl #16

	and		R12,R9,#0xFF000000				; octet 4
	ldrb	R12,[R13,R12,lsr #24]		; R12=lin2log(R12.b1)
	orr		R14,R14,R12, lsl #24

	str		R14,[R6],#4
	
	subs	R7,R7,#1
	bgt		PSG_boucle_mixage_final
	
	ldr		pc,save_R14_mixage

; --------------------------------------------------------
;
; structure PSG
;
; --------------------------------------------------------
; www.ym2149.com/ym2149.pdf
; https://www.fxjavadevblog.fr/m68k-atari-st-ym-player/

	.balign		4



valeur_1_div_14:	.long		4682				; ( 1/14 * 65536	) +1

PSG_pointeur_PSG:		.long			PSG

PSG:
; Tone
PSG_increment_frequence_tone_channel_A:		.long		0
PSG_increment_frequence_tone_channel_B:		.long		0
PSG_increment_frequence_tone_channel_C:		.long		0
PSG_mixer_settings_Tone:					.long		0
PSG_pointeur_table_volume_en_cours_channel_A:		.long		0
PSG_pointeur_table_volume_en_cours_channel_B:		.long		0
PSG_pointeur_table_volume_en_cours_channel_C:		.long		0
PSG_offset_actuel_parcours_onde_carree_channel_A:	.long		0
PSG_offset_actuel_parcours_onde_carree_channel_B:	.long		0
PSG_offset_actuel_parcours_onde_carree_channel_C:	.long		0


; Noise
PSG_increment_frequence_Noise:	.long		0
PSG_offset_precedent_Noise:		.long		0
PSG_mixer_settings_Noise:		.long		0
PSG_flag_Noise:					.long		0			; y a t il du noise cette VBL ?

; Enveloppe
PSG_increment_frequence_enveloppe:			.long		0
PSG_flag_enveloppe:							.long		0			; y a t il l'utilisation de l'enveloppe cette VBL ?
PSG_pointeur_vers_enveloppe_en_cours:		.long		0
PSG_offset_actuel_parcours_forme_enveloppe:	.long		0
PSG_mask_bouclage_enveloppe:				.long		0x001FFFFF

PSG_mixer_settings_all:			.long		0

; digidrums
PSG_taille_totale_des_digidrums:	.long		0
PSG_flag_digidrums:				.long		0
PSG_nb_digidrums:				.long		0
PSG_taille_totale_des_digidrums_plus_bouclage:		.long		0
PSG_pointeur_table_pointeurs_digidrums:		.long		PSG_table_pointeurs_digidrums
PSG_adresse_debut_digidrums:		.long		0
PSG_pointeur_table_MFP:				.long		PSG_table_MFP-1024

PSG_increment_digidrum_voie_A:		.long		0
PSG_increment_digidrum_voie_B:		.long		0
PSG_increment_digidrum_voie_C:		.long		0

PSG_numero_digidrum_voie_A:			.long		0
PSG_numero_digidrum_voie_B:			.long		0
PSG_numero_digidrum_voie_C:			.long		0

PSG_pointeur_sample_digidrum_voie_A:	.long		0
PSG_pointeur_sample_digidrum_voie_B:	.long		0
PSG_pointeur_sample_digidrum_voie_C:	.long		0

PSG_longeur_sample_digidrum_voie_A:		.long		0
PSG_longeur_sample_digidrum_voie_B:		.long		0
PSG_longeur_sample_digidrum_voie_C:		.long		0

PSG_flag_digidrum_voie_A:			.long		0
PSG_flag_digidrum_voie_B:			.long		0
PSG_flag_digidrum_voie_C:			.long		0

PSG_offset_en_cours_digidrum_A:			.long		0
PSG_offset_en_cours_digidrum_B:			.long		0
PSG_offset_en_cours_digidrum_C:			.long		0

PSG_pointeur_buffer_destination_mixage_Digidrum_channel_A:			.long		0
PSG_pointeur_buffer_destination_mixage_Digidrum_channel_B:			.long		0
PSG_pointeur_buffer_destination_mixage_Digidrum_channel_C:			.long		0


; --------------------------------------------------------
;
; variables replay YM
;
; --------------------------------------------------------
PSG_ecart_entre_les_registres_ymdata:	.long		0
PSG_pointeur_actuel_ymdata:			.long		0
; PSG_pointeur_debut_ymdata:			.long		0
PSG_pointeur_origine_ymdata:		.long		0


PSG_pointeur_table_de_frequences:		.long		PSG_table_de_frequences





PSG_registres:
PSG_register0:	.byte		0
PSG_register1:	.byte		0
PSG_register2:	.byte		0
PSG_register3:	.byte		0
PSG_register4:	.byte		0
PSG_register5:	.byte		0
PSG_register6:	.byte		0
PSG_register7:	.byte		0
PSG_register8:	.byte		0
PSG_register9:	.byte		0
PSG_register10:	.byte		0
PSG_register11:	.byte		0
PSG_register12:	.byte		0
PSG_register13:	.byte		0
PSG_register14:	.byte		0
PSG_register15:	.byte		0
;        -------------------------------------------------------
;              b7 b6 b5 b4 b3 b2 b1 b0
;         r0:  X  X  X  X  X  X  X  X   Period voice A
;         r1:  -  -  -  -  X  X  X  X   Period voice A + TS : b5-b4 is a 2bits code wich means: 00:     No TS. / 01:     TS running on voice A / 10:     TS running on voice B / 11:     TS running on voice C
;         r2:  X  X  X  X  X  X  X  X   Period voice B
;         r3:  -  -  -  -  X  X  X  X   Period voice B
;         r4:  X  X  X  X  X  X  X  X   Period voice C
;         r5:  -  -  -  -  X  X  X  X   Period voice C
;         r6:  -  -  -  X  X  X  X  X   Noise period
;         r7:  X  X  X  X  X  X  X  X   Mixer control
;         r8:  -  -  -  X  X  X  X  X   Volume voice A
;         r9:  -  -  -  X  X  X  X  X   Volume voice B
;        r10:  -  -  -  X  X  X  X  X   Volume voice C
;        r11:  X  X  X  X  X  X  X  X   Waveform period
;        r12:  X  X  X  X  X  X  X  X   Waveform period
;        r13:  -  -  -  -  X  X  X  X   Waveform shape
;        -------------------------------------------------------
;        New "virtual" registers to store extra data:
;        -------------------------------------------------------
;        r14:  -  -  -  -  -  -  -  -   Frequency for DD1 or TS1
;        r15:  -  -  -  -  -  -  -  -   Frequency for DD2 or TS2


PSG_flag_interleaved:			.long		0
PSG_flag_DRUMSIGNED:			.long		0
PSG_flag_DRUM4BITS:				.long		0
PSG_YM_clock:					.long		0
PSG_replay_frequency_HZ:		.long		0
PSG_loop_frame_YM6:				.long		0

LZH_pointeur_YM6packed:			.long		YM6packed



;-----------------------------------------------------
;
; routines & variables depacking LZH
;
;-----------------------------------------------------
; LHA depacker
; file have to LH5 format with -h0
; under DOSBOX :
; lha.exe a -h0 FILENAME.LZH FILENAME.BIN 

.equ	CRC16, 0xA001
.equ	BufSiz,	0x4000

.equ	NC, 0x200-2
.equ	NP,	14
.equ	NT,	19
.equ	NPT,	0x80

.equ	CBIT,	9
.equ	PBIT,	4
.equ	TBIT,	5

.equ	DSIZ,	0x2000
.equ	DSIZ2,	DSIZ*2

.equ	CRC16,	0xA001

LZH_save_adr_retour_local1:		.long		0
LZH_depack:
	str		R14,LZH_save_adr_retour_local1

	str		R0,LZH_pointeur_file

	bl		LZH_make_crc_table

; https://web.archive.org/web/20080821024159/http://homepage1.nifty.com/dangan/en/Content/Program/Java/jLHA/Notes/Level0Header.html
; depack YM6 packed

	ldr		R1,LZH_pointeur_file
	mov		R12,R1
	mov		R13,#2							; size of header minimal
	ldrb	R0,[R1]
	add		R13,R13,R0						; R13 = offset fin de header 
	str		R13,LZH_offset_debut_datas_packees
	add		R13,R13,R12
	str		R13,LZH_adresse_debut_datas_packees
	
	add		R1,R1,#2						; saute  	Size of header  + Header checksum 
	
; -lh5-  	8k sliding dictionary + static Huffman
;	ldrb	R0,[R1],#1
;	cmp		R0,#0x2D						; -
;	beq		LZH_ok1
;	SWI		BKP
;LZH_ok1:
;	ldrb	R0,[R1],#1
;	cmp		R0,#0x6C						; l
;	beq		LZH_ok2
;	SWI		BKP
;LZH_ok2:
;	ldrb	R0,[R1],#1
;	cmp		R0,#0x68						; h
;	beq		LZH_ok3
;	SWI		BKP
;LZH_ok3:
;	ldrb	R0,[R1],#1
;	cmp		R0,#0x35						; 5
;	beq		LZH_ok4
;	SWI		BKP
;LZH_ok4:
;	ldrb	R0,[R1],#1
;	cmp		R0,#0x2D						; -
;	beq		LZH_ok5
;	SWI		BKP
;LZH_ok5:

	add		R1,R1,#5				; saute -lh5-

; compressed size
	ldrb	R2,[R1],#1
	ldrb	R3,[R1],#1
	ldrb	R4,[R1],#1
	ldrb	R5,[R1],#1
	
	orr		R2,R2,R3,lsl #8
	orr		R2,R2,R4,lsl #16
	orr		R2,R2,R5,lsl #24

	str		R2,LZH_packsize

	add		R2,R2,R13					; + offset fin de header
	str		R2,LZH_offset_fin_de_fichier_packe
	add		R3,R12,R2					; R3 = adresse fin de fichier packé
	str		R3,LZH_adresse_fin_de_fichier_packe
	
; original size
	ldrb	R2,[R1],#1
	ldrb	R3,[R1],#1
	ldrb	R4,[R1],#1
	ldrb	R5,[R1],#1
	
	orr		R2,R2,R3,lsl #8
	orr		R2,R2,R4,lsl #16
	orr		R2,R2,R5,lsl #24
	
	str		R2,LZH_origsize				; taille d'origine
	str		R2,LZH_origsize_CRC			; taille d'origine
	
	add		R1,R1,#6					; on saute modified time + file attribute ms dos

; Length of Pathname 
	ldrb	R2,[R1],#1
	add		R1,R1,R2					; on saute le Pathname


; CRC16
		ldrb	R2,[R1],#1				; CRC16(L) 
		ldrb	R3,[R1],#1				; CRC16(H) 
		
		add		R2,R2,R3,lsl #8			; CRC16(L)  + CRC16(H)<<16
		
		str		R2,LZH_original_CRC16
	
	
; allocation mémoire de origsize octets
; pointeur buffer malloc dans LZH_pointeur_text

	mov		R0,#-1				; New size of current slot
	mov		R1,#-1				;  	New size of next slot
	SWI		Wimp_SlotSize			; Wimp_SlotSize 
	;str		R0,ancienne_taille_alloc_memoire_current_slot

	;R2 = taille mémoire dispo

	mov		R3,R2
	ldr		R2,LZH_origsize			; quantité d'octets à reserver
	cmp		R3,R2
	bge		LZH_ok_assez_de_ram

	SWI		0x01
	.byte	"Not enough memory.",10,13,0
	.p2align 2


	mov		R0,#-1
	b		LZH_exit



LZH_ok_assez_de_ram:
	add		R0,R0,R2				; current slot size + valeur_taille_memoire = New size of current slot
	mov		R1,#-1
	SWI 	Wimp_SlotSize			; Wimp_SlotSize 

; alloc mémoire
; clean la mémoire :
	ldr		R0,pointeur_FIN_DATA_actuel
	
	str		R0,LZH_pointeur_text	; pointeur vers le buffer alloué, destination des données décompressées
	
	ldr		R2,LZH_origsize
	add		R0,R0,R2
; on arrondi à multiple de 4
	add		R0,R0,#3
	and		R0,R0,#0xFFFFFFFC
	
	str		R0,pointeur_FIN_DATA_actuel		; on met à jour le pointeur vers la fin de la mémoire qu'on utilise.

	
	ldr		R2,LZH_origsize
	add		R1,R0,R2				; de R0 à R1 à mettre à zéro
	mov		R2,#0
LZH_boucle_clean_memory_bss:
	strb	R2,[R0],#1
	cmp		R0,R1
	bne		LZH_boucle_clean_memory_bss
	
	



; - depack
; R0=d0
; ...
; R7=d7
; R8=a5
; R9=a6
; R10=a0
; R13=sp/stack

	ldr		R13,LZH_pointeur_stack

	mov		R0,#0
	;str		R0,LZH_curcrc

	ldr		R0,LZH_adresse_debut_datas_packees
	str		R0,LZH_inpptr

;- debut decodage LZH

LZH_decode:
	
	mov		R0,#0
	str		R0,LZH_blocksize
	str		R0,LZH_bitbuf
	str		R0,LZH_subbitbuf
	str		R0,LZH_bitcount
	
	mov		R0,#16
	bl		LZH_fillbuf
	
	ldr		R9,LZH_pointeur_text
	b		LZH_entry

LZH_loop_decode:

	bl		LZH_decode_c_st1

	
	cmp		R0,#0x100
	bge		LZH_loc50
	
	strb	R0,[R9],#1

LZH_entry:
	ldr		R0,LZH_inpptr
	cmp		R0,#0
	beq		LZH_BUG
	
	ldr		R0,LZH_origsize
	subs	R0,R0,#1
	str		R0,LZH_origsize
	bge		LZH_loop_decode

	b		LZH_loc53

LZH_loc50:

	mov		R2,R0
	subs	R2,R2,#0x100-3
	bl		LZH_decode_p_st1
	stmfd	R13!,{R2}					; move	d2,-(sp)

	stmfd	R13!,{R7}
	
	mov		R8,R9					; R8=A5 / move.l	a6,a5		;si
	sub		R8,R8,#1
	sub		R8,R8,R0				; sub	d0,a5
LZH_circ0:
	ldr		R7,LZH_pointeur_text
	cmp		R7,R8
	bcc		LZH_circ1
	

	add		R8,R8,#DSIZ2
	b		LZH_circ0
	
	
LZH_circ1:
	ldmfd	R13!,{R7}

	

LZH_do1:
	ldrb	R0,[R8],#1				; move.b	(a5)+,(a6)+
	strb	R0,[R9],#1
	
;	ldr		R1,LZH_text_DSIZ2
;	cmp		R8,R1
;	blt		LZH_circ2
;	sub		R8,R8,#DSIZ2			; lea	-DSIZ2(a5),a5
;LZH_circ2:
;	cmp		R9,R1
;	blt		LZH_loc52
	;stmfd	R13!,{R2}			; move	d2,-(sp)
	;stmfd	R13!,{R8}			; pea	(a5)		;si
	;bl		LZH_putbuf
	;ldmfd	R13!,{R8}
	;ldmfd	R13!,{R2}
LZH_loc52:
	cmp		R2,#0
	beq		LZH_BUG
	subs	R2,R2,#1
	bne		LZH_do1
	
	ldr		R0,LZH_inpptr
	cmp		R0,#0
	beq		LZH_BUG
	ldmfd	R13!,{R2}				; move	(sp)+,d2
	ldr		R1,LZH_origsize
	subs	R1,R1,R2				; sub.l	d2,origsize
	str		R1,LZH_origsize
	bge		LZH_loop_decode
LZH_loc53:
	SWI		0x01
	.byte	"LZH unpack done.",13,10,0
	.p2align 2

; verif du CRC

	
	bl		LZH_calc_new_CRC
	
	ldr		R0,LZH_original_CRC16
	ldr		R1,LZH_nouveau_CRC16
	cmp		R0,R1
	bne		LZH_erreur_CRC_final

	SWI		0x01
	.byte	"CRC OK.",13,10,0
	.p2align 2

	ldr		R0,LZH_pointeur_text
	ldr		R1,LZH_origsize_CRC
	b		LZH_exit

LZH_erreur_CRC_final:
	SWI		0x01
	.byte	"CRC error.",13,10,0
	.p2align 2	
	mov		R0,#-1


LZH_exit:
	ldr		R14,LZH_save_adr_retour_local1
	
	
	mov		pc,lr



	
	
; R0=d0
; R1=d1
; R2=D2
; R3=d3
; R4=d4
; R5=A5
; R6=A6
; R7=tmp
; R8=A3
; R9=A4
; R10=A0
; R12=tmp
; R13=SP

LZH_read_pt_len:
	
; input : d3 d4 d2
	stmfd	R13!,{R4}			; move	d4,-(sp)	;si
	mov		R0,R3
	stmfd	R13!,{R14}
	bl		LZH_getbits
	ldmfd	R13!,{R14}
	cmp		R0,R4
	bgt		LZH_BUG				; LZH_brokenerr
	
	ldr		R6,LZH_pointeur_pt_len
	
	cmp		R0,#0
	bne		LZH_read_pt_len_loc1

	ldmfd	R13!,{R2}
	cmp		R2,#0
	beq		LZH_BUG
LZH_read_pt_len_loc2:
	strb	R0,[R6],#1
	subs	R2,R2,#1
	bne		LZH_read_pt_len_loc2
	
	ldr		R7,LZH_pointeur_fin_pt_len
	cmp		R6,R7
	bgt		LZH_BUG
	
	mov		R0,R3
	stmfd	R13!,{R14}
	bl		LZH_getbits
	ldmfd	R13!,{R14}
	mov		R2,#256
	ldr		R6,LZH_pointeur_pt_table
LZH_read_pt_len_loc3:
	str		R0,[R6],#4
	subs	R2,R2,#1
	bne		LZH_read_pt_len_loc3
	mov		pc,lr

LZH_read_pt_len_loc1:
	mov		R8,R6					; R8=A3
	add		R8,R8,R2
	
	mov		R5,R6					; R5=A5
	add		R5,R5,R0
	
LZH_read_pt_len_do1:

	mov		R0,#3
	stmfd	R13!,{R14}
	bl		LZH_getbits
	ldmfd	R13!,{R14}
	cmp		R0,#7
	bne		LZH_read_pt_len_not1

	
	ldr		R1,LZH_bitbuf
	mov		R1,R1,lsl #16
LZH_read_pt_len_while1:
										; add.w => Carry

	adds	R1,R1,R1
	bcc		LZH_read_pt_len_endw
	adds	R0,R0,#1
	b		LZH_read_pt_len_while1

LZH_read_pt_len_endw:
	stmfd	R13!,{R0}					; move	d0,-(sp)
	subs	R0,R0,#6
	
	stmfd	R13!,{R14}
	bl		LZH_fillbuf
	ldmfd	R13!,{R14}
	
	ldmfd	R13!,{R0}					; move	(sp)+,d0
LZH_read_pt_len_not1:
	strb	R0,[R6],#1
	cmp		R6,R8
	bne		LZH_read_pt_len_not2
	
	mov		R0,#2
	stmfd	R13!,{R14}
	bl		LZH_getbits
	ldmfd	R13!,{R14}
	mov		R2,R0
	mov		R0,#0
	cmp		R2,#0
	beq		LZH_BUG
LZH_read_pt_len_loc11:
	strb	R0,[R6],#1
	subs	R2,R2,#1
	bne		LZH_read_pt_len_loc11

LZH_read_pt_len_not2:
	cmp		R6,R5
	blt		LZH_read_pt_len_do1
	
	ldr		R7,LZH_LZH_pointeur_fin_pt_len
	cmp		R6,R7
	bgt		LZH_BUG

	ldmfd	R13!,{R4}
	
	ldr		R9,LZH_pointeur_pt_len
	mov		R2,R9
	subs	R2,R2,R6
	adds	R2,R2,R4
	beq		LZH_read_pt_len_none1
	mov		R0,#0
LZH_read_pt_len_loc12:
	strb	R0,[R6],#1
	subs	R2,R2,#1
	bne		LZH_read_pt_len_loc12
LZH_read_pt_len_none1:
	mov		R0,R4
	mov		R2,#8
	ldr		R6,LZH_pointeur_pt_table
	b		LZH_make_table

; --------------------------------------------------------
LZH_read_c_len:


	mov		R0,#CBIT
	stmfd	R13!,{R14}
	bl		LZH_getbits
	ldmfd	R13!,{R14}
	
	
	ldr		R12,LZH_valeur_NC
	cmp		R0,R12
	bgt		LZH_BUG				; LZH_brokenerr
	
	ldr		R6,LZH_pointeur_c_len
	cmp		R0,#0
	bne		LZH_LZH_read_c_len_not1

	mov		R2,#NC
LZH_LZH_read_c_len_lop1:
	strb	R0,[R6],#1
	subs	R2,R2,#1
	bne		LZH_LZH_read_c_len_lop1

	ldr		R7,LZH_pointeur_FIN_C_LEN
	cmp		R6,R7
	bgt		LZH_BUG

	mov		R0,#CBIT
	stmfd	R13!,{R14}
	bl		LZH_getbits
	ldmfd	R13!,{R14}

	mov		R2,#4096
	ldr		R6,LZH_pointeur_c_table
LZH_LZH_read_c_len_lop2:
	str		R0,[R6],#1
	subs	R2,R2,#1
	bne		LZH_LZH_read_c_len_lop2
	mov		pc,lr
	
LZH_LZH_read_c_len_not1:
	mov		R8,R6				; R8=A3
	adds	R8,R8,R0
	
	stmfd	R13!,{R6}			; pea	(a6)
	
LZH_LZH_read_c_len_do100:
	ldr		R0,LZH_bitbuf
	mov		R1,R0
	mov		R1,R1,lsr #8
	add		R1,R1,R1
	add		R1,R1,R1			; *4
	ldr		R10,LZH_pointeur_pt_table
	ldr		R1,[R10,R1]
	
	adr		R5,LZH_read_c_len_1
	mov		R2,#NT
	b		LZH_tree1

LZH_read_c_len_1:
	stmfd	R13!,{R1}
	ldr		R10,LZH_pointeur_pt_len
	mov		R0,#0
	ldrb	R0,[R10,R1]
	stmfd	R13!,{R14}
	bl		LZH_fillbuf
	ldmfd	R13!,{R14}
	ldmfd	R13!,{R0}
	
	subs	R0,R0,#2
	bgt		LZH_LZH_read_c_len_loc68
	bne		LZH_LZH_read_c_len_loc65

	mov		R0,#CBIT
	stmfd	R13!,{R14}
	bl		LZH_getbits
	ldmfd	R13!,{R14}
	adds	R0,R0,#20
	mov		R2,R0
	b		LZH_LZH_read_c_len_loc67

LZH_LZH_read_c_len_loc65:
	adds	R0,R0,#1
	bne		LZH_LZH_read_c_len_loc66

	mov		R0,#4
	stmfd	R13!,{R14}
	bl		LZH_getbits
	ldmfd	R13!,{R14}
	adds	R0,R0,#3
	mov		R2,R0
	b		LZH_LZH_read_c_len_loc67

LZH_LZH_read_c_len_loc66:
	mov		R2,#1
LZH_LZH_read_c_len_loc67:
	mov		R0,#0
LZH_LZH_read_c_len_lopxx1:
	cmp		R2,#0
	beq		LZH_BUG
	strb	R0,[R6],#1
	subs	R2,R2,#1
	bne		LZH_LZH_read_c_len_lopxx1
	b		LZH_LZH_read_c_len_loc69
	
LZH_LZH_read_c_len_loc68:
	strb	R0,[R6],#1
LZH_LZH_read_c_len_loc69:
	cmp		R6,R8
	blt		LZH_LZH_read_c_len_do100
	
	ldr		R7,LZH_pointeur_FIN_C_LEN
	cmp		R6,R7
	bgt		LZH_BUG
	
	mov		R0,#0
	ldr		R2,LZH_c_len_plus_NC
	subs	R2,R2,R6
	beq		LZH_LZH_read_c_len_NONE2
LZH_LZH_read_c_len_fil0:
	strb	R0,[R6],#1
	subs	R2,R2,#1
	bne		LZH_LZH_read_c_len_fil0
LZH_LZH_read_c_len_NONE2:
	mov		R0,#NC
	ldmfd	R13!,{R9}			; R9=A4
	
	mov		R2,#12
	ldr		R6,LZH_pointeur_c_table		; R6=A6
	
	b		LZH_make_table

;------------------------------------------------
LZH_decode_c:
LZH_decode_c_st1_2:
	stmfd	R13!,{R9}			; pea	(a6)	R9=A6
	mov		R0,#16
	stmfd	R13!,{R14}
	bl		LZH_getbits

	ldmfd	R13!,{R14}
	subs	R0,R0,#1
	str		R0,LZH_blocksize


	mov		R4,#NT
	mov		R3,#TBIT
	mov		R2,#3
	stmfd	R13!,{R14}
	bl		LZH_read_pt_len
	ldmfd	R13!,{R14}


	
	stmfd	R13!,{R14}
	bl		LZH_read_c_len
	ldmfd	R13!,{R14}

	
	mov		R4,#NP
	mov		R3,#PBIT
	mov		R2,#-1	
	stmfd	R13!,{R14}
	bl		LZH_read_pt_len
	ldmfd	R13!,{R14}
	
	ldmfd	R13!,{R9}
	b		LZH_decode_c_st1_3

LZH_decode_c_st1:
	
	ldr		R7,LZH_blocksize
	subs	R7,R7,#1
	str		R7,LZH_blocksize
	blt		LZH_decode_c_st1_2
LZH_decode_c_st1_3:
	

	
	ldr		R1,LZH_bitbuf
	
	mov		R1,R1,lsr #4
	mov		R2,#4
	add		R1,R1,R1
	add		R1,R1,R1
	ldr		R10,LZH_pointeur_c_table
	ldr		R1,[R10,R1]
	
	ldr		R12,LZH_valeur_NC
	cmp		R1,R12
	bgt		LZH_decode_c_st1_loc1

LZH_decode_c_st1_1:	
	stmfd	R13!,{R1}					; move	d1,-(sp)	
	ldr		R10,LZH_pointeur_c_len		; R10=A0
	mov		R0,#0
	ldrb	R0,[R10,R1]
	
	stmfd	R13!,{R14}
	bl		LZH_fillbuf
	ldmfd	R13!,{R14}
	
	ldmfd	R13!,{R0}
	mov		pc,lr

LZH_decode_c_st1_loc1:
	ldr		R0,LZH_bitbuf
	
	stmfd	R13!,{R7}
	ldr		R7,LZH_MASK_FFFF
	mov		R0,R0,asl R2				; asl.b	d2,d0
	and		R0,R0,R7					; masque les 16 bits du haut
	ldmfd	R13!,{R7}
	
	adr		R5,LZH_decode_c_st1_1
	mov		R2,#NC

LZH_tree0:

	ldr		R10,LZH_pointeur_left
; add.b	d0,d0
	stmfd	R13!,{R7}
	mov		R7,R0
	mov		R7,R7,lsr #8
	mov		R7,R7,lsl #8			; R7=16 bits du haut de R0
	and		R0,R0,#0xFF				; R0=partie basse de R0
	
	adds	R0,R0,R0				; probleme car add.b	d0,d0 ...--------------
	cmp		R0,#0x100
	bcc		LZH_loc1edz
	ldr		R10,LZH_pointeur_right
LZH_loc1edz:
	and		R0,R0,#0xFF				; R0=partie basse de R0	
	add		R0,R0,R7				; on reconstruit R0/D0
	ldmfd	R13!,{R7}

	
	mov		R1,R1,lsl #1
	ldr		R1,[R10,R1]

LZH_tree1:
	cmp		R1,R2
	bge		LZH_tree0
	mov		pc,R5						; jmp (A5)




; ---------------------------------------------------------

LZH_decode_p_st1:


	stmfd	R13!,{R2}			;move	d2,-(sp)
	mov		R1,#0
	ldrb	R1,LZH_bitbuf+1		; point fort !
	add		R1,R1,R1
	add		R1,R1,R1
	ldr		R10,LZH_pointeur_pt_table	; R10=A0
	ldr		R1,[R10,R1]
	
	cmp		R1,#NP
	bge		LZH_decode_c_st1_loc2



LZH_decode_p_st1_1:
	stmfd	R13!,{R1}			; move	d1,-(sp)
	ldr		R10,LZH_pointeur_pt_len
	mov		R0,#0
	ldrb	R0,[R10,R1]
	
	stmfd	R13!,{R14}
	bl		LZH_fillbuf
	ldmfd	R13!,{R14}
	
	ldmfd	R13!,{R0}
	cmp		R0,#1
	ble		LZH_decode_c_st1_loc3
	subs	R0,R0,#1
	mov		R2,R0
	
	stmfd	R13!,{R14}
	bl		LZH_getbits
	ldmfd	R13!,{R14}
	
	mov		R1,#1
	mov		R1,R1,asl R2
	
	orr		R0,R0,R1
LZH_decode_c_st1_loc3:
	ldmfd	R13!,{R2}			; move	(sp)+,d2
	mov		pc,lr

LZH_decode_c_st1_loc2:
	ldrb	R0,LZH_bitbuf+1
	adr		R5,LZH_decode_p_st1_1	; R5=A5
	mov		R2,#NP
	b		LZH_tree0


; ---------------------------------------------------------
; R2 = nb bits de la table, 12=4096 valeurs
; R6 = table destination
LZH_make_table:
	
	str		R0,LZH_nchar
	add		R0,R0,R0
	add		R0,R0,R0				; *4 car .L ?
	
	str		R0,LZH_avail_mt
	str		R2,LZH_tablebits
	str		R6,LZH_table

	mov		R0,#16
	subs	R0,R0,R2
	str		R0,LZH_restbits

	mov		R0,#1
	mov		R0,R0,asl R2
	mov		R2,R0
	cmp		R2,#0
	beq		LZH_BUG

	mov		R0,#0
LZH_stos:
	str		R0,[R6],#4			; move.w...clear table
	
	subs	R2,R2,#1
	bne		LZH_stos

	mov		R4,#0
	mov		R1,#0x8000
	mov		R3,#1
LZH_do200:
	mov		R6,R9				; move.l	a4,a6 / R9=A4
	ldr		R2,LZH_nchar
	cmp		R2,#0
	beq		LZH_BUG
LZH_make_table_do2:
	mov		R0,R3
LZH_make_table_scasb:
	ldrb	R7,[R6],#1
	cmp		R0,R7
	beq		LZH_make_table_fnd
	subs	R2,R2,#1
	bne		LZH_make_table_scasb
	b		LZH_make_table_mt1

LZH_make_table_fnd:
	bne		LZH_make_table_mt1
	mov		R0,R6
	subs	R0,R0,R9				; R9=A4
	subs	R0,R0,#1
	stmfd	R13!,{R2}			; move	d2,-(sp)
	stmfd	R13!,{R6}			; pea (a6)

;
; bx=weight = d1 = R1
; si=code = 
; dx=len = 
;


	mov		R2,#0
	ldr		R2,LZH_restbits
	mov		R7,R4				; R7=D7
	mov		R7,R7, lsr R2
	adds	R7,R7,R7			; *2 ou *4 ?
	adds	R7,R7,R7			; *4.
	
	ldr		R6,LZH_table
	adds	R6,R6,R7
	stmfd	R13!,{R1}			; move	d1,-(sp)		;weight
	
	stmfd	R13!,{R7}
	ldr		R7,LZH_tablebits
	cmp		R3,R7
	bgt		LZH_make_table_loc1
	ldmfd	R13!,{R7}					; pas existant sur 68000
	mov		R1,R1,lsr R2
	mov		R2,R1
	cmp		R2,#0
	beq		LZH_BUG
LZH_make_table_stosw1:
	str 	R0,[R6],#4					; stock un word !
	subs	R2,R2,#1
	bne		LZH_make_table_stosw1

	b		LZH_make_table_loc2

LZH_make_table_loc1:

	ldmfd	R13!,{R7}					; pas existant sur 68000
	
	stmfd	R13!,{R4}
	ldr		R2,LZH_tablebits
	mov		R4,R4,lsl R2				; asl.w
	mov		R4,R4,lsl #16				; on ne garde que le bas du asl.w
	mov		R4,R4,lsr #16
	
	rsb		R2,R2,#0					; neg d2
	adds	R2,R2,R3
	beq		LZH_BUG
LZH_make_table_do3:
	ldr		R1,[R6]
	cmp		R1,#0
	bne		LZH_make_table_loo
	ldr		R1,LZH_avail_mt
	
	ldr		R10,LZH_pointeur_right
	stmfd	R13!,{R7}					; sauvegarde R7, pas existant de 68000
	mov		R7,#0
	str		R7,[R10,R1]
	ldr		R10,LZH_pointeur_left
	str		R7,[R10,R1]
	ldmfd	R13!,{R7}					; pas existant sur 68000

	mov		R1,R1,lsr #1
	str		R1,[R6]
	mov		R1,R1,lsl #1
	adds	R1,R1,#4					; +4 au lieu de +2 car on stocke des .l
	str		R1,LZH_avail_mt
	
LZH_make_table_loo:

	ldr		R6,[R6]
	add		R6,R6,R6					; double le pointeur car longeur de chaque champ de right et left = 4 octets

	adds	R4,R4,R4
	cmp		R4,#0x10000
	blt		LZH_make_table_noc1
	; bcc		LZH_make_table_noc1
	
	stmfd	R13!,{R7}					; sauvegarde R7, pas existant de 68000
	ldr		R7,LZH_pointeur_right
	adds	R6,R6,R7
	b		LZH_make_table_noc2

LZH_make_table_noc1:
	stmfd	R13!,{R7}					; sauvegarde R7, pas existant de 68000
	ldr		R7,LZH_pointeur_left
	adds	R6,R6,R7

LZH_make_table_noc2:
	ldmfd	R13!,{R7}					; pas existant sur 68000
	subs	R2,R2,#1
	bne		LZH_make_table_do3
	str		R0,[R6]
	ldmfd	R13!,{R4}
LZH_make_table_loc2:
	ldmfd	R13!,{R1}
	ldmfd	R13!,{R6}
	ldmfd	R13!,{R2}
	adds	R4,R4,R1
	
	cmp		R4,#0x10000
	bge		LZH_make_table_mt2
	
	;bcs		LZH_make_table_mt2
	
	cmp		R2,#0
	beq		LZH_BUG
	
	subs	R2,R2,#1
	bne		LZH_make_table_do2
LZH_make_table_mt1:
	adds	R3,R3,#1
	movs	R1,R1,lsr #1
	bcc		LZH_do200

LZH_make_table_mt2:
	
	mov		pc,lr

; ---------------------------------------------------------	
LZH_BUG:
	SWI		0x01
	.byte	"BUG.",0
	.p2align 2
	SWI		BKP

; ---------------------------------------------------------
LZH_getbits:
; input d0
;
	cmp		R0,#16
	bgt		LZH_BUG
	
	stmfd	R13!,{R2}
	mov		R2,#16
	subs	R2,R2,R0
	stmfd	R13!,{R7}					; sauvegarde R7, pas existant de 68000
	ldr		R7,LZH_bitbuf
	stmfd	R13!,{R7}					; move	bitbuf,-(sp)

	stmfd	R13!,{R14}
	bl		LZH_fillbuf
	ldmfd	R13!,{R14}
	
	ldmfd	R13!,{R0}
	ldmfd	R13!,{R7}					; pas existant sur 68000
	mov		R0,R0,lsr R2
	ldmfd	R13!,{R2}
	mov		pc,lr
	
; ---------------------------------------------------------
;
; shift bitbuf n bits left, read n bits
;
; rafraichit LZH_bitbuf avec d0 bits
;
LZH_MASK_FFFF:		.long		0xFFFF
LZH_fillbuf:


	cmp		R0,#16
	bgt		LZH_BUG

	stmfd	R13!,{R1,R2,R3,R7}

	mov		R2,R0
	ldr		R1,LZH_bitcount
	ldr		R3,LZH_bitbuf
	
	ldr		R0,LZH_subbitbuf
	
	cmp		R2,R1
	ble		LZH_fillbuf_loc100

	subs	R2,R2,R1
	
	mov		R3,R3,asl R1					
	ldr		R7,LZH_MASK_FFFF				
	and		R3,R3,R7						; asl	d1,d3   .W!
	
	mov		R7,#32
	subs	R7,R7,R1
	mov		R0,R0,ror R7				; ror 32-n = rol n  / a verifier !
	
	
	mov		R7,R0, lsr #8
	and		R0,R0,#0xFF
	orr		R0,R7,R0				; rol.b ?
	adds	R3,R3,R0
	
	mov		R1,#8
LZH_fillbuf_fb1:

	stmfd	R13!,{R14}
	bl		LZH_getc
	ldmfd	R13!,{R14}
	; D0=1 octet


	
	cmp		R2,R1
	ble		LZH_fillbuf_loc100
	subs	R2,R2,R1
	mov		R3,R3, asl #8
	;and		R7,R0,#0xFF					; move.b	d0,d3
	orr		R3,R3,R0
	b		LZH_fillbuf_fb1

LZH_fillbuf_loc100:
	subs	R1,R1,R2
	str		R1,LZH_bitcount

	mov		R3,R3, asl R2
	mov		R0,R0, asl R2
	mov		R7,R0
	mov		R7,R7, lsr #8
	add		R3,R3,R7
	

	
	mov		R3,R3,lsl #16				; elimine les 16 bits du haut
	mov		R3,R3,lsr #16

	
	str		R3,LZH_bitbuf
	and		R0,R0,#0xFF
	str		R0,LZH_subbitbuf
	
	ldmfd	R13!,{R1,R2,R3,R7}
	mov		pc,lr

; ---------------------------------------------------------
; getc :
;
; retourne d0=1 octet lu
;
LZH_getc:
	ldr		R10,LZH_inpptr
	ldrb	R0,[R10],#1
	str		R10,LZH_inpptr
	mov		pc,lr


; ---------------------------------------------------------
; calcul du nouveau CRC
; algo:
; /* PCompress2, Arc, DMS, ProPack, LhA, Zoo, Shrink */
;uint16 DoCRC16_1(const uint8 * Mem, int32 Size)
;{
;  uint16 CRC = 0;
;  uint16 buf[256];
  
;  MakeCRC16(buf, 0xA001);

;  while(Size--)
;    CRC = buf[(CRC ^ *(Mem++)) & 0xFF] ^ (CRC >> 8);
;
;  return CRC;
	
;
; make CRC table
;
LZH_make_crc_table:
	ldr		R10,LZH_pointeur_crctbl
	mov		R2,#0
	mov		R3,#CRC16

LZH_make_crc_table_boucle1:
	mov		R0,R2
	mov		R1,#8
LZH_make_crc_table_boucle2:
	movs	R0,R0,lsr #1
	bcc		LZH_make_crc_table_boucle3
	eor		R0,R0,R3						; #CRC16
LZH_make_crc_table_boucle3:
	subs	R1,R1,#1
	bgt		LZH_make_crc_table_boucle2
	str		R0,[R10],#4
	adds	R2,R2,#1
	cmp		R2,#256
	bne		LZH_make_crc_table_boucle1
	mov		pc,lr

; ---------------------------------------------------------	
LZH_calc_new_CRC:

	ldr		R0,LZH_origsize_CRC

	ldr		R10,LZH_pointeur_text
	mov		R1,#0		; on commence à zéro
	ldr		R11,LZH_pointeur_crctbl	
LZH_calc_new_CRC_do:
	ldrb	R2,[R10],#1
	mov		R7,R1
	and		R7,R7,#0xFF
	eor		R2,R2,R7			; eor.b
	
	mov		R1,R1,lsr #8
	add		R2,R2,R2
	add		R2,R2,R2			; *4 pour .L
	ldr		R2,[R11,R2]
	eor		R1,R1,R2
	
	subs	R0,R0,#1
	bne		LZH_calc_new_CRC_do
	
	str		R1,LZH_nouveau_CRC16
	mov		pc,lr
	


	
.p2align 4

; -----------------------------------------------------
;pointeur_FIN_DATA:				.long		FIN_DATA
;ancienne_taille_alloc_memoire_current_slot:		.long		0

LZH_pointeur_crctbl:			.long		LZH_crctbl
LZH_original_CRC16:				.long		0
LZH_nouveau_CRC16:				.long		0
LZH_pointeur_file:				.long		0
LZH_pointeur_fin_pt_len:		.long		LZH_fin_pt_len
LZH_pointeur_text:				.long		0
LZH_pointeur_stack:				.long		LZH_stack
LZH_pointeur_FIN_C_LEN:			.long		LZH_FIN_C_LEN
LZH_pointeur_pt_len:			.long		LZH_pt_len
LZH_pointeur_pt_table:			.long		LZH_pt_table
LZH_pointeur_right:				.long		LZH_right
LZH_pointeur_left:				.long		LZH_left
LZH_pointeur_c_table:			.long		LZH_c_table
LZH_pointeur_c_len:				.long		LZH_c_len
LZH_LZH_pointeur_fin_pt_len:	.long		LZH_fin_pt_len
LZH_adresse_debut_datas_packees:	.long	0

LZH_c_len_plus_NC:				.long		LZH_c_len+NC

LZH_offset_debut_datas_packees:		.long	0
LZH_offset_fin_de_fichier_packe:	.long	0
LZH_adresse_fin_de_fichier_packe:	.long	0

LZH_valeur_NC:			.long	NC

LZH_c_len:					.skip	NC
LZH_FIN_C_LEN:
	.p2align 4

LZH_pt_len:					.skip	NPT
.p2align 4

LZH_fin_pt_len:

LZH_avail_mt:				.long	0
LZH_nchar:					.long	0
LZH_tablebits:				.long	0
LZH_table:					.long	0
LZH_restbits:				.long	0
	.p2align 4
	
; words,longs...
LZH_packsize:		.long	0
LZH_origsize:		.long	0
LZH_fnptr:			.long	0
LZH_inpptr:			.long	0
LZH_filetime:		.long	0
LZH_origsize_CRC:	.long	0
;LZH_orgcrc:			.long	0
;LZH_infile:			.long	0
;LZH_outfile:		.long	0
;LZH_curcrc:			.long	0

LZH_save_adr_retour:		.long	0
LZH_bitbuf:			.long	0				; $8004
LZH_subbitbuf:		.long	0				; $8008
LZH_bitcount:		.long	0				; $800C



LZH_blocksize:		.long	0

;LZH_crctbl:			.skip	$100*2



LZH_inpbuf:			.skip	BufSiz
	.p2align 4
LZH_left:					.skip	4*2*NC-1
.p2align 4
LZH_right:					.skip	4*2*NC-1
.p2align 4
LZH_c_table:				.skip	4096*4
.p2align 4
LZH_pt_table:				.skip	256*8
.p2align 4
LZH_crctbl:	
	.skip	256*4

	.skip			50*4
LZH_stack:
	.long			0
	.p2align 4





; --------------------------------------------------------
;  Variables PSG YM2149
; --------------------------------------------------------
; table de pointeurs mémoires vers les digidrums. 32 entrées * 2 : pointeur mémoire, longueur
PSG_table_pointeurs_digidrums:
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1

PSG_table_MFP:
	.include	"table_increments_MFP_20833.asm"
	.p2align	2

.long           0x9c, 0x9b, 0x9b, 0x9a, 0x99, 0x99, 0x98, 0x98

PSG_base_enveloppe:
; enveloppes non depliées, 32*2*16
	.include	"PSG_table_env.asm"
	.p2align	2

PSG_table_de_frequences:
	.include	"PSG_table_freq_20800.asm"
	.p2align	2

;sample1:
;	.incbin		"C:\Users\Public\Documents\Amiga Files\WinUAE\pleasew.bin"
;	.skip		1784

YM6packed:
	;.incbin		"Wings of Death 0 - loading.ym"
	;.incbin		"Wings of Death 6 - level 5.ym"
	;.incbin		"Wings of Death 5 - level 4.ym"
	;.incbin		"Leaving Teramis 11 - title.ym"
	.incbin			"Life's a Bitch - Ak screen.ym"
	
FIN_YM6packed:
	.p2align	2
	

;lin2logtab:		.skip		256
;	.p2align	2
	
;PSG_liste_des_tables_de_volume:
;	.skip		16*4
;	.p2align	2
;PSG_buffer_tables_volumes:
;	.skip		nb_octets_par_vbl*16
;	.p2align	2
	
;PSG_buffer_Noise_de_base:
;	.skip		16384
;	.p2align	2
;PSG_buffer_Noise_calcule_pour_cette_VBL:
;	.skip		nb_octets_par_vbl
;	.p2align	2
;PSG_liste_pointeurs_enveloppes_depliees:
;	.skip		4*16
;	.p2align	2
;PSG_buffer_enveloppes_depliees:
;	.skip		16*86*32
;	.p2align	2
;PSG_buffer_destination_mixage_Noise_channel_A:
;	.skip		nb_octets_par_vbl
;	.p2align	2
;PSG_buffer_destination_mixage_Noise_channel_B:
;	.skip		nb_octets_par_vbl
;	.p2align	2
;PSG_buffer_destination_mixage_Noise_channel_C:
;	.skip		nb_octets_par_vbl
;	.p2align	2
;PSG_buffer_enveloppe_calculee_pour_cette_VBL:
;	.skip		nb_octets_par_vbl
;	.p2align	2
;PSG_buffer_destination_mixage_Digidrum_channel_A:
;	.skip		nb_octets_par_vbl
;	.p2align	2
;PSG_buffer_destination_mixage_Digidrum_channel_B:
;	.skip		nb_octets_par_vbl
;	.p2align	2
;PSG_buffer_destination_mixage_Digidrum_channel_C:
;	.skip		nb_octets_par_vbl
;	.p2align	2

	
FIN_DATA: