; player YM7
;
; nouvelle version du player YM
; utilisation d'un registre pour valeurs relatives
;
; decompression LZ4 uniquement, pas de LZH
;
; OK - gérer les blocs lors de la lecture des registres + création table des blocs : pointeur vers adresse du bloc + ecart entre registres pour ce bloc   / + numéro bloc en cours + nb de blocs
; OK gérer digidrums : init
; OK gérer digidrums : replay
; OK gérer SID : init
; OK gérer SID : replay
; OK gérer Sync buzzer : init
; OK gérer Sync buzzer : replay
; OK passer à 2 voies 
; OK passer à 4 voies 
; OK bug sur buzzer vers 3 minutes / bouclage taille du dernier bloc LZ4
; OK division pour bouclage SID
; OK gérer Sinus SID : init
; OK gérer Sinus SID : replay - jamais de bouclage
; OK gérer le tout sur des fréquences <> de 50 hz
; OK verifier bouclage musique OK 
; - optimiser l'ensemble
;	- déboucler un peu : *16 / *4 / *1
;	- mixage Sinus sid = ne lire des octets que si nécessaire
;	- reflechir a la meme chose ailleurs ?


.equ		taille_totale_BSS,	256+(16*4)+(nb_octets_par_vbl*16)+16384+nb_octets_par_vbl+(4*16)+(16*86*32)+nb_octets_par_vbl+nb_octets_par_vbl+nb_octets_par_vbl+nb_octets_par_vbl

.equ		DEBUG,				1								; 1=debug, pas de RM, Risc OS ON, buffers DMAs plus loin pour laisser la place pour Qdbug
.equ		VOLUMES_ORIGINE,	0								; 1=volumes d'origine limités à 0x55
.equ		longueur_du_sample,				75851

; parametrage 
.equ		frequence_replay,	31250							; 20833 / 31250 / 62500
.equ		nombre_de_voies,	4
.if frequence_replay = 20833	
	.equ		nb_octets_par_vbl,	416								; 416 : 416x50.0801282 = 20 833,333
	.equ		nb_octets_par_vbl_fois_nb_canaux,	nb_octets_par_vbl*nombre_de_voies
	.equ		ms_freq_Archi,		48								; 48 : 1 000 000 / 48 = 20 833,333
	.equ		ms_freq_Archi_div_4_pour_registre_direct,		ms_freq_Archi/4
.endif

.if frequence_replay = 31250	
	.equ		nb_octets_par_vbl,	624								; 624x50.0801282 = 31Â 249,9999968
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

.if	nombre_de_voies = 8
	;.equ		nb_octets_par_vbl_fois_nb_canaux,	nb_octets_par_vbl*8
	.equ		ms_freq_Archi_div_8_pour_registre_direct,		ms_freq_Archi/8
.endif


.equ		nb_octets_par_vbl_fois_16,		nb_octets_par_vbl*16	

.equ		valeur_remplissage_buffer1_default, 0
.equ		valeur_remplissage_buffer2_default, 0

.equ YM2149_frequence, 2000000							; 2 000 000 = Atari ST , 1 000 000 Hz = Amstrad CPC, 1 773 400 Hz = ZX spectrum 

.include "swis.h.asm"

.equ	YM2149_shift_onde_carre_SID, 15
.equ	YM2149_shift_onde_carre_Tone, 16
.equ	YM2149_shift_Buzzer, 16


; DEBUG YM
.equ	YM_decalage_debut_YM_pour_debug, 0					;50*42
.equ	YM_stop_avancement_player, 0

	.org 0x8000
	
main:
	mov		R0,#131072				; New size of current slot
	mov		R1,#-1				;  	New size of next slot
	SWI		Wimp_SlotSize			; Wimp_SlotSize 



	SWI		0x01
	.if frequence_replay = 20833
		.byte	"-20.8 Khz YM7 replay- ",0
	.endif
	.if frequence_replay = 31250	
		.byte	"-31.2 Khz YM7 replay- ",0
	.endif	
	.if frequence_replay = 62500	
		.byte	"-62.5 Khz YM7 replay- ",0
	.endif
	.p2align 2

	SWI		0x01
	.if nombre_de_voies = 2
		.byte	"2 voices",13,10,0
	.endif
	.if nombre_de_voies = 4	
		.byte	"4 voices",13,10,0
	.endif	
	.if nombre_de_voies = 8	
		.byte	"8 voices",13,10,0
	.endif
	.p2align 2

	
	str		R13,pointeur_stack_OS

; set sound volume
	mov		R0,#127							; maxi 127
	SWI		XSound_Volume	


	bl		allocation_memoire_buffers
	
; init du YM2149
	bl		PSG_creer_tables_volumes
	bl		PSG_creer_Noise_de_base
	bl		PSG_etendre_enveloppes

	bl		create_table_lin2log

	ldr		R0,PSG_pointeur_fichier_YM7_haut
	bl		init_fichier_YM7


; init sound system Archimedes
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

; allocations buffers dans la mÃ©moire basse + calcul des adresses rÃ©elles
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

; rÃ©sultat valuers par dÃ©faut : 01,0xD0,0x30,0x01F04040,0x01815CD4
	
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

	.if		nombre_de_voies=8
	bl		set_my_stereos_8voies
	.endif
	.if		nombre_de_voies=4
	bl		set_my_stereos
	.endif
	.if		nombre_de_voies=2
	bl		set_my_stereos_2voies
	.endif



	MOV       R0,#0							;  	Channels for 8 bit sound
	MOV       R1,#0						; Samples per channel (in bytes)
	MOV       R2,#0						; Sample period (in microseconds per channel) 
	MOV       R3,#0
	MOV       R4,#0
	SWI       XSound_Configure						;"Sound_Configure"
	MUL       R0,R1,R0

	.if		nombre_de_voies=8
	bl		set_my_stereos_8voies
	.endif
	.if		nombre_de_voies=4
	bl		set_my_stereos
	.endif
	.if		nombre_de_voies=2
	bl		set_my_stereos_2voies
	.endif
		

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
	SWI		22
	MOVNV R0,R0
	bl		set_dma_dma1
	teqp  r15,#0                     
	mov   r0,r0	
	bl		swap_pointeurs_dma_son	

	SWI		22
	MOVNV R0,R0  

; write memc control register, start sound

	ldr		R0,memc_control_register_original	
	orr		R0,R0,#0b100000000000
	str		R0,[R0]


	teqp  r15,#0                     
	mov   r0,r0 

