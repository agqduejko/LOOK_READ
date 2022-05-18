;----------------------Vector Version---------------------------
;v107: 2019/12/23 Nick
;1. Add 1us delay after send write enable command
;2. Polling SR register at 1us interval
;3. InitialChip function(Check Status register WEL Bit): Add Send write disable command after send write enable command
;
;v108: 2020/6/20 Nick
;fix option byte verify issue	

;v109: 2021/04/29 Nick
;Add Polling_WEL_Bit Function
;After WriteEnable, it will Delay 10us and then go to polling WEL Bit to see if it is set to 1

;v110: 2021/06/08 Nick
;Add Exit4ByteMode Function
;---------------------------------------------------------------
	JP A1,=ResetVector 			;0		sram[0]~sram[15] set to zero.
	JP A1,=BusReset  			;1
	JP A1,=InitialChip			;2
	JP A1,=ReadID  				;3
	JP A1,=GetVerType  				;4
	JP A1,=Erase  				;5
	JP A1,=BlankCheck  			;6
	JP A1,=Program  			;7
	JP A1,=Verify  				;8
	JP A1,=Read  				;9
	JP A1,=Erase_SN  			;10
	JP A1,=Program_SN 			;11
	JP A1,=GetVerType
	JP A1,=GetVerType
	JP A1,=GetVerType
	JP A1,=GetVerType
;----------------------VectorEntry------------------------------
VectorEntry:
	MOV R1,#8			;this "#8"is address of SRAM. SRAM[8] = Command,Response.
	LDR R0,[R1]         ;copy the value of R1 address into R0  
	AND R0,#0x8000		;check whether Bit15 of R0 is 1 = 1 command finish
	JP BF,=VectorEntry	;Jump if Bit15 is 1
	LDR R0,[R1]         ;Load again	
	AND R0,#0xF 		;check the command
	PUSH R0				;Push R0 to stack -this R0 means pc counter
	POP PC				;pop R0 to jump to the suitable address - on the top
;END
OperationPass:
	MOV R0,#0x8000		;RO = BIT15
	JP A1,=__operation_result
OperationFail:
	MOV R0,#0xC000		;RO = BIT15|BIT14
	JP A1,=__operation_result
OperationUnsupport:
	MOV R0,#0xE000		;RO = BIT15|BIT14|BIT13
	JP A1,=__operation_result
__operation_result:
	MOV R1,#0x8
	OR  R0,[R1]			;R0 = BIT15|?BIT14|?BIT13[command_response]
	LDR [R1],R0
	JP A1,=VectorEntry
;END
;----------------------ResetVector------------------------------
ResetVector:
	MOV R0,#0x0 	
__reset_vector:		;sram[0]~sram[15] set to zero.
	LDR R1,R0 		;copy the value of R0(0~15) into R1 (SRAM[0]~SRAM[15])
	MOV [R1],#0		
	ADD R0,#1		
	JP B4,=GetVerType 		;IF R0 BIT4=1 JB GetVerType
	JP A1,=__reset_vector
;END
;----------------------ResetVector------------------------------
GetVerType:			
	MOV R1,#10			;[10] = VERSION
	MOV [R1],#0x8100		;version 101
	JP A1,=OperationPass
;END
;----------------------BusReset---------------------------------	
BusReset:
	JP A1,=OperationPass
;----------------------InitialChip------------------------------
InitialChip: 
	;Release from Deep Power-down
	MOV BSW3,#0xAB
	CALL =Send1Byte_CS_H
	CALL =Delay_10ms	
	
	MOV R1,#1
	LDR R0,[R1]
	JP B8,=IT2	;Check QE bit and Write Enable
	JP A1,=IT1	;Check Write Enable	

IT2:	;Check QE bit and Write Enable
	MOV R1,#1
	LDR R0,[R1]
	RSR R0,#16
	AND R0,#0xFF
	LDR R2,R0
	
	CALL =R_SR
	AND R0,#0x40
	
	XOR R0,R2
	JP Z,=IT1
	JP A1,=OperationFail
	
IT1:
	CALL =Polling_WEL_Bit 
	CALL =WriteDisable
	JP A1,=OperationPass
;--------------------------ReadID------------------------------
ReadID:  
	MOV R1,#1	;SRAM[1]: Config "InitParameter" parameter			
	LDR BSW3,[R1] 			
	CALL =Send1Byte_CS_L	
	CALL =Read4Byte_CS_H
	
	MOV R1,#16			
	LDR [R1],BSR0	;Copy ID value to SRAM[16]		
	JP A1,=OperationPass
;--------------------------Erase------------------------------
Erase:	
	CALL =Check_HPM
	CALL =Check4ByteMode
	CALL =UnLockChip
	
	MOV R1,#1
	LDR R0,[R1]
	JP B8,=BlockErase
		
;-------------Chip Erase	
ChipErase:	
	CALL =Polling_WEL_Bit 
	MOV R1,#1	;SRAM[1]: Config "ChipEraseParameter" parameter				
	LDR BSW3,[R1]
	CALL =Send1Byte_CS_H
	CALL =Polling_WIP_Bit
	CALL =Exit4ByteMode
	JP A1,=OperationPass	
	
;-------------Block Erase		
BlockErase:
	CALL =Polling_WEL_Bit	
	MOV R1,#1	;ChipEraseParameter
	LDR BSW3,[R1]
	CALL =Send1Byte_CS_L
	CALL =SendAddress_CS_H
	CALL =Polling_WIP_Bit
	MOV R1,#4	;BlockSizeInByte
	LDR R2,[R1]
	CALL =Update_AD_LS_DL
	JP Z,=BlockErase_Finish
	JP A1,=BlockErase	

BlockErase_Finish:	
	CALL =Exit4ByteMode
	JP A1,=OperationPass
;--------------------------BlankCheck------------------------------
BlankCheck:
	CALL =ClearDSET	
	MOV DSET,#0x7804
	
	CALL =Check_HPM

	CALL =CheckPartition3
	JP Z,=B_OTP		
	
;-------------BlankCheck Flash
	CALL =Check4ByteMode
	CALL =Check_Quad_Enable

B_Loop:
	MOV R1,#1	;ReadParameter	
	LDR R0,[R1]
	AND R0,#0xFF
	LDR R2,R0
	LDR BSW3,R0
	CALL =Send1Byte_CS_L
	
	LDR R0,R2
	XOR R0,#0x3B
	JP Z,=B_1
	
	LDR R0,R2
	XOR R0,#0x6B
	JP Z,=B_1

	LDR R0,R2
	XOR R0,#0xBB
	JP Z,=B_2
	
	LDR R0,R2
	XOR R0,#0xEB
	JP Z,=B_3	

	CALL =SendAddress_CS_L
	JP A1,=B_FIFO
	
B_1:;------Command 0x3B or 0x6B
	CALL =SendAddress_CS_L
	MOV BSW3,#0	;Dummy byte
	CALL =Send1Byte_CS_L
	JP A1,=B_FIFO	
B_2:;------Command 0xBB
	CALL =SendAddress_Dual_CS_L
	MOV BSW3,#0	;Dummy byte
	CALL =Send1Byte_Dual_CS_L
	JP A1,=B_FIFO
B_3:;------Command 0xEB
	CALL =SendAddress_Quad_CS_L
	MOV BSW3,#0	;Dummy byte
	CALL =Send3Byte_Quad_CS_L
	JP A1,=B_FIFO		

B_FIFO:	
	;Check Image Length >= 32768bytes?
	MOV R1,#3	;ImageLength			
	LDR R0,[R1]			
	SUB R0,#0x8000
	JP O,=B_Last
	JP Z,=B_Last

	MOV BSW2,#0x8000	;shift in 32768bytes
	CALL =R_FIFO_CS_H	
	
	MOV R0,#0x4000
	AND R0,CMPR	;For CRCR & CMPR : if bit14(result bit) is 1 then fail 
	JP BE,=OperationFail
	MOV R2,#0x8000
	CALL =Update_AD_LS_DL
	JP A1,=B_Loop
	
B_Last:
	MOV R1,#3	;ImageLength
	LDR BSW2,[R1]
	CALL =R_FIFO_CS_H

	MOV R0,#0x4000
	AND R0,CMPR	;For CRCR & CMPR : if bit14(result bit) is 1 then fail 
	JP BE,=OperationFail
	MOV R2,#0x8000
	CALL =Update_AD_LS_DL
	CALL =Check_Quad_Disable
	CALL =Exit4ByteMode
	JP A1,=OperationPass
	
;-------------BlankCheck OTP
B_OTP:
	CALL =Check4ByteMode
	CALL =EnterSecuredOTP

	MOV BSW3,#0x03	;normal read command
	CALL =Send1Byte_CS_L
	CALL =SendAddress_CS_L
	
	MOV R1,#3
	LDR BSW2,[R1]
	CALL =R_FIFO_Single_CS_H
	
	MOV R0,#0x4000
	AND R0,CMPR	;For CRCR & CMPR : if bit14(result bit) is 1 then fail 
	JP BE,=OperationFail

	CALL =ExitSecuredOTP
	CALL =Exit4ByteMode
	JP A1,=OperationPass
;--------------------------Program--------------------------------------
Program:
	CALL =ClearDSET
	MOV DSET,#0x8822
	
	CALL =Check_HPM
	
	CALL =CheckPartition2
	JP Z,=P_Register
	
	CALL =CheckPartition3
	JP Z,=P_OTP	
	
;-------------Program Flash	
	CALL =Check4ByteMode	
	CALL =UnLockChip
	CALL =Check_Quad_Enable

P_Loop:
	MOV R1,#17	;SRAM[17]: Config "UnprotectParameter" parameter
	LDR R0,[R1]
	JP B5,=UseKeyUnlock
	JP A1,=P_Loop2
