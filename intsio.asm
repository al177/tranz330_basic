;==================================================================================
; Original by Grant Searle
; http://searle.hostei.com/grant/index.html
; eMail: home.micros01@btinternet.com
;
; Modifed by smbaker@smbaker.com for use as general-purpose IO for nixie tube
; clock. Also added support for CTC chip. Switched to SIO implementation instead
; of 68B50. Removed all basic-related stuff.
;
; Interrupts:
;    RST08 - TX the character in A reg on port A
;    RST10 - RX a character (A reg is port, 0=A or 1=B)
;    RST18 - Check port status (A reg is port, 0=A or 1=B)
;    RST20 - TX the character in A reg on port B
;    RST28 - Set baud rate (A is 1=1200, 2=2400, 9=9600, 19=19200, 115=115200)
;    RST38 - Hardware interrupt from SIO
;
;==================================================================================

; Full input buffering with incoming data hardware handshaking
; Handshake shows full before the buffer is totally filled to allow run-on from the sender

SER_BUFSIZE     .EQU     3FH
SER_FULLSIZE    .EQU     30H
SER_EMPTYSIZE   .EQU     5

; Address of CTC for PORT B serial for setting baud rates
CTC_PORTB       .EQU     11H

SIOA_D          .EQU     $20
SIOA_C          .EQU     $21
SIOB_D          .EQU     $22
SIOB_C          .EQU     $23

RTS_HIGH        .EQU    0E8H
RTS_LOW         .EQU    0EAH

serBuf          .EQU     $8000
serInPtr        .EQU     serBuf+SER_BUFSIZE
serRdPtr        .EQU     serInPtr+2
serBufUsed      .EQU     serRdPtr+2

serInMask       .EQU     serInPtr&$FF

ser2Buf         .EQU     $8050
ser2InPtr       .EQU     ser2Buf+SER_BUFSIZE
ser2RdPtr       .EQU     ser2InPtr+2
ser2BufUsed     .EQU     ser2RdPtr+2

ser2InMask      .EQU     ser2InPtr&$FF

keypad_last_keycode .EQU	$80A0
keypad_shift		.EQU	$80A1
keypad_buffer		.EQU	$80A2
display_char_index	.EQU	$80A3

TEMPSTACK       .EQU     $FFF0           ; temporary stack somewhere near the
                                         ; end of high mem

CR              .EQU     0DH
LF              .EQU     0AH
CS              .EQU     0CH             ; Clear screen

                .ORG $0000
;------------------------------------------------------------------------------
; Reset

RST00           DI                       ;Disable interrupts
                JP       INIT            ;Initialize Hardware and go

;------------------------------------------------------------------------------
; TX a character over RS232 

                .ORG     0008H
RST08            JP      TXB

;------------------------------------------------------------------------------
; RX a character over RS232 Channel, hold here until char ready.
; Reg A = 0 for port A, 1 for port B

                .ORG 0010H
RST10            JP      RXB

;------------------------------------------------------------------------------
; Check serial status
; Reg A = 0 for port A, 1 for port B

                .ORG 0018H
RST18            JP      CKINCHARB

;------------------------------------------------------------------------------
; TX a character over RS232 Channel B [Console]
                .ORG 0020H
RST20            JP      TXA

;------------------------------------------------------------------------------
; Set Baud rate
                .ORG 0028H
RST28            JP      SETBAUDB

;------------------------------------------------------------------------------
; Check serial status on port B

;                .ORG 0030H
;RST30            JP      CKINCHARB

;------------------------------------------------------------------------------
; RST 38 - INTERRUPT VECTOR [ for IM 1 ]

                .ORG     0038H
RST38            JR      serialInt

;------------------------------------------------------------------------------
; RST 3C - INTERRUPT VECTOR [ for IM 2 ]

                .ORG     003CH
RST3C           .WORD    serialInt
				.WORD	 0H

;------------------------------------------------------------------------------
; RST 40 - INTERRUPT VECTOR [ for IM 2 ]

                .ORG     0040H
