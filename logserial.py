#!/usr/bin/env python
"""Simple python serial logger

Kelsey Jordahl
Time-stamp: <Sat Feb 18 17:57:46 EST 2012>
"""

import serial
import time
import os
from platform import uname

LOGDIR = '/usr/local/share/logserial'
LOGFILE = 'serial.log'
BAUDRATE = 9600
system = uname()[0]
if system == 'Darwin': # Mac OS X
    PORT = '/dev/tty.usbserial-A1000wT3'
elif system == 'Linux':
    PORT = '/dev/ttyUSB0'
else:
    raise Exception("Can't determine serial port")

ser = serial.Serial(PORT, BAUDRATE)
f = open(os.path.join(LOGDIR, LOGFILE), 'a', 0)
while True:
    f.write('%s %d %s' % (time.strftime("%a %b %d %H:%M:%S %Z"),
                        time.time(), ser.readline()))