UseKeyUnlock:
	CALL =UnLock7
	
P_Loop2:
	CALL =Polling_WEL_Bit
	MOV R1,#1	;ProgramParameter	
	LDR R0,[R1]
	AND R0,#0xFF
	LDR R2,R0
	LDR BSW3,R0
	CALL =Send1Byte_CS_L
	
	LDR R0,R2
	XOR R0,#0x33
	JP Z,=P_1
	
	LDR R0,R2
	XOR R0,#0x38
	JP Z,=P_1

	CALL =SendAddress_CS_L
	JP A1,=P_FIFO
	
P_1:
	CALL =SendAddress_Quad_CS_L
	JP A1,=P_FIFO	

P_FIFO:	
	JP DE,=this
	MOV R1,#4	;PageSizeInByte
	LDR BSW2,[R1]			
	CALL =Send_FIFO_CS_H
	CALL =Polling_WIP_Bit
	
	MOV R1,#4	;PageSizeInByte				
	LDR R2,[R1]				
	CALL =Update_AD_LS_DL
	JP Z,=P_Finish
	JP A1,=P_Loop
	
P_Finish:
	CALL =Check_Quad_Disable
	CALL =Exit4ByteMode
	JP A1,=OperationPass	
;-------;Program OTP	
P_OTP:
	CALL =Check4ByteMode
	CALL =EnterSecuredOTP
	
P_OTP_Loop:	
	CALL =Polling_WEL_Bit
	MOV BSW3,#0x02		
	CALL =Send1Byte_CS_L
	CALL =SendAddress_CS_L
	MOV R1,#3
	LDR R0,[R1]
	MOV R1,#4
	SUB R0,[R1]
	JP Z,=P_OTP_Last
	JP O,=P_OTP_Last	
	JP DE,=this		
	MOV R1,#4	;SRAM[4]: Config "PageSizeInByte" parameter
	LDR BSW2,[R1]			
	CALL =Send_FIFO_Single_CS_H
	CALL =Polling_WIP_Bit

	MOV R1,#4	;SRAM[4]: Config "PageSizeInByte" parameter
	LDR R2,[R1]
	CALL =Update_AD_LS_DL
	JP A1,=P_OTP_Loop
	
P_OTP_Last:			
	MOV R1,#3
	LDR BSW2,[R1]
	CALL =Send_FIFO_CS_H
	CALL =Polling_WIP_Bit			
	CALL =ExitSecuredOTP
	CALL =Exit4ByteMode
	JP A1,=OperationPass		

;-------Program Register
;SRAM[0x20]: Config "OptionCMD1" parameter
;SRAM[0x21]: Dialog SR value
;SRAM[0x22]: Dialog CR value
;SRAM[0x23]: Dialog SCUR value
;SRAM[0x24]: Dialog LR value
;SRAM[0x25]: Dialog SPBLR value
;SRAM[0x26]: Dialog ASP64PW_BYTE0_3 value
;SRAM[0x27]: Dialog ASP64PW_BYTE4_7 value
;SRAM[0x28]: Dialog Program_En value :
;	Bit[0] =1, Programming Status Register
;	Bit[1] =1, Programming Status Register and Configuration Register
;	Bit[2] =1, Programming Security Register LDSO bit
;	Bit[3] =1, Programming Security Register WPSEL bit
;	Bit[4] =1, Programming Password
;	Bit[5] =1, Programming Lock Register Password Protection Mode Lock Bit 
;	Bit[6] =1, Programming Lock Register Solid Protection Mode Lock Bit 
;	Bit[7] =1, Programming Lock Register SPB Lock Down Bit
;	Bit[8] =1, Programming SPB
;SRAM[0x29]: Dialog SPB_Count value	
;SRAM[0x2A]: Dialog SPB_address value
;SRAM[0x2B~0x6A]: Dialog SPB[64] value	
P_Register:  
	MOV R1,#0x20	;SRAM[0x20]: Config "OptionCMD1" parameter
	LDR R0,[R1]		
	JP BE,=P_Register7	;0x4000
	JP BD,=P_Register7	;0x2000
	JP BC,=P_Register6	;0x1000
	JP BB,=P_Register5	;0x800
	JP BA,=P_Register5	;0x400
	JP B9,=P_Register4	;0x200
	JP B8,=P_Register4 	;0x100 
	JP B7,=P_Register3	;0x80
	JP B6,=P_Register3 	;0x40 		
	JP B5,=P_Register3	;0x20
	JP B4,=P_Register2 	;0x10 	
	JP B3,=P_Register1	;0x08	
	JP B2,=P_Register1	;0x04
	JP B1,=P_Register1	;0x02
	JP B0,=P_Register1	;0x01    				
	JP A1,=OperationFail
	
;-------------------	
P_Register1:		
	CALL =P_SR
	JP A1,=OperationPass				
;-------------------
P_Register2:
	CALL =P_SR
	CALL =P_LDSO
	CALL =P_WPSEL
	JP A1,=OperationPass
;-------------------
P_Register3:
	CALL =P_SR
	CALL =P_LDSO
	JP A1,=OperationPass
;-------------------
P_Register4:
	CALL =P_SRCR
	CALL =P_LDSO
	CALL =P_WPSEL
	JP A1,=OperationPass
;-------------------
P_Register5:
	CALL =P_SRCR
	CALL =P_LDSO
	JP A1,=OperationPass
;-------------------
P_Register6:
	CALL =P_SRCR
	CALL =P_LDSO
	CALL =P_WPSEL
	CALL =P_SPB_SPBLKDN
	JP B0,=OperationFail
	CALL =P_LR
	JP B0,=OperationFail
	JP A1,=OperationPass
;-------------------
P_Register7:
	CALL =P_SRCR
	CALL =P_LDSO
	CALL =P_WPSEL
	CALL =P_PWD
	JP B0,=OperationFail
	CALL =P_LR
	JP B0,=OperationFail
	CALL =P_SPB
	JP B0,=OperationFail
	JP A1,=OperationPass
;------------------------------Verify--------------------------------------
Verify:
	CALL =ClearDSET
	MOV DSET,#0x6622	

	CALL =Check_HPM
	
	CALL =CheckPartition2
	JP Z,=V_Register
	
	CALL =CheckPartition3
	JP Z,=V_OTP	
	
;--------Verify Flash
	CALL =Check4ByteMode
	CALL =Check_Quad_Enable

V_Loop:
	MOV R1,#1	;ReadParameter	
	LDR R0,[R1]
	AND R0,#0xFF
	LDR R2,R0
	LDR BSW3,R0
	CALL =Send1Byte_CS_L
	
	LDR R0,R2
	XOR R0,#0x3B
	JP Z,=V_1
	
	LDR R0,R2
	XOR R0,#0x6B
	JP Z,=V_1

	LDR R0,R2
	XOR R0,#0xBB
	JP Z,=V_2
	
	LDR R0,R2
	XOR R0,#0xEB
	JP Z,=V_3	

	CALL =SendAddress_CS_L
	JP A1,=V_FIFO
	
V_1:;------Command 0x3B or 0x6B
	CALL =SendAddress_CS_L
	MOV BSW3,#0	;Dummy byte
	CALL =Send1Byte_CS_L
	JP A1,=V_FIFO	
V_2:;------Command 0xBB
	CALL =SendAddress_Dual_CS_L
	MOV BSW3,#0	;Dummy byte
	CALL =Send1Byte_Dual_CS_L
	JP A1,=V_FIFO
V_3:;------Command 0xEB
	CALL =SendAddress_Quad_CS_L
	MOV BSW3,#0	;Dummy byte
	CALL =Send3Byte_Quad_CS_L
	JP A1,=V_FIFO		

V_FIFO:	
	;Check Image Length >= 32768bytes?
	MOV R1,#3	;ImageLength			
	LDR R0,[R1]			
	SUB R0,#0x8000
	JP O,=V_Last
	JP Z,=V_Last
	
	JP DE,=this
	MOV BSW2,#0x8000	;shift in 32768bytes
	CALL =R_FIFO_CS_H	
	
	MOV R0,#0x4000
	AND R0,CMPR	;For CRCR & CMPR : if bit14(result bit) is 1 then fail 
	JP BE,=OperationFail
	MOV R2,#0x8000
	CALL =Update_AD_LS_DL
	JP A1,=V_Loop
	
V_Last:
	JP DE,=this
	MOV R1,#3	;ImageLength
	LDR BSW2,[R1]
	CALL =R_FIFO_CS_H

	MOV R0,#0x4000
	AND R0,CMPR	;For CRCR & CMPR : if bit14(result bit) is 1 then fail 
	JP BE,=OperationFail
	MOV R2,#0x8000
	CALL =Update_AD_LS_DL
	CALL =Check_Quad_Disable
	CALL =Exit4ByteMode
	MOV R1,#10
	LDR [R1],CRCR
	JP A1,=OperationPass
	
;--------Verify OTP
V_OTP:
	CALL =Check4ByteMode
	CALL =EnterSecuredOTP
	
	MOV BSW3,#0x03	;normal read command
	CALL =Send1Byte_CS_L
	CALL =SendAddress_CS_L
	
	JP DE,=this
	MOV R1,#3
	LDR BSW2,[R1]
	CALL =R_FIFO_Single_CS_H
	
	MOV R0,#0X4000      
	AND R0,CMPR	;For CRCR & CMPR : if bit14(result bit) is 1 then fail 
	JP BE,=OperationFail

	CALL =ExitSecuredOTP
	CALL =Exit4ByteMode
	MOV R1,#10
	LDR [R1],CRCR
	JP A1,=OperationPass
	