RST40           .WORD	 pioInt
				.WORD	 0H

;------------------------------------------------------------------------------
; PIO isr - do nothing for now
pioInt:			EI
				RETI

;------------------------------------------------------------------------------
serialInt:      PUSH     AF
                PUSH     HL

                SUB      A

                OUT      (SIOA_C),A
                IN       A, (SIOA_C)
                RRCA
                JR       NC, check2

                IN       A,(SIOA_D)
                PUSH     AF
                LD       A,(serBufUsed)
                CP       SER_BUFSIZE     ; If full then ignore
                JR       NZ,notFull
                POP      AF
                JR       check2

notFull:        LD       HL,(serInPtr)
                INC      HL
                LD       A,L             ; Only need to check low byte becasuse buffer<256 bytes
                CP       serInMask
                JR       NZ, notWrap
                LD       HL,serBuf
notWrap:        LD       (serInPtr),HL
                POP      AF
                LD       (HL),A
                LD       A,(serBufUsed)
                INC      A
                LD       (serBufUsed),A
                CP       SER_FULLSIZE
                JR       C,check2
                ; set rts high
                LD       A, $05
                OUT      (SIOA_C),A
                LD       A,RTS_HIGH
                OUT      (SIOA_C),A

; port 2

check2:         SUB      A
                OUT      (SIOB_C),A
                IN       A, (SIOB_C)
                RRCA
                JR       NC, rts0

                IN       A,(SIOB_D)
                PUSH     AF
                LD       A,(ser2BufUsed)
                CP       SER_BUFSIZE     ; If full then ignore
                JR       NZ,notFull2
                POP      AF
                JR       rts0

notFull2:       LD       HL,(ser2InPtr)
                INC      HL
                LD       A,L             ; Only need to check low byte becasuse buffer<256 bytes
                CP       ser2InMask
                JR       NZ, notWrap2
                LD       HL,ser2Buf
notWrap2:       LD       (ser2InPtr),HL
                POP      AF
                LD       (HL),A
                LD       A,(ser2BufUsed)
                INC      A
                LD       (ser2BufUsed),A
                CP       SER_FULLSIZE
                JR       C,rts0
                ; set rts high
                LD       A, $05
                OUT      (SIOB_C),A
                LD       A,RTS_HIGH
                OUT      (SIOB_C),A

rts0:           POP      HL
                POP      AF
                EI
                RETI

;------------------------------------------------------------------------------
RXA:
waitForChar:    LD       A,(serBufUsed)
                CP       $00
                JR       Z, waitForChar
                PUSH     HL
                LD       HL,(serRdPtr)
                INC      HL
                LD       A,L             ; Only need to check low byte becasuse buffer<256 bytes
                CP       serInMask
                JR       NZ, notRdWrap
                LD       HL,serBuf
notRdWrap:      DI
                LD       (serRdPtr),HL
                LD       A,(serBufUsed)
                DEC      A
                LD       (serBufUsed),A
                CP       SER_EMPTYSIZE
                JR       NC,rts1
                ; set rts low
                LD       A, $05
                OUT      (SIOA_C),A
                LD       A,RTS_LOW
                OUT      (SIOA_C),A
rts1:
                LD       A,(HL)
                EI
                POP      HL
                RET                      ; Char ready in A

;------------------------------------------------------------------------------
RXB:
                CP      1               ; is A==1 ?
                JR      Z, RXA
waitForChar2:   LD       A,(ser2BufUsed)
                CP       $00
                JR       Z, waitForChar2
                PUSH     HL
                LD       HL,(ser2RdPtr)
                INC      HL
                LD       A,L             ; Only need to check low byte becasuse buffer<256 bytes
                CP       ser2InMask
                JR       NZ, notRdWrap2
                LD       HL,ser2Buf
notRdWrap2:     DI
                LD       (ser2RdPtr),HL
                LD       A,(ser2BufUsed)
                DEC      A
                LD       (ser2BufUsed),A
                CP       SER_EMPTYSIZE
                JR       NC,rts1_2
                ; set rts low
                LD       A, $05
                OUT      (SIOB_C),A
                LD       A,RTS_LOW
                OUT      (SIOB_C),A
