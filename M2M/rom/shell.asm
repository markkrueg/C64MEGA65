; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; Shell: User interface and core automation
;
; The intention of the Shell is to provide a uniform user interface and core
; automation for all MiSTer2MEGA65 projects.
;
; done by sy2002 in 2021 and licensed under GPL v3
; ****************************************************************************

; ----------------------------------------------------------------------------
; Main Program
;
; START_SHELL is called from m2m-rom.asm as the main entry point to the Shell.
; The call is performed doing an RBRA not an RSUB, so the main program is
; not supposed to return to the caller.
; ----------------------------------------------------------------------------

                ; ------------------------------------------------------------
                ; Reset management
                ; ------------------------------------------------------------

                ; @TODO: different behavior of C64 core than in the framework
                ; make reset and pause behavior configurable in config.vhd
                ; Make sure that SCR$OSM_O_ON (and the others) are behaving
                ; consistent to this setting in config.vhd
                ; And anyway, as a first step the shell should keep the core
                ; in reset state for "a while" so that it can settle and we
                ; have no reset related bugs
START_SHELL     MOVE    M2M$CSR, R0             ; Reset core and clear all
                MOVE    M2M$CSR_RESET, @R0      ; other CSR flags, so that
                                                ; no keypress propagates to
                                                ; the core
                MOVE    100, R1
_RESET_A_WHILE  SUB     1, R1
                RBRA    _RESET_A_WHILE, !Z
                MOVE    0, @R0                  ; remove reset signal

                ; log M2M message to serial terminal (not visible to end user)
                MOVE    LOG_M2M, R8
                SYSCALL(puts, 1)

                ; ------------------------------------------------------------
                ; Initialize variables, libraries, IO and show welcome screen
                ; ------------------------------------------------------------

                ; initialize device (SD card) and file handle
                MOVE    HANDLE_DEV, R8
                MOVE    0, @R8
                MOVE    HANDLE_FILE, R8
                MOVE    0, @R8

                ; initialize file browser persistence variables
                MOVE    M2M$CSR, R8             ; get active SD card
                MOVE    @R8, R8
                AND     M2M$CSR_SD_ACTIVE, R8
                MOVE    SD_ACTIVE, R9
                MOVE    R8, @R9
                RSUB    FB_INIT, 1              ; init persistence variables
                MOVE    FB_HEAP, R8             ; heap for file browsing
                MOVE    HEAP, @R8                 
                ADD     MENU_HEAP_SIZE, @R8

                ; make sure OPTM_HEAP is initialized to zero, as it will be
                ; calculated and activated inside HELP_MENU
                MOVE    OPTM_HEAP, R8
                MOVE    0, @R8
                MOVE    OPTM_HEAP_SIZE, R8
                MOVE    0, @R8

                ; initialize screen library and show welcome screen:
                ; draw frame and print text
                RSUB    SCR$INIT, 1             ; retrieve VHDL generics
                RSUB    FRAME_FULLSCR, 1        ; draw fullscreen frame
                MOVE    M2M$RAMROM_DEV, R0      ; Device = config data
                MOVE    M2M$CONFIG, @R0
                MOVE    M2M$RAMROM_4KWIN, R0    ; Selector = Welcome screen
                MOVE    M2M$CFG_WELCOME, @R0
                MOVE    M2M$RAMROM_DATA, R8     ; R8 = welcome screen string
                RSUB    SCR$PRINTSTR, 1

                ; switch on main OSM
                RSUB    SCR$OSM_M_ON, 1

                ; initialize all other libraries as late as here, so that
                ; error messages (if any) can be printed on screen because the
                ; screen is already initialized using the sequence above
                RSUB    KEYB$INIT, 1            ; keyboard library
                RSUB    HELP_MENU_INIT, 1       ; menu library                

                ; Wait for "Space to continue"
                ; TODO: The whole startup behavior of the Shell needs to be
                ; more flexible than this, see also README.md
