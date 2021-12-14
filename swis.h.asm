.equ OS_WriteC, 0
.equ OS_WriteO, 2
.equ OS_NewLine, 3
.equ OS_Byte, 6
.equ XOS_Byte, OS_Byte | (1 << 17)
.equ OS_Word, 7
.equ OS_File, 8
.equ OS_Exit, 0x11
.equ OS_ExitAndDie, 0x50
.equ OS_BreakPt, 0x17
.equ OS_ChangeDynamicArea, 0x2a
.equ OS_GenerateError, 0x2b
.equ OS_ReadVduVariables, 0x31
.equ OS_ReadMonotonicTime, 0x42
.equ OS_ReadDynamicArea, 0x5c
.equ OS_ConvertCardinal4, 0xd8	
.equ OS_EnterOS, 0x16						; supervisor
.equ OS_supervisor, 0x16						; supervisor
.equ OS_ScreenMode, 0x65

.equ OS_Module, 0x1E

.equ OSByte_EventEnable, 14
.equ OSByte_EventDisable, 13
.equ OSByte_Vsync, 19
.equ OSByte_WriteVDUBank, 112
.equ OSByte_WriteDisplayBank, 113
.equ OSByte_ReadKey, 129

.equ OSWord_WritePalette, 12

.equ IKey_LeftClick, 0xf6
.equ IKey_RightClick, 0xf4
.equ IKey_Space, 0x9d

.equ DynArea_Screen, 2

.equ VD_ScreenStart, 148 

.equ OS_Claim, 0x1f
.equ OS_Release, 0x20
.equ OS_AddToVector, 0x47

.equ ErrorV, 0x01
.equ EventV, 0x10
.equ Event_VSync, 4

.equ OS_ConvertHex2, 0xd1
.equ OS_ConvertHex4, 0xd2
.equ OS_ConvertHex8, 0xd4

.equ QTM_Load, 0x47E40
.equ QTM_Start, 0x47E41
.equ QTM_Stop, 0x47E42
.equ QTM_SetSampleSpeed, 0x47E49

; Rasterman 
.equ	RasterMan_Version,			0x47e84
.equ	RasterMan_SetTables,		0x47e83
.equ	RasterMan_Install,			0x47e80
.equ	RasterMan_Release,			0x47e81
.equ	RasterMan_Wait,				0x47e82
.equ	RasterMan_ReadScanline,		0x47e85
.equ	RasterMan_SetVIDCRegister,	0x47e86
.equ	RasterMan_SetMEMCRegister,	0x47e87
.equ	RasterMan_QTMParamAddr,		0x47e88
.equ	RasterMan_ScanKeyboard,		0x47e89
.equ	RasterMan_ClearKeyBuffer, 	0x47e8a
.equ	RasterMan_ReadScanAddr,		0x47e8b

; QDebug_Break
.equ	BKP, 0x44B85
.equ	bkp, 0x44B85

; XOS
.equ	XOS_ServiceCall,		0x20030
.equ	OS_ReadMonotonicTime,		0x42

; memory management
.equ	OS_ReadMemMapInfo,		0x51
.equ	OS_FindMemMapEntries,		0x60
.equ	XSound_SoundLog,		0x60181
.equ	XSound_Volume,			0x60180
.equ	XSound_Configure,		0x60140
.equ	XSound_Enable,			0x60141
.equ	Sound_Stereo,			0x40142
.equ	XSound_Stereo,			0x60142
.equ	Wimp_SlotSize,			0x400EC