rts1_2:
                LD       A,(HL)
                EI
                POP      HL
                RET                      ; Char ready in A

;------------------------------------------------------------------------------
TXA:            PUSH     AF              ; Store character
conout1:        SUB      A
                OUT      (SIOA_C),A
                IN       A,(SIOA_C)
                RRCA
                BIT      1,A             ; Set Zero flag if still transmitting character
                JR       Z,conout1       ; Loop until flag signals ready
                POP      AF              ; Retrieve character
                OUT      (SIOA_D),A      ; Output the character
                RET

;------------------------------------------------------------------------------
TXB:            PUSH     AF              ; Store character
conout1_2:      SUB      A
                OUT      (SIOB_C),A
                IN       A,(SIOB_C)
                RRCA
                BIT      1,A             ; Set Zero flag if still transmitting character
                JR       Z,conout1_2     ; Loop until flag signals ready
                POP      AF              ; Retrieve character
                OUT      (SIOB_D),A      ; Output the character
				PUSH		AF
				PUSH		BC	
				CP		 $0A			; test for linefeed
				JR		NZ, TXB_NOT_LF	
	
				CALL	display_clear
				JP		TXB_END
TXB_NOT_LF:		
				CP		'a'	
				JR		C, TXB_NOT_LCASE	; character is < 'a'
				CP		'z'+1
				JR		NC,	TXB_NOT_LCASE	; character is > 'z'
				AND		A, $DF				; mask bit 5
				
TXB_NOT_LCASE:

				LD		C,A
				CALL	display_send_byte
TXB_END:		
				POP		BC
                POP		AF
				RET

;------------------------------------------------------------------------------
CKINCHAR:       LD       A,(serBufUsed)
                CP       $0
                RET

PRINT:          LD       A,(HL)          ; Get character
                OR       A               ; Is it $00 ?
                RET      Z               ; Then RETurn on terminator
                RST      08H             ; Print it
                INC      HL              ; Next Character
                JR       PRINT           ; Continue until $00
                RET

PRINTB:         LD       A,(HL)          ; Get character
                OR       A               ; Is it $00 ?
                RET      Z               ; Then RETurn on terminator
                RST      20H             ; Print it
                INC      HL              ; Next Character
                JR       PRINTB           ; Continue until $00
                RET

;------------------------------------------------------------------------------

CKINCHARB:      CP      1               ; is A==1 ?
                JR      Z, CKINCHAR
		        LD       A,(ser2BufUsed)
                CP       $0
                RET

                ; Baud set routine
                ; Assumes trigger is connected to system clock of 7.3728 Mhz
                ; Assumes SIO/2 is configured with divide-by-16 clock

SETBAUDB:       CP       1
                JR       NZ, NOT1200
                LD       A, $5D
                OUT      (CTC_PORTB), A  ; 1200
                LD       A, 48 
                OUT      (CTC_PORTB), A
                RET
NOT1200:        CP       2
                JR       NZ, NOT2400
                LD       A, $5D
                OUT      (CTC_PORTB), A  ; 2400
                LD       A, 24
                OUT      (CTC_PORTB), A
                RET
NOT2400:        CP       9
                JR       NZ, NOT9600
                LD       A, $5D
                OUT      (CTC_PORTB), A  ; 9600
                LD       A, 12
                OUT      (CTC_PORTB), A
                RET
NOT9600:        CP       19
                JR       NZ, NOT19200
                LD       A, $5D
                OUT      (CTC_PORTB), A  ; 19200
                LD       A, 6
                OUT      (CTC_PORTB), A
NOT19200:       CP       115
                JR       NZ, NOT115200
                LD       A, $5D
                OUT      (CTC_PORTB), A  ; 115200
                LD       A, 1
                OUT      (CTC_PORTB), A
NOT115200:      RET


display_print_string:
    ; pointer to the string is in HL
    ; the string must be terminated with a 0 byte
    LD A,(HL)
    INC HL
    OR A
    RET Z
    LD C,A
    CALL display_send_byte
    JR display_print_string

