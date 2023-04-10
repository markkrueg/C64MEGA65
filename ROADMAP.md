Roadmap
=======

We are planning to improve this core steadily. The MiSTer core offers many
more features than our current Release of the port. Here is a list of features
(in no particular order) that we are planning to deliver at a later stage:

Feature Roadmap
---------------

* NTSC
* Support two drives: 8 and 9
* Dual SID
* Tape mounting via SD card (`*.TAP`)
* Directly load program files (`*.PRG`)
* Cartridge mounting via SD card (`*.CRT`)
* Support for raw GCR mode (`*.G64`)
* C1581 virtual drive support via SD card (`*.D81`)
* Support `*.D64` images with error maps (filesizes 175,531 and 197,376)
* Support the creation of empty disk images
* Support the creation of empty config files and the migration of the config
  file from an older version to a newer version
* Alternative KERNAL & Floppy Disk ROMs and fast loaders
* Parallel C1541 port for faster (~20x) loading time using DolphinDOS
* Support the following MEGA65 hardware ports:
  * Cartridges via the MEGA65's hardware Expansion Port
  * IEC port (for example to plug in a real C1541)
  * C1581 via MEGA65's disk drive
  * REU via expansion port
* Utilize full 16:9 screen real estate for file- and directory browsing and
  core configuration on HDMI while saving screen real estate on 4:3 VGA
* More sophisticated scalers and scandoublers 
* Simulate the blending of colours when ALM and DCM are used
  as described here: https://github.com/MiSTer-devel/C64_MiSTer/issues/104

Technical Roadmap
-----------------

To implement some of the above-mentioned features and also to improve the
robustness, performance, and stability of the whole system, we will need
to implement certain technical improvements in the "backend", again in no
particular order:

* Merge T65 upstream fix (fixes All Hallows' Eve) from branch `dev-irqdisp`
* Merge these MiSTer upstream fixes (needs thorough regression testing):
  - CIA: Disk parport: ignore inputs on pins configured as output (sorgelig)
    commit 4da804c
  - CIA: fix timer reset values (Arctic Shipwreck) (gyurco) commit 7eca7e3
  - VIC: change xscroll and turbo latch time (sorgelig) commit f3a137b
* Merge branch `fix-issue-2` that fixes the frequency-ratio bug in
  HDMI-Flicker-Free mode that prevented "Input 64 Issue 1/85" to run while
  the flicker-free mode was on.
* Maximize compatibility of C1541 by implementing MiSTer's raw GCR mode which
  exclusively uses GCR internally (c1541_direct_gcr.sv instead of
  c1541_gcr.sv). `*.D64` images are converted to/from GCR when reading/writing
  from SD card.
* Refactor asynchronous resets and other things around clk.vhd to reduce
  warnings upon `report_cdc` and to make sure the whole clock architecture
  is cleaner. (Also need to double-check M2M itself.)
* HDMI compatibility: MJoergen research project to fix the HDMI sound on his
  monitor which might lead to more HDMI compatibility in general. Research
  path: Use an FPGA board with HDMI input, to capture the data from both the
  MEGA65 (has no sound) and the laptop (has sound), to compare them. Might
  very well help to fix https://github.com/MJoergen/C64MEGA65/issues/4
* Put major/minor version in the first two bytes of the config file so that
  in case of a mismatch a warning can be issued (e.g. by directly printing
  it into the C64's screen RAM). Needs new version of make_config.sh.
* Eliminate HDMI Flicker-free "~20min period artefact" by manual clock
  frequency tuning
* Support for R2 version of MEGA65
* VGA retro CSync generation
* Fix visible tearing in Bromance demo (vertical scroll effect), but only,
  when HDMI Zoom is ON: https://csdb.dk/release/?id=205526
* Update to newer ascal version (wait until MiSTer does the same upstream)
* Investigate dynamic PLL adjustment/autotune in conjunction with ascal
  to improve flicker-free HDMI further (maybe there is a possibility to
  achieve flicker-free without the need of slowing down by 0.25%)
* Re-do QNICE's SD Card controller: Go from SPI to native
* HyperRAM device support to QNICE
* Hardware debugger (single-step the CPU via the on-screen-menu)
* Line 65 in fdc1772.v: back to 2 or work with generic?