;-------Verify Register
;SRAM[0x20]: Config "OptionCMD1" parameter
;SRAM[0x21]: Dialog SR value
;SRAM[0x22]: Dialog CR value
;SRAM[0x23]: Dialog SCUR value
;SRAM[0x24]: Dialog LR value
;SRAM[0x25]: Dialog SPBLR value
;SRAM[0x26]: Dialog ASP64PW_BYTE0_3 value
;SRAM[0x27]: Dialog ASP64PW_BYTE4_7 value
;SRAM[0x28]: Dialog Program_En value :
;	Bit[0] =1, Programming Status Register
;	Bit[1] =1, Programming Status Register and Configuration Register
;	Bit[2] =1, Programming Security Register LDSO bit
;	Bit[3] =1, Programming Security Register WPSEL bit
;	Bit[4] =1, Programming Password
;	Bit[5] =1, Programming Lock Register Password Protection Mode Lock Bit 
;	Bit[6] =1, Programming Lock Register Solid Protection Mode Lock Bit 
;	Bit[7] =1, Programming Lock Register SPB Lock Down Bit
;	Bit[8] =1, Programming SPB
;SRAM[0x29]: Dialog SPB_Count value	
;SRAM[0x2A]: Dialog SPB_address value
;SRAM[0x2B~0x6A]: Dialog SPB[64] value	
V_Register:  
	MOV R1,#0x20	;SRAM[0x20]: Config "OptionCMD1" parameter
	LDR R0,[R1]	
	JP BE,=V_Register13	;0x4000	
	JP BD,=V_Register12	;0x2000
	JP BC,=V_Register11	;0x1000
	JP BB,=V_Register10	;0x800
	JP BA,=V_Register10	;0x400
	JP B9,=V_Register9	;0x200
	JP B8,=V_Register9 	;0x100 
	JP B7,=V_Register8	;0x80
	JP B6,=V_Register7 	;0x40 		
	JP B5,=V_Register6	;0x20
	JP B4,=V_Register5 	;0x10 	
	JP B3,=V_Register4	;0x08	
	JP B2,=V_Register3	;0x04
	JP B1,=V_Register2	;0x02
	JP B0,=V_Register1	;0x01    				
	JP A1,=OperationFail
	
;-------------------	
V_Register1:
	MOV R3,#0x8C
	CALL =V_SR
	JP Z,=OperationPass
	JP A1,=OperationFail	
;-------------------	
V_Register2:
	MOV R3,#0x9C
	CALL =V_SR
	JP Z,=OperationPass
	JP A1,=OperationFail
;-------------------	
V_Register3:
	MOV R3,#0xCC
	CALL =V_SR
	JP Z,=OperationPass
	JP A1,=OperationFail	
;-------------------	
V_Register4:
	MOV R3,#0xBC
	CALL =V_SR
	JP Z,=OperationPass
	JP A1,=OperationFail	
;-------------------	
V_Register5:
	MOV R3,#0xFC
	CALL =V_SR
	JP Z,=V_Register5_2
	JP A1,=OperationFail	
V_Register5_2:
	MOV R3,#0x80
	CALL =V_WPSEL
	JP Z,=V_Register5_3
	JP A1,=OperationFail
V_Register5_3:	
	MOV R3,#0x02
	CALL =V_LDSO
	JP Z,=OperationPass
	JP A1,=OperationFail
;-------------------	
V_Register6:
	MOV R3,#0xBC
	CALL =V_SR
	JP Z,=_V_Register6
	JP A1,=OperationFail
_V_Register6:
	MOV R3,#0x02
	CALL =V_LDSO
	JP Z,=OperationPass
	JP A1,=OperationFail	
;-------------------	
V_Register7:
	MOV R3,#0x9C
	CALL =V_SR
	JP Z,=_V_Register7
	JP A1,=OperationFail
_V_Register7:
	MOV R3,#0x02
	CALL =V_LDSO
	JP Z,=OperationPass
	JP A1,=OperationFail
;-------------------	
V_Register8:
	MOV R3,#0xFC
	CALL =V_SR
	JP Z,=_V_Register8
	JP A1,=OperationFail
_V_Register8:
	MOV R3,#0x02
	CALL =V_LDSO
	JP Z,=OperationPass
	JP A1,=OperationFail
;-------------------	
V_Register9:
	MOV R3,#0xFC
	CALL =V_SR
	JP Z,=V_Register9_2
	JP A1,=OperationFail
V_Register9_2:
	MOV R3,#0x08
	CALL =V_CR
	JP Z,=V_Register9_3
	JP A1,=OperationFail
V_Register9_3:
	MOV R3,#0x80
	CALL =V_WPSEL
	JP Z,=V_Register9_4
	JP A1,=OperationFail
V_Register9_4:	
	MOV R3,#0x02
	CALL =V_LDSO
	JP Z,=OperationPass
	JP A1,=OperationFail	
;-------------------	
V_Register10:
	MOV R3,#0xFC
	CALL =V_SR
	JP Z,=V_Register10_2
	JP A1,=OperationFail
V_Register10_2:
	MOV R3,#0x08
	CALL =V_CR
	JP Z,=V_Register10_3
	JP A1,=OperationFail
V_Register10_3:	
	MOV R3,#0x02
	CALL =V_LDSO
	JP Z,=OperationPass
	JP A1,=OperationFail
;-------------------	
V_Register11:
	MOV R3,#0xFC
	CALL =V_SR
	JP Z,=V_Register11_2
	JP A1,=OperationFail
V_Register11_2:
	MOV R3,#0x08
	CALL =V_CR
	JP Z,=V_Register11_3
	JP A1,=OperationFail
V_Register11_3:
	MOV R3,#0x80
	CALL =V_WPSEL
	JP Z,=V_Register11_4
	JP A1,=OperationFail
V_Register11_4:	
	MOV R3,#0x02
	CALL =V_LDSO
	JP Z,=V_Register11_5
	JP A1,=OperationFail
V_Register11_5:
	MOV R3,#0x40
	CALL =V_LR
	JP Z,=V_Register11_6
	JP A1,=OperationFail	
V_Register11_6:
	CALL =V_SPB
	JP B0,=OperationFail
	JP A1,=OperationPass
;-------------------	
V_Register12:
	MOV R3,#0xFC
	CALL =V_SR
	JP Z,=V_Register12_2
	JP A1,=OperationFail
V_Register12_2:
	MOV R3,#0x08
	CALL =V_CR
	JP Z,=V_Register12_3
	JP A1,=OperationFail
V_Register12_3:
	MOV R3,#0x80
	CALL =V_WPSEL
	JP Z,=V_Register12_4
	JP A1,=OperationFail
V_Register12_4:	
	MOV R3,#0x02
	CALL =V_LDSO
	JP Z,=V_Register12_5
	JP A1,=OperationFail
V_Register12_5:
	MOV R3,#0x06
	CALL =V_LR
	JP Z,=V_Register12_6
	JP A1,=OperationFail
V_Register12_6:
	CALL =V_SPB
	JP B0,=OperationFail
	JP A1,=OperationPass
;-------------------	
V_Register13:
	MOV R3,#0xFC
	CALL =V_SR
	JP Z,=V_Register13_2
	JP A1,=OperationFail
V_Register13_2:
	MOV R3,#0x08
	CALL =V_CR
	JP Z,=V_Register13_3
	JP A1,=OperationFail
V_Register13_3:
	MOV R3,#0x80
	CALL =V_WPSEL
	JP Z,=V_Register13_4
	JP A1,=OperationFail
V_Register13_4:	
	MOV R3,#0x02
	CALL =V_LDSO
	JP Z,=V_Register13_5
	JP A1,=OperationFail
V_Register13_5:
	MOV R3,#0x44
	CALL =V_LR
	JP Z,=V_Register13_6
	JP A1,=OperationFail
V_Register13_6:
	CALL =V_SPB
	JP B0,=OperationFail
	JP A1,=OperationPass	
;--------		
V_SR:	;-----parameter:R3, return:R0
	MOV R1,#0x28	;SRAM[0x28]: Dialog Program_En
	LDR R0,[R1]
	JP B0,=_V_SR
	JP B1,=_V_SR
	MOV R0,#0	
	XOR R0,#0	;v108	;R0=0=skip V_SR
	RET
_V_SR:	
	MOV R1,#0x21	;SRAM[0x21]: Dialog SR value
	LDR R0,[R1]
	AND R0,R3
	LDR R2,R0
	CALL =R_SR
	AND R0,R3
	XOR R0,R2
	RET
;--------		
V_CR:	;-----parameter:R3, return:R0
	MOV R1,#0x28	;SRAM[0x28]: Dialog Program_En
	LDR R0,[R1]
	JP B1,=_V_CR
	MOV R0,#0	
	XOR R0,#0	;v108	;R0=0=skip V_CR
	RET
_V_CR:	
	MOV R1,#0x22	;SRAM[0x22]: Dialog CR value
	LDR R0,[R1]
	AND R0,R3
	LDR R2,R0
	CALL =R_CR
	AND R0,R3
	XOR R0,R2
	RET
;--------		
V_LDSO:	;-----parameter:R3, return:R0
	MOV R1,#0x28	;SRAM[0x28]: Dialog Program_En
	LDR R0,[R1]
	JP B2,=V_SCUR
	MOV R0,#0	
	XOR R0,#0	;v108	;R0=0=skip V_LDSO
	RET
	
V_WPSEL:	;-----parameter:R3, return:R0
	MOV R1,#0x28	;SRAM[0x28]: Dialog Program_En
	LDR R0,[R1]
	JP B3,=V_SCUR
	MOV R0,#0	
	XOR R0,#0	;v108	;R0=0=skip V_WPSEL
	RET	
	