display_clear:
	PUSH	BC
	PUSH	DE
    LD C,$AF           ; set the cursor to the beginning of the line
    CALL display_send_byte
    LD D,$10           ; 16 spaces to print
display_clear_l1:
	LD C,' '
    CALL display_send_byte
    DEC D
    JR NZ,display_clear_l1
	POP		DE
	POP		BC
    RET

display_send_byte:
    ; byte to be sent is in C
    ; note the display controller does not support lower-case letters!
	PUSH	AF
	PUSH	BC
	PUSH	DE
    LD B,$08           ; 8 bits to send
display_send_byte_l1:
	IN A,($00)         ; get current port state
    RLA                 ; rotate the port word until the data bit is in the carry flag
    RLA
    RLA
    RL C                ; shift the next output data bit into the carry flag
    RRA                 ; rotate the port word until the data bit is in bit 5
    RRA
    RRA
    OUT ($00),A        ; setup the output bit
    OR $40             ; set clock high (bit 6)
    OUT ($00),A
    AND $BF            ; set clock low (bit 6)
    OUT ($00),A
    DJNZ display_send_byte_l1  ; continue with the next bit
	POP		DE
	POP		BC
	POP		AF
    RET

keypad_read:
    ; columns can be activated by setting port 0 bits 3-0 low
    ; active rows be detected by sensing port 2 bits 3-0 low
    LD C,$FE           ; initial column mask
keypad_read_l1:
	IN A,($00)         ; get current port state
    OR $0F             ; disable all columns
    AND C               ; activate next column
    OUT ($00),A        
    IN A,($02)         ; read result
    AND $0F            ; mask the rows
    CP $0F             ; any rows active?
    JR NZ,keypad_read_key
    RLC C               ; adjust column mask
    LD A,$EF           ; was that the last column?
    CP C
    JR NZ,keypad_read_l1           ; next column
    LD A,$00           ; no keys are pressed
    RET

keypad_read_key:    
    LD B,A              ; put row data in B
    LD A,$00           ; initialize key code
keypad_read_key_l4:
	SRA B               ; shift right row data
    JR NC,keypad_read_key_l3           ; was that the active row?
    ADD A,$04          ; no, add 4 to key code
    JR keypad_read_key_l4
keypad_read_key_l3:
	SRA C               ; shift right column data
    JR NC,keypad_read_key_l5           ; was that the active column?
    INC A               ; no, add 1 to key code
    JR keypad_read_key_l3
keypad_read_key_l5:
	INC A               ; convert to 1-based key code
    RET

keycode_to_ascii:
    ; keycode is in A, result is returned in A
    SLA A               ; multiply keycode by 4
    SLA A
    LD HL,keypad_shift
    ADD A,(HL)          ; add the shift value
    LD E,A
    LD D,$00
    LD HL,keycode_table-4
    ADD HL,DE
    LD A,(HL)
    RET
    
keycode_table:
    .byte "1QZ.2ABC3DEFA   4GHI5JKL6MNOB   7PRS8TUV9WXYC   *,'"
	.byte 22H
	.byte "0- +#:;@D   "



;------------------------------------------------------------------------------
INIT:          LD        HL,TEMPSTACK    ; Temp stack
               LD        SP,HL           ; Set up a temporary stack
				IM 2                ; use mode 2 interrupts
				LD A,00H            ; interrupt vectors in page 0
				LD I,A