; je n'ai pas d'octets qui restent à produire sans replay
	ldr		R12,PSG_pointeur_structure_PSG_haut
	mov		R0,#0
	str		R0,[R12,#PSG_nb_octet_restant_avant_prochain_replay_complet-PSG_structure_PSG]


;------------------------------------------------ boucle centrale VBL

boucle:
	bl		affiche_ligne_infos


; gestion de frequence differente de 50 HZ
; on demarre un nouveau buffer DMA audio
	ldr		R12,PSG_pointeur_structure_PSG_haut

; on se met au debut du buffer DMA
	ldr		R0,[R12,#adresse_dma1_logical-PSG_structure_PSG]
	str		R0,[R12,#PSG_pointeur_position_actuelle_remplissage_buffer_DMA_audio_VBL-PSG_structure_PSG]
	
	mov		R0,#nb_octets_par_vbl
	str		R0,[R12,#PSG_nb_octets_pour_cette_VBL-PSG_structure_PSG]

	ldr		R2,[R12,#PSG_nb_octet_restant_avant_prochain_replay_complet-PSG_structure_PSG]
	cmp		R2,#0
	beq		boucle_principale_il_ne_reste_pas_d_octets_du_precedent_replay

; nb octets a produire = octets du precedent replay
	str		R2,[R12,#PSG_nb_octet_a_produire-PSG_structure_PSG]
; on met a zero le nb d ocets a produire sans replay
	mov		R1,#0
	str		R1,[R12,#PSG_nb_octet_restant_avant_prochain_replay_complet-PSG_structure_PSG]
; on saute pour les produire sans replay
	b		mixage_PSG_sans_replay

boucle_replay:
boucle_principale_il_ne_reste_pas_d_octets_du_precedent_replay:

	ldr		R12,PSG_pointeur_structure_PSG_haut

	ldr		R0,[R12,#PSG_nb_octets_pour_cette_VBL-PSG_structure_PSG]
	ldr		R1,[R12,#PSG_nb_octet_par_run_de_replay-PSG_structure_PSG]
	
	cmp		R0,R1
	bgt		boucle_replay_il_faut_produire_un_replay_entier
; on doit produire uniquement PSG_nb_octets_pour_cette_VBL
	str		R0,[R12,#PSG_nb_octet_a_produire-PSG_structure_PSG]
	
	subs	R2,R1,R0			; R2 = nb octet par run de replay - nb octets restant pour cette VBL
	str		R2,[R12,#PSG_nb_octet_restant_avant_prochain_replay_complet-PSG_structure_PSG]
		
	b		boucle_replay_il_faut_produire_un_replay_partiel

boucle_replay_il_faut_produire_un_replay_entier:
; on doit produire nb octet par run
	str		R1,[R12,#PSG_nb_octet_a_produire-PSG_structure_PSG]

boucle_replay_il_faut_produire_un_replay_partiel:


	.ifeq	1
	mov		R0,#5750
boucle_attente:
	mov		R0,R0
	subs	R0,R0,#1
	bgt		boucle_attente
	.endif

; +++++ROUGE VIF
	SWI		22
	MOVNV R0,R0            

	mov   r0,#0x3400000               
	mov   r1,#0x0F
; border	
	orr   r1,r1,#0x40000000              
	str   r1,[r0]                     

	teqp  r15,#0                     
	mov   r0,r0	

; on fait tout ici

; routines en VBL

	bl		lecture_registres_player_VBL_YM7									; lecture des données pour les registres YM / YM7

; ++++++++++++++++++++++++++++++++++++++++++++++++
; ------++++ mixage sans replay +++++-------------
; ++++++++++++++++++++++++++++++++++++++++++++++++
mixage_PSG_sans_replay:

; +++++VERT VIF	
		SWI		22
	MOVNV R0,R0            

	mov   r0,#0x3400000               
	mov   r1,#0XF0
; border	
	orr   r1,r1,#0x40000000              
	str   r1,[r0]                     

	teqp  r15,#0                     
	mov   r0,r0	
	
	bl		PSG_interepretation_registres

; +++++BLEU VIF		
		SWI		22
	MOVNV R0,R0            

	mov   r0,#0x3400000               
	mov   r1,#0xF00
; border	
	orr   r1,r1,#0x40000000              
	str   r1,[r0]                     

	teqp  r15,#0                     
	mov   r0,r0	
	
	
	bl		PSG_fabrication_Noise_pour_cette_VBL								; fabrique un noise avec la bonne frequence pour cette VBL

; +++++BLANC VIF
	SWI		22
	MOVNV R0,R0            

	mov   r0,#0x3400000               
	mov   r1,#0xFFF
; border	
	orr   r1,r1,#0x40000000              
	str   r1,[r0]                     

	teqp  r15,#0                     
	mov   r0,r0	


	bl		PSG_mixage_Noise_et_Tone_voie_A										; mixe onde carrÃ©e Ã  la bonne frÃ©quence et noise fabriquÃ© Ã  la bonne frÃ©quence
	bl		PSG_mixage_Noise_et_Tone_voie_B
	bl		PSG_mixage_Noise_et_Tone_voie_C

; +++++ROSE VIF
	SWI		22
	MOVNV R0,R0            

	mov   r0,#0x3400000               
	mov   r1,#0xF0F
; border	
	orr   r1,r1,#0x40000000              
	str   r1,[r0]                     

	teqp  r15,#0                     
	mov   r0,r0	

	bl		PSG_preparation_enveloppe_pour_la_VBL								; crÃ©er une enveloppe Ã  la bonne frÃ©quence en fonction de la forme choisie

; +++++CYAN bleu clair
	SWI		22
	MOVNV R0,R0            

	mov   r0,#0x3400000               
	mov   r1,#0xFF0
; border	
	orr   r1,r1,#0x40000000              
	str   r1,[r0]                     

	teqp  r15,#0                     
	mov   r0,r0	

	bl		PSG_creation_buffer_effet_digidrum_ou_Sid_channel_A
	bl		PSG_creation_buffer_effet_digidrum_ou_Sid_channel_B
	bl		PSG_creation_buffer_effet_digidrum_ou_Sid_channel_C

; 220=JAUNE
	SWI		22
	MOVNV R0,R0            

	mov   r0,#0x3400000               
	mov   r1,#220
; border	
	orr   r1,r1,#0x40000000              
	str   r1,[r0]                     

	teqp  r15,#0                     
	mov   r0,r0	

	
	bl		PSG_mixage_final

; 330=ORANGE
	SWI		22
	MOVNV R0,R0            

	mov   r0,#0x3400000               
	mov   r1,#330
; border	
	orr   r1,r1,#0x40000000              
	str   r1,[r0]                     

	teqp  r15,#0                     
	mov   r0,r0	


	bl		PSG_fill_dma_buffer_voice4_Sinus_Sid

	ldr		R12,PSG_pointeur_structure_PSG_haut
	ldr		R2,[R12,#PSG_nb_octet_a_produire-PSG_structure_PSG]
	ldr		R1,[R12,#PSG_nb_octets_pour_cette_VBL-PSG_structure_PSG]
	
	subs	R1,R1,R2			; R1 = nb octets pour cette VBL - ceux qui viennent d'etre produits
	beq		on_a_fini_le_buffer_dma
	
	str		R1,[R12,#PSG_nb_octets_pour_cette_VBL-PSG_structure_PSG]
	
	b		boucle_replay

;- fin de la boucle de mixage / replay PSG

on_a_fini_le_buffer_dma:


; on swap aprÃ¨s
	SWI		22
	MOVNV R0,R0
	bl		set_dma_dma1
	teqp  r15,#0                     
	mov   r0,r0	
	bl		swap_pointeurs_dma_son


; --- remet le fond en noir
	SWI		22
	MOVNV R0,R0            

	mov   r0,#0x3400000               
	mov   r1,#0x000  
; border	
	orr   r1,r1,#0x40000000               
	str   r1,[r0]  

	teqp  r15,#0                     
	mov   r0,r0		

; --------------



	
	
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


	
exit_final:	
; liberer la ram
	ldr		R0,ancienne_taille_alloc_memoire_current_slot 	; New size of current slot
	mov		R1,#-1											;  	New size of next slot
	SWI		Wimp_SlotSize										; Wimp_SlotSize 


; sortie
	MOV R0,#0
	SWI OS_Exit	


backup_params_sons:	
	.long		0
	.long		0
	.long		0
	.long		0
	.long		0
	.long		0

memc_control_register_original:			.long	0

PSG_pointeur_fichier_YM7_haut:			.long		YM7packed


pointeur_stack_OS:		.long		0

; --------------------------------------------------------
;
;    routines standards
;
; --------------------------------------------------------

; --------------------------------------------------------
; routine de division 
; R0 = R1 / R2
; en sortie:
;  - R1=reste
;  - R2=diviseur
;  - R0=resultat

routine_division_R0_egal_R1_divise_par_R2_saveR3:			.long		0
;-----+-+-+-+-
routine_division_R0_egal_R1_divise_par_R2:

	str		R3,routine_division_R0_egal_R1_divise_par_R2_saveR3

	MOV      R0,#0     			; clear R0 to accumulate result
	MOV      R3,#1     			; set bit 0 in R3, which will be
								; shifted left then right
routine_division_R0_egal_R1_divise_par_R2_startdivY:
	CMP      R2,R1
	MOVLS    R2,R2,LSL#1
	MOVLS    R3,R3,LSL#1
	BLS      routine_division_R0_egal_R1_divise_par_R2_startdivY
								;shift R2 left until it is about to
								;be bigger than R1
								;shift R3 left in parallel in order
								;to flag how far we have to go

routine_division_R0_egal_R1_divise_par_R2_nextdivY:
	CMP       R1,R2     				;carry set if R11&gt;R13 (don't ask why)
	SUBCS     R1,R1,R2  				;subtract R2 from R1 if this would
										;give a positive answer
	ADDCS     R0,R0,R3  				;and add the current bit in R3 to
										;the accumulating answer in R0

	MOVS      R3,R3,LSR #1    			;Shift R3 right into carry flag
	MOVCC     R2,R2,LSR #1     			;and if bit 0 of R3 was zero, also
										;shift R13 right
	BCC       routine_division_R0_egal_R1_divise_par_R2_nextdivY            ;If carry not clear, R3 has shifted
																			;back to where it started, and we
	ldr		R3,routine_division_R0_egal_R1_divise_par_R2_saveR3																		;can end

	mov		pc,lr
;-----+-+-+-+-


; --------------------------------------------------------
allocation_memoire_buffers:
	mov		R0,#-1				; New size of current slot
	mov		R1,#-1				;  	New size of next slot
	SWI		Wimp_SlotSize			; Wimp_SlotSize 
	str		R0,ancienne_taille_alloc_memoire_current_slot
	
	;R2 = taille mÃ©moire dispo

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

; alloc mÃ©moire
	ldr		R12,PSG_pointeur_structure_PSG_haut
; clean la mÃ©moire :
	ldr		R0,[R12,#pointeur_FIN_DATA_actuel-PSG_structure_PSG]
	ldr		R2,valeur_taille_memoire
	add		R1,R0,R2				; de R0 Ã  R1 Ã  mettre Ã  zÃ©ro
	mov		R2,#0
boucle_clean_memory_bss:
	strb	R2,[R0],#1
	cmp		R0,R1
	bne		boucle_clean_memory_bss


	ldr		R12,PSG_pointeur_structure_PSG_haut

	ldr		R0,[R12,#pointeur_FIN_DATA_actuel-PSG_structure_PSG]
	str		R0,[R12,#pointeur_table_lin2logtab-PSG_structure_PSG]
	add		R0,R0,#256
	str		R0,[R12,#PSG_pointeur_liste_des_tables_de_volume-PSG_structure_PSG]
	add		R0,R0,#64
	str		R0,[R12,#PSG_pointeur_buffer_tables_volumes-PSG_structure_PSG]
	add		R0,R0,#nb_octets_par_vbl_fois_16
	str		R0,[R12,#PSG_pointeur_buffer_Noise_de_base-PSG_structure_PSG]
	add		R0,R0,#16384
	str		R0,[R12,#PSG_pointeur_buffer_Noise_calcule_pour_cette_VBL-PSG_structure_PSG]
	add		R0,R0,#nb_octets_par_vbl
	str		R0,[R12,#PSG_pointeur_sur_table_liste_des_enveloppes_depliees-PSG_structure_PSG]
	add		R0,R0,#64
	str		R0,[R12,#PSG_pointeur_buffer_enveloppes_depliees-PSG_structure_PSG]
	add		R0,R0,#44032
	str		R0,[R12,#PSG_pointeur_buffer_destination_mixage_Noise_channel_A-PSG_structure_PSG]
	add		R0,R0,#nb_octets_par_vbl
	str		R0,[R12,#PSG_pointeur_buffer_destination_mixage_Noise_channel_B-PSG_structure_PSG]
	add		R0,R0,#nb_octets_par_vbl
	str		R0,[R12,#PSG_pointeur_buffer_destination_mixage_Noise_channel_C-PSG_structure_PSG]
	add		R0,R0,#nb_octets_par_vbl
	str		R0,[R12,#PSG_pointeur_buffer_enveloppe_calculee_pour_cette_VBL-PSG_structure_PSG]
	add		R0,R0,#nb_octets_par_vbl
	str		R0,[R12,#PSG_pointeur_buffer_destination_mixage_Digidrum_channel_A-PSG_structure_PSG]
	add		R0,R0,#nb_octets_par_vbl
	str		R0,[R12,#PSG_pointeur_buffer_destination_mixage_Digidrum_channel_B-PSG_structure_PSG]
	add		R0,R0,#nb_octets_par_vbl
	str		R0,[R12,#PSG_pointeur_buffer_destination_mixage_Digidrum_channel_C-PSG_structure_PSG]
	add		R0,R0,#nb_octets_par_vbl
	str		R0,[R12,#pointeur_FIN_DATA_actuel-PSG_structure_PSG]

	mov		pc,lr

ancienne_taille_alloc_memoire_current_slot:		.long		0
valeur_taille_memoire:	.long		taille_totale_BSS
PSG_pointeur_structure_PSG_haut:			.long		PSG_structure_PSG	
; --------------------------------------------------------
mes_stereos_4voies:
			.byte		-79,79,47,-47,-79,79,47,-47
			.p2align	3

mes_stereos_2voies:
			.byte		-79,79,-79,79,-79,79,-79,79
			.p2align	3
stockage_stereos:			.long		0,0

; steros pour 4 voies
set_my_stereos:
	MOV     R0,#1
	adr		R2,mes_stereos_4voies

set_mes_stloop:
	LDRB	R1,[R2,R0]
	MOV     R1,R1,LSL#24
	MOV     R1,R1,ASR#24
	SWI     XSound_Stereo
	ADD     R0,R0,#1
	
	CMP     R0,#8
	BLE     set_mes_stloop
	mov		pc,lr	


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

; steros pour 8 voies
	.if			nombre_de_voies=8

mes_stereos_8voies:
			.byte		-79,79,47,-47,-63,63,24,-24

set_my_stereos_8voies:
	MOV     R0,#1
	adr		R2,mes_stereos_8voies

set_mes_stloop_8voies:
	LDRB	R1,[R2,R0]
	MOV     R1,R1,LSL#24
	MOV     R1,R1,ASR#24
	SWI     XSound_Stereo
	ADD     R0,R0,#1
	
	CMP     R0,#8
	BLE     set_mes_stloop_8voies
	mov		pc,lr	
	.endif


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
	ldr		R12,PSG_pointeur_structure_PSG_haut
	ldr		  R3,[R12,#adresse_dma1_memc-PSG_structure_PSG]
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

	ldr		R12,PSG_pointeur_structure_PSG_haut

	ldr		R8,[R12,#adresse_dma1_memc-PSG_structure_PSG]
	ldr		R9,[R12,#adresse_dma2_memc-PSG_structure_PSG]
	str		R8,[R12,#adresse_dma2_memc-PSG_structure_PSG]
	str		R9,[R12,#adresse_dma1_memc-PSG_structure_PSG]
	
	ldr		R8,[R12,#adresse_dma1_logical-PSG_structure_PSG]
	ldr		R9,[R12,#adresse_dma2_logical-PSG_structure_PSG]
	str		R8,[R12,#adresse_dma2_logical-PSG_structure_PSG]
	str		R9,[R12,#adresse_dma1_logical-PSG_structure_PSG]

	mov		pc,lr	

clear_dma_buffers:
; on met Ã  zÃ©ro les buffers DMA en superviseur

	;SWI		22
	;MOVNV R0,R0  
	ldr		R12,PSG_pointeur_structure_PSG_haut
	
	ldr		R1,[R12,#pointeur_adresse_dma1_logical-PSG_structure_PSG]
	ldr		R1,[R1]
	mov		R2,#nb_octets_par_vbl*2					; buffer 1 
	mov		R0,#valeur_remplissage_buffer1_default
boucle_cls_buffer_dma1:
	strb	R0,[R1],#1
	subs	R2,R2,#1
	bgt		boucle_cls_buffer_dma1

	ldr		R1,[R12,#pointeur_adresse_dma2_logical-PSG_structure_PSG]
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
	ldr		R12,PSG_pointeur_structure_PSG_haut

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
	add		R0,R0,R10		; au bout de la mÃ©moire video, le buffer dma
	str		R0,fin_de_la_memoire_video
	
	;add		R0,R0,#4096
	.if		DEBUG=1
	add		R0,R0,#65536
	add		R0,R0,#65536
	.endif
	
	ldr		R2,[R12,#pointeur_adresse_dma1_logical-PSG_structure_PSG]
	str		R0,[R2]

	add		R1,R0,#8192

	ldr		R2,[R12,#pointeur_adresse_dma2_logical-PSG_structure_PSG]
	str		R1,[R2]

		ldr		R6,[R12,#pointeur_adresse_dma1_logical-PSG_structure_PSG]
		ldr		R6,[R6]
		ldr		R5,[R12,#pointeur_adresse_dma2_logical-PSG_structure_PSG]
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
		ldr		R10,[R12,#pointeur_adresse_dma2_memc-PSG_structure_PSG]
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
		ldr		R10,[R12,#pointeur_adresse_dma1_memc-PSG_structure_PSG]
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

fin_de_la_memoire_video:	.long		0
taille_actuelle_memoire_ecran:			.long		0

PSG_pointeur_PSG_aff_infos_dizaines_minutes:		.long			PSG_aff_infos_dizaines_minutes
affiche_ligne_infos:


	ldr		R10,PSG_pointeur_PSG_aff_infos_dizaines_minutes
	ldr		R0,PSG_aff_infos_compteur
	add		R0,R0,#1
	cmp		R0,#50
	bne		affiche_ligne_infos_pas_plus_de_secondes

	mov		R0,#0
	ldrb	R1,PSG_aff_infos_unites_secondes			; de 0 à 9 : de 48 a 57
	add		R1,R1,#1
	cmp		R1,#58
	bne		affiche_ligne_infos_pas_plus_de_dizaines_de_secondes
	mov		R1,#48
	ldrb	R2,PSG_aff_infos_dizaines_secondes			; de 0 à 9 : de 48 a 57
	add		R2,R2,#1
	cmp		R2,#54
	bne		affiche_ligne_infos_pas_plus_de_minutes
	mov		R2,#48
	ldrb	R3,PSG_aff_infos_unites_minutes			; de 0 à 9 : de 48 a 57
	add		R3,R3,#1
	cmp		R3,#58
	bne		affiche_ligne_infos_pas_plus_de_dizaines_de_minutes
	mov		R3,#48
	ldrb	R4,PSG_aff_infos_dizaines_minutes			; de 0 à 9 : de 48 a 57
	add		R4,R4,#1
	cmp		R4,#54
	bne		affiche_ligne_infos_pas_plus_de_centaines_de_minutes
	mov		R4,#48

affiche_ligne_infos_pas_plus_de_centaines_de_minutes:
	strb	R4,PSG_aff_infos_dizaines_minutes
affiche_ligne_infos_pas_plus_de_dizaines_de_minutes:
	strb	R3,PSG_aff_infos_unites_minutes
affiche_ligne_infos_pas_plus_de_minutes:
	strb	R2,PSG_aff_infos_dizaines_secondes
affiche_ligne_infos_pas_plus_de_dizaines_de_secondes:
	strb	R1,PSG_aff_infos_unites_secondes

affiche_ligne_infos_pas_plus_de_secondes:
	str		R0,PSG_aff_infos_compteur





	ldr		R12,PSG_pointeur_structure_PSG_haut

	adr		R1,PSG_aff_voie_A
	add		R1,R1,#PSG_aff_infos_Tone_A-PSG_aff_voie_A
	ldr		R0,[R12,#PSG_flag_Tone_voie_A-PSG_structure_PSG]
	cmp		R0,#0
	movne	R0,#84					; T
	moveq	R0,#32
	;adr		R1,PSG_aff_infos_Tone_A
	strb	R0,[R1]
	ldr		R0,[R12,#PSG_flag_Noise_voie_A-PSG_structure_PSG]
	cmp		R0,#0
	movne	R0,#78					; N
	moveq	R0,#32
	add		R1,R1,#PSG_aff_infos_Noise_A-PSG_aff_infos_Tone_A
	;adr		R1,PSG_aff_infos_Noise_A
	strb	R0,[R1]
	ldr		R0,[R12,#PSG_flag_Env_voie_A-PSG_structure_PSG]
	cmp		R0,#0
	movne	R0,#69					; E
	moveq	R0,#32
	add		R1,R1,#PSG_aff_infos_Env_A-PSG_aff_infos_Noise_A
	;adr		R1,PSG_aff_infos_Env_A
	strb	R0,[R1]
	ldr		R0,[R12,#PSG_flag_SID_voie_A-PSG_structure_PSG]
	cmp		R0,#0
	movne	R0,#83					; S
	moveq	R0,#32
	add		R1,R1,#PSG_aff_infos_SID_A-PSG_aff_infos_Env_A
	;adr		R1,PSG_aff_infos_SID_A
	strb	R0,[R1]
	ldr		R0,[R12,#PSG_flag_digidrum_voie_A-PSG_structure_PSG]
	cmp		R0,#0
	movne	R0,#68
	moveq	R0,#32
	adr		R1,PSG_aff_infos_Digidrums_A
	strb	R0,[R1]


	
	ldr		R0,[R12,#PSG_flag_Tone_voie_B-PSG_structure_PSG]
	cmp		R0,#0
	movne	R0,#84					; T
	moveq	R0,#32
	;adr		R1,PSG_aff_infos_Tone_B
	add		R1,R1,#PSG_aff_infos_Tone_B-PSG_aff_infos_SID_A
	strb	R0,[R1]
	ldr		R0,[R12,#PSG_flag_Tone_voie_C-PSG_structure_PSG]
	cmp		R0,#0
	movne	R0,#84					; T
	moveq	R0,#32
	;adr		R1,PSG_aff_infos_Tone_C
	add		R1,R1,#PSG_aff_infos_Tone_C-PSG_aff_infos_Tone_B
	strb	R0,[R1]

	ldr		R0,[R12,#PSG_flag_Noise_voie_B-PSG_structure_PSG]
	cmp		R0,#0
	movne	R0,#78					; N
	moveq	R0,#32
	adr		R1,PSG_aff_infos_Noise_B
	strb	R0,[R1]
	ldr		R0,[R12,#PSG_flag_Noise_voie_C-PSG_structure_PSG]
	cmp		R0,#0
	movne	R0,#78					; N
	moveq	R0,#32
	adr		R1,PSG_aff_infos_Noise_C
	strb	R0,[R1]


	ldr		R0,[R12,#PSG_flag_Env_voie_B-PSG_structure_PSG]
	cmp		R0,#0
	movne	R0,#69					; E
	moveq	R0,#32
	adr		R1,PSG_aff_infos_Env_B
	strb	R0,[R1]
	ldr		R0,[R12,#PSG_flag_Env_voie_C-PSG_structure_PSG]
	cmp		R0,#0
	movne	R0,#69					; E
	moveq	R0,#32
	adr		R1,PSG_aff_infos_Env_C
	strb	R0,[R1]

	ldr		R0,[R12,#PSG_flag_SID_voie_B-PSG_structure_PSG]
	cmp		R0,#0
	movne	R0,#83					; S
	moveq	R0,#32
	adr		R1,PSG_aff_infos_SID_B
	strb	R0,[R1]
	ldr		R0,[R12,#PSG_flag_SID_voie_C-PSG_structure_PSG]
	cmp		R0,#0
	movne	R0,#83					; S
	moveq	R0,#32
	adr		R1,PSG_aff_infos_SID_C
	strb	R0,[R1]


	ldr		R0,[R12,#PSG_flag_digidrum_voie_B-PSG_structure_PSG]
	cmp		R0,#0
	movne	R0,#68
	moveq	R0,#32
	adr		R1,PSG_aff_infos_Digidrums_B
	strb	R0,[R1]
	ldr		R0,[R12,#PSG_flag_digidrum_voie_C-PSG_structure_PSG]
	cmp		R0,#0
	movne	R0,#68
	moveq	R0,#32
	adr		R1,PSG_aff_infos_Digidrums_C
	strb	R0,[R1]

	ldr		R0,[R12,#PSG_flag_buzzer-PSG_structure_PSG]
	cmp		R0,#0
	movne	R0,#66			; "B"
	moveq	R0,#32
	adr		R1,PSG_aff_infos_Buzzer
	strb	R0,[R1]

	ldr		R0,[R12,#PSG_flag_Sinus_Sid-PSG_structure_PSG]
	cmp		R0,#0
	movne	R0,#83		; "S"
	moveq	R0,#32
	adr		R1,PSG_aff_infos_Sinus
	strb	R0,[R1]

	

; affichage texte infos:
PSG_aff_voie_A:
	SWI		0x01
	.byte	"(A) "
PSG_aff_infos_Tone_A:
	.byte 	"T "
PSG_aff_infos_Noise_A:
	.byte	"N "
PSG_aff_infos_Env_A:
	.byte	"E "
PSG_aff_infos_SID_A:
	.byte	"S "
PSG_aff_infos_Digidrums_A:
	.byte	"D"

	.byte	"    (B) "
PSG_aff_infos_Tone_B:
	.byte 	"T "
PSG_aff_infos_Noise_B:
	.byte	"N "
PSG_aff_infos_Env_B:
	.byte	"E "
PSG_aff_infos_SID_B:
	.byte	"S "
PSG_aff_infos_Digidrums_B:
	.byte	"D"

	.byte	"    (C) "
PSG_aff_infos_Tone_C:
	.byte 	"T "
PSG_aff_infos_Noise_C:
	.byte	"N "
PSG_aff_infos_Env_C:
	.byte	"E "
PSG_aff_infos_SID_C:
	.byte	"S "
PSG_aff_infos_Digidrums_C:
	.byte	"D   -  "
PSG_aff_infos_Buzzer:
	.byte	"B "
PSG_aff_infos_Sinus:
	.byte	"    "
PSG_aff_infos_dizaines_minutes:
	.byte	"0"
PSG_aff_infos_unites_minutes:
	.byte	"0'"
PSG_aff_infos_dizaines_secondes:
	.byte	"0"
PSG_aff_infos_unites_secondes:
	.byte	"0"
	
	.byte	13,0
	.p2align 2
	
	mov		pc,lr
PSG_aff_infos_compteur:			.long		0


mask_sound_off_memc_control_register:		.long		0b011111111111


; --------------------------------------------------------
;
;    routines Init PSG
;
; --------------------------------------------------------



; --------------------------------------------------------	
create_table_lin2log:
	ldr		R12,PSG_pointeur_structure_PSG_haut
	ldr		R11,[R12,#pointeur_table_lin2logtab-PSG_structure_PSG]

 	MOV     R1,#255
setlinlogtab:

	MOV     R0,R1,LSL#24		; R0=R1<<24 : en entrÃ©e du 8 bits donc shiftÃ© en haut, sur du 32 bits
	SWI     XSound_SoundLog		; This SWI is used to convert a signed linear sample to the 8 bit logarithmic format thatâ€™s used by the 8 bit sound system. The returned value will be scaled by the current volume (as set by Sound_Volume).
	STRB    R0,[R11,R1]			; 8 bit mu-law logarithmic sample 
	SUBS    R1,R1,#1
	BGE     setlinlogtab
	mov		pc,lr


; Creer les tables de volumes

PSG_creer_tables_volumes:
	ldr		R12,PSG_pointeur_structure_PSG_haut

	ldr		R0,[R12,#PSG_pointeur_tables_de_16_volumes-PSG_structure_PSG]													; le volume est sur 4 bits dans les registres 8,9 et 10 (A)
	ldr		R1,[R12,#PSG_pointeur_buffer_tables_volumes-PSG_structure_PSG]
	ldr		R2,[R12,#PSG_pointeur_liste_des_tables_de_volume-PSG_structure_PSG]

	mov		R7,#16
PSG_boucle_creer_table_volume1:	
	mov		R6,#nb_octets_par_vbl
	ldrb	R3,[R0],#1				; octet de volume
	str		R1,[R2],#4				; pointeur dÃ©but de la table

PSG_boucle_creer_table_volume2:	
	strb	R3,[R1],#1
	subs	R6,R6,#1
	bgt		PSG_boucle_creer_table_volume2
	subs	R7,R7,#1
	bgt		PSG_boucle_creer_table_volume1
	mov		pc,lr


; --------------------------------------------------------	
; CrÃ©er le Noise de base


PSG_creer_Noise_de_base:
	ldr		R12,PSG_pointeur_structure_PSG_haut
	
	ldr		R9,[R12,#PSG_pointeur_buffer_Noise_de_base-PSG_structure_PSG]
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
; CrÃ©er les enveloppes
; 
; prend les 2 temps de l'enveloppe de base
; Ã©tend le 2eme temps sur 85 fois * 32 octets
; remplit une table de pointeur

PSG_etendre_enveloppes:
	ldr		R12,PSG_pointeur_structure_PSG_haut
	
	ldr		R5,[R12,#PSG_pointeur_sur_table_liste_des_enveloppes_depliees-PSG_structure_PSG]
	ldr		R6,[R12,#PSG_pointeur_buffer_enveloppes_depliees-PSG_structure_PSG]
	ldr		R10,[R12,#PSG_pointeur_enveloppe_base-PSG_structure_PSG]
	mov		R7,#16								; 16 enveloppes Ã  Ã©tendre

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
save_R14_init_YM7:			.long		0
init_fichier_YM7:

	str		R14,save_R14_init_YM7

; R0=adresse fichier YM7
	ldr		R12,PSG_pointeur_structure_PSG_haut

	SWI		0x01
	.byte	"--YM7--",10,13,0
	.p2align 2

; saute "YM7!"+"LeOnArD!"
	add		R0,R0,#12
; saute 02+02 : numéro de version du YM7 ?
	add		R0,R0,#4
	
;  	Nb of frame in the file
	ldrb	R1,[R0],#1
	mov		R1,R1,lsl #24
	ldrb	R2,[R0],#1
	orr		R1,R1,R2,lsl #16
	ldrb	R2,[R0],#1
	orr		R1,R1,R2,lsl #8
	ldrb	R2,[R0],#1
	orr		R1,R1,R2						; R1 = Nb of frame in the file
	str		R1,[R12,#PSG_compteur_frames-PSG_structure_PSG]


init_fichier_YM7_frame_in_hz:
; Original player frame in Hz (traditionnaly 50)
	ldrb	R1,[R0],#1
	mov		R1,R1,lsl #8
	ldrb	R2,[R0],#1
	add		R1,R1,R2						; R1 =  Player frequency in Hz
	str		R1,[R12,#PSG_replay_frequency_HZ-PSG_structure_PSG]
	
; calcul du nb d'octets par run de replay
	mov		R8,R0
	mov		R9,R1
	mov		R10,R14


; vbl archimedes = 50.0801282
; (nb octets * 50) / frequence

	mov		R2,#nb_octets_par_vbl
	mov		R3,#50
	mul		R1,R2,R3
	
	mov		R2,R9

; R0 = R1/R2 / R1=reste
	bl		routine_division_R0_egal_R1_divise_par_R2
	
	str		R0,[R12,#PSG_nb_octet_par_run_de_replay-PSG_structure_PSG]

	mov		R14,R10
	mov		R0,R8
	mov		R1,R9

; R1 = frequence replay HZ

	mov		R8,R0
	mov		R9,R1
	mov		R10,R14

; on divise par 100
	mov		R1,R9			; frequence HZ
	mov		R2,#100
	bl		routine_division_R0_egal_R1_divise_par_R2
	cmp		R0,#0
	beq		init_fichier_YM7_frequence_replay_centaine_egal_zero
	add		R0,R0,#48				;"0"
	strb	R0,init_fichier_YM7_frequence_replay_centaine	

; on divise par 10
init_fichier_YM7_frequence_replay_centaine_egal_zero:
	mov		R2,#10
	
	bl		routine_division_R0_egal_R1_divise_par_R2
; R0=dizaine
; R1=reste/unite
	add		R0,R0,#48				;"0"
	strb	R0,init_fichier_YM7_frequence_replay_dizaine
	add		R1,R1,#48				;"0"
	strb	R1,init_fichier_YM7_frequence_replay_unite

	SWI		0x01
	.byte	"replay : "
init_fichier_YM7_frequence_replay_centaine:
	.byte	" "
init_fichier_YM7_frequence_replay_dizaine:
	.byte	"2"
init_fichier_YM7_frequence_replay_unite:
	.byte	"2 hz.",10,13,0
	.p2align 2

	mov		R14,R10
	mov		R0,R8
	mov		R1,R9
	

; mask effets sur les voies
	ldrb	R1,[R0],#1
	mov		R1,R1,lsl #8
	ldrb	R2,[R0],#1
	add		R1,R1,R2						; R1 =  Player frequency in Hz
	str		R1,[R12,#PSG_flag_effets_global-PSG_structure_PSG]
	
	mov		R2,#1
	
	mov		R8,#14				; nb d'octet par frame = 14 de base = 14 registres
	
	tst		R1,#0b0001			; test voie A
	beq		init_fichier_ym7_pas_d_effet_voie_A
	str		R2,[R12,#PSG_flag_effets_voie_A-PSG_structure_PSG]
	add		R8,R8,#2			; + 2 registres
	SWI		0x01
	.byte	"Sid or DG on voice A.",10,13,0
	.p2align 2

init_fichier_ym7_pas_d_effet_voie_A:
	tst		R1,#0b0010			; test voie B
	beq		init_fichier_ym7_pas_d_effet_voie_B
	str		R2,[R12,#PSG_flag_effets_voie_B-PSG_structure_PSG]
	add		R8,R8,#2			; + 2 registres
	SWI		0x01
	.byte	"Sid or DG on voice B.",10,13,0
	.p2align 2

init_fichier_ym7_pas_d_effet_voie_B:
	tst		R1,#0b0100			; test voie C
	beq		init_fichier_ym7_pas_d_effet_voie_C
	str		R2,[R12,#PSG_flag_effets_voie_C-PSG_structure_PSG]
	add		R8,R8,#2			; + 2 registres
	SWI		0x01
	.byte	"Sid or DG on voice C.",10,13,0
	.p2align 2

init_fichier_ym7_pas_d_effet_voie_C:
; test sync buzzer
	tst		R1,#0b1000			; test sync buzzer
	beq		init_fichier_ym7_pas_d_effet_sync_buzzer
	add		R8,R8,#2			; + 2 registres
	str		R2,[R12,#PSG_flag_effets_Sync_buzzer-PSG_structure_PSG]
	SWI		0x01
	.byte	"Sync Buzzer.",10,13,0
	.p2align 2

init_fichier_ym7_pas_d_effet_sync_buzzer:
; test D Sinus SID
	tst		R1,#0b10000			; test D Sinus Sid
	beq		init_fichier_ym7_pas_d_effet_sinus_sid_D
	add		R8,R8,#1			; + 1 registre pour D
	str		R2,[R12,#PSG_flag_effets_Sinus_sid_D-PSG_structure_PSG]
	SWI		0x01
	.byte	"Sinus Sid - D -.",10,13,0
	.p2align 2

init_fichier_ym7_pas_d_effet_sinus_sid_D:

	str		R8,[R12,#PSG_nb_registres_par_frame-PSG_structure_PSG]


; init des DG
; nombre de digidrums
	ldrb	R1,[R0],#1
	mov		R1,R1,lsl #8
	ldrb	R2,[R0],#1
	add		R1,R1,R2						; R1 =  nb digidrums
	str		R1,[R12,#PSG_nb_digidrums-PSG_structure_PSG]
	
	cmp		R1,#0
	beq		init_fichier_ym7_pas_de_digidrums
; R1 = nb de DG

; PSG_table_pointeurs_digidrums
; * calculer taille totale
; * arrondir au multiple de 2 supÃ©rieur chaque longueur
; * ajouter 1784 a chaque longueur
; * allouer de la ram a partir de pointeur_FIN_DATA_actuel
; * update pointeur_FIN_DATA_actuel
; copier chaque sample en le convertissant en volume YM

; - allouer de la ram
; - copier les DG en ajoutant de l'espace (1784)
; - creer une table des DG + leur longeur

	; R1=nb digidrums
	mov		R9,R0				; R9=pointeur debut taille digidrums
	mov		R4,#0				; R4 = taille totale des digidrums
	mov		R5,#0				; R5 = taille totale des digidrums + espace vide bouclage
	mov		R6,R1				; R1=nb digidrums

; ------- calcul sommes des tailles des DG + 1784 de bouclage par DG
init_fichier_YM_boucle_add_tailles_digidrums:
; 1 word = taille 
	ldrb	R3,[R0],#1
	mov		R3,R3,lsl #8
	ldrb	R2,[R0],#1
	orr		R2,R3,R2			; R2=taille du DG
; 1 word = multiplicateur
	ldrb	R7,[R0],#1
	mov		R7,R7,lsl #8
	ldrb	R3,[R0],#1
	orr		R7,R3,R7			; R7=multiplicateur

	mul		R3,R2,R7			; R3 = R2*R7 = taille * multiplicateur

	; R3 =  taille du digidrum
	
	
; arrondi
	add		R3,R3,#1
	and		R3,R3,#0xFFFFFFFE				; dernier bit = 0 => arrondi au multiple de 2 supÃ©rieur

	add		R4,R4,R3						; taille rÃ©elle
	
	add		R5,R5,R3
	add		R5,R5,#1784						; taille avec boucle
	
	subs	R6,R6,#1
	bgt		init_fichier_YM_boucle_add_tailles_digidrums
; R4=taille totale des digidrums
	str		R4,[R12,#PSG_taille_totale_des_digidrums-PSG_structure_PSG]
	str		R5,[R12,#PSG_taille_totale_des_digidrums_plus_bouclage-PSG_structure_PSG]


; ------- allocation mémoire pour les DG + bouclage 
; allouer PSG_taille_totale_des_digidrums_plus_bouclage octets en + de pointeur_FIN_DATA_actuel
; recuperer l'allocation ram actuelle
	mov		R0,#-1				; New size of current slot
	mov		R1,#-1				;  	New size of next slot
	SWI		Wimp_SlotSize			; Wimp_SlotSize 

	add		R0,R0,R5				; current slot size + valeur_taille_memoire = New size of current slot
	mov		R1,#-1
	SWI 	Wimp_SlotSize			; Wimp_SlotSize 

; ------- clean la mÃ©moire allouee
	ldr		R4,[R12,#pointeur_FIN_DATA_actuel-PSG_structure_PSG]
	str		R4,[R12,#PSG_adresse_debut_digidrums-PSG_structure_PSG]
	
	add		R6,R4,R5				; + PSG_taille_totale_des_digidrums_plus_bouclage

; on arrondi Ã  multiple de 4
	add		R6,R6,#3
	and		R6,R6,#0xFFFFFFFC
	str		R6,[R12,#pointeur_FIN_DATA_actuel-PSG_structure_PSG]
	
	mov		R2,R5
	mov		R6,#0
init_fichier_YM_boucle_clean_memoire_digidrums:
	strb	R6,[R4],#1
	subs	R2,R2,#1
	bgt		init_fichier_YM_boucle_clean_memoire_digidrums

; -------  remplir la table des pointeurs de digidrums : 
; R9=pointeur debut digidrums : PSG_table_pointeurs_digidrums


	mov		R1,R9													; source des digidrums
	ldr		R2,[R12,#PSG_adresse_debut_digidrums-PSG_structure_PSG]							; destination des digidrums
	ldr		R3,[R12,#PSG_pointeur_table_pointeurs_digidrums-PSG_structure_PSG]				; table de pointeurs adresse digidrums + longueur
	ldr		R4,[R12,#PSG_pointeur_tables_de_16_volumes_DG-PSG_structure_PSG]							; table des volumes 4 bits
	
	
	ldr		R7,[R12,#PSG_nb_digidrums-PSG_structure_PSG]
init_fichier_YM_boucle_copie_1_DG:
	ldrb	R5,[R1],#1
	mov		R5,R5,lsl #8
	ldrb	R6,[R1],#1
	orr		R6,R5,R6						; R6= taille
	
	ldrb	R8,[R1],#1
	mov		R8,R8,lsl #8
	ldrb	R5,[R1],#1
	orr		R8,R5,R8						; R8 = multiplier

	mul		R5,R8,R6				; R5 = taille * multiplicateur
	
	; R5 =  taille du digidrum

	str		R2,[R3],#4						; pointeur debut digidrum destination
	str		R5,[R3],#4						; taille digidrum 
	
; arrondi
	add		R5,R5,#1
	and		R5,R5,#0xFFFFFFFE				; dernier bit = 0 => arrondi au multiple de 2 supÃ©rieur
	
	add		R2,R2,#1784
	add		R2,R2,R5						; pointeur DG suivant

	subs	R7,R7,#1
	bgt		init_fichier_YM_boucle_copie_1_DG	

; copier les digidrums
; convertir avec la table de volume

	ldr		R7,[R12,#PSG_nb_digidrums-PSG_structure_PSG]
	ldr		R3,[R12,#PSG_pointeur_table_pointeurs_digidrums-PSG_structure_PSG]				; table de pointeurs adresse digidrums + longueur	
	
init_fichier_YM_boucle_copie_1_DG_header:

	ldr		R2,[R3],#4						; pointeur dest = memoire allouee pour DG
	ldr		R5,[R3],#4						; taille du DG
	
init_fichier_YM_boucle_copie_1_DG_datas:	


	ldrb	R0,[R1],#1						; lit l'octet en 4 bits ou 8 bits
	
	ldrb	R0,[R4,R0]						; converti en volume YM
	strb	R0,[R2],#1						; ecrit dans la nouvelle destination
	subs	R5,R5,#1
	bgt		init_fichier_YM_boucle_copie_1_DG_datas
	
; arrondi
	;add		R2,R2,#1
	;and		R2,R2,#0xFFFFFFFE				; dernier bit = 0 => arrondi au multiple de 2 supÃ©rieur
		
	;add		R2,R2,#1784
	subs	R7,R7,#1
	bgt		init_fichier_YM_boucle_copie_1_DG_header

; remet le pointeur sur R0 juste après les DG
	mov		R0,R1

; on arrondit R0
	add		R0,R0,#1
	and		R0,R0,#0xFFFFFFFE				; dernier bit = 0 => arrondi au multiple de 2 supÃ©rieur

; ------------------------------------- init SID ---------------------------------------	
init_fichier_ym7_pas_de_digidrums:


; nombre de samples SID
	ldrb	R1,[R0],#1
	mov		R1,R1,lsl #8
	ldrb	R2,[R0],#1
	add		R1,R1,R2						; R1 =  nb SID
	str		R1,[R12,#PSG_nb_SID-PSG_structure_PSG]
	
	cmp		R1,#0
	beq		init_fichier_ym7_pas_de_SID

; R1 = nb de Sid

	mov		R9,R0				; R9=pointeur debut tailles SID
	mov		R4,#0				; R4 = taille totale des SID
	mov		R6,R1				; R1 & R6=nb SID

; ------- calcul sommes des tailles des SID
init_fichier_YM_boucle_add_tailles_SID:
; 1 word = taille 
	ldrb	R3,[R0],#1
	mov		R3,R3,lsl #8
	ldrb	R2,[R0],#1
	orr		R2,R3,R2			; R2=taille du SID
; 1 word = multiplicateur
	ldrb	R7,[R0],#1
	mov		R7,R7,lsl #8
	ldrb	R3,[R0],#1
	orr		R7,R3,R7			; R7=multiplicateur

	mul		R3,R2,R7			; R3 = R2*R7 = taille * multiplicateur

	; R3 =  taille du SID
	
	
; arrondi
	add		R3,R3,#1
	and		R3,R3,#0xFFFFFFFE				; dernier bit = 0 => arrondi au multiple de 2 supÃ©rieur

	add		R4,R4,R3						; taille rÃ©elle
	
	subs	R6,R6,#1
	bgt		init_fichier_YM_boucle_add_tailles_SID
; R4=taille totale des SID
	str		R4,[R12,#PSG_taille_totale_des_SID-PSG_structure_PSG]

; ------- allocation mémoire pour les SID
; allouer PSG_taille_totale_des_SID octets en + de pointeur_FIN_DATA_actuel

; recuperer l'allocation ram actuelle
	mov		R0,#-1				; New size of current slot
	mov		R1,#-1				;  	New size of next slot
	SWI		Wimp_SlotSize			; Wimp_SlotSize 

	add		R0,R0,R4				; current slot size + valeur_taille_memoire SID = New size of current slot
	mov		R1,#-1
	SWI 	Wimp_SlotSize			; Wimp_SlotSize 

; ------- clean la mÃ©moire allouee
	ldr		R5,[R12,#pointeur_FIN_DATA_actuel-PSG_structure_PSG]
	str		R5,[R12,#PSG_adresse_debut_SID-PSG_structure_PSG]
	
	add		R6,R4,R5				; R6 = pointeur fin de ram + PSG_taille_totale_des_SID

; on arrondi Ã  multiple de 4
	add		R6,R6,#3
	and		R6,R6,#0xFFFFFFFC
	str		R6,[R12,#pointeur_FIN_DATA_actuel-PSG_structure_PSG]
	
	mov		R2,R4					; taille des SID
	mov		R6,#0
init_fichier_YM_boucle_clean_memoire_SID:
	strb	R6,[R5],#1
	subs	R2,R2,#1
	bgt		init_fichier_YM_boucle_clean_memoire_SID

; -------  remplir la table des pointeurs de SID : 
; R9=pointeur debut SID : PSG_table_pointeurs_SID

	mov		R1,R9													; source des SID
	ldr		R2,[R12,#PSG_adresse_debut_SID-PSG_structure_PSG]							; destination des SID
	ldr		R3,[R12,#PSG_pointeur_table_pointeurs_SID-PSG_structure_PSG]				; table de pointeurs adresse SID + longueur
	ldr		R4,[R12,#PSG_pointeur_tables_de_16_volumes_DG-PSG_structure_PSG]							; table des volumes 4 bits
	
	
	ldr		R7,[R12,#PSG_nb_SID-PSG_structure_PSG]
init_fichier_YM_boucle_copie_1_SID:
	ldrb	R5,[R1],#1
	mov		R5,R5,lsl #8
	ldrb	R6,[R1],#1
	orr		R6,R5,R6						; R6= taille
	
	ldrb	R8,[R1],#1
	mov		R8,R8,lsl #8
	ldrb	R5,[R1],#1
	orr		R8,R5,R8						; R8 = multiplier

	mul		R5,R8,R6				; R5 = taille * multiplicateur
	
	; R5 =  taille du digidrum

	str		R2,[R3],#4						; pointeur debut digidrum destination
	str		R6,[R3],#4						; taille digidrum non multiplié
	
; arrondi
	add		R5,R5,#1
	and		R5,R5,#0xFFFFFFFE				; dernier bit = 0 => arrondi au multiple de 2 supÃ©rieur
	
	add		R2,R2,R5						; pointeur DG suivant

	subs	R7,R7,#1
	bgt		init_fichier_YM_boucle_copie_1_SID	

; -------   copier les SID
; convertir avec la table de volume

	ldr		R7,[R12,#PSG_nb_SID-PSG_structure_PSG]
	ldr		R3,[R12,#PSG_pointeur_table_pointeurs_SID-PSG_structure_PSG]				; table de pointeurs adresse SID + longueur	
; R9=taille.w, multiplier.w * N
; R1=pointeur sur les données sample du 1er SID
; R4=PSG_pointeur_tables_de_16_volumes_DG
init_fichier_YM_boucle_copie_1_SID_header:
	ldrb	R5,[R9],#1
	mov		R5,R5,lsl #8
	ldrb	R6,[R9],#1
	orr		R6,R5,R6						; R6= taille
	
	ldrb	R8,[R9],#1
	mov		R8,R8,lsl #8
	ldrb	R5,[R9],#1
	orr		R8,R5,R8						; R8 = multiplier

	ldr		R2,[R3],#4						; pointeur dest = memoire allouee pour SID
	add		R3,R3,#4						; saute la taille totale du sample
	
init_fichier_YM_boucle_copie_1_SID_multiplier:
	mov		R5,R6							; taille du Sid
	mov		R10,R1							; source du sample
	
init_fichier_YM_boucle_copie_1_SID_taille:

	ldrb	R0,[R10],#1						; octet du sample du SID
	ldrb	R0,[R4,R0]						; converti en volume YM
	strb	R0,[R2],#1						; ecrit dans la nouvelle destination

	subs	R5,R5,#1
	bgt		init_fichier_YM_boucle_copie_1_SID_taille

	subs	R8,R8,#1						; diminue le multiplier
	bgt		init_fichier_YM_boucle_copie_1_SID_multiplier

	mov		R1,R10							; avance au sample source suivant
	subs	R7,R7,#1
	bgt		init_fichier_YM_boucle_copie_1_SID_header

	mov		R0,R10
; saute octets de vmax a la suite des SID
	ldr		R7,[R12,#PSG_nb_SID-PSG_structure_PSG]
	add		R0,R0,R7

; on arrondit R0 multiple de 2
	add		R0,R0,#1
	and		R0,R0,#0xFFFFFFFE				; dernier bit = 0 => arrondi au multiple de 2 supÃ©rieur
	
; +++++++++++++++++++++ test init Buzzer
init_fichier_ym7_pas_de_SID:

; nombre de samples Buzzer
	ldrb	R1,[R0],#1
	mov		R1,R1,lsl #8
	ldrb	R2,[R0],#1
	add		R1,R1,R2						; R1 =  nb buzzer
	str		R1,[R12,#PSG_nb_buzzer-PSG_structure_PSG]
	
	cmp		R1,#0
	beq		init_fichier_ym7_pas_de_buzzer

; tableau ou stocker les pointeurs vers liste d'env pour buzzer
; R0 pointe sur les tailles des enveloppes-buzzer, suivi par nb de repetitions  de chaque enveloppe-buzzer , suivi par numero des enveloppes constituant les enveloppes-buzzer
; R1 = nb d'enveloppes-buzzer

	mov		R9,R0		; R9 = stocke pointeur param env Buzzer
	mov		R10,R1		; R10 = stocke nb env buzzer
	str		R1,[R12,#PSG_nb_env_Buzzer-PSG_structure_PSG]


	str		R0,[R12,#PSG_pointeur_datas_configuration_buzzer_fichier_YM7-PSG_structure_PSG]
	mov		R2,R0				; R2 = tailles de l'envloppe-buzzer
	add		R0,R0,R1			; saute les tailles des env-buzzer
	mov		R11,R0				; R11 = repetition de l'enveloppe-buzzer
	add		R0,R0,R1			; R0 = numéro des enveloppes constituants l'enveloppe-buzzer
	str		R0,[R12,#PSG_pointeur_numeros_env_buzzer_fichier_YM7-PSG_structure_PSG]

	mov		R7,R1				; R7 = nb env buzzers
	mov		R8,#0

init_fichier_ym7_buzzer_boucle_calcul_taille_totale:	
	ldrb	R3,[R2],#1
	ldrb	R4,[R11],#1
	add		R4,R4,#10
	mul		R5,R4,R3			; R5 = taille * repetition
	mov		R5,R5,lsl #2		; 4 = table de .long
	
	add		R8,R8,R5			; R8 = taille totale
	
	subs	R7,R7,#1
	bgt		init_fichier_ym7_buzzer_boucle_calcul_taille_totale

; ------- allocation mémoire pour les env Buzzer

; recuperer l'allocation ram actuelle
	mov		R0,#-1				; New size of current slot
	mov		R1,#-1				;  	New size of next slot
	SWI		Wimp_SlotSize			; Wimp_SlotSize 

	add		R0,R0,R8				; current slot size + valeur_taille_memoire env buzzer = New size of current slot
	mov		R1,#-1
	SWI 	Wimp_SlotSize			; Wimp_SlotSize 

; ------- stocke les pointeurs
	ldr		R5,[R12,#pointeur_FIN_DATA_actuel-PSG_structure_PSG]
	str		R5,[R12,#PSG_adresse_debut_table_env_Buzzer-PSG_structure_PSG]
	
	add		R6,R8,R5				; R6 = pointeur fin de ram + PSG_taille_totale_des_env buzzer

; on arrondi a multiple de 4
	add		R6,R6,#3
	and		R6,R6,#0xFFFFFFFC
	
	str		R6,[R12,#pointeur_FIN_DATA_actuel-PSG_structure_PSG]


; ------- crée les tables de pointeurs d'env pour Buzzer
; R0=pointeur numero env
; R1=table des pointeurs sur env buzzer
; R2=pointeur sur les tailles des enveloppes-buzzer
; R3=tmp
; R4=espace memoire de stockage des listes de pointeurs pour env buzzer
; R5=liste des env depliees
; R6=taille de l'env buzzer en cours
; R7=nb env buzzer
; R11=pointeur liste de repetition des tailles des env buzzer

	ldr		R5,[R12,#PSG_pointeur_sur_table_liste_des_enveloppes_depliees-PSG_structure_PSG]							; table des pointeurs des enveloppes
	
	ldr		R1,[R12,#PSG_pointeur_vers_table_pointeurs_env_Buzzer-PSG_structure_PSG]
	
	ldr		R0,[R12,#PSG_pointeur_numeros_env_buzzer_fichier_YM7-PSG_structure_PSG]					; R0 = numéro des enveloppes constituants l'enveloppe-buzzer
	ldr		R4,[R12,#PSG_adresse_debut_table_env_Buzzer-PSG_structure_PSG]
	ldr		R7,[R12,#PSG_nb_env_Buzzer-PSG_structure_PSG]			; R7 = nb env buzzer à creer
	sub		R11,R0,R7							; R11 = repetition de l'enveloppe-buzzer
	sub		R2,R11,R7							; R2 = taille de l'enveloppe-buzzer


init_fichier_ym7_buzzer_boucle_1_env:
	ldrb	R6,[R2],#1							; taille de l'env buzzer en cours ( 01 01 04 )
	mov		R9,R6
	str		R4,[R1],#4							; remplit table des pointeurs sur les liste de pointeurs pour env buzzer !
	mov		R8,R4

init_fichier_ym7_buzzer_boucle_copie_pointeur_env:
	ldrb	R3,[R0],#1							; numéro d'enveloppe
	ldr		R3,[R5,R3,lsl #2]					; pointeur sur l'enveloppe
	str		R3,[R4],#4							; stocke le resultat
	
	subs	R6,R6,#1
	bgt		init_fichier_ym7_buzzer_boucle_copie_pointeur_env

; copier repetition-1 de R8 vers R4
	ldrb	R6,[R11],#1							; repetition ( 12 0A 08 )
	sub		R6,R6,#1							; -1
	add		R6,R6,#10							; repetition + 10
	mul		R10,R6,R9							; R7 = (repetition -1 +10 ) * taille de l'env

init_fichier_ym7_buzzer_boucle_copie_pointeur_env_suite:
	ldr		R3,[R8],#4
	str		R3,[R4],#4
	subs	R10,R10,#1
	bgt		init_fichier_ym7_buzzer_boucle_copie_pointeur_env_suite

; on passe a l'env buzzer suivante

	subs	R7,R7,#1
	bgt		init_fichier_ym7_buzzer_boucle_1_env

; on arrondit R0 multiple de 2
	add		R0,R0,#1
	and		R0,R0,#0xFFFFFFFE				; dernier bit = 0 => arrondi au multiple de 2 supÃ©rieur



; +++++++++++++++++++++ test init Sinus SID	
init_fichier_ym7_pas_de_buzzer:

; nombre de samples sinus SID
	ldrb	R1,[R0],#1
	mov		R1,R1,lsl #8
	ldrb	R2,[R0],#1
	add		R1,R1,R2						; R1 =  nb Sinus SID
	str		R1,[R12,#PSG_nb_sinus_sid-PSG_structure_PSG]
	
	cmp		R1,#0
	beq		init_fichier_ym7_pas_de_sinus_sid

; debut init sinus sid
;  R1=nb sinus sid / samples 
; R0=pointeur sur début parametres samples

	add		R10,R0,R1,lsl #2			; R2 = pointeur sur les datas samples

	mov		R8,#0					; R8=taille totale des samples
	mov		R7,R1					; R7=nb samples
	mov		R9,R0					; R9=pointeur debut parametres sample sinus sid


init_fichier_ym7_Sinus_Sid_sample_boucle_calcul_memoire:
	ldrb	R3,[R0],#1
	ldrb	R4,[R0],#1
	add		R3,R4,R3,lsl #8						; R3 =  taille du sample sinus sid
	
	ldrb	R4,[R0],#1
	ldrb	R5,[R0],#1
	add		R4,R5,R4,lsl #8						; R4 =  flag sample sinus sid

	tst		R4,#0b1000
	beq		init_fichier_ym7_Sinus_Sid_sample_pas_stereo_calcul_memoire
	mov		R3,R3,lsr #1						; Stereo => taille / 2

init_fichier_ym7_Sinus_Sid_sample_pas_stereo_calcul_memoire:

	add		R8,R8,R3

	subs	R7,R7,#1
	bgt		init_fichier_ym7_Sinus_Sid_sample_boucle_calcul_memoire
	
; R8=taille à allouer
; ------- allocation mémoire pour les samples sinus sid

	mov		R7,R1

; recuperer l'allocation ram actuelle
	mov		R0,#-1				; New size of current slot
	mov		R1,#-1				;  	New size of next slot
	SWI		Wimp_SlotSize			; Wimp_SlotSize 

	add		R0,R0,R8				; current slot size + valeur_taille_memoire env buzzer = New size of current slot
	mov		R1,#-1
	SWI 	Wimp_SlotSize			; Wimp_SlotSize 
	

; ------- stocke les pointeurs
	ldr		R4,[R12,#pointeur_FIN_DATA_actuel-PSG_structure_PSG]
	str		R4,[R12,#PSG_adresse_debut_samples_Sinus_Sid-PSG_structure_PSG]
	
	add		R6,R8,R4				; R6 = pointeur fin de ram + PSG_taille_totale_des_env buzzer

; on arrondi a multiple de 4
	add		R6,R6,#3
	and		R6,R6,#0xFFFFFFFC
	
	str		R6,[R12,#pointeur_FIN_DATA_actuel-PSG_structure_PSG]

; -------------

; copie des samples + remplissage table de parametres
	mov		R2,R10					; pointe sur le début des datas de samples sinus sid

	ldr		R6,[R12,#PSG_adresse_debut_samples_Sinus_Sid-PSG_structure_PSG]

	ldr		R10,[R12,#PSG_pointeur_vers_table_pointeurs_samples_Sinus_Sid-PSG_structure_PSG]
	ldr		R11,[R12,#pointeur_table_lin2logtab-PSG_structure_PSG]

	mov		R1,R7					; nb samples sinus sid
	mov		R0,R9					; pointeur debut parametres samples sinus sid

init_fichier_ym7_Sinus_Sid_sample_boucle_copie_tous_les_samples:

	ldrb	R3,[R0],#1
	ldrb	R4,[R0],#1
	add		R3,R4,R3,lsl #8						; R3 =  taille du sample sinus sid
	
	ldrb	R4,[R0],#1
	ldrb	R5,[R0],#1
	add		R4,R5,R4,lsl #8						; R4 =  flag sample sinus sid

	tst		R4,#0b1000
	beq		init_fichier_ym7_Sinus_Sid_sample_pas_stereo_avant_copie
	mov		R3,R3,lsr #1						; Stereo => taille / 2	
	
init_fichier_ym7_Sinus_Sid_sample_pas_stereo_avant_copie:
	str		R6,[R10],#4					; stocke le pointeur vers le sample
	str		R3,[R10],#4					; stocke la taille du sample

init_fichier_ym7_Sinus_Sid_sample_boucle_copie_1_sample:
	ldrb	R5,[R2],#1					; octet du sample
	ldrb	R5,[R11,R5]					; conversion mu law
	strb	R5,[R6],#1					; copie sample converti dans la dest

	tst		R4,#0b1000
	beq		init_fichier_ym7_Sinus_Sid_sample_pas_stereo_copie
	add		R2,R2,#1					; stereo : saute un octet sur 2


init_fichier_ym7_Sinus_Sid_sample_pas_stereo_copie:
	subs	R3,R3,#1
	bgt		init_fichier_ym7_Sinus_Sid_sample_boucle_copie_1_sample

	subs	R7,R7,#1
	bgt		init_fichier_ym7_Sinus_Sid_sample_boucle_copie_tous_les_samples
	
	mov		R0,R2
	
	
init_fichier_ym7_pas_de_sinus_sid:

; debut parametres compression LZ4

	add		R0,R0,#2				; saute la valeur 0x40 / 64

	ldrb	R3,[R0],#1
	mov		R3,R3,lsl #8
	ldrb	R2,[R0],#1
	add		R3,R3,R2				; R3 =  ecart entre les frames pour les N-1 premiers blocs
	
	str		R3,[R12,#PSG_compteur_frames_restantes-PSG_structure_PSG]
	str		R3,[R12,#PSG_ecart_entre_les_registres_ymdata-PSG_structure_PSG]

	ldrb	R4,[R0],#1
	mov		R4,R4,lsl #8
	ldrb	R2,[R0],#1
	add		R4,R4,R2				; R4 =  ecart entre les frames pour le dernier blocs
	
	
	ldrb	R1,[R0],#1
	mov		R1,R1,lsl #8
	ldrb	R2,[R0],#1
	add		R1,R1,R2						; R1 =  nombre de bloc compressés
	str		R1,LZ4_nombre_de_bloc_a_decompresser
	str		R1,[R12,#PSG_nb_bloc_fichier_YM7-PSG_structure_PSG]
	str		R0,LZ4_pointeur_tailles_des_blocs
	
	ldr		R6,[R12,#PSG_pointeur_tableau_des_blocs_decompresses-PSG_structure_PSG]
	
init_fichier_YM7_boucle_copie_ecarts_tableau_des_blocs:
	subs	R1,R1,#1
	beq		init_fichier_YM7_fin_boucle_copie_ecarts_tableau_des_blocs
	str		R3,[R6,#4]			; R3 =  ecart entre les frames pour les N-1 premiers blocs
	add		R6,R6,#8			; avance pointeur sur bloc + ecart du bloc
	b		init_fichier_YM7_boucle_copie_ecarts_tableau_des_blocs
	
init_fichier_YM7_fin_boucle_copie_ecarts_tableau_des_blocs:
	str		R4,[R6,#4]				; R4 =  ecart entre les frames pour le dernier blocs
	

	
; allouer la ram  PSG_compteur_frames* 16
	ldr		R7,[R12,#PSG_compteur_frames-PSG_structure_PSG]
	ldr		R8,[R12,#PSG_nb_registres_par_frame-PSG_structure_PSG]
	mul		R5,R7,R8
	
	
	
;  R5=taille à allouer = * 21 registres de 1 octet par frame

; recuperer l'allocation ram actuelle
	mov		R0,#-1					; New size of current slot
	mov		R1,#-1					;  	New size of next slot
	SWI		Wimp_SlotSize			; Wimp_SlotSize 
; R0=taille actuelle mémoire utilisée

	add		R0,R0,R5				; current slot size + valeur_taille_memoire = New size of current slot
	mov		R1,#-1
	SWI 	Wimp_SlotSize			; Wimp_SlotSize 

	ldr		R4,[R12,#pointeur_FIN_DATA_actuel-PSG_structure_PSG]
	str		R4,[R12,#PSG_pointeur_origine_ymdata-PSG_structure_PSG]
	str		R4,LZ4_pointeur_destination_bloc_actuel
	
	add		R6,R4,R5				; R6 = fin de la ram allouée

; on arrondi Ã  multiple de 4
	add		R6,R6,#3
	and		R6,R6,#0xFFFFFFFC
	str		R6,[R12,#pointeur_FIN_DATA_actuel-PSG_structure_PSG]
	
	
	ldr		R4,LZ4_pointeur_tailles_des_blocs
	ldr		R5,LZ4_nombre_de_bloc_a_decompresser
	add		R4,R4,R5,lsl #1									; * nb bloc * 2 
	str		R4,LZ4_pointeur_bloc_actuel_a_decompresser

	ldr		R10,[R12,#PSG_pointeur_tableau_des_blocs_decompresses-PSG_structure_PSG]
	

init_fichier_YM_boucle_decompression_LZ4:

	ldr		R0,LZ4_pointeur_tailles_des_blocs
	ldrb	R1,[R0],#1
	mov		R1,R1,lsl #8
	ldrb	R2,[R0],#1
	add		R1,R1,R2						; R1 =  taille du bloc compressé

	str		R0,LZ4_pointeur_tailles_des_blocs
	str		R1,LZ4_taille_du_bloc_actuel
	mov		R0,R1

	ldr		R8,LZ4_pointeur_bloc_actuel_a_decompresser

	ldr		R9,LZ4_pointeur_destination_bloc_actuel
	
	str		R9,[R10],#8

	bl		lz4_depack
	
	ldr		R8,LZ4_pointeur_bloc_actuel_a_decompresser
	ldr		R0,LZ4_taille_du_bloc_actuel
	add		R8,R8,R0
	str		R8,LZ4_pointeur_bloc_actuel_a_decompresser
	
	str		R9,LZ4_pointeur_destination_bloc_actuel

	ldr		R1,LZ4_nombre_de_bloc_a_decompresser
	subs	R1,R1,#1
	str		R1,LZ4_nombre_de_bloc_a_decompresser
	bgt		init_fichier_YM_boucle_decompression_LZ4

	SWI		0x01
	.byte	"LZ4 unpacking OK",10,13,0
	.p2align 2

	ldr		R12,PSG_pointeur_structure_PSG_haut
	ldr		R10,[R12,#PSG_pointeur_tableau_des_blocs_decompresses-PSG_structure_PSG]
	ldr		R1,[R10]
	str		R1,[R12,#PSG_pointeur_actuel_ymdata-PSG_structure_PSG]			; le 1er bloc decompressé = adresse ou lire les registres

	mov		R1,#0
	str		R1,[R12,#PSG_numero_bloc_en_cours-PSG_structure_PSG]


	ldr		R14,save_R14_init_YM7

	mov		pc,lr

LZ4_taille_du_bloc_actuel:				.long		0
LZ4_pointeur_destination_bloc_actuel:	.long		0
LZ4_nombre_de_bloc_a_decompresser:		.long		0
LZ4_pointeur_bloc_actuel_a_decompresser:		.long		0
LZ4_pointeur_tailles_des_blocs:			.long		0

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

lz4_depack:
			add		R12,R8,R0		; packed buffer end
			
			mov		R0,#0
			mov		R2,#0
			mov		R3,#0
			mov		R4,#15
			b		lz4_depack_tokenLoop

lz4_depack_lenOffset:
			ldrb	R3,[R8],#1
			ldrb	R1,[R8],#1			; a tester en réel, voir le sens de la recup depuis la mémoire
			orr		R3,R3,R1, lsl #8		; R3 = .w / voir si il faut inverser
			
			mov		R11,R9
			subs	R11,R11,R3
			mov		R1,#0x0F
			and		R1,R1,R0
			cmp		R1,R4
			bne		lz4_depack_small

lz4_depack_readLen0:
			ldrb	R2,[R8],#1
			add		R1,R1,R2
			mvn		R2,R2					; not
			and		R2,R2,#0xFF				; passe en  .b
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
			rsb		R1,R1,#0			;  !neg R1 
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
			mov		R1,R0
			mov		R1,R1,lsr #4
			cmp		R1,#0
			beq		lz4_depack_lenOffset

			cmp		R1,R4
			beq		lz4_depack_readLen1

lz4_depack_litcopys:
			mov		R1,R1,lsl #3		; * 8
			rsb		R1,R1,#0			;  !neg R1 
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
			mvn		R2,R2					; not
			and		R2,R2,#0xFF				; passe en  .b
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
			

; --------------------------------------------------------
;
; routines de replay PSG YM2149
;
; --------------------------------------------------------

PSG_mask_0x7FF:		.long		0x000007FF
PSG_mask_FFFF0000:	.long		0xFFFF0000

lecture_registres_player_VBL_YM7:
	ldr		R9,PSG_pointeur_structure_PSG
	
	ldr		R10,[R9,#PSG_pointeur_registres-PSG_structure_PSG]
	ldr		R12,[R9,#PSG_pointeur_actuel_ymdata-PSG_structure_PSG]
	
	ldr		R11,[R9,#PSG_ecart_entre_les_registres_ymdata-PSG_structure_PSG]


; YM7 = maxi 21 registres	: de 0 a 20 : 14 de bases + 2 * voie + 1 pour Sync buzzer + 1 pour D
	ldrb	R0,[R12],R11			; registre 0	- de base
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
; R3 = RbRaR9R8
	ldrb	R4,[R12],R11			; registre 12
	ldrb	R5,[R12],R11			; registre 13	- de base
	add		R4,R4,R5, lsl #8
	;ldrb	R5,[R12],R11			; registre 14	- voie A - 1
	;add		R4,R4,R5, lsl #16

;	ldrb	R5,[R12]				; registre 15	- voie A - 2
;	add		R4,R4,R5, lsl #24
; R4 = 0000RdRc
	stmia	R10!,{R0,R2-R4}

; lis des registres si besoin en fonction des effets présents dans l'entete du fichier YM7
; lis 2 octets
; => 16 bits
; bit 15 = flag Digidrums 
; bit 14 = flag SID
; bit 13 = 
; bit 12
; bit 10 à 0 = frequence replay digidrums

; ------------ faire un sid stop avant

; ================ voie A = + 2 registres
	ldr		R1,[R9,#PSG_flag_effets_voie_A-PSG_structure_PSG]
	cmp		R1,#0
	beq		lecture_registres_player_VBL_YM7_pas_effet_voie_A
	ldrb	R0,[R12],R11			; registre additionnel 1 << 8
	ldrb	R1,[R12],R11			; registre additionnel 2
	add		R0,R1,R0, lsl #8

; bit 14 = SID
	tst		R0,#0b0100000000000000									; bit 14 = SID
	beq		lecture_registres_player_VBL_YM7_pas_SID_voie_A
; SID sur la voie A

	mov		R4,#1
	str		R4,[R9,#PSG_flag_SID_voie_A-PSG_structure_PSG]

	ldrb	R2,[R9,#PSG_register8-PSG_structure_PSG]						; registre 8 = numero de sample du SID
	ldr		R3,[R9,#PSG_pointeur_table_pointeurs_SID-PSG_structure_PSG]				; table de pointeurs adresse SID + longueur		
	add		R3,R3,R2,lsl #3
	ldr		R4,[R3],#4												; R4=pointeur sur sample du SID
	ldr		R3,[R3]													; R3= taille du SID non multiplié

	ldr		R6,PSG_mask_0x7FF
	and		R5,R0,R6						; R5 = 11 bits du bas de la frequence
	
	str		R4,[R9,#PSG_pointeur_sample_SID_voie_A-PSG_structure_PSG]
	;str		R3,[R9,#PSG_taille_sample_SID_voie_A-PSG_structure_PSG]

	ldr		R4,[R9,#PSG_offset_en_cours_SID_A-PSG_structure_PSG]
; test bit 13 = reset virgule offset sample Sid
	tst		R0,#0b0010000000000000
	beq		lecture_registres_player_VBL_YM7_pas_reset_virgule_offset_voie_A
	;ldr		R6,PSG_mask_FFFF0000
	;and		R4,R4,R6							; mets à zéro les bits de virgule de l'offset du sample SID voie A
	mov		R4,R4,lsr #16
	mov		R4,R4,lsl #16							; mets à zéro les bits de virgule de l'offset du sample SID voie A
	
	

lecture_registres_player_VBL_YM7_pas_reset_virgule_offset_voie_A:
; test la taille actuelle du sid en cours, si <> : partie entiere = 0 + stocke la taille du sid 
	ldr		R6,[R9,#PSG_taille_sample_SID_voie_A-PSG_structure_PSG]
	cmp		R6,R3
	beq		lecture_registres_player_VBL_YM7_taille_SID_identique_voie_A
	
;	and		R4,R4,#0x0000FFFF
	mov		R4,R4,lsl #16
	mov		R4,R4,lsr #16							; mets à zéro les bits de entier de l'offset du sample SID voie A
	str		R3,[R9,#PSG_taille_sample_SID_voie_A-PSG_structure_PSG]
	
lecture_registres_player_VBL_YM7_taille_SID_identique_voie_A:
	str		R4,[R9,#PSG_offset_en_cours_SID_A-PSG_structure_PSG]

; frequence/increment SID voie A
; valeur frq dans R5
	ldr		R3,[R9,#PSG_pointeur_table_MFP-PSG_structure_PSG]
	ldr		R5,[R3,R5,lsl #2]						; increment frequence en .L
	str		R5,[R9,#PSG_increment_SID_voie_A-PSG_structure_PSG]
	b		lecture_registres_player_VBL_YM7_pas_effet_voie_A


lecture_registres_player_VBL_YM7_pas_SID_voie_A:
; bit 15 = DG
	tst		R0,#0b1000000000000000
	beq		lecture_registres_player_VBL_YM7_pas_DG_voie_A_sid_stop_voie_A


; digidrum voie A
	mov		R4,#0
	str		R4,[R9,#PSG_offset_en_cours_digidrum_A-PSG_structure_PSG]
	str		R4,[R9,#PSG_flag_SID_voie_A-PSG_structure_PSG]					; stop sid sur la voie

	mov		R1,#1
	str		R1,[R9,#PSG_flag_digidrum_voie_A-PSG_structure_PSG]

	ldrb	R1,[R9,#PSG_register8-PSG_structure_PSG]						; 5 bits du bas de volume B = numero de sample voie B
	str		R1,[R9,#PSG_numero_digidrum_voie_A-PSG_structure_PSG]


	ldr		R10,[R9,#PSG_pointeur_table_pointeurs_digidrums-PSG_structure_PSG]
	add		R10,r10,R1,lsl #3
	ldr		R2,[R10],#4						; pointeur adresse sample
	ldr		R3,[R10],#4						; pointeur longeur sample
	str		R2,[R9,#PSG_pointeur_sample_digidrum_voie_A-PSG_structure_PSG]
	mov		R3,R3,lsl #16					; partie entiere pour comparer Ã  l'offset
	str		R3,[R9,#PSG_longeur_sample_digidrum_voie_A-PSG_structure_PSG]
	
	ldr		R2,PSG_mask_0x7FF
	and		R0,R0,R2
	ldr		R2,[R9,#PSG_pointeur_table_MFP-PSG_structure_PSG]
	ldr		R4,[R2,R0,lsl #2]						; increment frequence en .L
	str		R4,[R9,#PSG_increment_digidrum_voie_A-PSG_structure_PSG]
	b		lecture_registres_player_VBL_YM7_pas_effet_voie_A
	
lecture_registres_player_VBL_YM7_pas_DG_voie_A_sid_stop_voie_A:
	mov		R4,#0
	str		R4,[R9,#PSG_flag_SID_voie_A-PSG_structure_PSG]
	
lecture_registres_player_VBL_YM7_pas_effet_voie_A:
lecture_registres_player_VBL_YM7_pas_DG_voie_A:

; ================ voie B = + 2 registres
	ldr		R1,[R9,#PSG_flag_effets_voie_B-PSG_structure_PSG]
	cmp		R1,#0
	beq		lecture_registres_player_VBL_YM7_pas_effet_voie_B
	ldrb	R0,[R12],R11			; registre additionnel 1 << 8
	ldrb	R1,[R12],R11			; registre additionnel 2
	add		R0,R1,R0, lsl #8

; bit 14 = SID
	tst		R0,#0b0100000000000000									; bit 14 = SID
	beq		lecture_registres_player_VBL_YM7_pas_SID_voie_B
; SID sur la voie B

	mov		R4,#1
	str		R4,[R9,#PSG_flag_SID_voie_B-PSG_structure_PSG]

	ldrb	R2,[R9,#PSG_register9-PSG_structure_PSG]						; registre 8 = numero de sample du SID
	ldr		R3,[R9,#PSG_pointeur_table_pointeurs_SID-PSG_structure_PSG]				; table de pointeurs adresse SID + longueur		
	add		R3,R3,R2,lsl #3
	ldr		R4,[R3],#4												; R4=pointeur sur sample du SID
	ldr		R3,[R3]													; R3= taille du SID non multiplié

	ldr		R6,PSG_mask_0x7FF
	and		R5,R0,R6						; R5 = 11 bits du bas de la frequence
	
	str		R4,[R9,#PSG_pointeur_sample_SID_voie_B-PSG_structure_PSG]
	;str		R3,[R9,#PSG_taille_sample_SID_voie_B-PSG_structure_PSG]

	ldr		R4,[R9,#PSG_offset_en_cours_SID_B-PSG_structure_PSG]
; test bit 13 = reset virgule offset sample Sid
	tst		R0,#0b0010000000000000
	beq		lecture_registres_player_VBL_YM7_pas_reset_virgule_offset_voie_B
	;ldr		R6,PSG_mask_FFFF0000
	;and		R4,R4,R6							; mets à zéro les bits de virgule de l'offset du sample SID voie A
	mov		R4,R4,lsr #16
	mov		R4,R4,lsl #16							; mets à zéro les bits de virgule de l'offset du sample SID voie A
	
	

lecture_registres_player_VBL_YM7_pas_reset_virgule_offset_voie_B:
; test la taille actuelle du sid en cours, si <> : partie entiere = 0 + stocke la taille du sid 
	ldr		R6,[R9,#PSG_taille_sample_SID_voie_B-PSG_structure_PSG]
	cmp		R6,R3
	beq		lecture_registres_player_VBL_YM7_taille_SID_identique_voie_B
	
;	and		R4,R4,#0x0000FFFF
	mov		R4,R4,lsl #16
	mov		R4,R4,lsr #16							; mets à zéro les bits de entier de l'offset du sample SID voie A
	str		R3,[R9,#PSG_taille_sample_SID_voie_B-PSG_structure_PSG]
	
lecture_registres_player_VBL_YM7_taille_SID_identique_voie_B:
	str		R4,[R9,#PSG_offset_en_cours_SID_B-PSG_structure_PSG]

; frequence/increment SID voie B
; valeur frq dans R5
	ldr		R3,[R9,#PSG_pointeur_table_MFP-PSG_structure_PSG]
	ldr		R5,[R3,R5,lsl #2]						; increment frequence en .L
	str		R5,[R9,#PSG_increment_SID_voie_B-PSG_structure_PSG]
	b		lecture_registres_player_VBL_YM7_pas_effet_voie_B


lecture_registres_player_VBL_YM7_pas_SID_voie_B:
; bit 15 = DG
	tst		R0,#0b1000000000000000
	beq		lecture_registres_player_VBL_YM7_pas_DG_voie_B_sid_stop_voie_B


; digidrum voie B
	mov		R4,#0
	str		R4,[R9,#PSG_offset_en_cours_digidrum_B-PSG_structure_PSG]
	str		R4,[R9,#PSG_flag_SID_voie_B-PSG_structure_PSG]					; stop sid sur la voie

	mov		R1,#1
	str		R1,[R9,#PSG_flag_digidrum_voie_B-PSG_structure_PSG]

	ldrb	R1,[R9,#PSG_register9-PSG_structure_PSG]						; 5 bits du bas de volume B = numero de sample voie B
	str		R1,[R9,#PSG_numero_digidrum_voie_B-PSG_structure_PSG]


	ldr		R10,[R9,#PSG_pointeur_table_pointeurs_digidrums-PSG_structure_PSG]
	add		R10,r10,R1,lsl #3
	ldr		R2,[R10],#4						; pointeur adresse sample
	ldr		R3,[R10],#4						; pointeur longeur sample
	str		R2,[R9,#PSG_pointeur_sample_digidrum_voie_B-PSG_structure_PSG]
	mov		R3,R3,lsl #16					; partie entiere pour comparer Ã  l'offset
	str		R3,[R9,#PSG_longeur_sample_digidrum_voie_B-PSG_structure_PSG]
	
	ldr		R2,PSG_mask_0x7FF
	and		R0,R0,R2
	ldr		R2,[R9,#PSG_pointeur_table_MFP-PSG_structure_PSG]
	ldr		R4,[R2,R0,lsl #2]						; increment frequence en .L
	str		R4,[R9,#PSG_increment_digidrum_voie_B-PSG_structure_PSG]
	b		lecture_registres_player_VBL_YM7_pas_effet_voie_B
	
lecture_registres_player_VBL_YM7_pas_DG_voie_B_sid_stop_voie_B:
	mov		R4,#0
	str		R4,[R9,#PSG_flag_SID_voie_B-PSG_structure_PSG]
	
lecture_registres_player_VBL_YM7_pas_effet_voie_B:
lecture_registres_player_VBL_YM7_pas_DG_voie_B:


; ================ voie C = + 2 registres
	ldr		R1,[R9,#PSG_flag_effets_voie_C-PSG_structure_PSG]
	cmp		R1,#0
	beq		lecture_registres_player_VBL_YM7_pas_effet_voie_C
	ldrb	R0,[R12],R11			; registre additionnel 1 << 8
	ldrb	R1,[R12],R11			; registre additionnel 2
	add		R0,R1,R0, lsl #8

; bit 14 = SID
	tst		R0,#0b0100000000000000									; bit 14 = SID
	beq		lecture_registres_player_VBL_YM7_pas_SID_voie_C
; SID sur la voie C


	
	
	mov		R4,#1
	str		R4,[R9,#PSG_flag_SID_voie_C-PSG_structure_PSG]

	ldrb	R2,[R9,#PSG_register10-PSG_structure_PSG]						; registre 8 = numero de sample du SID
	ldr		R3,[R9,#PSG_pointeur_table_pointeurs_SID-PSG_structure_PSG]				; table de pointeurs adresse SID + longueur		
	add		R3,R3,R2,lsl #3
	ldr		R4,[R3],#4												; R4=pointeur sur sample du SID
	ldr		R3,[R3]													; R3= taille du SID non multiplié

	ldr		R6,PSG_mask_0x7FF
	and		R5,R0,R6						; R5 = 11 bits du bas de la frequence
	
	str		R4,[R9,#PSG_pointeur_sample_SID_voie_C-PSG_structure_PSG]
	;str		R3,[R9,#PSG_taille_sample_SID_voie_C-PSG_structure_PSG]

	ldr		R4,[R9,#PSG_offset_en_cours_SID_C-PSG_structure_PSG]
; test bit 13 = reset virgule offset sample Sid
	tst		R0,#0b0010000000000000
	beq		lecture_registres_player_VBL_YM7_pas_reset_virgule_offset_voie_C
	;ldr		R6,PSG_mask_FFFF0000
	;and		R4,R4,R6							; mets à zéro les bits de virgule de l'offset du sample SID voie C
	mov		R4,R4,lsr #16
	mov		R4,R4,lsl #16							; mets à zéro les bits de virgule de l'offset du sample SID voie C
	
	

lecture_registres_player_VBL_YM7_pas_reset_virgule_offset_voie_C:
; test la taille actuelle du sid en cours, si <> : partie entiere = 0 + stocke la taille du sid 
	ldr		R6,[R9,#PSG_taille_sample_SID_voie_C-PSG_structure_PSG]
	cmp		R6,R3
	beq		lecture_registres_player_VBL_YM7_taille_SID_identique_voie_C
	
;	and		R4,R4,#0x0000FFFF
	mov		R4,R4,lsl #16
	mov		R4,R4,lsr #16							; mets à zéro les bits de entier de l'offset du sample SID voie C
	str		R3,[R9,#PSG_taille_sample_SID_voie_C-PSG_structure_PSG]
	
lecture_registres_player_VBL_YM7_taille_SID_identique_voie_C:
	str		R4,[R9,#PSG_offset_en_cours_SID_C-PSG_structure_PSG]

; frequence/increment SID voie C
; valeur frq dans R5
	ldr		R3,[R9,#PSG_pointeur_table_MFP-PSG_structure_PSG]
	ldr		R5,[R3,R5,lsl #2]						; increment frequence en .L
	str		R5,[R9,#PSG_increment_SID_voie_C-PSG_structure_PSG]
	b		lecture_registres_player_VBL_YM7_pas_effet_voie_C


lecture_registres_player_VBL_YM7_pas_SID_voie_C:
; bit 15 = DG
	tst		R0,#0b1000000000000000
	beq		lecture_registres_player_VBL_YM7_pas_DG_voie_C_sid_stop_voie_C


; digidrum voie C
	mov		R4,#0
	str		R4,[R9,#PSG_offset_en_cours_digidrum_C-PSG_structure_PSG]
	str		R4,[R9,#PSG_flag_SID_voie_C-PSG_structure_PSG]					; stop sid sur la voie

	mov		R1,#1
	str		R1,[R9,#PSG_flag_digidrum_voie_C-PSG_structure_PSG]

	ldrb	R1,[R9,#PSG_register10-PSG_structure_PSG]						; 5 bits du bas de volume C = numero de sample voie C
	str		R1,[R9,#PSG_numero_digidrum_voie_C-PSG_structure_PSG]


	ldr		R10,[R9,#PSG_pointeur_table_pointeurs_digidrums-PSG_structure_PSG]
	add		R10,r10,R1,lsl #3
	ldr		R2,[R10],#4						; pointeur adresse sample
	ldr		R3,[R10],#4						; pointeur longeur sample
	str		R2,[R9,#PSG_pointeur_sample_digidrum_voie_C-PSG_structure_PSG]
	mov		R3,R3,lsl #16					; partie entiere pour comparer Ã  l'offset
	str		R3,[R9,#PSG_longeur_sample_digidrum_voie_C-PSG_structure_PSG]
	
	ldr		R2,PSG_mask_0x7FF
	and		R0,R0,R2
	ldr		R2,[R9,#PSG_pointeur_table_MFP-PSG_structure_PSG]
	ldr		R4,[R2,R0,lsl #2]						; increment frequence en .L
	str		R4,[R9,#PSG_increment_digidrum_voie_C-PSG_structure_PSG]
	b		lecture_registres_player_VBL_YM7_pas_effet_voie_C
	
lecture_registres_player_VBL_YM7_pas_DG_voie_C_sid_stop_voie_C:
	mov		R4,#0
	str		R4,[R9,#PSG_flag_SID_voie_C-PSG_structure_PSG]
	
lecture_registres_player_VBL_YM7_pas_effet_voie_C:
lecture_registres_player_VBL_YM7_pas_DG_voie_C:



; ================= sync buzzer
; Sync buzzer = + 2 registres
	ldr		R1,[R9,#PSG_flag_effets_Sync_buzzer-PSG_structure_PSG]
	cmp		R1,#0
	beq		lecture_registres_player_VBL_YM7_pas_effet_Sync_buzzer
	
	ldrb	R0,[R12],R11			; registre additionnel 1 << 8
	ldrb	R1,[R12],R11			; registre additionnel 2
	add		R0,R1,R0, lsl #8		; R0=16 bits additionnels

	mov		R2,#0					; stop le sync buzzer / flag de sync buzzer = 0

; R0=registre 16 bits buzzer
; R2=PSG_flag_buzzer
	
; bit 15 = Buzzer ?
	tst		R0,#0b1000000000000000									; bit 15 = Buzzer
	beq		lecture_registres_player_VBL_YM7_pas_effet_Sync_buzzer_bit15

	mov		R2,#1					; R2= flag buzzer = 1
	
	ldr		R3,[R9,#PSG_register13-PSG_structure_PSG]				; registre 13 = numéro d'enveloppe-buzzer
	and		R3,R3,#127

	ldr		R4,[R9,#PSG_pointeur_datas_configuration_buzzer_fichier_YM7-PSG_structure_PSG]				; 496 @(496)
	ldrb	R4,[R4,R3]																			; R4 = taille de l'enveloppe ( 01 01 04 )
		
	ldr		R5,PSG_mask_0x7FF
	and		R6,R0,R5																		; limite la frequence à 11 bits
	ldr		R5,[R9,#PSG_pointeur_table_MFP-PSG_structure_PSG]
	add		R5,R5,R6,lsl #2
	ldr		R5,[R5]
	str		R5,[R9,#PSG_Buzzer_pointeur_freq_incr_envbuzzer_en_cours-PSG_structure_PSG]		; pointeur sur l'increment en fonction de la frequence
	
	
	ldr		R5,[R9,#PSG_pointeur_vers_table_pointeurs_env_Buzzer-PSG_structure_PSG]						; @(500)
	ldr		R5,[R5,R3,lsl #2]																	; R5 = pointeur mémoire env-buzzer
	str		R5,[R9,#PSG_Buzzer_pointeur_sur_envbuzzer_en_cours-PSG_structure_PSG]
	
	tst		R0,#0b0010000000000000									; bit 13 = Buzzer, reset offset
	bne		lecture_registres_player_VBL_YM7_reset_offset_Buzzer

	ldr		R5,[R9,#PSG_Buzzer_taille_env_en_cours-PSG_structure_PSG]
	cmp		R4,R5
	beq		lecture_registres_player_VBL_YM7_pas_de_reset_offset_Buzzer
	
lecture_registres_player_VBL_YM7_reset_offset_Buzzer:
	mov		R5,#0
	str		R5,[R9,#PSG_Buzzer_pos_dans_env_buzzer_en_cours-PSG_structure_PSG]
	str		R4,[R9,#PSG_Buzzer_taille_env_en_cours-PSG_structure_PSG]

lecture_registres_player_VBL_YM7_pas_de_reset_offset_Buzzer:
	
	
lecture_registres_player_VBL_YM7_pas_effet_Sync_buzzer_bit15:
	str		R2,[R9,#PSG_flag_buzzer-PSG_structure_PSG]

; ================= Sinus SID / D
lecture_registres_player_VBL_YM7_pas_effet_Sync_buzzer:
; Sinus sid = + 1 registre
	ldr		R1,[R9,#PSG_flag_effets_Sinus_sid_D-PSG_structure_PSG]
	cmp		R1,#0
	beq		lecture_registres_player_VBL_YM7_pas_effet_Sinus_sid_D

	ldrb	R0,[R12],R11			; registre additionnel Sinus Sid : bit7=active sinus sid/ bit 6-2=numero de sample /bit 1-0 = index frequence ( valeurs possibles : $0236 $011B $008D $008D )
	
; bit 7 = Sinus sid ON ?
	tst		R0,#0b10000000									; bit 7 = active Sinus Sid
	beq		lecture_registres_player_VBL_YM7_pas_effet_SinusSid_bit7

	and		R1,R0,#0b11					; R1 = index frequence Sinus Sid 0-3
	ldr		R2,[R9,#PSG_Sinus_Sid_pointeur_table_frequences-PSG_structure_PSG]
	ldr		R1,[R2,R1, lsl #2]							; increment frequence en fonction de l'index lu
	str		R1,[R9,#PSG_Paula_frequence_sample_en_cours-PSG_structure_PSG]
	
	add		R0,R0,R0				 
	and		R0,R0,#248				; 1111 1000 => vire 3 bits du bas
	
	ldr		R2,[R9,#PSG_pointeur_vers_table_pointeurs_samples_Sinus_Sid-PSG_structure_PSG]
	add		R2,R2,R0
	
	ldr		R0,[R2],#4				; pointeur sample
	ldr		R1,[R2],#4				; taille sample
	str		R0,[R9,#PSG_Paula_pointeur_sample_en_cours-PSG_structure_PSG]
	str		R1,[R9,#PSG_Paula_taille_sample_en_cours-PSG_structure_PSG]

	mov		R4,#1
	str		R4,[R9,#PSG_flag_Sinus_Sid-PSG_structure_PSG]
	


lecture_registres_player_VBL_YM7_pas_effet_SinusSid_bit7:


lecture_registres_player_VBL_YM7_pas_effet_Sinus_sid_D:

; gerer avancée + bouclage sur la lecture des registres
; gérer changement de bloc

	ldr		R12,[R9,#PSG_pointeur_actuel_ymdata-PSG_structure_PSG]
	add		R12,R12,#1
	ldr		R0,[R9,#PSG_compteur_frames_restantes-PSG_structure_PSG]
	subs	R0,R0,#1
	bne		lecture_registres_player_VBL_YM7_pas_fin_du_bloc
; fin du bloc en cours
	ldr		R1,[R9,#PSG_numero_bloc_en_cours-PSG_structure_PSG]
	add		R1,R1,#1
	ldr		R2,[R9,#PSG_nb_bloc_fichier_YM7-PSG_structure_PSG]
	cmp		R2,R1
	bne		lecture_registres_player_VBL_YM7_pas_fin_de_tous_les_blocs

	mov		R1,#0
	strb	R1,PSG_aff_infos_compteur
	mov		R4,#48
	strb	R4,PSG_aff_infos_dizaines_minutes
	strb	R4,PSG_aff_infos_unites_minutes
	strb	R4,PSG_aff_infos_dizaines_secondes
	strb	R4,PSG_aff_infos_unites_secondes

lecture_registres_player_VBL_YM7_pas_fin_de_tous_les_blocs:
	str		R1,[R9,#PSG_numero_bloc_en_cours-PSG_structure_PSG]
; lire les infos du nouveau bloc

	ldr		R11,[R9,#PSG_pointeur_tableau_des_blocs_decompresses-PSG_structure_PSG]

	add		R11,R11,R1,lsl #3			; numero de bloc * 8 

	ldr		R12,[R11],#4			; pointeur sur le bloc
	ldr		R0,[R11]				; nombre de frames pour ce bloc
	str		R0,[R9,#PSG_ecart_entre_les_registres_ymdata-PSG_structure_PSG]

lecture_registres_player_VBL_YM7_pas_fin_du_bloc:

	str		R12,[R9,#PSG_pointeur_actuel_ymdata-PSG_structure_PSG]
	str		R0,[R9,#PSG_compteur_frames_restantes-PSG_structure_PSG]

	mov		pc,lr

; --------------------------------------------------------	
; interpretation des registres du PSG
;
; 	- increments de frequence des 3 voies
;	- increment de frequence de l'enveloppe
;	- increment de frÃ©quence du Noise
;	- volumes A B C
;	- 

; Ã  optimiser, lecture de N registres d'un bloc
; --------------------------------------------------------	
PSG_interepretation_registres:

	ldr		R10,PSG_pointeur_structure_PSG
	
	;mov		R4,#0
	;str		R4,[R10,#PSG_flag_SID_voie_A-PSG_structure_PSG]
	;str		R4,[R10,#PSG_flag_SID_voie_B-PSG_structure_PSG]
	;str		R4,[R10,#PSG_flag_SID_voie_C-PSG_structure_PSG]

	ldr		R12,[R10,#PSG_pointeur_table_de_frequences-PSG_structure_PSG]
	
	
; registre 0+1
; Ã  lire en 1 fois...
	ldrb	R0,[R10,#PSG_register0-PSG_structure_PSG]			; 8 bit fine tone adjustment - Frequency of channel A
	ldrb	R1,[R10,#PSG_register1-PSG_structure_PSG]			; 4 bit rough tone adjustment - Frequency of channel A
	and		R1,R1,#0b1111				; on ne garde que 4 bits
	add		R0,R0,R1,lsl #8				; R0=total frequence channel A
	ldr		R0,[R12,R0,lsl #2]			; recupere l'increment de la frÃ©quence
	str		R0,[R10,#PSG_increment_frequence_tone_channel_A-PSG_structure_PSG]

; registre 2+3
; Ã  lire en 1 fois...
	ldrb	R0,[R10,#PSG_register2-PSG_structure_PSG]			; 8 bit fine tone adjustment - Frequency of channel B
	ldrb	R1,[R10,#PSG_register3-PSG_structure_PSG]			; 4 bit rough tone adjustment - Frequency of channel B
	and		R1,R1,#0b1111				; on ne garde que 4 bits
	add		R0,R0,R1,lsl #8				; R0=total frequence channel A
	ldr		R0,[R12,R0,lsl #2]			; recupere l'increment de la frÃ©quence
	str		R0,[R10,#PSG_increment_frequence_tone_channel_B-PSG_structure_PSG]

; registre 4+5
; Ã  lire en 1 fois...

	ldrb	R0,[R10,#PSG_register4-PSG_structure_PSG]			; 8 bit fine tone adjustment - Frequency of channel C
	ldrb	R1,[R10,#PSG_register5-PSG_structure_PSG]			; 4 bit rough tone adjustment - Frequency of channel C
	and		R1,R1,#0b1111				; on ne garde que 4 bits
	add		R0,R0,R1,lsl #8				; R0=total frequence channel A
	ldr		R0,[R12,R0,lsl #2]			; recupere l'increment de la frÃ©quence
	str		R0,[R10,#PSG_increment_frequence_tone_channel_C-PSG_structure_PSG]

; registre 6
; 5 bit noise frequency
	ldrb	R0,[R10,#PSG_register6-PSG_structure_PSG]			; 5 bit noise frequency - Frequency of noise
	ands	R0,R0,#0b11111				; on ne garde que 5 bits
	bne		PSG_interepretation_registres_frequence_Noise_pas_zero
	mov		R0,#1
PSG_interepretation_registres_frequence_Noise_pas_zero:
	ldr		R0,[R12,R0,lsl #2]			; recupere l'increment de la frÃ©quence
	str		R0,[R10,#PSG_increment_frequence_Noise-PSG_structure_PSG]

; registre 7 
; 6 bits interessants
;	Noise	 Tone
;	C B A    C B A
	ldrb	R0,[R10,#PSG_register7-PSG_structure_PSG]
	and		R0,R0,#0b111111
	str		R0,[R10,#PSG_mixer_settings_all-PSG_structure_PSG]
	ands	R1,R0,#0b111000
	cmp		R1,#0b111000					; bits de noise ?
	movne	R2,#1							; bits 3 ou 4 ou 5 = 0 => on a du Noise
	moveq	R2,#0							; tous les bits Noise = 1 => pas de noise
	str		R2,[R10,#PSG_flag_Noise-PSG_structure_PSG]				; 1 = on a du Noise
	str		R1,[R10,#PSG_mixer_settings_Noise-PSG_structure_PSG]
	and		R1,R0,#0b000111
	str		R1,[R10,#PSG_mixer_settings_Tone-PSG_structure_PSG]
; rajouter flags Tone ici

; par dÃ©faut on utilise l'enveloppe comme table de volume ( le digidrum se met dans l'enveloppe)
	ldr		R3,[R10,#PSG_pointeur_buffer_enveloppe_calculee_pour_cette_VBL-PSG_structure_PSG]					; pointe vers le buffer qui sera rempli avec l'enveloppe calculÃ©e
	str		R3,[R10,#PSG_pointeur_table_volume_en_cours_channel_A-PSG_structure_PSG]
	str		R3,[R10,#PSG_pointeur_table_volume_en_cours_channel_B-PSG_structure_PSG]
	str		R3,[R10,#PSG_pointeur_table_volume_en_cours_channel_C-PSG_structure_PSG]

	mov		R3,#1
	str		R3,[R10,#PSG_flag_Tone_voie_A-PSG_structure_PSG]
	str		R3,[R10,#PSG_flag_Tone_voie_B-PSG_structure_PSG]
	str		R3,[R10,#PSG_flag_Tone_voie_C-PSG_structure_PSG]
	
	mov		R3,#1
	str		R3,[R10,#PSG_flag_Env_voie_A-PSG_structure_PSG]
	str		R3,[R10,#PSG_flag_Env_voie_B-PSG_structure_PSG]
	str		R3,[R10,#PSG_flag_Env_voie_C-PSG_structure_PSG]
	
	ldrb	R1,[R10,#PSG_register8-PSG_structure_PSG]
	ldrb	R2,[R10,#PSG_register9-PSG_structure_PSG]
	ldrb	R3,[R10,#PSG_register10-PSG_structure_PSG]
	orr		R0,R1,R2
	orr		R0,R0,R3			; cumule tous les bits des 3 registres
	tst		R0,#0b10000			; test bit 4 = M
	movne	R0,#1				; M=1 => on utilise l'enveloppe
	moveq	R0,#0				; pas d'enveloppe utilisée
	str		R0,[R10,#PSG_flag_enveloppe-PSG_structure_PSG]


	ldr		R11,[R10,#PSG_pointeur_liste_des_tables_de_volume-PSG_structure_PSG]
	
; test utilisation du volume channel A
	tst		R1,#0b10000												; test bit 4 = M
	bne		PSG_utilise_enveloppe_channel_A							; bit M R8 = 1 => on reste sur l'enveloppe, on utilise pas la table de volumes fixes
	mov		R5,#0
	str		R5,[R10,#PSG_flag_Env_voie_A-PSG_structure_PSG]
	ands	R0,R1,#0b1111
	bne		PSG_utilise_enveloppe_channel_A_volume_pas_a_zero
	str		R5,[R10,#PSG_flag_Tone_voie_A-PSG_structure_PSG]
PSG_utilise_enveloppe_channel_A_volume_pas_a_zero:

	ldr		R4,[R11,R0,lsl #2]										; volume du channel * 4 pour lire pointeur vers la table de volume
	str		R4,[R10,#PSG_pointeur_table_volume_en_cours_channel_A-PSG_structure_PSG]			; pointeur table de volume actuel pour noise canal A
	;mov		R4,#0
	;str		R4,[R10,#PSG_flag_SID_voie_A-PSG_structure_PSG]
	;str		R4,[R10,#PSG_offset_en_cours_SID_A-PSG_structure_PSG]
PSG_utilise_enveloppe_channel_A:

; test utilisation du volume channel B
	tst		R2,#0b10000			; test bit 4
	bne		PSG_utilise_enveloppe_channel_B
	mov		R5,#0
	str		R5,[R10,#PSG_flag_Env_voie_B-PSG_structure_PSG]
	ands	R0,R2,#0b1111
	bne		PSG_utilise_enveloppe_channel_B_volume_pas_a_zero
	str		R5,[R10,#PSG_flag_Tone_voie_B-PSG_structure_PSG]
PSG_utilise_enveloppe_channel_B_volume_pas_a_zero:
	ldr		R4,[R11,R0,lsl #2]										; volume du channel * 4 pour lire pointeur vers la table de volume
	str		R4,[R10,#PSG_pointeur_table_volume_en_cours_channel_B-PSG_structure_PSG]			; pointeur table de volume actuel pour noise canal B
	;mov		R4,#0
	;str		R4,[R10,#PSG_flag_SID_voie_B-PSG_structure_PSG]
	;str		R4,[R10,#PSG_offset_en_cours_SID_B-PSG_structure_PSG]
PSG_utilise_enveloppe_channel_B:

; test utilisation du volume channel C
	tst		R3,#0b10000			; test bit 4
	bne		PSG_utilise_enveloppe_channel_C
	mov		R5,#0
	str		R5,[R10,#PSG_flag_Env_voie_C-PSG_structure_PSG]
	ands	R0,R3,#0b1111
	bne		PSG_utilise_enveloppe_channel_C_volume_pas_a_zero
	str		R5,[R10,#PSG_flag_Tone_voie_C-PSG_structure_PSG]
PSG_utilise_enveloppe_channel_C_volume_pas_a_zero:
	ldr		R4,[R11,R0,lsl #2]										; volume du channel * 4 pour lire pointeur vers la table de volume
	str		R4,[R10,#PSG_pointeur_table_volume_en_cours_channel_C-PSG_structure_PSG]			; pointeur table de volume actuel pour noise canal C
	;mov		R4,#0
	;str		R4,[R10,#PSG_flag_SID_voie_C-PSG_structure_PSG]
	;str		R4,[R10,#PSG_offset_en_cours_SID_C-PSG_structure_PSG]

PSG_utilise_enveloppe_channel_C:

; registres 11 et 12 : frequence de l'enveloppe sur 16 bits
	mov		R4,#0													; resultat = increment frequence de l'enveloppe = 0 par dÃ©faut
	ldrb	R1,[R10,#PSG_register11-PSG_structure_PSG]										; 8 bits du bas
	ldrb	R2,[R10,#PSG_register12-PSG_structure_PSG]										; 8 bits du haut
	orr		R0,R1,R2,lsl #8											; R8 = frequence sur 16 bits
	mov		R3,#4095
	cmp		R0,R3													; frequence > 4095 ?
	bgt		PSG_frequence_enveloppe_trop_eleve
	ldr		R4,[R12,R0,lsl #2]										; recupere l'increment de la frÃ©quence pour l'enveloppe

PSG_frequence_enveloppe_trop_eleve:
	str		R4,[R10,#PSG_increment_frequence_enveloppe-PSG_structure_PSG]

; registre 13 : shape of envelope 
	ldrb	R1,[R10,#PSG_register13-PSG_structure_PSG]
	tst		R1,#0b10000000											; test le bit 7, valeur negative avec le 68000
	bne		PSG_forme_enveloppe_negative

	orr		R1,R1,#0b10000000										; met le bit 7 sur le registre 13
	strb	R1,[R10,#PSG_register13-PSG_structure_PSG]
	and		R1,R1,#0b00001111										; 4 derniers bits = Envelope shape control register
	ldr		R2,[R10,#PSG_pointeur_sur_table_liste_des_enveloppes_depliees-PSG_structure_PSG]
	ldr		R1,[R2,R1,lsl #2]										; selectionne la bonne enveloppe
	str		R1,[R10,#PSG_pointeur_vers_enveloppe_en_cours-PSG_structure_PSG]

	mov		R1,#0xFFE00000											; -32 pour sauter la 1ere partie non rÃ©pÃ©titive de l'enveloppe
	str		R1,[R10,#PSG_offset_actuel_parcours_forme_enveloppe-PSG_structure_PSG]

PSG_forme_enveloppe_negative:


PSG_check_digidrum_already_running_YM7:

; si digdrum en cours sur une voie, N&T=1
	ldr		R1,[R10,#PSG_flag_digidrum_voie_A-PSG_structure_PSG]
	cmp		R1,#1
	bne		PSG_test_digidrum_each_VBL_voie_A_non
	ldrb	R1,[R10,#PSG_register7-PSG_structure_PSG]						; force Noise = 1 et Tone = 1 / ni l'un ni l'autre. Noise et Tone OFF
	orr		R1,R1,#0b001001
	strb	R1,[R10,#PSG_register7-PSG_structure_PSG]

PSG_test_digidrum_each_VBL_voie_A_non:
	ldr		R1,[R10,#PSG_flag_digidrum_voie_B-PSG_structure_PSG]
	cmp		R1,#1
	bne		PSG_test_digidrum_each_VBL_voie_B_non
	ldrb	R1,[R10,#PSG_register7-PSG_structure_PSG]						; force Noise = 1 et Tone = 1 / ni l'un ni l'autre. Noise et Tone OFF
	orr		R1,R1,#0b010010
	strb	R1,[R10,#PSG_register7-PSG_structure_PSG]

PSG_test_digidrum_each_VBL_voie_B_non:

	ldr		R1,[R10,#PSG_flag_digidrum_voie_C-PSG_structure_PSG]
	cmp		R1,#1
	bne		PSG_test_digidrum_each_VBL_voie_C_non
	ldrb	R1,[R10,#PSG_register7-PSG_structure_PSG]						; force Noise = 1 et Tone = 1 / ni l'un ni l'autre. Noise et Tone OFF
	orr		R1,R1,#0b100100
	strb	R1,[R10,#PSG_register7-PSG_structure_PSG]

PSG_test_digidrum_each_VBL_voie_C_non:



	mov		pc,lr

; --------------------------------------------------------
; Fabrication du Noise pour cette VBL
; en fonction du Noise prÃ©gÃ©nÃ©rÃ©, et de la frequence de replay du Noise
; remplit un buffer de nb_octets_par_vbl octets
;
; 00c06544

PSG_fabrication_Noise_pour_cette_VBL:

	ldr		R12,PSG_pointeur_structure_PSG
	ldr		R0,[R12,#PSG_flag_Noise-PSG_structure_PSG]
	
	cmp		R0,#1
	bne		PSG_pas_de_Noise_cette_VBL

	ldr		R0,[R12,#PSG_increment_frequence_Noise-PSG_structure_PSG]
	ldr		R1,[R12,#PSG_offset_precedent_Noise-PSG_structure_PSG]

	ldr		R10,[R12,#PSG_pointeur_buffer_Noise_de_base-PSG_structure_PSG]
	ldr		R11,[R12,#PSG_pointeur_buffer_Noise_calcule_pour_cette_VBL-PSG_structure_PSG]
	
	
	mov		R2,#0x3FFFFFFF										; $3FFF << 16, pour boucler dans le parcours
; parcours du Noise
; 00c060de
	
	ldr		R7,[R12,#PSG_nb_octet_a_produire-PSG_structure_PSG]

PSG_boucle_calcul_Noise_pour_VBL:
	add		R1,R1,R0				; incremente l'offset suivant la frequence du Noise
	and		R1,R1,R2				; limite Ã  $4000<<12
	ldrb	R3,[R10,R1,lsr #16]
	strb	R3,[R11],#1
	subs	R7,R7,#1
	bgt		PSG_boucle_calcul_Noise_pour_VBL
	
	str		R1,[R12,#PSG_offset_precedent_Noise-PSG_structure_PSG]
PSG_pas_de_Noise_cette_VBL:
	mov		pc,lr



; --------------------------------------------------------
; mixage final des 6 sources vers adresse_dma1_logical
; ( noise + tone voie A & table de volume A/enveloppe/enveloppe modifiÃ©e ) 
;      +
; ( noise + tone voie B & table de volume B/enveloppe/enveloppe modifiÃ©e ) 
;      +
; ( noise + tone voie C & table de volume C/enveloppe/enveloppe modifiÃ©e ) 
; 
; + normalisation
;
; + Lin to Log sur chaque octet

; maxi = 3 * $55 = 255 / $FF
;
mask_signature_sample:		.long		0x00000080
save_R14_mixage:			.long		0
save_R13_mixage:			.long		0
;adresse_dma1_logical_tmp:	.long		adresse_dma1_logical
PSG_mixage_final:

	str		R14,save_R14_mixage
	str		R13,save_R13_mixage

	ldr		R9,PSG_pointeur_structure_PSG


	;ldr		R6,adresse_dma1_logical_tmp
	;ldr		R6,[R6]
	ldr		R6,[R9,#PSG_pointeur_position_actuelle_remplissage_buffer_DMA_audio_VBL-PSG_structure_PSG]
	
	
	ldr		R0,[R9,#PSG_pointeur_buffer_destination_mixage_Noise_channel_A-PSG_structure_PSG]
	ldr		R1,[R9,#PSG_pointeur_buffer_destination_mixage_Noise_channel_B-PSG_structure_PSG]
	ldr		R2,[R9,#PSG_pointeur_buffer_destination_mixage_Noise_channel_C-PSG_structure_PSG]
	
	ldr		R3,[R9,#PSG_pointeur_table_volume_en_cours_channel_A-PSG_structure_PSG]
	ldr		R4,[R9,#PSG_pointeur_table_volume_en_cours_channel_B-PSG_structure_PSG]
	ldr		R5,[R9,#PSG_pointeur_table_volume_en_cours_channel_C-PSG_structure_PSG]

; test flag effet dans enveloppe , si oui, remplacer R3 R4 R5 / digidrum / sinus sid

	ldr		R7,[R9,#PSG_nb_octet_a_produire-PSG_structure_PSG]
	ldr		R8,mask_signature_sample

	ldr		R13,[R9,#pointeur_table_lin2logtab-PSG_structure_PSG]


PSG_boucle_mixage_final:

	ldrb	R11,[R0],#1					; R9 = noise + tone voie A
	ldrb	R12,[R3],#1					; R12 = table de volume A/enveloppe/enveloppe modifiÃ©e
	and		R11,R11,R12
	
	ldrb	R10,[R1],#1					; R10 = noise + tone voie B
	ldrb	R12,[R4],#1					; R12 = table de volume B/enveloppe/enveloppe modifiÃ©e
	and		R10,R10,R12

	ldrb	R9,[R2],#1					; R9 = noise + tone voie C
	ldrb	R12,[R5],#1					; R12 = table de volume C/enveloppe/enveloppe modifiÃ©e
	and		R9,R9,R12

	eor		R9,R9,R8					; signature du sample
	eor		R10,R10,R8					; signature du sample
	eor		R11,R11,R8					; signature du sample

	
; lin2log
;-
	ldrb	R12,[R13,R9]				; R12=lin2log(R12.b0)
	strb	R12,[R6],#1
	.if		nombre_de_voies=8
		strb	R12,[R6],#1
	.endif

	ldrb	R12,[R13,R10]				; R12=lin2log(R12.b0)
	strb	R12,[R6],#1
	.if		nombre_de_voies=8
		strb	R12,[R6],#1
	.endif

	ldrb	R12,[R13,R11]				; R12=lin2log(R12.b0)
	strb	R12,[R6],#2
	.if		nombre_de_voies=8
		strb	R12,[R6],#2
	.endif
	
	subs	R7,R7,#1
	bgt		PSG_boucle_mixage_final
	
	ldr		R13,save_R13_mixage
	ldr		pc,save_R14_mixage

; --------------------------------------------------------
;  on remplit adresse_dma1_logical / PSG_pointeur_position_actuelle_remplissage_buffer_DMA_audio_VBL + 3
; avec le sample Sinus Sid a la bonne frequence
; ne gere pas 8 voies
PSG_sample_silence_remplissage_Sinus_Sid_local:		.long		0,0

PSG_fill_dma_buffer_voice4_Sinus_Sid:
	ldr		R9,PSG_pointeur_structure_PSG
	ldr		R6,[R9,#PSG_pointeur_position_actuelle_remplissage_buffer_DMA_audio_VBL-PSG_structure_PSG]
	add		R6,R6,#3				; on se met sur la voie 4

; on commence simple, sans double buffer registres internes paula
; R1 = pointeur sample en cours


	ldr		R1,[R9,#PSG_Paula_pointeur_sample_en_cours-PSG_structure_PSG]
	ldr		R2,[R9,#PSG_Paula_frequence_sample_en_cours-PSG_structure_PSG]
	ldr		R3,[R9,#PSG_Paula_offset_sample_en_cours-PSG_structure_PSG]
	ldr		R4,[R9,#PSG_Paula_taille_sample_en_cours-PSG_structure_PSG]
	mov		R4,R4,lsl #16

	ldr		R7,[R9,#PSG_nb_octet_a_produire-PSG_structure_PSG]
	
PSG_fill_dma_buffer_voice4_Sinus_Sid_boucle_remplissage:
	
	adds	R3,R3,R2				; on avance l'offset
	cmp		R3,R4
	blt		PSG_fill_dma_buffer_voice4_Sinus_Sid_pas_de_fin_sample
	adr		R1,PSG_sample_silence_remplissage_Sinus_Sid_local
	mov		R2,#0
	mov		R3,#0
	str		R3,[R9,#PSG_flag_Sinus_Sid-PSG_structure_PSG]
	mov		R4,#0x10000
	str		R1,[R9,#PSG_Paula_pointeur_sample_en_cours-PSG_structure_PSG]
	str		R2,[R9,#PSG_Paula_frequence_sample_en_cours-PSG_structure_PSG]
	str		R4,[R9,#PSG_Paula_taille_sample_en_cours-PSG_structure_PSG]
	
PSG_fill_dma_buffer_voice4_Sinus_Sid_pas_de_fin_sample:
	ldrb	R0,[R1,R3,lsr #16]
	strb	R0,[R6],#4

	subs	R7,R7,#1
	bgt		PSG_fill_dma_buffer_voice4_Sinus_Sid_boucle_remplissage

	sub		R6,R6,#3
	str		R6,[R9,#PSG_pointeur_position_actuelle_remplissage_buffer_DMA_audio_VBL-PSG_structure_PSG]
	str		R3,[R9,#PSG_Paula_offset_sample_en_cours-PSG_structure_PSG]
	
	mov		pc,lr
	
; --------------------------------------------------------
; preparation application de l'enveloppe
; parcours l'enveloppe Ã  la bonne frequence
; le Sync-Buzzer sera Ã  gÃ©rer ici
; surement aussi d'autres effets : digidrum ?
; 0c05e1c
;

PSG_preparation_enveloppe_pour_la_VBL:
	ldr		R9,PSG_pointeur_structure_PSG
	ldr		R0,[R9,#PSG_increment_frequence_enveloppe-PSG_structure_PSG]
	ldr		R1,[R9,#PSG_offset_actuel_parcours_forme_enveloppe-PSG_structure_PSG]


; test sync buzzer ici => routine de sync buzzer 

	ldr		R2,[R9,#PSG_flag_buzzer-PSG_structure_PSG]
	cmp		R2,#0
	beq		PSG_preparation_enveloppe_pas_de_Buzzer

; +-+-+-+- remplissage ENV Buzzer
	
	ldr		R5,[R9,#PSG_Buzzer_pointeur_sur_envbuzzer_en_cours-PSG_structure_PSG]				; A5
	ldr		R2,[R9,#PSG_Buzzer_taille_env_en_cours-PSG_structure_PSG]							; D2
	sub		R2,R2,#1
	
	ldr		R8,[R9,#PSG_Buzzer_pos_dans_env_buzzer_en_cours-PSG_structure_PSG]
	and		R2,R8,R2																			; D2
	add		R5,R5,R2,lsl #2
	
	ldr		R11,[R9,#PSG_pointeur_buffer_enveloppe_calculee_pour_cette_VBL-PSG_structure_PSG]
	ldr		R12,[R9,#PSG_Buzzer_offset_parcours_envbuzzer-PSG_structure_PSG]
	
	ldr		R3,[R9,#PSG_Buzzer_pointeur_freq_incr_envbuzzer_en_cours-PSG_structure_PSG]
	mov		R3,R3,lsl #YM2149_shift_Buzzer
	
	mov		R4,#0xFFE00000											; -32 pour sauter la 1ere partie non rÃ©pÃ©titive de l'enveloppe

; c05f6e
	ldr		R10,[R5],#4
	ldr		R7,[R9,#PSG_nb_octet_a_produire-PSG_structure_PSG]
	
PSG_preparation_enveloppe_Buzzer_boucle:

	adds	R1,R1,R0
	adds	R12,R12,R3
	bcc 	PSG_preparation_enveloppe_Buzzer_boucle_pas_de_depassement
	
	mov		R1,R4
	;mov		R1,R1,lsr #16
	;mov		R1,R1,lsl #16			; partie a virgule de l'offset = 0
	ldr		R10,[R5],#4
		
PSG_preparation_enveloppe_Buzzer_boucle_pas_de_depassement:	
	ldrb	R8,[R10,R1,asr #16]
	strb	R8,[R11],#1

	subs	R7,R7,#1
	bgt		PSG_preparation_enveloppe_Buzzer_boucle
; fin de boucle de remplissage ENV buzzer

	subs	R5,R5,#4
	str		R12,[R9,#PSG_Buzzer_offset_parcours_envbuzzer-PSG_structure_PSG]
	
	ldr		R0,[R9,#PSG_Buzzer_pointeur_sur_envbuzzer_en_cours-PSG_structure_PSG]
	subs	R5,R5,R0
	mov		R5,R5,lsr #2
	str		R5,[R9,#PSG_Buzzer_pos_dans_env_buzzer_en_cours-PSG_structure_PSG]

	cmp		R1,#0
	bmi		PSG_preparation_enveloppe_Buzzer_offset_negatif
	ldr		R3,[R9,#PSG_mask_bouclage_enveloppe-PSG_structure_PSG]
	and		R1,R3,R1							; on masque pour boucler	

PSG_preparation_enveloppe_Buzzer_offset_negatif:
	str		R1,[R9,#PSG_offset_actuel_parcours_forme_enveloppe-PSG_structure_PSG]

	mov		pc,lr

; +-+-+-+- remplissage ENV normale
PSG_preparation_enveloppe_pas_de_Buzzer:

	ldr		R3,[R9,#PSG_flag_enveloppe-PSG_structure_PSG]
	cmp		R3,#0
	bne		PSG_preparation_enveloppe_pour_la_VBL_il_y_a_une_enveloppe
	
	ldr		R7,[R9,#PSG_nb_octet_a_produire-PSG_structure_PSG]
	;mov		R7,R7,lsr #2				; /4

; il n'y a pas d'enveloppe, on simule juste son avancÃ©e
	;mov		R2,R0,lsl #2				; R2 = increment * 4
PSG_preparation_enveloppe_pour_la_VBL_boucle_pas_d_enveloppe:
	add		R1,R1,R2
	subs	R7,R7,#1
	bgt		PSG_preparation_enveloppe_pour_la_VBL_boucle_pas_d_enveloppe
	b		PSG_preparation_enveloppe_pour_la_VBL_finalise
	

PSG_preparation_enveloppe_pour_la_VBL_il_y_a_une_enveloppe:
	
	ldr		R10,[R9,#PSG_pointeur_vers_enveloppe_en_cours-PSG_structure_PSG]
	ldr		R11,[R9,#PSG_pointeur_buffer_enveloppe_calculee_pour_cette_VBL-PSG_structure_PSG]
; parcours de l'enveloppe Ã  la bonne frÃ©quence
	ldr		R7,[R9,#PSG_nb_octet_a_produire-PSG_structure_PSG]
PSG_preparation_enveloppe_pour_la_VBL_boucle_creation_enveloppe:

	adds	R1,R1,R0				; incremente avec l'increment de frequence d'enveloppe
	ldrb	R3,[R10,R1,asr #16]		; source enveloppe en cours au rythme de la frequence
	strb	R3,[R11],#1
	
	subs	R7,R7,#1
	bgt		PSG_preparation_enveloppe_pour_la_VBL_boucle_creation_enveloppe
	
PSG_preparation_enveloppe_pour_la_VBL_finalise:
	cmp		R1,#0								; si l'offset de l'enveloppe est nÃ©gatif c'est qu'il est dans la partie non rÃ©pÃ©titive
	bmi		PSG_offset_enveloppe_negatif
	ldr		R3,[R9,#PSG_mask_bouclage_enveloppe-PSG_structure_PSG]
	and		R1,R3,R1							; on masque pour boucler

PSG_offset_enveloppe_negatif:
	str		R1,[R9,#PSG_offset_actuel_parcours_forme_enveloppe-PSG_structure_PSG]
	mov		pc,lr


; --------------------------------------------------------
; mixage de Noise et onde carrÃ©e de base, suivant frÃ©quence du channel
; 0c05c38
; a voir en ldmia/stmia
PSG_mixage_Noise_et_Tone_saveR14:		.long		0
PSG_mixage_Noise_et_Tone_voie_A:
	
	ldr		R12,PSG_pointeur_structure_PSG
	
	ldr		R11,[R12,#PSG_pointeur_buffer_destination_mixage_Noise_channel_A-PSG_structure_PSG]
	ldr		R1,[R12,#PSG_offset_actuel_parcours_onde_carree_channel_A-PSG_structure_PSG]
	ldr		R0,[R12,#PSG_increment_frequence_tone_channel_A-PSG_structure_PSG]
	mov		R0,R0,lsl #YM2149_shift_onde_carre_Tone

	cmp		R0,#0
	bne		PSG_mixage_Noise_et_Tone_voie_A_pas_increment_a_zero
	mov		R1,#-1
PSG_mixage_Noise_et_Tone_voie_A_pas_increment_a_zero:

	
	ldr		R7,[R12,#PSG_nb_octet_a_produire-PSG_structure_PSG]

	ldrb	R4,[R12,#PSG_register7-PSG_structure_PSG]				; R7 = mixer settings
	and		R5,R4,#0b000001					; Tone channel A						= NT / 0=Noise+Tone, 1=Noise, 2=Tone, 3=rien/$FF
	and		R6,R4,#0b001000					; Noise channel A
	orr		R5,R5,R6,lsr #2					; bits 0 & 1 = NT
	adr		R6,PSG_table_saut_routines_mixage_Noise_onde_carree
	ldr		R6,[R6,R5,lsl #2]				; * 4 pour lire la table, R6 = routine
	
	str		R14,PSG_mixage_Noise_et_Tone_saveR14
	adr		R14,PSG_mixage_Noise_et_Tone_voie_A_retour
	ldr		R8,[R12,#PSG_pointeur_flag_Noise_voie_A-PSG_structure_PSG]
	ldr		R9,[R12,#PSG_pointeur_flag_Tone_voie_A-PSG_structure_PSG]

	ldr		R12,[R12,#PSG_pointeur_buffer_Noise_calcule_pour_cette_VBL-PSG_structure_PSG]

	mov		pc,R6				; saut en R6 / routine
	
PSG_mixage_Noise_et_Tone_voie_A_retour:
	ldr		R12,PSG_pointeur_structure_PSG
	str		R1,[R12,#PSG_offset_actuel_parcours_onde_carree_channel_A-PSG_structure_PSG]
	ldr		pc,PSG_mixage_Noise_et_Tone_saveR14
	
PSG_mixage_Noise_et_Tone_voie_B:
	ldr		R12,PSG_pointeur_structure_PSG
	
	ldr		R11,[R12,#PSG_pointeur_buffer_destination_mixage_Noise_channel_B-PSG_structure_PSG]
	ldr		R1,[R12,#PSG_offset_actuel_parcours_onde_carree_channel_B-PSG_structure_PSG]
	ldr		R0,[R12,#PSG_increment_frequence_tone_channel_B-PSG_structure_PSG]
	mov		R0,R0,lsl #YM2149_shift_onde_carre_Tone

	cmp		R0,#0
	bne		PSG_mixage_Noise_et_Tone_voie_B_pas_increment_a_zero
	mov		R1,#-1
PSG_mixage_Noise_et_Tone_voie_B_pas_increment_a_zero:
	
	ldr		R7,[R12,#PSG_nb_octet_a_produire-PSG_structure_PSG]

	ldrb	R4,[R12,#PSG_register7-PSG_structure_PSG]				; R7 = mixer settings
	and		R5,R4,#0b000010					; Tone channel B
	and		R6,R4,#0b010000					; Noise channel B
	orr		R5,R5,R6,lsr #2					; bits 0 & 1 = NT
	adr		R6,PSG_table_saut_routines_mixage_Noise_onde_carree
	ldr		R6,[R6,R5,lsl #1]				; * 4 pour lire la table, R6 = routine
	
	str		R14,PSG_mixage_Noise_et_Tone_saveR14
	adr		R14,PSG_mixage_Noise_et_Tone_voie_B_retour
	ldr		R8,[R12,#PSG_pointeur_flag_Noise_voie_B-PSG_structure_PSG]
	ldr		R9,[R12,#PSG_pointeur_flag_Tone_voie_B-PSG_structure_PSG]
	ldr		R12,[R12,#PSG_pointeur_buffer_Noise_calcule_pour_cette_VBL-PSG_structure_PSG]
	
	mov		pc,R6
	
PSG_mixage_Noise_et_Tone_voie_B_retour:
	ldr		R12,PSG_pointeur_structure_PSG
	str		R1,[R12,#PSG_offset_actuel_parcours_onde_carree_channel_B-PSG_structure_PSG]
	ldr		pc,PSG_mixage_Noise_et_Tone_saveR14


PSG_mixage_Noise_et_Tone_voie_C:
	ldr		R12,PSG_pointeur_structure_PSG
	
	ldr		R11,[R12,#PSG_pointeur_buffer_destination_mixage_Noise_channel_C-PSG_structure_PSG]
	ldr		R1,[R12,#PSG_offset_actuel_parcours_onde_carree_channel_C-PSG_structure_PSG]
	ldr		R0,[R12,#PSG_increment_frequence_tone_channel_C-PSG_structure_PSG]
	mov		R0,R0,lsl #YM2149_shift_onde_carre_Tone

	cmp		R0,#0
	bne		PSG_mixage_Noise_et_Tone_voie_C_pas_increment_a_zero
	mov		R1,#-1
PSG_mixage_Noise_et_Tone_voie_C_pas_increment_a_zero:
	
	ldr		R7,[R12,#PSG_nb_octet_a_produire-PSG_structure_PSG]

	ldrb	R4,[R12,#PSG_register7-PSG_structure_PSG]				; R7 = mixer settings
	and		R5,R4,#0b000100					; Tone channel C
	and		R6,R4,#0b100000					; Noise channel C
	orr		R5,R5,R6,lsr #2					; bits 0 & 1 = NT
	adr		R6,PSG_table_saut_routines_mixage_Noise_onde_carree
	ldr		R6,[R6,R5]				; * 4 pour lire la table, R6 = routine
	
	str		R14,PSG_mixage_Noise_et_Tone_saveR14
	adr		R14,PSG_mixage_Noise_et_Tone_voie_C_retour
	ldr		R8,[R12,#PSG_pointeur_flag_Noise_voie_C-PSG_structure_PSG]
	ldr		R9,[R12,#PSG_pointeur_flag_Tone_voie_C-PSG_structure_PSG]
	ldr		R12,[R12,#PSG_pointeur_buffer_Noise_calcule_pour_cette_VBL-PSG_structure_PSG]
	
	mov		pc,R6
	
PSG_mixage_Noise_et_Tone_voie_C_retour:
	ldr		R12,PSG_pointeur_structure_PSG
	str		R1,[R12,#PSG_offset_actuel_parcours_onde_carree_channel_C-PSG_structure_PSG]
	ldr		pc,PSG_mixage_Noise_et_Tone_saveR14

	
; Faire les 4 routines
; ====================================> !!!!!!!!!!!!  attention, 0=actif, 1=coupÃ©
; routine1 = Noise AND Tone/Note = 03
; routine2 = Noise uniquement ( pas de Note/Tone) = 02
; routine3 = Note/tone uniquement ( pas de Noise ) = 01
; routine4 = tout Ã  $FF : ni Tone / ni Noise = 00

PSG_table_saut_routines_mixage_Noise_onde_carree:
	.long		PSG_routines_mixage_Noise_onde_carree_routine1				; Routine 1 = Noise AND Tone/Note						=0
	.long		PSG_routines_mixage_Noise_onde_carree_routine2				; Routine 2 = Noise uniquement ( pas de Note/Tone)		=1
	.long		PSG_routines_mixage_Noise_onde_carree_routine3				; routine3 = Note/tone uniquement ( pas de Noise )		=2
	.long		PSG_routines_mixage_Noise_onde_carree_routine4				; routine4 = tout Ã  $FF : ni Tone / ni Noise => on met un mask qui accepte tout 	=3
	

PSG_routines_mixage_Noise_onde_carree_routine1:
; Routine 1 = Noise AND Tone/Note
	mov		R2,#1
	str		R2,[R8]					; flag Noise = 1
	;str		R2,[R9]					; flag Tone = 1

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
	mov		R2,#1
	str		R2,[R8]					; flag Noise = 1
	mov		R2,#0
	str		R2,[R9]					; flag Tone = 0

	;mov		R7,R7,lsr #2							; divisÃ© par 4 car str.l
	;mov		R0,R0,lsl #2							; increment *4 car on fait des str.l

PSG_boucle_mixage_Noise_et_Onde_carree_routine2:
	adds	R1,R1,R0
	ldrb	R3,[R12],#1								; on lit le noise
	strb	R3,[R11],#1								; on le copie directement
	subs	R7,R7,#1
	bgt		PSG_boucle_mixage_Noise_et_Onde_carree_routine2
	mov		pc,lr	

PSG_routines_mixage_Noise_onde_carree_routine3:
; routine3 = Note/tone uniquement ( pas de Noise )
	mov		R2,#0
	str		R2,[R8]					; flag Noise = 0
	;mov		R2,#1
	;str		R2,[R9]					; flag Tone = 1

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
; routine4 = tout Ã  $FF : ni Tone / ni Noise => on met un mask qui accepte tout
	mov		R2,#0
	str		R2,[R8]					; flag Noise = 0
	str		R2,[R9]					; flag Tone = 0

	mov		R3,#0xFFFFFFFF
	;mov		R7,R7,lsr #2							; divisÃ© par 4 car str.l
	;mov		R0,R0,lsl #2							; increment *4 car on fait des str.l

PSG_boucle_mixage_Noise_et_Onde_carree_routine4:
	adds	R1,R1,R0
	strb	R3,[R11],#1
	subs	R7,R7,#1
	bgt		PSG_boucle_mixage_Noise_et_Onde_carree_routine4	
	mov		pc,lr

;-------------------------------------------------------------------------------

; ---------------- DD / SID voie A
PSG_creation_buffer_effet_digidrum_ou_Sid_channel_A:
	ldr		R9,PSG_pointeur_structure_PSG
	
	ldr		R0,[R9,#PSG_flag_digidrum_voie_A-PSG_structure_PSG]
	cmp		R0,#0
	bne		PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_A_continue
	
	ldr		R0,[R9,#PSG_flag_SID_voie_A-PSG_structure_PSG]
	cmp		R0,#0
	bne		PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_A_SID

; retour
	mov		pc,lr

; il y a un SID sur voie A
PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_A_SID:
	ldr		R10,[R9,#PSG_pointeur_sample_SID_voie_A-PSG_structure_PSG]
	ldr		R1,[R9,#PSG_offset_en_cours_SID_A-PSG_structure_PSG]
	ldr		R0,[R9,#PSG_increment_SID_voie_A-PSG_structure_PSG]
	ldr		R11,[R9,#PSG_pointeur_buffer_destination_mixage_Digidrum_channel_A-PSG_structure_PSG]
	str		R11,[R9,#PSG_pointeur_table_volume_en_cours_channel_A-PSG_structure_PSG]

; - mixage
; parcours du sample DG Ã  la bonne frÃ©quence
	ldr		R7,[R9,#PSG_nb_octet_a_produire-PSG_structure_PSG]
	
PSG_preparation_SID_A_boucle:

	add		R1,R1,R0				; incremente avec l'increment de frequence d'enveloppe
	ldrb	R3,[R10,R1,lsr #16]		; source enveloppe en cours au rythme de la frequence
	strb	R3,[R11],#1
	
	subs	R7,R7,#1
	bgt		PSG_preparation_SID_A_boucle
	

; apres :
; si offset parcours DG A> taille DG A => flag DG A = 0
	mov		R3,R1,lsr #16						; partie entiere de l'offset de lecture du SID voie A
	ldr		R5,[R9,#PSG_taille_sample_SID_voie_A-PSG_structure_PSG]
	cmp		R1,R5
	blt		PSG_preparation_SID_A_pas_de_bouclage

	cmp		R5,#2
	beq		PSG_preparation_SID_A_bouclage_valeur_2

	cmp		R5,#4
	beq		PSG_preparation_SID_A_bouclage_valeur_4

; il faut diviser R3 par R5

	mov		R10,R1
	mov		R12,R14

	mov		R1,R3
	mov		R2,R5
	bl		routine_division_R0_egal_R1_divise_par_R2
; resultat dans R0, reste dans R1
	mov		R3,R1
	mov		R14,R12
	mov		R1,R10

	mov		R1,R1,lsl #16			; garde juste la virgule
	mov		R1,R1,lsr #16
	orr		R1,R1,R3, lsl #16 		; entier.w virgule.w
	str		R1,[R9,#PSG_offset_en_cours_SID_A-PSG_structure_PSG]
	mov		pc,lr
	

PSG_preparation_SID_A_bouclage_valeur_4:
	and		R3,R3,#3
	mov		R1,R1,lsl #16			; garde juste la virgule
	mov		R1,R1,lsr #16
	orr		R1,R1,R3, lsl #16 		; entier.w virgule.w
	str		R1,[R9,#PSG_offset_en_cours_SID_A-PSG_structure_PSG]
	mov		pc,lr

PSG_preparation_SID_A_bouclage_valeur_2:
	and		R3,R3,#1
	mov		R1,R1,lsl #16			; garde juste la virgule
	mov		R1,R1,lsr #16
	orr		R1,R1,R3, lsl #16 		; entier.w virgule.w
	
PSG_preparation_SID_A_pas_de_bouclage:
	str		R1,[R9,#PSG_offset_en_cours_SID_A-PSG_structure_PSG]
	mov		pc,lr

PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_A_continue:
; increment frequence DG A = R0
; offset parcours DG A = R1
; pointeur debut sample DG A = R10
; buffer destination DG A = R11

	ldr		R10,[R9,#PSG_pointeur_sample_digidrum_voie_A-PSG_structure_PSG]
	ldr		R1,[R9,#PSG_offset_en_cours_digidrum_A-PSG_structure_PSG]
	ldr		R0,[R9,#PSG_increment_digidrum_voie_A-PSG_structure_PSG]
	ldr		R11,[R9,#PSG_pointeur_buffer_destination_mixage_Digidrum_channel_A-PSG_structure_PSG]
	str		R11,[R9,#PSG_pointeur_table_volume_en_cours_channel_A-PSG_structure_PSG]

; - mixage
; parcours du sample DG Ã  la bonne frÃ©quence
	ldr		R7,[R9,#PSG_nb_octet_a_produire-PSG_structure_PSG]
	
PSG_preparation_DG_A_boucle:

	add		R1,R1,R0				; incremente avec l'increment de frequence d'enveloppe
	ldrb	R3,[R10,R1,lsr #16]		; source enveloppe en cours au rythme de la frequence
	strb	R3,[R11],#1
	
	subs	R7,R7,#1
	bgt		PSG_preparation_DG_A_boucle
	

; apres :
; si offset parcours DG A> taille DG A => flag DG A = 0
	ldr		R5,[R9,#PSG_longeur_sample_digidrum_voie_A-PSG_structure_PSG]
	cmp		R1,R5
	blt		PSG_preparation_DG_A_pas_de_bouclage
	mov		R0,#0
	str		R0,[R9,#PSG_flag_digidrum_voie_A-PSG_structure_PSG]			; fin du DG	
PSG_preparation_DG_A_pas_de_bouclage:
	str		R1,[R9,#PSG_offset_en_cours_digidrum_A-PSG_structure_PSG]
	mov		pc,lr



; ---------------- DD / SID voie B
PSG_creation_buffer_effet_digidrum_ou_Sid_channel_B:
	ldr		R9,PSG_pointeur_structure_PSG
	
	ldr		R0,[R9,#PSG_flag_digidrum_voie_B-PSG_structure_PSG]
	cmp		R0,#0
	bne		PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_B_continue
	
	ldr		R0,[R9,#PSG_flag_SID_voie_B-PSG_structure_PSG]
	cmp		R0,#0
	bne		PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_B_SID

; retour
	mov		pc,lr

; il y a un SID sur voie B
PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_B_SID:
	ldr		R10,[R9,#PSG_pointeur_sample_SID_voie_B-PSG_structure_PSG]
	ldr		R1,[R9,#PSG_offset_en_cours_SID_B-PSG_structure_PSG]
	ldr		R0,[R9,#PSG_increment_SID_voie_B-PSG_structure_PSG]
	ldr		R11,[R9,#PSG_pointeur_buffer_destination_mixage_Digidrum_channel_B-PSG_structure_PSG]
	str		R11,[R9,#PSG_pointeur_table_volume_en_cours_channel_B-PSG_structure_PSG]

; - mixage
; parcours du sample SID a  la bonne frÃ©quence
	ldr		R7,[R9,#PSG_nb_octet_a_produire-PSG_structure_PSG]
	
PSG_preparation_SID_B_boucle:

	add		R1,R1,R0				; incremente avec l'increment de frequence d'enveloppe
	ldrb	R3,[R10,R1,lsr #16]		; source enveloppe en cours au rythme de la frequence
	strb	R3,[R11],#1
	
	subs	R7,R7,#1
	bgt		PSG_preparation_SID_B_boucle
	

; apres :
	mov		R3,R1,lsr #16						; partie entiere de l'offset de lecture du SID voie B
	ldr		R5,[R9,#PSG_taille_sample_SID_voie_B-PSG_structure_PSG]
	cmp		R1,R5
	blt		PSG_preparation_SID_B_pas_de_bouclage

	cmp		R5,#2
	beq		PSG_preparation_SID_B_bouclage_valeur_2

	cmp		R5,#4
	beq		PSG_preparation_SID_B_bouclage_valeur_4

; il faut diviser R3 par R5

	mov		R10,R1
	mov		R1,R3
	mov		R2,R5
	mov		R12,R14
	bl		routine_division_R0_egal_R1_divise_par_R2
; resultat dans R0, reste dans R1
	mov		R3,R1
	mov		R14,R12
	mov		R1,R10

	mov		R1,R1,lsl #16			; garde juste la virgule
	mov		R1,R1,lsr #16
	orr		R1,R1,R3, lsl #16 		; entier.w virgule.w
	str		R1,[R9,#PSG_offset_en_cours_SID_B-PSG_structure_PSG]
	mov		pc,lr


PSG_preparation_SID_B_bouclage_valeur_4:
	and		R3,R3,#3
	mov		R1,R1,lsl #16			; garde juste la virgule
	mov		R1,R1,lsr #16
	orr		R1,R1,R3, lsl #16 		; entier.w virgule.w
	str		R1,[R9,#PSG_offset_en_cours_SID_B-PSG_structure_PSG]
	mov		pc,lr

PSG_preparation_SID_B_bouclage_valeur_2:
	and		R3,R3,#1
	mov		R1,R1,lsl #16			; garde juste la virgule
	mov		R1,R1,lsr #16
	orr		R1,R1,R3, lsl #16 		; entier.w virgule.w
	
PSG_preparation_SID_B_pas_de_bouclage:
	str		R1,[R9,#PSG_offset_en_cours_SID_B-PSG_structure_PSG]
	mov		pc,lr

PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_B_continue:
; increment frequence DG A = R0
; offset parcours DG A = R1
; pointeur debut sample DG A = R10
; buffer destination DG A = R11

	ldr		R10,[R9,#PSG_pointeur_sample_digidrum_voie_B-PSG_structure_PSG]
	ldr		R1,[R9,#PSG_offset_en_cours_digidrum_B-PSG_structure_PSG]
	ldr		R0,[R9,#PSG_increment_digidrum_voie_B-PSG_structure_PSG]
	ldr		R11,[R9,#PSG_pointeur_buffer_destination_mixage_Digidrum_channel_B-PSG_structure_PSG]
	str		R11,[R9,#PSG_pointeur_table_volume_en_cours_channel_B-PSG_structure_PSG]

; - mixage
; parcours du sample DG Ã  la bonne frÃ©quence
	ldr		R7,[R9,#PSG_nb_octet_a_produire-PSG_structure_PSG]
	
PSG_preparation_DG_B_boucle:

	add		R1,R1,R0				; incremente avec l'increment de frequence d'enveloppe
	ldrb	R3,[R10,R1,lsr #16]		; source enveloppe en cours au rythme de la frequence
	strb	R3,[R11],#1
	
	subs	R7,R7,#1
	bgt		PSG_preparation_DG_B_boucle
	

; apres :
; si offset parcours DG A> taille DG A => flag DG A = 0
	ldr		R5,[R9,#PSG_longeur_sample_digidrum_voie_B-PSG_structure_PSG]
	cmp		R1,R5
	blt		PSG_preparation_DG_B_pas_de_bouclage
	mov		R0,#0
	str		R0,[R9,#PSG_flag_digidrum_voie_B-PSG_structure_PSG]			; fin du DG	
PSG_preparation_DG_B_pas_de_bouclage:
	str		R1,[R9,#PSG_offset_en_cours_digidrum_B-PSG_structure_PSG]
	mov		pc,lr




; ---------------- DD / SID voie C
PSG_creation_buffer_effet_digidrum_ou_Sid_channel_C:
	ldr		R9,PSG_pointeur_structure_PSG
	
	ldr		R0,[R9,#PSG_flag_digidrum_voie_C-PSG_structure_PSG]
	cmp		R0,#0
	bne		PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_C_continue
	
	ldr		R0,[R9,#PSG_flag_SID_voie_C-PSG_structure_PSG]
	cmp		R0,#0
	bne		PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_C_SID

; retour
	mov		pc,lr

; il y a un SID sur voie C
PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_C_SID:
	
	
	ldr		R10,[R9,#PSG_pointeur_sample_SID_voie_C-PSG_structure_PSG]
	ldr		R1,[R9,#PSG_offset_en_cours_SID_C-PSG_structure_PSG]
	ldr		R0,[R9,#PSG_increment_SID_voie_C-PSG_structure_PSG]
	ldr		R11,[R9,#PSG_pointeur_buffer_destination_mixage_Digidrum_channel_C-PSG_structure_PSG]
	str		R11,[R9,#PSG_pointeur_table_volume_en_cours_channel_C-PSG_structure_PSG]

; - mixage
; parcours du sample SID a  la bonne frÃ©quence
	ldr		R7,[R9,#PSG_nb_octet_a_produire-PSG_structure_PSG]
	
PSG_preparation_SID_C_boucle:

	add		R1,R1,R0				; incremente avec l'increment de frequence d'enveloppe
	ldrb	R3,[R10,R1,lsr #16]		; source enveloppe en cours au rythme de la frequence
	strb	R3,[R11],#1
	
	subs	R7,R7,#1
	bgt		PSG_preparation_SID_C_boucle
	

; apres :
	mov		R3,R1,lsr #16						; partie entiere de l'offset de lecture du SID voie B
	ldr		R5,[R9,#PSG_taille_sample_SID_voie_C-PSG_structure_PSG]
	cmp		R1,R5
	blt		PSG_preparation_SID_C_pas_de_bouclage

	cmp		R5,#2
	beq		PSG_preparation_SID_C_bouclage_valeur_2
	cmp		R5,#4
	beq		PSG_preparation_SID_C_bouclage_valeur_4

; il faut diviser R3 par R5
	mov		R10,R1
	mov		R1,R3
	mov		R2,R5
	mov		R12,R14
	bl		routine_division_R0_egal_R1_divise_par_R2
; resultat dans R0, reste dans R1
	mov		R3,R1
	mov		R14,R12
	mov		R1,R10

	mov		R1,R1,lsl #16			; garde juste la virgule
	mov		R1,R1,lsr #16
	orr		R1,R1,R3, lsl #16 		; entier.w virgule.w
	str		R1,[R9,#PSG_offset_en_cours_SID_C-PSG_structure_PSG]
	mov		pc,lr


PSG_preparation_SID_C_bouclage_valeur_4:
	and		R3,R3,#3
	mov		R1,R1,lsl #16			; garde juste la virgule
	mov		R1,R1,lsr #16
	orr		R1,R1,R3, lsl #16 		; entier.w virgule.w
	str		R1,[R9,#PSG_offset_en_cours_SID_C-PSG_structure_PSG]
	mov		pc,lr


PSG_preparation_SID_C_bouclage_valeur_2:
	and		R3,R3,#1
	mov		R1,R1,lsl #16			; garde juste la virgule
	mov		R1,R1,lsr #16
	orr		R1,R1,R3, lsl #16 		; entier.w virgule.w
	
PSG_preparation_SID_C_pas_de_bouclage:
	str		R1,[R9,#PSG_offset_en_cours_SID_C-PSG_structure_PSG]
	mov		pc,lr

PSG_creation_buffer_effet_digidrum_ou_Sinus_Sid_channel_C_continue:
; increment frequence DG A = R0
; offset parcours DG A = R1
; pointeur debut sample DG A = R10
; buffer destination DG A = R11

	ldr		R10,[R9,#PSG_pointeur_sample_digidrum_voie_C-PSG_structure_PSG]
	ldr		R1,[R9,#PSG_offset_en_cours_digidrum_C-PSG_structure_PSG]
	ldr		R0,[R9,#PSG_increment_digidrum_voie_C-PSG_structure_PSG]
	ldr		R11,[R9,#PSG_pointeur_buffer_destination_mixage_Digidrum_channel_C-PSG_structure_PSG]
	str		R11,[R9,#PSG_pointeur_table_volume_en_cours_channel_C-PSG_structure_PSG]

; - mixage
; parcours du sample DG Ã  la bonne frÃ©quence
	ldr		R7,[R9,#PSG_nb_octet_a_produire-PSG_structure_PSG]
	
PSG_preparation_DG_C_boucle:

	add		R1,R1,R0				; incremente avec l'increment de frequence d'enveloppe
	ldrb	R3,[R10,R1,lsr #16]		; source enveloppe en cours au rythme de la frequence
	strb	R3,[R11],#1
	
	subs	R7,R7,#1
	bgt		PSG_preparation_DG_C_boucle
	

; apres :
; si offset parcours DG A> taille DG A => flag DG A = 0
	ldr		R5,[R9,#PSG_longeur_sample_digidrum_voie_C-PSG_structure_PSG]
	cmp		R1,R5
	blt		PSG_preparation_DG_C_pas_de_bouclage
	mov		R0,#0
	str		R0,[R9,#PSG_flag_digidrum_voie_C-PSG_structure_PSG]			; fin du DG	
PSG_preparation_DG_C_pas_de_bouclage:
	str		R1,[R9,#PSG_offset_en_cours_digidrum_C-PSG_structure_PSG]
	mov		pc,lr

	
; --------------------------------------------------------
;
; structure PSG
;
; --------------------------------------------------------
; www.ym2149.com/ym2149.pdf
; https://www.fxjavadevblog.fr/m68k-atari-st-ym-player/


PSG_pointeur_structure_PSG:				.long		PSG_structure_PSG
PSG_pointeur_fichier_YM7:			.long		YM7packed

		.rept		20
		.long		0
		.endr
; ----------------
PSG_structure_PSG:

pointeur_adresse_dma1_logical:		.long		adresse_dma1_logical
pointeur_adresse_dma1_memc:			.long		adresse_dma1_memc
pointeur_adresse_dma2_logical:		.long		adresse_dma2_logical
pointeur_adresse_dma2_memc:			.long		adresse_dma2_memc

adresse_dma1_logical:				.long		0
adresse_dma1_memc:					.long		0

adresse_dma2_logical:				.long		0
adresse_dma2_memc:					.long		0



pointeur_FIN_DATA_actuel:		.long	FIN_DATA

pointeur_table_lin2logtab:		.long		-1

PSG_pointeur_registres:			.long		PSG_registres

PSG_pointeur_tables_de_16_volumes:			.long		PSG_tables_de_16_volumes
PSG_pointeur_tables_de_16_volumes_DG:			.long		PSG_tables_de_16_volumes_DG
PSG_replay_frequency_HZ:		.long		0
PSG_loop_frame_YM7:				.long		0
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

PSG_ecart_entre_les_registres_ymdata:	.long		0

PSG_tables_de_16_volumes:
; table lineaire:
	;.byte		0,6,11,17,23,28,34,40,45,51,57,62,68,74,79,85
	;.byte		0x00,6,11,17,23,28,34,40,45,51,57,62,68,74,79,85
	;.byte		00,00,01,03,06,9,14,19,24,31,38,45,54,64,74,85
	;.byte		00,01,02,03,05,8,12,17,19,27,34,43,50,60,72,85
; le YM est logarithmique

	.if		VOLUMES_ORIGINE = 1
		.byte		0x00,0x00,0x00,0x00,0x01,0x02,0x02,0x04,0x05,0x08,0x0B,0x10,0x18,0x22,0x37,0x55
	.endif
	.if		VOLUMES_ORIGINE = 0
		.byte		0x00,0x01,0x01,0x02,0x03,0x06,0x09,0x0C,0x0F,0x18,0x21,0x30,0x48,0x66,0xA5,0xFF
	.endif

	.p2align     2
PSG_tables_de_16_volumes_DG:
	.if		VOLUMES_ORIGINE = 1
		.byte		0x00,0x00,0x00,0x00,0x01,0x02,0x02,0x04,0x05,0x08,0x0B,0x10,0x18,0x22,0x37,0x55
	.endif
	.if		VOLUMES_ORIGINE = 0
		.byte		0x00,0x01,0x01,0x02,0x03,0x06,0x09,0x0C,0x0F,0x18,0x21,0x30,0x48,0x66,0xA5,0xFF
	.endif

	.p2align	2
	
PSG_compteur_frames:				.long		0
PSG_compteur_frames_restantes:		.long		0
PSG_nb_octet_par_run_de_replay:		.long		0
PSG_nb_octets_pour_cette_VBL:		.long		0
PSG_nb_octet_a_produire:			.long		0
PSG_nb_octet_restant_avant_prochain_replay_complet:				.long		0
PSG_pointeur_position_actuelle_remplissage_buffer_DMA_audio_VBL:		.long		0


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

PSG_pointeur_actuel_ymdata:			.long		0
; PSG_pointeur_debut_ymdata:			.long		0
PSG_pointeur_origine_ymdata:		.long		0

valeur_1_div_14:	.long		4682				; ( 1/14 * 65536	) +1


; SID
PSG_nb_SID:					.long		0
PSG_taille_sample_SID_voie_A:	.long		0
PSG_taille_sample_SID_voie_B:	.long		0
PSG_taille_sample_SID_voie_C:	.long		0
PSG_pointeur_sample_SID_voie_A:	.long		0
PSG_pointeur_sample_SID_voie_B:	.long		0
PSG_pointeur_sample_SID_voie_C:	.long		0
PSG_increment_SID_voie_A:	.long		0
PSG_increment_SID_voie_B:	.long		0
PSG_increment_SID_voie_C:	.long		0
PSG_vmax_SID_voie_A:		.long		0
PSG_vmax_SID_voie_B:		.long		0
PSG_vmax_SID_voie_C:		.long		0
PSG_flag_SID_voie_A:		.long		0
PSG_flag_SID_voie_B:		.long		0
PSG_flag_SID_voie_C:		.long		0
PSG_offset_en_cours_SID_A:	.long		0
PSG_offset_en_cours_SID_B:	.long		0
PSG_offset_en_cours_SID_C:	.long		0
PSG_taille_totale_des_SID:	.long		0
PSG_adresse_debut_SID:		.long		0
PSG_pointeur_table_pointeurs_SID:		.long		PSG_table_pointeurs_SID


; buzzer
PSG_nb_buzzer:				.long		0

; sinus SID
PSG_nb_sinus_sid:				.long		0

PSG_flag_Env_voie_A:		.long		0
PSG_flag_Env_voie_B:		.long		0
PSG_flag_Env_voie_C:		.long		0

PSG_flag_Noise_voie_A:		.long		0
PSG_flag_Noise_voie_B:		.long		0
PSG_flag_Noise_voie_C:		.long		0

PSG_flag_Tone_voie_A:		.long		0
PSG_flag_Tone_voie_B:		.long		0
PSG_flag_Tone_voie_C:		.long		0

PSG_pointeur_flag_Tone_voie_A:			.long		PSG_flag_Tone_voie_A
PSG_pointeur_flag_Noise_voie_A:			.long		PSG_flag_Noise_voie_A
PSG_pointeur_flag_Tone_voie_B:			.long		PSG_flag_Tone_voie_B
PSG_pointeur_flag_Noise_voie_B:			.long		PSG_flag_Noise_voie_B
PSG_pointeur_flag_Tone_voie_C:			.long		PSG_flag_Tone_voie_C
PSG_pointeur_flag_Noise_voie_C:			.long		PSG_flag_Noise_voie_C

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

PSG_flag_effets_voie_A:				.long		0
PSG_flag_effets_voie_B:				.long		0
PSG_flag_effets_voie_C:				.long		0
PSG_flag_effets_global:				.long		0
PSG_flag_effets_Sync_buzzer:		.long		0
PSG_flag_effets_Sinus_sid_D:		.long		0

pointeur_PSG_tables_de_16_volumes:		.long		PSG_tables_de_16_volumes

PSG_pointeur_table_de_frequences:		.long		PSG_table_de_frequences

PSG_pointeur_tableau_des_blocs_decompresses:		.long		PSG_tableau_des_blocs_decompresses
PSG_numero_bloc_en_cours:			.long		0
PSG_nb_bloc_fichier_YM7:			.long		0
PSG_nb_registres_par_frame:			.long		0

; Buzzer
PSG_pointeur_vers_table_pointeurs_env_Buzzer:			.long	PSG_table_pointeurs_enveloppes_Buzzer			; @(500)
PSG_flag_buzzer:										.long		0						; flag buzzer ON/OFF pendant le replay
PSG_pointeur_datas_configuration_buzzer_fichier_YM7:	.long		0						; 496 @(496)
PSG_adresse_debut_table_env_Buzzer:						.long		0						; pointeur vers memoire allouée pour les adresses vers enveloppes
PSG_nb_env_Buzzer:										.long		0						; nombre d'enveloppes-buzzer
PSG_pointeur_numeros_env_buzzer_fichier_YM7:			.long		0						; 
PSG_Buzzer_taille_env_en_cours:							.long		0						; @(118) = taille de l'enveloppe buzzer en nb d'enveloppes
PSG_Buzzer_pointeur_sur_envbuzzer_en_cours:				.long		0						; @(112) = pointeur sur l'env buzzer en cours de replay
PSG_Buzzer_pos_dans_env_buzzer_en_cours:				.long		0						; @(116) = position numérique dans la liste des env-buzzer
PSG_Buzzer_pointeur_freq_incr_envbuzzer_en_cours:		.long		0						; @(104) = pointeur sur la frequence d'increment
PSG_Buzzer_offset_parcours_envbuzzer:					.long		0						; @(108)= offset parcours env-buzzer

; Sinus SID + emulation Paula pour Sinus Sid
PSG_pointeur_vers_table_pointeurs_samples_Sinus_Sid:	.long	PSG_table_pointeurs_samples_Sinus_Sid			; @(356)
PSG_adresse_debut_samples_Sinus_Sid:					.long		0
PSG_flag_Sinus_Sid:										.long		0						; flag sinus sid ON/OFF pendant le replay
PSG_Sinus_Sid_increment_frequence:							.long		0						; @(10)=frequence
PSG_pointeur_sample_Sinus_Sid:							.long		0						; @(4)=pointeur sample
PSG_taille_sample_Sinus_Sid:							.long		0						; @(8) = taille en word 


PSG_Sinus_Sid_pointeur_table_frequences:		.long		PSG_Sinus_Sid_table_frequences
PSG_Sinus_Sid_table_frequences:
; frq = 3546895 / freq;
; freq = 1000000 / temps_us;
; temps_us : 48 32 16 => freq = 20833,3333333 / 31250 / 62500
; round((frq / i) * 65536)
; $0236 $011B $008D $008D / 566 283 141 141
; 20833 : 170,25096000027240153600043584246
	.if frequence_replay = 20833
		.long			19713 , 39426 , 79132 , 79132
	.endif
	.if frequence_replay = 31250
		.long			13142 , 26284 , 52754 , 52754
	.endif
	.if frequence_replay = 62500
		.long			 6571 , 13142 , 26377 , 26377
	.endif

; --emulation Paula--
; registres internes non accessibles
PSG_Paula_pointeur_sample_en_cours:						.long		PSG_sample_silence
PSG_Paula_taille_sample_en_cours:						.long		1
PSG_Paula_frequence_sample_en_cours:					.long		0
PSG_Paula_offset_sample_en_cours:						.long		0

; registres externes
PSG_Paula_AUD3LCH_AUD3LCL:						.long		PSG_sample_silence
PSG_Paula_AUD3LEN:								.long		1
PSG_Paula_AUD3PER:								.long		0



; YM registers
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
	.p2align	2

PSG_table_pointeurs_digidrums:
; 32  entrees
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1

PSG_table_pointeurs_SID:
; 64  entrees
	.rept		4
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.endr

PSG_table_pointeurs_enveloppes_Buzzer:
; 32  entrees
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1

PSG_table_pointeurs_samples_Sinus_Sid:
; 32  entrees
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1
	.long		-1,-1,-1,-1,-1,-1,-1,-1


PSG_tableau_des_blocs_decompresses:
; pointeur adresse bloc mémoire decompressé, écart entre les registres pour ce bloc
	.rept 10
		.long		0,0
	.endr

.if frequence_replay = 20833
PSG_table_MFP:
	.include	"table_increments_MFP_20833.asm"
	.p2align	2
PSG_table_de_frequences:
	.include	"PSG_table_freq_20833.asm"
	.p2align	2
.endif


.if frequence_replay = 31250
PSG_table_MFP:
	.include	"table_increments_MFP_31250.asm"
	.p2align	2
PSG_table_de_frequences:
	.include	"PSG_table_freq_31250.asm"
	.p2align	2
.endif


.if frequence_replay = 62500
PSG_table_MFP:
	.include	"table_increments_MFP_62500.asm"
	.p2align	2
PSG_table_de_frequences:
	.include	"PSG_table_freq_62500.asm"
	.p2align	2
.endif

.long           0x9c, 0x9b, 0x9b, 0x9a, 0x99, 0x99, 0x98, 0x98

PSG_base_enveloppe:
; enveloppes non depliÃ©es, 32*2*16
	.include	"PSG_table_env_8bits.asm"
	.p2align	2

PSG_sample_silence:
	.rept	1600
		.byte	0
	.endr

YM7packed:
	.incbin			"505_Oxygene.ym7"							; 51 hz
	;.incbin			"UltraSyd_Thunderdome.ym7"					; 69 HZ
	;.incbin			"Tao_Ultimate_Medley_Part_1.ym7"		; 200 HZ
	;.incbin			"Gwem_Stardust_Memory.ym7"				; D/Sinus Sid + Sid
	;.incbin			"Dma_Sc_Galaxy_Trip.ym7"				; D/Sinus Sid + Sid 
	;.incbin			"505_Robost.ym7"						; D/sinus Sid
	; .incbin			"Cube_Bullet_Sequence.ym7"				; SID + Buzzer
	;.incbin			"Tomchi_Sidified.ym7"					; SID
	;.incbin		"Mad_Max_Buzzer.ym7"					; YM7 buzzer + SID
	;.incbin		"DMA_Sc_Fantasia_main.ym7"					; YM7 SID
	;.incbin		"Furax_Virtualescape_main.ym7"				; YM7 SID
	; .incbin		"MadMax_Virtual_Esc_End.ym7"			; YM7 SID voie A
	; .incbin		"Jess_For_Your_Loader.ym7"				; YM7 sans effets avec env
	;.incbin		"ancool_atari_baby.ym7"				; YM7 sans effets
	;.incbin		"Decade_boot.ym7"					; YM7 avec env
	;.incbin		"PYM_main_menu.ym7"					; YM7 avec enveloppe et digidrums
	; .incbin		"buzztone.ym7"						; digidrums sur B & C
	.p2align	2
FIN_YM7packed:
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

		.p2align	2
FIN_DATA:
	.p2align	2