START_SPACE     RSUB    KEYB$SCAN, 1
                RSUB    KEYB$GETKEY, 1
                CMP     M2M$KEY_SPACE, R8
                RBRA    START_SPACE, !Z         ; loop until Space was pressed

                ; Hide OSM and connect keyboard and joysticks to the core
                RSUB    SCR$OSM_OFF, 1

                ; Avoid that the keypress to exit the splash screen gets
                ; noticed by the core: Wait 1 second and only after that
                ; connect the keyboard and the joysticks to the core
                RSUB    WAIT333MS, 1
                MOVE    M2M$CSR, R0
                OR      M2M$CSR_KBD_JOY, @R0

                ; if drives have been mounted, the mount strobe needs to be
                ; renewed after a reset, as the reset signal also resets
                ; the state of vdrives.vhd
                ;RSUB    PREPARE_CORE_IO, 1

                ; ------------------------------------------------------------
                ; Main loop:
                ;
                ; The core is running and QNICE is waiting for triggers to
                ; react. Such triggers could be for example the "Help" button
                ; which is meant to open the options menu but also triggers
                ; from the core such as data requests from disk drives.
                ;
                ; The latter one could also be done via interrupts, but we
                ; will try to keep it simple in the first iteration and only
                ; increase complexity by using interrupts if neccessary.
                ; ------------------------------------------------------------

MAIN_LOOP       RSUB    HANDLE_IO, 1            ; IO handling (e.g. vdrives)
                RSUB    CHECK_DEBUG, 1          ; (Run/Stop+Cursor Up) + Help

                RSUB    KEYB$SCAN, 1            ; scan for single key presses
                RSUB    KEYB$GETKEY, 1

                RSUB    HELP_MENU, 1            ; check/manage help menu

                RBRA    MAIN_LOOP, 1

; ----------------------------------------------------------------------------
; SD card & virtual drive mount handling
; ----------------------------------------------------------------------------

; Handle mounting:
;
; Input:
;   R8 contains the drive number
;   R9: 0=unmount drive, if it has been mounted before
;       @TODO:
;       1=just replace the disk image, if it has been mounted
;         before without unmounting the drive (aka resetting
;         the drive/"switching the drive on/off")
HANDLE_MOUNTING SYSCALL(enter, 1)

                MOVE    R8, R7                  ; R7: drive number
                MOVE    R9, R6                  ; R6: mount mode

                RSUB    VD_MOUNTED, 1           ; C=1: the given drive in R8..
                RBRA    _HM_MOUNTED, C          ; ..is already mounted

                ; Drive in R8 is not yet mounted:
                ; 1. Hide OSM to enable the full-screen window
                ; 2. If the SD card is not yet mounted: mount it and handle
                ;    errors, allow re-tries, etc.
                ; 3. As soon as the SD card is mounted: Show the file browser
                ;    and let the user select a disk image
                ; 4. Copy the disk image into the mount buffer and hide
                ;    the fullscreen OSM afterwards
                ; 5. Notify MiSTer using the "SD" protocol (see vdrives.vhd)
                ; 6. Redraw and show the OSM, including the disk images
                ;    of the mounted drives

                ; Step #1 - Hide OSM and show full-screen window
_HM_START_MOUNT RSUB    SCR$OSM_OFF, 1
_HM_RETRY_MOUNT RSUB    FRAME_FULLSCR, 1
                MOVE    1, R8
                MOVE    1, R9
                RSUB    SCR$GOTOXY, 1
                RSUB    SCR$OSM_M_ON, 1

                ; Step #2 - Mount SD card
                MOVE    HANDLE_DEV, R8          ; device handle
                CMP     0, @R8
                RBRA    _HM_SDMOUNTED1, !Z

_HM_SDUNMOUNTED MOVE    1, R9                   ; partition #1 hardcoded
                SYSCALL(f32_mnt_sd, 1)
                CMP     0, R9                   ; R9=error code; 0=OK
                RBRA    _HM_SDMOUNTED2, Z

                ; Mounting did not work - offer retry
                MOVE    ERR_MOUNT, R8
                RSUB    SCR$PRINTSTR, 1
                MOVE    R9, R8
                MOVE    SCRATCH_HEX, R9
                RSUB    WORD2HEXSTR, 1
                MOVE    R9, R8
                RSUB    SCR$PRINTSTR, 1
                MOVE    ERR_MOUNT_RET, R8
                RSUB    SCR$PRINTSTR, 1
                RSUB    WAIT333MS, 1