V_SCUR:	
	MOV R1,#0x23	;SRAM[0x23]: Dialog SCUR value
	LDR R0,[R1]
	AND R0,R3
	LDR R2,R0
	CALL =R_SCUR
	AND R0,R3
	XOR R0,R2
	RET
;--------
V_LR:	;-----parameter:R3, return:R0
	MOV R1,#0x28	;SRAM[0x28]: Dialog Program_En
	LDR R0,[R1]
	JP B5,=_V_LR
	JP B6,=_V_LR
	JP B7,=_V_LR
	MOV R0,#0
	XOR R0,#0	;v108	;R0=0=skip V_LR
	RET
_V_LR:
	MOV R1,#0x24	;SRAM[0x24]: Dialog LR value
	LDR R0,[R1]
	AND R0,R3
	LDR R2,R0
	CALL =R_LR
	AND R0,R3
	XOR R0,R2
	RET
;--------
;SRAM[0x29]: Get dialog SPB_Count value
;SRAM[0x2A]: Get dialog SPB_address value
;SRAM[0x2B~0x6A]: Get dialog SPB[64] value	
V_SPB:	;----return:R0
	MOV R1,#0x28	;SRAM[0x28]: Dialog Program_En
	LDR R0,[R1]
	JP B8,=V_SPB2
	MOV R0,#0	
	XOR R0,#0	;v108	;R0=0=skip V_SPB
	RET
	
V_SPB2:	
	MOV R1,#18	;SRAM[18]: SPB Address
	MOV R0,#0	;Clear Address
	LDR [R1],R0
	
	MOV R2,#0x01	;CheckBit
	MOV R3,#0x2B	;SRAM	
V_SPB_Loop:
	MOV R0,#32	;Count is 32 because one SRAM have 32bit;
V_SPB_Loop2:
	PUSH R0
	
		;Check SRAM[R3]:bitX is = 1?
		LDR R1,R3
		LDR R0,[R1]
		AND R0,R2
		XOR R0,R2
		JP Z,=VerifySPB	;if SRAM[R3] bitX =1 then Verify PPB
		JP A1,=V_SPB_UploadParamete		

	VerifySPB:
		MOV BSW3,#0xE2	;Read SPB Status command
		CALL =Send1Byte_CS_L
		
		PUSH R2
		
			;Send4ByteAddress_CS_L
			MOV R1,#18	;SRAM[18]: SPB Address
			LDR R2,[R1]
			CALL =Send4ByteAddress_CS_L
			
		POP R2
		
		CALL =Read1Byte_CS_H
		LDR R0,BSR0
		AND R0,#0xFF
		XOR R0,#0xFF	;FFh = SPB Protect
		JP Z,=V_SPB_UploadParamete
		JP A1,=V_SPB_Fail
		
	V_SPB_UploadParamete:
		;Increase SPB_address to read next Block
		MOV R1,#4	;SRAM[4]: Config "BlockSizeInByte" parameter
		LDR R0,[R1]
		MOV R1,#18	;SRAM[18]: SPB Address
		ADD R0,[R1]
		LDR [R1],R0	
		;left Shift CheckBit
		LDR R0,R2
		RSL R0,#1
		LDR R2,R0 
		;PPB_Count - 1
		MOV R1,#17	;SRAM[17]: BlockNumber= "SizeInByte"(config parameter)/"BlockSizeInByte"(config parameter)"
		LDR R0,[R1]
		SUB R0,#1
		LDR [R1],R0		
		JP Z,=V_SPB_Pass	
	
	POP R0
	SUB R0,#1
	JP Z,=Increase_V_SPB_SRAM
	JP A1,=V_SPB_Loop2
	
Increase_V_SPB_SRAM:
	;SRAM + 1 
	LDR R0,R3
	ADD R0,#1
	LDR R3,R0
	JP A1,=V_SPB_Loop
	
V_SPB_Pass:
	POP R0
	MOV R0,#0	;return:R0 = 0 = Pass
	RET
	
V_SPB_Fail:
	POP R0
	MOV R0,#1	;return:R0 = 1 = Fail
	RET
;--------------------------Read--------------------------------------
Read:
	CALL =ClearDSET
	MOV DSET,#0x8810

	CALL =Check_HPM
	
	CALL =CheckPartition2
	JP Z,=R_Register	
	
	CALL =CheckPartition3
	JP Z,=R_OTP

;-------Read Flash	
	CALL =Check4ByteMode
	CALL =Check_Quad_Enable

	MOV R1,#1	;ReadParameter	
	LDR R0,[R1]
	AND R0,#0xFF
	LDR R2,R0
	LDR BSW3,R0
	CALL =Send1Byte_CS_L	;Send command
	
	LDR R0,R2
	XOR R0,#0x3B
	JP Z,=R_1
	
	LDR R0,R2
	XOR R0,#0x6B
	JP Z,=R_1

	LDR R0,R2
	XOR R0,#0xBB
	JP Z,=R_2
	
	LDR R0,R2
	XOR R0,#0xEB
	JP Z,=R_3
	
;-------Read Flash(Command 0x3)
	CALL =SendAddress_CS_L
	JP A1,=R_FIFO
;-------Read Flash(Command 0x3B or 0x6B)
R_1:
	CALL =SendAddress_CS_L
	MOV BSW3,#0	;Dummy byte
	CALL =Send1Byte_CS_L
	JP A1,=R_FIFO
;-------Read Flash(Command 0xBB)
R_2:
	CALL =SendAddress_Dual_CS_L
	MOV BSW3,#0	;Dummy byte
	CALL =Send1Byte_Dual_CS_L
	JP A1,=R_FIFO	
;-------Read Flash(Command 0xEB)
R_3:
	CALL =SendAddress_Quad_CS_L
	MOV BSW3,#0	;Dummy byte
	CALL =Send3Byte_Quad_CS_L
	JP A1,=R_FIFO	
;-------
R_FIFO:	
	JP UF,=this
	MOV R1,#3	;ImageLength		
	LDR BSW2,[R1]	
	CALL =R_FIFO_CS_H
	CALL =Check_Quad_Disable
	CALL =Exit4ByteMode
	JP  A1,=OperationPass
	
;-------Read OTP
R_OTP:
	CALL =Check4ByteMode
	CALL =EnterSecuredOTP
	MOV BSW3,#0x03	;normal read command
	CALL =Send1Byte_CS_L
	CALL =SendAddress_CS_L	
	JP UF,=this
	MOV R1,#3	;SRAM[3]: uiImageLength	
	LDR BSW2,[R1]
	CALL =R_FIFO_Single_CS_H
	CALL =ExitSecuredOTP
	CALL =Exit4ByteMode	
	JP A1,=OperationPass
;--------Read Register
;SRAM[0x20]: Config "OptionCMD1" parameter
;SRAM[0x21]: Dialog SR value
;SRAM[0x22]: Dialog CR value
;SRAM[0x23]: Dialog SCUR value
;SRAM[0x24]: Dialog LR value
;SRAM[0x25]: Dialog SPBLR value
;SRAM[0x26]: Dialog ASP64PW_BYTE0_3 value
;SRAM[0x27]: Dialog ASP64PW_BYTE4_7 value
;SRAM[0x28]: Dialog Program_En value
;	Bit[0] =1, Programming Status Register
;	Bit[1] =1, Programming Status Register and Configuration Register
;	Bit[2] =1, Programming Security Register LDSO bit
;	Bit[3] =1, Programming Security Register WPSEL bit
;	Bit[4] =1, Programming Password
;	Bit[5] =1, Programming Lock Register Password Protection Mode Lock Bit 
;	Bit[6] =1, Programming Lock Register Solid Protection Mode Lock Bit 
;	Bit[7] =1, Programming Lock Register SPB Lock Down Bit
;	Bit[8] =1, Programming SPB
;SRAM[0x29]: Dialog SPB_Count value	
;SRAM[0x2A]: Dialog SPB_address value
;SRAM[0x2B~0x6A]: Dialog SPB[64] value	

;OperationDLL:
;	struct READ_BUF //for vector
;	{
;		unsigned short SR;
;		unsigned short SCUR;
;		unsigned short CR;
;		unsigned short LR;
;		unsigned short SPBLR;
;		unsigned short ASP64PW_BYTE0_3[2];
;		unsigned short ASP64PW_BYTE4_7[2];
;		unsigned short SPB[2048];	//MXIC IC max memory size is 1G-BIT (BlockNumber=ChipSizeInByte/BlockSizeInByte=134217728(1G)/65536=2048) 
;		//Invalid value : 5120-4114=1006bytes
;		unsigned short Invalid_value[503];
;	} struct_ReadBuf;//5120bytes

R_Register:  
	MOV R1,#0x20	;SRAM[0x20]: Config "OptionCMD1" parameter
	LDR R0,[R1]		
	JP BE,=R_Register6	;0x4000
	JP BD,=R_Register5	;0x2000
	JP BC,=R_Register4	;0x1000
	JP BB,=R_Register3	;0x800
	JP BA,=R_Register3	;0x400
	JP B9,=R_Register3	;0x200
	JP B8,=R_Register3	;0x100 
	JP B7,=R_Register2	;0x80
	JP B6,=R_Register2	;0x40 		
	JP B5,=R_Register2	;0x20
	JP B4,=R_Register2	;0x10 	
	JP B3,=R_Register1	;0x08	
	JP B2,=R_Register1	;0x04
	JP B1,=R_Register1	;0x02
	JP B0,=R_Register1	;0x01    				
	JP A1,=OperationFail
	
;--------
R_Register1:
	CALL =R_SR_UPFIFO
	JP A1,=R_Register_Final
;--------
R_Register2:
	CALL =R_SR_UPFIFO
	CALL =R_SCUR_UPFIFO
	JP A1,=R_Register_Final
