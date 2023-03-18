### Version 5 Work-in-Progress: List of inofficial builds

The purpose of this list is to track down regressions introduced in newer
builds that were not there in older builds. By finding the last known-to-work
build, we have a better chance to hunt down problems. The name of the build
can be checked in the "About & Help" menu of the core.

| Name        | Date     | Commit  | Comment
|-------------|----------|---------|--------------------------------------
| WIP-V5-A1   | 11/30/22 | c124785 | First attempt to fix the analog VGA display challenge ("underwater" waving screen effect) discovered by Discord user Maurice#4307 and as described here: https://discord.com/channels/719326990221574164/794775503818588200/1045984002634428427
| WIP-V5-A2   | 12/02/22 | dba02bd | Same as WIP V5-A1 but built with Vivado 2022.2
| WIP-V5-A3   | 12/03/22 | f7b34fb | Rework interrupt dispatching. Fixed frequency-ratio bug in HDMI-Flicker-Free mode. Refactor audio clock. CIA: Disk parport: ignore inputs on pins configured as output. CIA: fix timer reset values (Arctic Shipwreck). VIC: change xscroll and turbo latch time.
| WIP-V5-A4   | 12/17/22 | f712c84 | Removed i_clk_hdmi_576p which generates 27.00 MHz for 576p @ 50 Hz and 5x27.00 MHz = 135.0 MHz for TMDS in the hope that this MMCM is the root cause of the "signal noise" that apparently disturbs the VGA signal. 5:4 and 4:3 HDMI modes, as well as the 60 Hz mode of 16:9 and DVI are not working any more with this experimental core. 50 Hz 720p HDMI does work.
| WIP-V5-A5   | 01/06/23 | caffa9c | First working version after the big refactoring to align the C64 core and the M2M framework
| WIP-V5-A6   | 01/07/23 | 6150985 | Identical with A5, but with a fixed regression introduced by the refactoring: In 5:4 and 4:3 modes, the file browser did not fit on the screen
| WIP-V5-A7   | 01/16/23 | cdfe960 | HDMI output works with more monitors, frame grabbers, switches, etc. than before: Asserting the +5V power signal according to 4.2.7 of the HDMI specification version 1.4b
| WIP-V5-A8   | 02/26/23 | aa1840d | Upgraded to new M2M framework containing the refactored menu system: More clearly arranged menu using submenus including preparing the menu for the new Expansion Port features. Needs a new c64mega65 menu file.
| WIP-V5-A9   | 03/11/23 | 65d8fc8 | Add work-around for errata in some HyperRAM devices: This improves the REU experience on newer batches of the MEGA65.
| WIP-V5-A10  | 03/13/23 | 9c336c2 | First version that supports hardware cartridges in the MEGA65's expansion port
| WIP-V5-A11  |          |         | Debug version: HyperRAM latency information is shown at the top of the screen: Number of fast accesses divided by number slow accesses in the last few seconds. The higher the numbers the better. The core is based on WIP-V5-A9 (commit 65d8fc8), i.e. it does not have the features of WIP-V5-A10.