_HM_KEYLOOP     MOVE    M2M$KEYBOARD, R8
                AND     M2M$KEY_RETURN, @R8
                RBRA    _HM_KEYLOOP, !Z         ; wait for return; low-active
                MOVE    HANDLE_DEV, R8
                MOVE    0, @R8 
                RBRA    _HM_RETRY_MOUNT, 1

                ; SD card already mounted, but is it still the same card slot?
_HM_SDMOUNTED1  MOVE    SD_ACTIVE, R0
                MOVE    M2M$CSR, R1             ; extract currently active SD
                MOVE    @R1, R1
                AND     M2M$CSR_SD_ACTIVE, R1
                CMP     @R0, R1
                RBRA    _HM_SDMOUNTED2, Z       ; still same slot
                MOVE    R1, @R0                 ; different slot: remember it
                RBRA    _HM_SDUNMOUNTED, 1      ; and treat it as unmounted

                ; SD card freshly mounted or already mounted and still
                ; the same card slot:
                ;
                ; Step #3: Show the file browser & let user select disk image
                ;
                ; Run file- and directory browser. Returns:
                ;   R8: pointer to filename string
                ;   R9: status- and error code (see selectfile.asm)
                ;
                ; The status of the device handle HANDLE_DEV will be at the
                ; subdirectory that has been selected so that a subsequent
                ; file open can be directly done.
_HM_SDMOUNTED2  RSUB    SELECT_FILE, 1

                ; No error and no special status
                CMP     0, R9
                RBRA    _HM_SDMOUNTED3, Z

                ; Handle SD card change during file-browsing
                CMP     1, R9                   ; SD card changed?
                RBRA    _HM_SDMOUNTED2A, !Z     ; no
                MOVE    LOG_STR_SD, R8
                SYSCALL(puts, 1)
                MOVE    HANDLE_DEV, R8          ; reset device handle
                MOVE    0, @R8
                RSUB    FB_INIT, 1              ; reset file browser
                RBRA    _HM_SDUNMOUNTED, 1      ; re-mount, re-browse files

                ; Cancelled via Run/Stop
_HM_SDMOUNTED2A CMP     2, R9                   ; Run/Stop?
                RBRA    _HM_SDMOUNTED2B, !Z     ; no
                SYSCALL(exit, 1)

                ; Unknown error / fatal
_HM_SDMOUNTED2B MOVE    ERR_BROWSE_UNKN, R8     ; and R9 contains error code
                RBRA    FATAL, 1                

                ; Step #4: Copy the disk image into the mount buffer
_HM_SDMOUNTED3  MOVE    R8, R0                  ; R8: selected file name
                MOVE    LOG_STR_FILE, R8        ; log to UART
                SYSCALL(puts, 1)
                MOVE    R0, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)

                ; remember the file name for displaying it in the OSM
                ; the convention for the position in the @OPTM_HEAP is:
                ; virtual drive number times @SCR$OSM_O_DX
                MOVE    R8, R2                  ; R2: file name
                MOVE    OPTM_HEAP, R0
                MOVE    @R0, R0
                RBRA    _HM_SDMOUNTED5, Z       ; OPTM_HEAP not ready, yet
                MOVE    R7, R8
                MOVE    SCR$OSM_O_DX, R9
                MOVE    @R9, R9
                SYSCALL(mulu, 1)
                ADD     R10, R0                 ; R0: string ptr for file name
                MOVE    R9, R1                  ; R1: maximum string length
                SUB     2, R1                   ; minus 2 because of frame

                ; if the length of the name is <= the maximum size then just
                ; copy as is; otherwise copy maximum size + 1 so that the
                ;  ellipsis is triggered (see _OPTM_CBS_REPL in options.asm)
                MOVE    R2, R8
                SYSCALL(strlen, 1)
                CMP     R9, R1                  ; strlen(name) > maximum?
                RBRA    _HM_SDMOUNTED4, N       ; yes
                MOVE    R2, R8
                MOVE    R0, R9
                SYSCALL(strcpy, 1)
                RBRA    _HM_SDMOUNTED5, 1

                ; strlen(name) > maximum: copy maximum + 1 to trigger ellipsis
_HM_SDMOUNTED4  MOVE    R2, R8
                MOVE    R0, R9
                MOVE    R1, R10
                ADD     1, R10
                SYSCALL(memcpy, 1)
                ADD     R10, R9                 ; add zero terminator
                MOVE    0, @R9

                ; set "%s is replaced" flag for filename string to zero                