;--------
R_Register3:
	CALL =R_SR_UPFIFO
	CALL =R_SCUR_UPFIFO
	CALL =R_CR_UPFIFO
	JP A1,=R_Register_Final
;--------
R_Register4:
	CALL =R_SR_UPFIFO
	CALL =R_SCUR_UPFIFO
	CALL =R_CR_UPFIFO
	CALL =R_LR_UPFIFO
	MOV BSW2,#10	;Skip SPBLR, ASP64PW_BYTE0_3[2], ASP64PW_BYTE4_7[2], Upload 10 byte blank value to FIFO 
	CALL =R_FIFO_Single_CS_H
	CALL =R_SPB_UPFIO
	JP A1,=R_Register_Final
;--------
R_Register5:
	CALL =R_SR_UPFIFO
	CALL =R_SCUR_UPFIFO
	CALL =R_CR_UPFIFO
	CALL =R_LR_UPFIFO
	CALL =R_SPBLR_UPFIFO
	CALL =R_PWD_UPFIO
	CALL =R_SPB_UPFIO
	JP A1,=R_Register_Final
;--------
R_Register6:
	CALL =R_SR_UPFIFO
	CALL =R_SCUR_UPFIFO
	CALL =R_CR_UPFIFO
	CALL =R_LR_UPFIFO
	CALL =R_PWD_UPFIO
	CALL =R_SPB_UPFIO
	JP A1,=R_Register_Final	
;--------
R_Register_Final:
	MOV R1,#3	;SRAM[3]: uiImageLength		
	LDR BSW2,[R1]
	CALL =R_FIFO_Single_CS_H
	JP  A1,=OperationPass	
;--------------------------Erase_SN---------------------------------
Erase_SN:
	CALL =Check_HPM
	CALL =Check4ByteMode
	CALL =UnLockChip	
	
SectorErase:
	CALL =Polling_WEL_Bit	
	MOV R1,#1	;ChipEraseParameter
	LDR BSW3,[R1]
	CALL =Send1Byte_CS_L
	CALL =SendAddress_CS_H
	CALL =Polling_WIP_Bit
	JP A1,=OperationPass		
;--------------------------Program_SN---------------------------------	
Program_SN:
	CALL =ClearDSET
	MOV DSET,#0x8822
	
	CALL =Check_HPM
	CALL =Check4ByteMode

;-------------Program Flash		
	CALL =UnLockChip

	MOV R1,#17	;SRAM[17]: Config "UnprotectParameter" parameter
	LDR R0,[R1]
	JP B5,=P_SN_UseKeyUnlock
	JP A1,=P_SN
P_SN_UseKeyUnlock:
	CALL =UnLock7
	
P_SN:
	CALL =Polling_WEL_Bit
	MOV R1,#1	;ProgramParameter	
	LDR R0,[R1]
	AND R0,#0xFF
	LDR R2,R0
	LDR BSW3,R0
	CALL =Send1Byte_CS_L
	
	CALL =SendAddress_CS_L

	MOV R2,#0x80	;SRAM
	MOV R1,#4	;PageSizeInByte
	LDR R0,[R1]
	SUB R0,#4
P_SN_SRAM:
	PUSH R0
	
		LDR R1,R2
		LDR BSW3,[R1]
		CALL =Send4Byte_CS_L
		
		LDR R0,R2
		ADD R0,#1
		LDR R2,R0
	
	POP R0
	SUB R0,#4
	JP Z,=P_SN_SRAM_Finish
	JP A1,=P_SN_SRAM
	
P_SN_SRAM_Finish:
	LDR R1,R2
	LDR BSW3,[R1]
	CALL =Send4Byte_CS_H
	CALL =Polling_WIP_Bit
	JP A1,=OperationPass
;-------------------------Function-------------------------
Update_AD_LS_DL:;--------------parameter:R2
	;IncreaseAddress
	MOV R1,#2			
	LDR R0,[R1]			
	ADD R0,R2			
	LDR [R1],R0				
	;UpdateLastSuccess
	MOV R1,#2
	LDR R0,[R1]		
	MOV R1,#9			
	LDR [R1],R0		
	;DecreaseDataLength
	MOV R1,#3			
	LDR R0,[R1]			
	SUB R0,R2			
	LDR [R1],R0		
	RET
;-------------------
CheckPartition2:	;---return R0
	MOV R1,#0	;operation area
	MOV R0,#1		
	XOR R0,[R1]
	RET
;-------------------
CheckPartition3:	;---return R0
	MOV R1,#0	;operation area
	MOV R0,#2		
	XOR R0,[R1]
	RET
;-------------------
P_PWD:	;Program Password Register----return:R0
	MOV R1,#0x28	;SRAM[0x28]: Dialog Program_En
	LDR R0,[R1]
	JP B4,=P_PWD_2
	JP A1,=P_PWD_Pass	;Skip P_PWD
	RET
	
P_PWD_2:
	CALL =R_SCUR
	JP B7,=P_PWD_3	;Check SCUR WPSEL bit=1?
	JP A1,=P_PWD_Fail
	
P_PWD_3:
	CALL =Polling_WEL_Bit
	MOV BSW3,#0x28	;;Write Password Register Command
	CALL =Send1Byte_CS_L
	MOV R1,#0x26	;SRAM[0x26]: Dialog ASP64PW_BYTE0_3 value
	LDR BSW3,[R1]
	CALL =Send4Byte_CS_L
	MOV R1,#0x27	;SRAM[0x27]: Dialog ASP64PW_BYTE4_7 value	
	LDR BSW3,[R1]	
	CALL =Send4Byte_CS_H
	CALL =Polling_WIP_Bit
	
	;Verify Password Register Byte0~byte3
	CALL =R_PWD
	MOV R1,#0x26	;SRAM[0x26]: Dialog ASP64PW_BYTE0_3 value
	LDR R0,[R1]
	XOR R0,BSR0	;BSR0:Password Byte0~byte3
	JP Z,=V_PWD_Byte4_7
	JP A1,=P_PWD_Fail
	
V_PWD_Byte4_7:	
	;Verify Password Register Byte4~byte7
	MOV R1,#0x27	;SRAM[0x27]: Dialog ASP64PW_BYTE4_7 value
	LDR R0,[R1]
	XOR R0,BSR1	;BSR1:Password Byte4~byte7
	JP Z,=P_PWD_Pass
	JP A1,=P_PWD_Fail	
	
P_PWD_Pass:
	MOV R0,#0	;return:R0=0=Pass
	RET	
	
P_PWD_Fail:
	MOV R0,#1	;return:R0=1=Fail
	RET
;-------------------		
P_LR: ;Write LockRegister----return:R0
	MOV R1,#0x28	;SRAM[0x28]: Dialog Program_En
	LDR R0,[R1]
	JP B5,=P_LR_2
	JP B6,=P_LR_2
	JP B7,=P_LR_2
	JP A1,=P_LR_Pass	;Skip P_LR
	RET
	
P_LR_2:
	CALL =R_SCUR
	JP B7,=P_LR_3	;Check SCUR WPSEL bit=1?
	JP A1,=P_LR_Fail

P_LR_3:
	CALL =Polling_WEL_Bit
	MOV BSW3,#0x2C	;Write Lock Register Comamnd
	CALL =Send1Byte_CS_L
	MOV R1,#0x24	;SRAM[0x24]: Dialog LR value
	LDR BSW3,[R1]
	CALL =Send2Byte_CS_H
	CALL =Polling_WIP_Bit
	JP A1,=P_LR_Pass
	
P_LR_Pass:
	MOV R0,#0	;return:R0=0=Pass
	RET		
	
P_LR_Fail:
	MOV R0,#1	;return:R0=1=Fail
	RET	
;-------------------	
P_SPB: ;Write SPB----return:R0
	MOV R1,#0x28	;SRAM[0x28]: Dialog Program_En
	LDR R0,[R1]
	JP B8,=P_SPB_CheckSCUR
	JP A1,=P_SPB_Pass	;Skip P_SPB
	RET
	
P_SPB_CheckSCUR:
	CALL =R_SCUR
	JP B7,=P_SPB_CheckLR	;Check SCUR WPSEL bit=1?
	JP A1,=P_SPB_Fail
	
P_SPB_CheckLR:
	CALL =R_LR
	AND R0,#0xF
	XOR R0,#0xB	;LR Bit 2(Password Protection Mode Lock Bit bit=0?)
	JP Z,=P_SPB_UnlockPassword
	JP A1,=P_SPB_Loop
	
P_SPB_UnlockPassword:
	CALL =Polling_WEL_Bit
	MOV BSW3,#0x29		;Password Unlock Command
	CALL =Send1Byte_CS_L
	MOV R1,#0x26	;SRAM[0x26]: Dialog ASP64PW_BYTE0_3 value
	LDR BSW3,[R1]
	CALL =Send4Byte_CS_L
	MOV R1,#0x27	;SRAM[0x27]: Dialog ASP64PW_BYTE4_7 value
	LDR BSW3,[R1]
	CALL =Send4Byte_CS_H
	CALL =Polling_WIP_Bit
	CALL =Delay_1ms	
	CALL =R_SCUR
	JP B5,=P_SPB_Fail	;If unlock password fail then security register bit5(P_FAIL) =1 
	JP A1,=P_SPB_Loop
	
P_SPB_Pass:
	MOV R0,#0	;return:R0=0=Pass
	RET		
	
P_SPB_Fail:
	MOV R0,#1	;return:R0=1=Fail
	RET
;-------------------	
P_SPB_SPBLKDN: ;Write SPB and Check SPBLKDN bit----return:R0
	MOV R1,#0x28	;SRAM[0x28]: Dialog Program_En
	LDR R0,[R1]
	JP B8,=P_SPB_SPBLKDN_CheckSCUR
	JP A1,=P_SPB_SPBLKDN_Pass	;Skip P_SPB_SPBLKDN
	RET
	
