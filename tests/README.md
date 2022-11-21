C64 for MEGA65 Regression Testing
=================================

Before releasing a new version we strive to run all regression tests from
this folder. Since running through all the [demos](demos.md) takes some
serious effort, it might be that we are not always doing it.

Version 4 - MONTH, DD, YYYY
---------------------------

| Status             | Test                                        | Done by                | Date              
|:-------------------|---------------------------------------------|:-----------------------|:--------------------------
| :question:         | Basic regression tests                      |                        |
| :white_check_mark: | C64 Emulator Test Suite V2.15               | sy2002                 | 11/19/22
| :white_check_mark: | [Demos](demos.md)                           | AmokPhaze101           | October & November 2022
| :white_check_mark: | Disk-Write-Test.d64                         | sy2002                 | 11/19/22
| :white_check_mark: | Dedicated REU tests                         | AmokPhaze101           | 11/19/22
| :white_check_mark: | GEOS: REU + disk write test                 | sy2002                 | 11/19/22

### How to interpret the test results

We consider the pattern of success (:white_check_mark:) and failure (:x:) in the [Demos](demos.md), the C64 Emulator Test suite and the dedicated
REU tests (scroll down, see below) as the baseline for Version 4 and therefore as "success". Future versions must deliver
the same - or better.

### Basic regression tests

```
Mount disk
Filebrowser
Save configuration, switch off/switch, check configuration
Flip joystick ports
SID: 6581 and 8580
REU: 1750 with 512KB
HDMI : CRT emulation
HDMI : Zoom-in
HDMI : 16:9 50 Hz
HDMI : 16:9 60 Hz
HDMI :  4:3 50 Hz
HDMI :  5:4 50 Hz
HDMI : Flicker-free
HDMI : DVI (no sound)
VGA  : Retro 15Khz RGB
CIA  : Use 8521 (C64C)
Audio Improvements
About and Hel
Close Menu
```

### C64 Emulator Test Suite V2.15

Tested with 6526 CIA

| Status             | Detail                                      | Done by                | Date              
|:-------------------|---------------------------------------------|:-----------------------|:--------------------------
| :white_check_mark: | Disc 1: Complete                            | sy2002                 | 11/19/22
| :white_check_mark: | Disc 2: From start to and incl. "Trap16"    | sy2002                 | 11/19/22
| :x:                | Disc 2: "Trap17"                            | sy2002                 | 11/19/22
| :white_check_mark: | Disc 2: "Branchwrap" to  "MMU"              | sy2002                 | 11/19/22
| :x:                | Disc 2: "CPUPort"                           | sy2002                 | 11/19/22
| :white_check_mark: | Disc 2: "CPUTiming" to  "Cntdef"            | sy2002                 | 11/19/22
| :x:                | Disc 2: "CIA1TA"                            | sy2002                 | 11/19/22
| :x:                | Disc 2: "CIA1TB"                            | sy2002                 | 11/19/22
| :x:                | Disc 2: "CIA2TA"                            | sy2002                 | 11/19/22
| :x:                | Disc 2: "CIA2TA"                            | sy2002                 | 11/19/22
| :x:                | Disc 2: "CIA2TB"                            | sy2002                 | 11/19/22

### Dedicated REU tests

All done by AmokPhaze101 on 11/19/22

#### Demos

| Status             | Demo                                        | Comment
|:-------------------|---------------------------------------------|:---------------------------------------------------
| :white_check_mark: | Dark Mights - Movie 32                      | 
| :white_check_mark: | Expand by Bonzai                            | 
| :x:                | fREUd                                       | In the part with boucing balls all the backgrounds are screwed up. Same Issue on Mister C64_20221117.rbf. Perfectly runs on true Commodore C64 with Ultimate Cartridge.
| :white_check_mark: | globe2016                                   | Wait 7minutes before rendering starts
| :white_check_mark: | Life will never be the same Digidemo 286K_1 | Press SPACE after having swapped disk
| :white_check_mark: | Qi                                          | 
| :white_check_mark: | REU demo Zelda                              | Just scroll the map with joystick in port2
| :white_check_mark: | Treu Love                                   | OK but no 100%: In the main first scroller Sprites have horizontal white pixel lines when on left and right borders, while they should not. Same issue on Mister C64_20221117.rbf. Perfectly run on true Commodore C64 with Ultimate Cartridge.

#### Games

| Status             | Game                                        | Comment
|:-------------------|---------------------------------------------|:---------------------------------------------------
| :white_check_mark: | Sonic The Hedgehog v1.2+5                   | Joystick in port 2, choose options with ARROWS and RETURN, accept to load Full game in REU when asked
| :x:                | Creatures II +9Hi - Mystic                  | Impossible to load the game until the end. Same issues on Mister C64_20221117.rbf and real C64+Ultimate Cartridge.
| :white_check_mark: | Exterminator_1991_Audiogenic_(REU)          | 
| :white_check_mark: | from_the_west[r]                            | All is happening in REU (not disk access) but interraction is quite slow
| :white_check_mark: | Ski_or_Die_1990_Electronic_Arts_REU         | Joystick in port 2. Takes ages to load from disk to the REU on our core as well as on MiSTer and a real C64.
| :white_check_mark: | Walkerz +3                                  | Joystick in port 2