_HM_SDMOUNTED5  MOVE    SCR$OSM_O_DX, R8        ; set "%s is replaced" flag
                MOVE    @R8, R8
                SUB     1, R8
                ADD     R0, R8
                MOVE    0, @R8

                ; load the disk image to the mount buffer
                MOVE    R7, R8                  ; R8: drive ID to be mounted
                MOVE    R2, R9                  ; R9: file name of disk image                
                RSUB    LOAD_IMAGE, 1           ; copy disk img to mount buf.
                CMP     0, R8                   ; everything OK?
                RBRA    _HM_SDMOUNTED6, Z       ; yes

                ; loading the disk image did not work
                ; none of the errors that LOAD_IMAGE returns is fatal, so we
                ; will show an error message to the user and then we will
                ; let him chose another file
                SYSCALL(exit, 1)                

_HM_SDMOUNTED6  MOVE    R9, R6                  ; R6: disk image type
                RSUB    SCR$OSM_OFF, 1          ; hide the big window

                ; Step #5: Notify MiSTer using the "SD" protocol
                MOVE    R7, R8                  ; R8: drive number
                MOVE    HANDLE_FILE, R9
                ADD     FAT32$FDH_SIZE_LO, R9
                MOVE    @R9, R9                 ; R9: file size: low word
                MOVE    HANDLE_FILE, R10
                ADD     FAT32$FDH_SIZE_HI, R10
                MOVE    @R10, R10               ; R10: file size: high word
                MOVE    1, R11                  ; R11=1=read only @TODO
                MOVE    R6, R12                 ; R12: disk image type
                RSUB    VD_STROBE_IM, 1         ; notify MiSTer

                MOVE    LOG_STR_MOUNT, R8
                SYSCALL(puts, 1)
                MOVE    R7, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)

                ; 6. Redraw and show the OSM
                RSUB    OPTM_SHOW, 1            
                RSUB    SCR$OSM_O_ON, 1
                RBRA    _HM_RET, 1

                ; Virtual drive (number in R8) is already mounted
                ; @TODO: Support two cases:
                ; R9=0 (see function description above) and R9=1
                ; Right now we just switch the disk image in the drive, i.e
                ; we are hardcoded performing the case R9=1

                ; Make sure the current drive stays selected in M2M$CFM_DATA.
                ; The standard semantics of menu.asm is that single-select
                ; menu items are toggle-items, so a second drive mount is
                ; toggling the single-select item to OFF. We are re-setting
                ; the OPTM_IR_STDSEL data structure to make sure that
                ; M2M$CFM_DATA is correctly treated inside OPTM_CB_SEL in
                ; options.asm. It is actually options.asm that adds drive
                ; mounting semantics to the rather generic menu.asm.
                ; This also makes sure that re-opening the menu shows the
                ; visual representation of "successfuly mounted".
                ;
                ; But menu.asm already has deleted the visual representation
                ; at this point, so we need to hack the visual representation
                ; of the currently open menu and actually print it.
_HM_MOUNTED     MOVE    R7, R8                  ; R7: virtual drive number
                RSUB    VD_MENGRP, 1            ; get index of menu item
                RBRA    _HM_MOUNTED_1, C

                MOVE    ERR_FATAL_INST, R8
                MOVE    ERR_FATAL_INST2, R9
                RBRA    FATAL, 1 

_HM_MOUNTED_1   MOVE    OPTM_DATA, R8
                MOVE    @R8, R8
                ADD     OPTM_IR_STDSEL, R8
                MOVE    @R8, R8
                ADD     R9, R8                  ; R9 contains menu index
                MOVE    R9, R11                 ; save menu index
                MOVE    1, @R8                  ; re-set single-select flag

                MOVE    OPTM_DATA, R8           ; R8: single-select char
                MOVE    @R8, R8
                MOVE    OPTM_IR_SEL, R8
                MOVE    @R8, R8
                ADD     2, R8
                MOVE    OPTM_X, R9              ; R9: x-pos
                MOVE    @R9, R9
                ADD     1, R9                   ; x-pos on screen b/c frame
                MOVE    OPTM_Y, R10             ; R10: y-pos
                MOVE    @R10, R10
                ADD     R11, R10                ; add menu index
                ADD     1, R10                  ; y-pos on screen b/c frame
                RSUB    SCR$PRINTSTRXY, 1

                RBRA    _HM_START_MOUNT, 1      ; show browser and mount