P_SPB_SPBLKDN_CheckSCUR:
	CALL =R_SCUR
	JP B7,=P_SPB_SPBLKDN_CheckLR	;Check SCUR WPSEL bit=1?
	JP A1,=P_SPB_SPBLKDN_Fail

P_SPB_SPBLKDN_CheckLR:
	CALL =R_LR
	AND R0,#0xF0
	XOR R0,#0xB0	;LR Bit 6(SPB Lock Down Bit=0?)
	JP Z,=P_SPB_SPBLKDN_Fail
	JP A1,=P_SPB_Loop
	
P_SPB_SPBLKDN_Pass:
	MOV R0,#0	;return:R0=0=Pass
	RET		

P_SPB_SPBLKDN_Fail:
	MOV R0,#1	;return:R0=1=Fail
	RET
;-------------------
;SRAM[0x29]: Get dialog SPB_Count value
;SRAM[0x2A]: Get dialog SPB_address value
;SRAM[0x2B~0x6A]: Get dialog SPB[64] value		
P_SPB_Loop:	;Write SPB Loop----return:R0
	MOV R2,#0x01	;CheckBit
	MOV R3,#0x2B	;SRAM
P_SPB_Loop2:
	MOV R0,#32	;Count is 32 because one SRAM have 32bit
P_SPB_Loop3:
	PUSH R0

		;Check SRAM[R3]:bitX is = 1?
		LDR R1,R3
		LDR R0,[R1]
		AND R0,R2
		XOR R0,R2
		JP Z,=ProgramSPB	;if SRAM[R3] bitX =1 then Program PPB
		JP A1,=SPB_UploadParamete
		
	ProgramSPB:
		MOV R0,#16	;Count
	ProgramSPB_Loop:
		PUSH R0		
		
			CALL =Polling_WEL_Bit
			MOV BSW3,#0xE3		;SPB Program Command
			CALL =Send1Byte_CS_L
			
			PUSH R2
			
				;Send4ByteAddress_CS_H
				MOV R1,#0x2A	;SRAM[0x2A]: Dialog SPB_address value
				LDR R2,[R1]
				CALL =Send4ByteAddress_CS_H
			
			POP R2
				
			CALL =Polling_WIP_Bit
			JP A1,=ProgramSPB_Loop1
			
		ProgramSPB_Loop1:
			;Increase PPB_address to write next sector
			MOV R1,#18	;SRAM[18]: Config "SectorSizeInByte" parameter
			LDR R0,[R1]
			MOV R1,#0x2A ;SRAM[0x2A]: Dialog SPB_address value
			ADD R0,[R1]
			LDR [R1],R0				
			
		POP R0
		SUB R0,#1
		JP Z,=SPB_UploadParamete1
		JP A1,=ProgramSPB_Loop
		
	SPB_UploadParamete:
		;Increase SPB_address to write next block
		MOV R1,#4	;SRAM[4]: Config "BlockSizeInByte" parameter
		LDR R0,[R1]
		MOV R1,#0x2A ;SRAM[0x2A]: Dialog SPB_address value
		ADD R0,[R1]
		LDR [R1],R0	
	SPB_UploadParamete1:
		;Left Shift CheckBit
		LDR R0,R2
		RSL R0,#1
		LDR R2,R0 
		;PPB_Count - 1
		MOV R1,#0x29	;SRAM[0x29]: Dialog SPB_Count value
		LDR R0,[R1]
		SUB R0,#1
		LDR [R1],R0		
		JP Z,=SPB_Pass
	
	POP R0	
	SUB R0,#1
	JP Z,=Increase_SPB_SRAM
	JP A1,=P_SPB_Loop3
	
Increase_SPB_SRAM:
	;SARM + 1
	LDR R0,R3
	ADD R0,#1
	LDR R3,R0
	JP A1,=P_SPB_Loop2

SPB_Pass:
	POP R0
	MOV R0,#0	;return:R0=0=Pass
	RET
;-------------------			
R_SR: ;Read StatusRegister----return:R0
	MOV BSW3,#0x05	
	CALL =Send1Byte_CS_L
	CALL =Read1Byte_CS_H
	LDR R0,BSR0
	AND R0,#0xFF
	RET
;-------------------		
R_CR: ;Read ConfigurationRegister----return:R0
	MOV BSW3,#0x15	
	CALL =Send1Byte_CS_L
	CALL =Read1Byte_CS_H
	LDR R0,BSR0
	AND R0,#0xFF
	RET
;-------------------			
R_SCUR: ;Read SecurityRegister----return:R0
	MOV BSW3,#0x2B
	CALL =Send1Byte_CS_L
	CALL =Read1Byte_CS_H
	LDR R0,BSR0
	AND R0,#0xFF
	RET
;-------------------			
R_LR: ;Read LockRegister----return:R0
	MOV BSW3,#0x2D
	CALL =Send1Byte_CS_L
	CALL =Read2Byte_CS_H
	LDR R0,BSR0
	AND R0,#0xFFFF
	RET
;------------------------Subroutines-------------------------
UnLockChip:
	MOV R1,#17	;SRAM[17]: Config "UnprotectParameter" parameter
	LDR R0,[R1]
	JP B5,=UnLock7	;0x20
	JP B4,=UnLock6	;0x10
	JP B3,=UnLock5	;0x08
	JP B2,=UnLock4	;0x04
	JP B1,=UnLock3	;0x02
	JP B0,=UnLock2	;0x01
	JP A1,=UnLock1
;---------	
UnLock1:
	CALL =ClearSR
	RET
;---------	
UnLock2:
	CALL =ClearSR
	CALL =R_SCUR
	JP B7,=_UnLock2	;Check Security Register bit7(WPSEL) = 1?
	RET
	
_UnLock2:
	CALL =UnlockDPB
	RET
;---------	
UnLock3:
	CALL =ClearSR
	CALL =R_SCUR
	JP B7,=_UnLock3	;Check Security Register bit7(WPSEL) = 1?
	RET
	
_UnLock3:
	CALL =UnlockSPB
	RET
;---------	
UnLock4:
	CALL =ClearSR
	CALL =R_SCUR
	JP B7,=_UnLock4	;Check Security Register bit7(WPSEL) = 1?
	RET
	
_UnLock4:
	CALL =R_LR
	AND R0,#0XF
	XOR R0,#0XB	;LR Bit 1(Password Protection Mode Lock Bit bit=0?)
	JP Z,=UnlockPassword_And_SPB_DPB
	CALL =UnlockDPB
	CALL =UnlockSPB
	RET
;---------	
UnLock5:
	CALL =ClearSR
	CALL =R_SCUR
	JP B7,=_UnLock5	;Check Security Register bit7(WPSEL) = 1?
	RET
	
_UnLock5:
	CALL =UnlockDPB
	CALL =UnlockSPB
	RET
;---------
UnLock6:
	CALL =Polling_WEL_Bit
	MOV BSW3,#0xF3
	CALL =Send1Byte_CS_H
	CALL =Polling_WIP_Bit
	RET
;---------
UnLock7:
	CALL =ClearSR
	MOV BSW3,#0xC3
	CALL =Send1Byte_CS_H
	MOV BSW3,#0xA5
	CALL =Send1Byte_CS_H
	MOV BSW3,#0xC3
	CALL =Send1Byte_CS_H
	MOV BSW3,#0xA5
	CALL =Send1Byte_CS_H	
	CALL =ClearSR
	CALL =R_SR
	JP B6,=UnLock7
	RET
	
;---------		
ClearSR:
	CALL =Polling_WEL_Bit
	MOV BSW3,#0x01	;Write Status Register command 
	CALL =Send1Byte_CS_L
	MOV BSW3,#0x00	;Data  
	CALL =Send1Byte_CS_H
	CALL =Polling_WIP_Bit	
	RET
	
UnlockDPB:
	CALL =Polling_WEL_Bit
	MOV BSW3,#0x98	;Gang Sector/Block Unlock (GBUN) Command
	CALL =Send1Byte_CS_H
	CALL =Polling_WIP_Bit
	RET	
	
UnlockSPB:
	CALL =Polling_WEL_Bit
	MOV BSW3,#0xE4	;SPB Erase command
	CALL =Send1Byte_CS_H
	CALL =Polling_WIP_Bit
	RET		
	
UnlockPassword_And_SPB_DPB:
	CALL =Polling_WEL_Bit
	MOV BSW3,#0x29		;Password Unlock Command
	CALL =Send1Byte_CS_L
	MOV R1,#0x26	;SRAM[0x26]: Dialog ASP64PW_BYTE0_3 value
	LDR BSW3,[R1]
	CALL =Send4Byte_CS_L
	MOV R1,#0x27	;SRAM[0x27]: Dialog ASP64PW_BYTE4_7 value
	LDR BSW3,[R1]
	CALL =Send4Byte_CS_H
	CALL =Polling_WIP_Bit
	CALL =Delay_1ms	
	CALL =UnlockDPB
	CALL =UnlockSPB
	RET
;-------------------	
ClearDSET:
	MOV DSET,#0x88C0
	DLYUS #5
	MOV DSET,#0x8800    ;need to restore Fifo reset signal to 0
	DLYUS #5
	LDR R0,FFLEN
	OR R0,#0
	JP Z,=Clear_Out
	JP A1,=ClearDSET
	
Clear_Out:
	RET
;-------------------
Polling_WEL_Bit: ;v109
	CALL =WriteEnable
	
_Polling_WEL_Bit:
	CALL =R_SR
	JP B1,=Polling_WEL_Bit_Exit
	JP A1,=_Polling_WEL_Bit
	
Polling_WEL_Bit_Exit:	
	RET
