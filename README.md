# tranz330_basic
MS BASIC port to the Tranz 330 card terminal

Based on Scott Baker's RC2014 SIO BIOS and BASIC at https://github.com/sbelectronics/rc2014 ...

...which is based on Grant Searle's SBC BASIC at http://searle.hostei.com/grant/index.html...

...which is based on NASCOM ROM BASIC 4.7 scanned from a magazine...

...which is MS BASIC.

Includes portions of the "Mozart's Credit Card" demo from BMOW at https://www.bigmessowires.com/mozart-tranz-330/

Build directions are forthcoming.  If you want to try this on your own hardware, flash tranz330_basic.rom to the bottom of a 27256 EPROM.


## Notes on loading eliza with GNU screen

1. Make sure your screenrc has `defslowpaste 100` in it
2. Start screen on the serial port (`screen /dev/ttyUSB0 9600`) or so
3. Load the file into the register "p"
    `[CTRL-A]:readreg p git/tranz330_basic/eliza_cc1977_tranz330.bas`
4. Send the register
    `[CTRL-A]:paste p`