_HM_RET         SYSCALL(leave, 1)
                RET

; Load disk image to virtual drive buffer (VDRIVES_BUFS)
;
; Input:
;   R8: drive number
;   R9: file name of disk image
;
; And HANDLE_DEV needs to be fully initialized and the status needs to be
; such, that the directory where R9 resides is active
;
; Output:
;   R8: 0=OK, error code otherwise
;   R9: image type if R8=0, otherwise 0 or optional ptr to  error msg string
LOAD_IMAGE      SYSCALL(enter, 1)

                MOVE    VDRIVES_BUFS, R0
                ADD     R8, R0
                MOVE    @R0, R0                 ; R0: device number of buffer
                MOVE    R0, R8

                MOVE    R8, R1                  ; R1: drive number
                MOVE    R9, R2                  ; R2: file name

                ; Open file
                MOVE    HANDLE_DEV, R8
                MOVE    HANDLE_FILE, R9
                MOVE    R2, R10
                XOR     R11, R11
                SYSCALL(f32_fopen, 1)
                CMP     0, R10                  ; R10=error code; 0=OK
                RBRA    _LI_FOPEN_OK, Z
                MOVE    ERR_FATAL_FNF, R8
                MOVE    R10, R9
                RBRA    FATAL, 1

                ; Callback function that can handle headers, sanity check
                ; the disk image, determine the type of the disk image, etc.
_LI_FOPEN_OK    MOVE    HANDLE_FILE, R8
                RSUB    PREP_LOAD_IMAGE, 1
                MOVE    R8, R6                  ; R6: error code=0 (means OK)
                MOVE    R9, R7                  ; R7: img type or error msg
                CMP     0, R6                   ; everything OK?
                RBRA    _LI_FREAD_RET, !Z       ; no

                ; load disk image into buffer RAM
                XOR     R1, R1                  ; R1=window: start from 0
                XOR     R2, R2                  ; R2=start address in window
                ADD     M2M$RAMROM_DATA, R2
                MOVE    M2M$RAMROM_DATA, R3     ; R3=end of 4k page reached
                ADD     0x1000, R3

                MOVE    M2M$RAMROM_DEV, R8
                MOVE    R0, @R8                 ; mount buffer device handle
_LI_FREAD_NXTWN MOVE    M2M$RAMROM_4KWIN, R8    ; set 4k window
                MOVE    R1, @R8

_LI_FREAD_NXTB  MOVE    HANDLE_FILE, R8         ; read next byte to R9
                SYSCALL(f32_fread, 1)
                CMP     FAT32$EOF, R10
                RBRA    _LI_FREAD_EOF, Z
                CMP     0, R10
                RBRA    _LI_FREAD_CONT, Z
                MOVE    ERR_FATAL_LOAD, R8
                MOVE    R10, R9
                RBRA    FATAL, 1

_LI_FREAD_CONT  MOVE    R9, @R2++               ; write byte to mount buffer

                CMP     R3, R2                  ; end of 4k page reached?
                RBRA    _LI_FREAD_NXTB, !Z      ; no: read next byte
                ADD     1, R1                   ; inc. window counter
                MOVE    M2M$RAMROM_DATA, R2     ; start at beginning of window
                RBRA    _LI_FREAD_NXTWN, 1      ; set next window

_LI_FREAD_EOF   MOVE    LOG_STR_LOADOK, R8
                SYSCALL(puts, 1)

_LI_FREAD_RET   MOVE    R6, @--SP               ; lift return codes over ...
                MOVE    R7, @--SP               ; the "leave hump"
                SYSCALL(leave, 1)
                MOVE    @SP++, R9               ; R9: image type
                MOVE    @SP++, R8               ; R8: status/error code
                RET

; ----------------------------------------------------------------------------
; IO Handler:
; Meant to be polled in the main loop and while waiting for keys in the OSM
; ----------------------------------------------------------------------------