;-------------------
Polling_WIP_Bit: 
	DLYUS #1
	CALL =R_SR
	JP B0,=Polling_WIP_Bit ;If WIP bit=1 then the device is busy
	RET
;-------------------			
WriteEnable:
	MOV BSW3,#0x06	;write enable command
	CALL =Send1Byte_CS_H
	DLYUS #10
	RET
;-------------------			
WriteDisable:
	MOV BSW3,#0x04	;write disable command
	CALL =Send1Byte_CS_H
	RET			
;-------------------	
EnterSecuredOTP:
	MOV BSW3,#0xB1	;enter secured OTP command
	CALL =Send1Byte_CS_H
	RET
;-------------------
ExitSecuredOTP:
	MOV BSW3,#0xC1	;exit secured OTP command
	CALL =Send1Byte_CS_H
	RET
;-------------------
Check_HPM: ;Enable High Performance mode
	MOV R1,#1
	LDR R0,[R1]
	JP BE,=Enbale_HPM
	RET
Enbale_HPM:
	CALL =Polling_WEL_Bit
	MOV BSW3,#0x01	;Write Status Register Command
	CALL =Send1Byte_CS_L
	CALL =R_SR
	LDR BSW3,R0
	CALL =Send1Byte_CS_L
	CALL =R_CR
	LDR BSW3,R0
	CALL =Send1Byte_CS_L	
	MOV BSW2,#0x02	;Bit 1 = 1 = High performance mode
	CALL =Send1Byte_CS_H
	CALL =Polling_WIP_Bit
	RET
;-------------------	
SendAddress_CS_L:
	MOV R1,#2	;start address
	LDR R2,[R1]
	MOV R1,#1	
	LDR R0,[R1]	
	JP BD,=Send4ByteAddress_CS_L
	JP A1,=Send3ByteAddress_CS_L
	
Send4ByteAddress_CS_L:
	LDR R0,R2	;start address	bit31~bit24
	RSL R0,#8
	LDR BSW3,R0
	CALL =Send1Byte_CS_L	
Send3ByteAddress_CS_L:
	LDR R0,R2	;start address	bit23~bit16
	RSR R0,#16
	LDR BSW3,R0
	CALL =Send1Byte_CS_L
	LDR R0,R2	;start address	bit15~bit8
	RSR R0,#8
	LDR BSW3,R0
	CALL =Send1Byte_CS_L
	LDR BSW3,R2	;start address	bit7~bit0
	CALL =Send1Byte_CS_L
	RET	
;-------------------
SendAddress_Dual_CS_L:
	MOV R1,#2	;start address
	LDR R2,[R1]
	MOV R1,#1
	LDR R0,[R1]	
	JP BD,=Send4ByteAddress_Dual_CS_L
	JP A1,=Send3ByteAddress_Dual_CS_L
	
Send4ByteAddress_Dual_CS_L:
	LDR R0,R2	
	RSL R0,#8	
	LDR BSW3,R0	;start address bit31~bit24
	CALL =Send1Byte_Dual_CS_L		
Send3ByteAddress_Dual_CS_L:
	LDR R0,R2	
	RSR R0,#16	
	LDR BSW3,R0	;start address bit23~bit16
	CALL =Send1Byte_Dual_CS_L	
	LDR R0,R2		
	RSR R0,#8	
	LDR BSW3,R0	;start address bit15~bit8
	CALL =Send1Byte_Dual_CS_L
	LDR BSW3,R2	;start address bit7~bit0			
	CALL =Send1Byte_Dual_CS_L
	RET
;-------------------
SendAddress_Quad_CS_L:
	MOV R1,#2	;start address
	LDR R2,[R1]
	MOV R1,#1
	LDR R0,[R1]	
	JP BD,=Send4ByteAddress_Quad_CS_L
	JP A1,=Send3ByteAddress_Quad_CS_L
	
Send4ByteAddress_Quad_CS_L:
	LDR R0,R2	
	RSL R0,#8	
	LDR BSW3,R0	;start address bit31~bit24
	CALL =Send1Byte_Quad_CS_L		
Send3ByteAddress_Quad_CS_L:
	LDR R0,R2	
	RSR R0,#16	
	LDR BSW3,R0	;start address bit23~bit16
	CALL =Send1Byte_Quad_CS_L	
	LDR R0,R2		
	RSR R0,#8	
	LDR BSW3,R0	;start address bit15~bit8
	CALL =Send1Byte_Quad_CS_L
	LDR BSW3,R2	;start address bit7~bit0			
	CALL =Send1Byte_Quad_CS_L
	RET
;-------------------	
SendAddress_CS_H:
	MOV R1,#2	;start address
	LDR R2,[R1]
	MOV R1,#1	
	LDR R0,[R1]	
	JP BD,=Send4ByteAddress_CS_H
	JP A1,=Send3ByteAddress_CS_H
	
Send4ByteAddress_CS_H:
	LDR R0,R2	;start address	bit31~bit24
	RSL R0,#8
	LDR BSW3,R0
	CALL =Send1Byte_CS_L	
Send3ByteAddress_CS_H:
	LDR R0,R2	;start address	bit23~bit16
	RSR R0,#16
	LDR BSW3,R0
	CALL =Send1Byte_CS_L
	LDR R0,R2	;start address	bit15~bit8
	RSR R0,#8
	LDR BSW3,R0
	CALL =Send1Byte_CS_L
	LDR BSW3,R2	;start address	bit7~bit0
	CALL =Send1Byte_CS_H
	RET	
;-------------------	
Check4ByteMode:
	MOV R1,#1
	LDR R0,[R1]
	JP BD,=Enter4ByteMode
	RET
	
Enter4ByteMode:
	CALL =Polling_WEL_Bit
	MOV BSW3,#0xB7
	CALL =Send1Byte_CS_H	
	RET	
;-------------------		
Exit4ByteMode:	;V110
	MOV R1,#1
	LDR R0,[R1]
	JP BD,=_Exit4ByteMode
	RET
		
_Exit4ByteMode:	
	MOV BSW3,#0xE9
	CALL =Send1Byte_CS_H	
	RET			
;-------------------
Check_Quad_Enable:
	MOV R1,#1
	LDR R0,[R1]
	JP BA,=Quad_Enable
	RET
	
Quad_Enable:
	MOV R1,#16	;ProtectParameter
	LDR R0,[R1]
	JP B0,=Quad_Enable0
	RET
	
Quad_Enable0:	;QE in SR1 bit6
	CALL =R_SR
	OR R0,#0x40
	
	CALL =Polling_WEL_Bit
	MOV BSW3,#0x01	;Write Status Register-1 command
	CALL =Send1Byte_CS_L
	LDR BSW3,R0	;Status Register-1 data
	CALL =Send1Byte_CS_H
	CALL =Polling_WIP_Bit
	RET	
;-------------------
Check_Quad_Disable:
	MOV R1,#1
	LDR R0,[R1]
	JP BA,=Quad_Disable
	RET
	
Quad_Disable:
	MOV R1,#16	;ProtectParameter
	LDR R0,[R1]
	JP B0,=Quad_Disable0
	RET
	
Quad_Disable0:	;QE in SR1 bit6
	CALL =R_SR
	AND R0,#0xBF
	
	CALL =Polling_WEL_Bit
	MOV BSW3,#0x01	;Write Status Register-1 command
	CALL =Send1Byte_CS_L
	LDR BSW3,R0	;Status Register-1 data
	CALL =Send1Byte_CS_H
	CALL =Polling_WIP_Bit
	RET	
;-------------------		
P_SR:	;Write Status Register
	MOV R1,#0x28	;SRAM[0x28]: Dialog Program_En
	LDR R0,[R1]
	JP B0,=_P_SR
	RET
	
_P_SR:
	CALL =Polling_WEL_Bit
	MOV BSW3,#0x01	;Write Status Register Command
	CALL =Send1Byte_CS_L
	MOV R1,#0x21	;SRAM[0x21]: Dialog SR value
	LDR BSW3,[R1]
	CALL =Send1Byte_CS_H 
	CALL =Polling_WIP_Bit
	RET
;-------------------		
P_SRCR: ;Write Status Register and ConfigurationRegister
	MOV R1,#0x28	;SRAM[0x28]: Dialog Program_En
	LDR R0,[R1]
	JP B1,=_P_SRCR
	RET
	
_P_SRCR:
	CALL =Polling_WEL_Bit
	MOV BSW3,#0x01	;Write Status Register and ConfigurationRegister Command		
	CALL =Send1Byte_CS_L
	MOV R1,#0x21	;SRAM[0x21]: Dialog SR value
	LDR BSW3,[R1]
	CALL =Send1Byte_CS_L
	
	MOV R1,#0x22	;SRAM[0x22]: Dialog CR value
	LDR BSW3,[R1]
	CALL =Send1Byte_CS_H
	CALL =Polling_WIP_Bit 
	RET
;-------------------
P_LDSO:	;Write Security Register LDSO Bit
	MOV R1,#0x28	;SRAM[0x28]: Dialog Program_En
	LDR R0,[R1]
	JP B2,=_P_LDSO
	RET
	
_P_LDSO:
	CALL =Polling_WEL_Bit
	MOV BSW3,#0x2F	;Write Security Register Command
	CALL =Send1Byte_CS_H
	CALL =Polling_WIP_Bit
	RET
;-------------------
P_WPSEL:	;Write Security Register WPSEL Bit
	MOV R1,#0x28	;SRAM[0x28]: Dialog Program_En
	LDR R0,[R1]
	JP B3,=_P_WPSEL
	RET
	
_P_WPSEL:
	CALL =Polling_WEL_Bit
	MOV BSW3,#0x68	;Write Protect Selection Command
	CALL =Send1Byte_CS_H
	CALL =Polling_WIP_Bit
	RET