;       Initialise SIO

                LD      A,$30            ; write 0
                OUT     (SIOA_C),A
                LD      A,$18            ; reset ext/status interrupts
                OUT     (SIOA_C),A

                LD      A,$04            ; write 4
                OUT     (SIOA_C),A
                LD      A,$44            ; X64, no parity, 1 stop
                OUT     (SIOA_C),A

                LD      A,$01            ; write 1
                OUT     (SIOA_C),A
                LD      A,$00            ; no interrupt
                OUT     (SIOA_C),A

                LD      A,$03            ; write 3
                OUT     (SIOA_C),A
                LD      A,$E1            ; 8 bits, auto enable, rcv enab
                OUT     (SIOA_C),A

                LD      A,$05            ; write 5
                OUT     (SIOA_C),A
                LD      A,RTS_LOW		; dtr enable, 8 bits, tx enable, rts
                OUT     (SIOA_C),A

                LD      A,$30
                OUT     (SIOB_C),A
                LD      A,$18
                OUT     (SIOB_C),A

                LD      A,$04            ; write 4
                OUT     (SIOB_C),A
                LD      A,$44            ; X16, no parity, 1 stop
                OUT     (SIOB_C),A

                LD      A,$01
                OUT     (SIOB_C),A
                LD      A,$18
                OUT     (SIOB_C),A

                LD      A,$02           ; write reg 2
                OUT     (SIOB_C),A
                LD      A,$3C           ; INTERRUPT VECTOR ADDRESS
                OUT     (SIOB_C),A


                LD      A,$05
                OUT     (SIOB_C),A
                LD      A,RTS_LOW
                OUT     (SIOB_C),A
                
				LD      A,$03
                OUT     (SIOB_C),A
                LD      A,$C1			; Enable RX, 8 bit, no auto, no CRC
                OUT     (SIOB_C),A

               ; baud generator for 2nd serial port, default to 115200
               LD       A, 5DH
               OUT      (CTC_PORTB), A  ; 115200
               LD       A, 1
               OUT      (CTC_PORTB), A
				LD		A, 'H'
				CALL	TXB

				; Wipe SRAM
				LD		BC, 8000H
SRAM_WIPEL:		LD		A, 0
				LD		(BC), A
				INC		BC
				LD		A,B
				OR		C
				JR		NZ, SRAM_WIPEL


               ; initialize first serial port
               LD        HL,serBuf
               LD        (serInPtr),HL
               LD        (serRdPtr),HL
               XOR       A               ;0 to accumulator
               LD        (serBufUsed),A

               ; initialize second serial port
               LD        HL,ser2Buf
               LD        (ser2InPtr),HL
               LD        (ser2RdPtr),HL
               XOR       A               ;0 to accumulator
               LD        (ser2BufUsed),A

; From BMOW: init addl hw

    ; init port 0 - controls the display (bits 6,5,4) and keypad columns (bits 3,2,1,0)
    ; port 1 is the control register for port 0
    LD A,$CF           ; we want to control each port bit individually
    OUT ($01),A	
    LD A,$80           ; bit 7 is input, others are outputs
    OUT ($01),A
    LD A,$40           ; use interrupt vector 18
    OUT ($01),A
    LD A,$97           ; generate interrupt if any masked bit is low
    OUT ($01),A
    LD A,$7F           ; mask = bit 7
    OUT ($01),A
	
    LD A,$3F           ; set the initial output values for port 0	
    OUT ($00),A
	
    ; initialize the display
    IN A,($00)         ; get current port state
    AND $EF            ; clear bit 4 (display reset)
    OUT ($00),A
    LD B,$1C           ; wait $1C cycles
DISP_INIT1:
    DJNZ DISP_INIT1
    OR $10             ; set bit 4 (display reset)
    OUT ($00),A 
    LD C,$FF           ; set the display duty cycle to 31 (maximum brightness)
    CALL display_send_byte
    
    ; initialize the keypad input
    LD HL,keypad_last_keycode
    LD (HL),$00
    LD HL,keypad_shift
    LD (HL),$00
    ; print a prompt message
    CALL display_clear
    LD HL,WELCOME
    CALL display_print_string
    


               ; enable interrupts
               EI
                ; Clear any pending SIO port B interrupts
                LD      A,$00            ; write 0
                OUT     (SIOB_C),A
                LD      A,$10            ; reset ext/status interrupts
                OUT     (SIOB_C),A
				
				LD		A, 'I'
				CALL	TXB

               JP        $400             ; Run the program


WELCOME: .BYTE   "Hi",0,0

END