HANDLE_IO       INCRB

                ; Loop through all VDRIVES and check for read requests
                XOR     R0, R0                  ; R0: number of virtual drive
                MOVE    VDRIVES_NUM, R1
                MOVE    @R1, R1                 ; R1: amount of vdrives

                ; read request pending?
_HANDLE_IO_1    MOVE    R0, R8
                MOVE    VD_IEC_RD, R9
                RSUB    VD_DRV_READ, 1
                CMP     1, R8                   ; read request?
                RBRA    _HANDLE_IO_NXT, !Z      ; no: next drive, if any

                ; handle read request
                MOVE    R0, R8
                RSUB    HANDLE_DRV_RD, 1

                ; next drive, if applicable
_HANDLE_IO_NXT  ADD     1, R0                   ; next drive
                CMP     R0, R1                  ; done?
                RBRA    _HANDLE_IO_1, !Z        ; no, continue

                DECRB
                RET

; Handle read request from drive number in R8:
;
; Transfer the data requested by the core from the linear disk image buffer
; to the internal buffer inside the core
HANDLE_DRV_RD   SYSCALL(enter, 1)

                MOVE    R8, R11                 ; R11: virtual drive ID

                MOVE    VD_IEC_SIZEB, R9        ; virtual drive ID still in R8
                RSUB    VD_DRV_READ, 1
                MOVE    R8, R0                  ; R0=# bytes to be transmitted
                MOVE    R11, R8
                MOVE    VD_IEC_4K_WIN, R9
                RSUB    VD_DRV_READ, 1
                MOVE    R8, R1                  ; R1=start 4k win of transmis.
                MOVE    R11, R8
                MOVE    VD_IEC_4K_OFFS, R9
                RSUB    VD_DRV_READ, 1
                MOVE    R8, R2                  ; R2=start offs in 4k win

                ; transmit data to internal buffer of drive
                MOVE    R11, R8
                MOVE    VD_IEC_ACK, R9          ; ackknowledge sd_rd_i
                MOVE    1, R10
                RSUB    VD_DRV_WRITE, 1

                MOVE    M2M$RAMROM_DEV, R3      ; R3=device selector
                MOVE    M2M$RAMROM_4KWIN, R4    ; R4=window selector
                MOVE    M2M$RAMROM_DATA, R5     ; R5=data window
                ADD     R2, R5                  ; start offset within window
                XOR     R6, R6                  ; R6=# transmitted bytes
                MOVE    M2M$RAMROM_DATA, R7     ; R7=end of window marker
                ADD     0x1000, R7

_HDR_SEND_LOOP  CMP     R6, R0                  ; transmission done?
                RBRA    _HDR_SEND_DONE, Z       ; yes

                MOVE    VDRIVES_BUFS, R9        ; array of buf RAM device IDs
                ADD     R11, R9                 ; select right ID for vdrive
                MOVE    @R9, @R3                ; select device
                MOVE    R1, @R4                 ; select window in RAM
                MOVE    @R5++, R12              ; R12=next byte from disk img

                MOVE    VD_IEC_B_ADDR, R8       ; write buffer: address
                MOVE    R6, R9
                RSUB    VD_CAD_WRITE, 1

                MOVE    VD_IEC_B_DOUT, R8      ; write buffer: data out
                MOVE    R12, R9
                RSUB    VD_CAD_WRITE, 1

                MOVE    VD_IEC_B_WREN, R8      ; strobe write enable
                MOVE    1, R9
                RSUB    VD_CAD_WRITE, 1
                XOR     0, R9
                RSUB    VD_CAD_WRITE, 1

                ADD     1, R6                   ; next byte

                CMP     R5, R7                  ; window boundary reached?
                RBRA    _HDR_SEND_LOOP, !Z      ; no
                ADD     1, R1                   ; next window
                MOVE    M2M$RAMROM_DATA, R5     ; byte zero in next window
                RBRA    _HDR_SEND_LOOP, 1

                ; unassert ACK
_HDR_SEND_DONE  MOVE    R11, R8                 ; virtual drive ID
                MOVE    VD_IEC_ACK, R9          ; unassert ACK
                MOVE    0, R10
                RSUB    VD_DRV_WRITE, 1

                SYSCALL(leave, 1)
                RET