;-------------------		
R_PWD: ;Read PasswordRegister
	MOV BSW3,#0x27
	CALL =Send1Byte_CS_L
	CALL =Read8Byte_CS_H
	RET	
;-------------------	
R_SR_UPFIFO: ;Read Status Register Upload FIFO
	MOV BSW3,#0x05	
	CALL =Send1Byte_CS_L
	MOV BSW2,#2
	CALL =R_FIFO_Single_CS_H
	;DecreaseDataLength
	MOV R1,#3	;SRAM[3]: uiImageLength		
	LDR R0,[R1]
	SUB R0,#2
	LDR [R1],R0	
	RET
;-------------------		
R_CR_UPFIFO: ;Read Configuration Register Upload FIFO
	MOV BSW3,#0x15	
	CALL =Send1Byte_CS_L
	MOV BSW2,#2
	CALL =R_FIFO_Single_CS_H
	;DecreaseDataLength
	MOV R1,#3	;SRAM[3]: uiImageLength		
	LDR R0,[R1]
	SUB R0,#2
	LDR [R1],R0	
	RET
;-------------------		
R_SCUR_UPFIFO: ;Read Security Register Upload FIFO
	MOV BSW3,#0x2B	
	CALL =Send1Byte_CS_L
	MOV BSW2,#2
	CALL =R_FIFO_Single_CS_H
	;DecreaseDataLength
	MOV R1,#3	;SRAM[3]: uiImageLength		
	LDR R0,[R1]
	SUB R0,#2
	LDR [R1],R0	
	RET
;-------------------		
R_LR_UPFIFO: ;Read Lock Register Upload FIFO
	MOV BSW3,#0x2D	
	CALL =Send1Byte_CS_L
	MOV BSW2,#2
	CALL =R_FIFO_Single_CS_H
	;DecreaseDataLength
	MOV R1,#3	;SRAM[3]: uiImageLength		
	LDR R0,[R1]
	SUB R0,#2
	LDR [R1],R0	
	RET
;-------------------		
R_SPBLR_UPFIFO: ; Read SPB Lock Register Upload FIFO
	MOV BSW3,#0xA7	
	CALL =Send1Byte_CS_L
	MOV BSW2,#2
	CALL =R_FIFO_Single_CS_H
	;DecreaseDataLength
	MOV R1,#3	;SRAM[3]: uiImageLength		
	LDR R0,[R1]
	SUB R0,#2
	LDR [R1],R0	
	RET	
;-------------------		
R_PWD_UPFIO: ;Read Password Register Upload FIFO
	MOV BSW3,#0x27	
	CALL =Send1Byte_CS_L
	MOV BSW2,#8
	CALL =R_FIFO_Single_CS_H
	;DecreaseDataLength
	MOV R1,#3	;SRAM[3]: uiImageLength		
	LDR R0,[R1]
	SUB R0,#8
	LDR [R1],R0	
	RET		
;-------------------	
R_SPB_UPFIO:
	;DecreaseDataLength
	MOV R1,#17	;SRAM[17]: BlockNumber= "SizeInByte"(config parameter)/"BlockSizeInByte"(config parameter)"
	LDR R2,[R1]
	MOV R1,#3	;SRAM[3]: uiImageLength		
	LDR R0,[R1]
	SUB R0,R2
	LDR [R1],R0

	MOV R1,#18	;SRAM[18]: SPB Address
	MOV R0,#0	;Clear Address
	LDR [R1],R0
R_SPB_UPFIO_Loop:
	MOV BSW3,#0xE2	;Read SPB Status command
	CALL =Send1Byte_CS_L
	;Send4ByteAddress_CS_L
	MOV R1,#18	;SRAM[18]: SPB Address
	LDR R2,[R1]
	CALL =Send4ByteAddress_CS_L
	MOV BSW2,#2
	CALL =R_FIFO_Single_CS_H
	
	;Increase SPB_address
	MOV R1,#4	;SRAM[4]: Config "BlockSizeInByte" parameter
	LDR R0,[R1]
	MOV R1,#18 ;SRAM[18]: SPB Address
	ADD R0,[R1]
	LDR [R1],R0		
	;PPB_Count - 1
	MOV R1,#17	;SRAM[17]: BlockNumber= "SizeInByte"(config parameter)/"BlockSizeInByte"(config parameter)"
	LDR R0,[R1]
	SUB R0,#1
	LDR [R1],R0		
	JP Z,=R_SPB_UPFIO_out
	JP A1,=R_SPB_UPFIO_Loop
	
R_SPB_UPFIO_out:
	RET
;-------------------------Send Register CS Control--------------------------
Send1Byte_CS_L:
	MOV BSW0,#0x10  ;CS pull low after shifting, shift out, use register, single io
	MOV BSW2,#1		;shift 1 byte
	RUN
	JP BSY,=this
	RET

Send2Byte_CS_L:
	MOV BSW0,#0x10  ;CS pull low after shifting, shift out, use register, single io
	MOV BSW2,#2		;shift 2 byte
	RUN
	JP BSY,=this
	RET
	
Send3Byte_CS_L:
	MOV BSW0,#0x10  ;CS pull low after shifting, shift out, use register, single io
	MOV BSW2,#3		;shift 3 byte
	RUN
	JP BSY,=this
	RET
	
Send4Byte_CS_L:
	MOV BSW0,#0x10  ;CS pull low after shifting, shift out, use register, single io
	MOV BSW2,#4		;shift 4 byte
	RUN
	JP BSY,=this
	RET
	
Send1Byte_Dual_CS_L:
	MOV BSW0,#0x210  ;CS pull low after shifting, shift out, use register, dual io
	MOV BSW2,#1		;shift 1 byte
	RUN
	JP BSY,=this
	RET	
	
Send1Byte_Quad_CS_L:
	MOV BSW0,#0x410  ;CS pull low after shifting, shift out, use register, quad io
	MOV BSW2,#1		;shift 1 byte
	RUN
	JP BSY,=this
	RET	
	
Send3Byte_Quad_CS_L:
	MOV BSW0,#0x410  ;CS pull low after shifting, shift out, use register, quad io
	MOV BSW2,#3		;shift 1 byte
	RUN
	JP BSY,=this
	RET	

Send1Byte_CS_H:
	MOV BSW0,#0x12	;CS pull high after shifting, shift out, use register, single io
	MOV BSW2,#1		;shift 1 byte
	RUN
	JP BSY,=this
	RET

Send2Byte_CS_H:
	MOV BSW0,#0x12	;CS pull high after shifting, shift out, use register, single io
	MOV BSW2,#2		;shift 2 byte
	RUN
	JP BSY,=this
	RET
	
Send3Byte_CS_H:
	MOV BSW0,#0x12	;CS pull high after shifting, shift out, use register, single io
	MOV BSW2,#3		;shift 3 byte
	RUN
	JP BSY,=this
	RET
	
Send4Byte_CS_H:
	MOV BSW0,#0x12	;CS pull high after shifting, shift out, use register, single io
	MOV BSW2,#4		;shift 4 byte
	RUN
	JP BSY,=this
	RET
;-------------------------Read Register CS Control--------------------------
Read1Byte_CS_H:
	MOV BSW0,#0x22	;CS pull high after shifting, shift out, use register, single io
	MOV BSW2,#1		;shift 1 byte
	RUN
	JP BSY,=this
	RET

Read2Byte_CS_H:
	MOV BSW0,#0x22	;CS pull high after shifting, shift out, use register, single io
	MOV BSW2,#2		;shift 2 byte
	RUN
	JP BSY,=this
	RET

Read3Byte_CS_H:
	MOV BSW0,#0x22	;CS pull high after shifting, shift out, use register, single io
	MOV BSW2,#3		;shift 3 byte
	RUN
	JP BSY,=this
	RET

Read4Byte_CS_H:
	MOV BSW0,#0x22	;CS pull high after shifting, shift out, use register, single io
	MOV BSW2,#4		;shift 4 byte
	RUN
	JP BSY,=this
	RET
	
Read8Byte_CS_H:
	MOV BSW0,#0x22	;CS pull high after shifting, shift out, use register, single io
	MOV BSW2,#8		;shift 8 byte
	RUN
	JP BSY,=this
	RET
;-------------------------Send Byte, Use FIFO, CS Control--------------------------
Send_FIFO_Single_CS_H:
	MOV BSW0,#0x112
	RUN		
	JP BSY,=this
	RET

Send_FIFO_CS_H:
	MOV R1,#1
	LDR R0,[R1]
	AND R0,#0x600	;Select Single IO ,Dual IO or Quad IO according to ReadParameter(or ProgramParameter)
	OR R0,#0x112
	LDR BSW0,R0
	RUN		
	JP BSY,=this
	RET
;-------------------------Read Byte, Use FIFO, CS Control--------------------------
R_FIFO_Single_CS_H:
	MOV BSW0,#0x122
	RUN		
	JP BSY,=this
	RET		

R_FIFO_CS_H:
	MOV R1,#1
	LDR R0,[R1]
	AND R0,#0x600	;Select Single IO ,Dual IO or Quad IO according to ReadParameter(or ProgramParameter)
	OR R0,#0x122
	LDR BSW0,R0
	RUN		
	JP BSY,=this
	RET		
;------------------delay function--------------------
Delay_100ms: ;100ms
	PUSH R0
	MOV R0,#1000
	JP A1,=DT1
Delay_10ms:  ;10ms
	PUSH R0
	MOV R0,#100
	JP A1,=DT1
Delay_1ms:
	PUSH R0
	MOV R0,#10
	JP A1,=DT1
DT1:
	DLYUS #100
	SUB R0,#1
	JP Z,=DT1_out
	JP A1,=DT1
DT1_out:
	POP R0
	RET