; ----------------------------------------------------------------------------
; Debug mode:
; Hold "Run/Stop" + "Cursor Up" and then while holding these, press "Help"
; ----------------------------------------------------------------------------

                ; Debug mode: Exits the main loop and starts the QNICE
                ; Monitor which can be used to debug via UART and a
                ; terminal program. You can return to the Shell by using
                ; the Monitor C/R command while entering the start address
                ; that is shown in the terminal (using the "puthex" below).
CHECK_DEBUG     INCRB
                MOVE    M2M$KEY_UP, R0
                OR      M2M$KEY_RUNSTOP, R0
                OR      M2M$KEY_HELP, R0
                MOVE    M2M$KEYBOARD, R1        ; read keyboard status
                MOVE    @R1, R2
                NOT     R2, R2                  ; convert low active to hi
                AND     R0, R2
                CMP     R0, R2                  ; key combi pressed?
                DECRB
                RBRA    START_MONITOR, Z        ; yes: enter debug mode
                RET                             ; no: return to main loop
                
START_MONITOR   MOVE    DBG_START1, R8          ; print info message via UART
                SYSCALL(puts, 1)
                MOVE    START_SHELL, R8         ; show how to return to ..
                SYSCALL(puthex, 1)              ; .. the shell
                MOVE    DBG_START2, R8
                SYSCALL(puts, 1)
                SYSCALL(exit, 1)                ; small/irrelevant stack leak

; ----------------------------------------------------------------------------
; Fatal error:
;
; Output message to the screen and to the serial terminal and then quit to the
; QNICE Monitor. This is invisible to end users but might be helpful for
; debugging purposes, if you are able to connect a JTAG interface.
;
; R8: Pointer to error message from strings.asm
; R9: if not zero: contains an error code for additional debugging info
; ----------------------------------------------------------------------------

FATAL           MOVE    R8, R0
                RSUB    SCR$CLRINNER, 1
                MOVE    1, R8
                MOVE    1, R9
                RSUB    SCR$GOTOXY, 1
                MOVE    ERR_FATAL, R8
                RSUB    SCR$PRINTSTR, 1
                SYSCALL(puts, 1)
                MOVE    R0, R8                  ; actual error message
                RSUB    SCR$PRINTSTR, 1
                SYSCALL(puts, 1)

                CMP     0, R9
                RBRA    _FATAL_END, Z
                MOVE    ERR_CODE, R8
                RSUB    SCR$PRINTSTR, 1
                SYSCALL(puts, 1)
                MOVE    R9, R8
                MOVE    SCRATCH_HEX, R9
                RSUB    WORD2HEXSTR, 1
                MOVE    R9, R8
                RSUB    SCR$PRINTSTR, 1
                SYSCALL(puts, 1)
                MOVE    NEWLINE, R8
                RSUB    SCR$PRINTSTR, 1
                SYSCALL(crlf, 1)

_FATAL_END      MOVE    ERR_FATAL_STOP, R8
                RSUB    SCR$PRINTSTR, 1
                SYSCALL(puts, 1)

                SYSCALL(exit, 1)

; ----------------------------------------------------------------------------
; Screen handling
; ----------------------------------------------------------------------------

FRAME_FULLSCR   SYSCALL(enter, 1)
                RSUB    SCR$CLR, 1              ; clear screen                                
                MOVE    SCR$OSM_M_X, R8         ; retrieve frame coordinates
                MOVE    @R8, R8
                MOVE    SCR$OSM_M_Y, R9
                MOVE    @R9, R9
                MOVE    SCR$OSM_M_DX, R10
                MOVE    @R10, R10
                MOVE    SCR$OSM_M_DY, R11
                MOVE    @R11, R11
                RSUB    SCR$PRINTFRAME, 1       ; draw frame
                SYSCALL(leave, 1)
                RET

; ----------------------------------------------------------------------------
; Strings and Libraries
; ----------------------------------------------------------------------------

; "Outsourced" code from shell.asm, i.e. this code directly accesses the
; shell.asm environment incl. all variables
#include "options.asm"
#include "selectfile.asm"
#include "strings.asm"
#include "vdrives.asm"

; framework libraries
#include "dirbrowse.asm"
#include "keyboard.asm"
#include "menu.asm"
#include "screen.asm"
#include "tools.asm"
