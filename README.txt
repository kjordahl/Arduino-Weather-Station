                                README
                                ======

Author: Kelsey Jordahl <kels@serrano.local>
Date: 2011-02-19 15:15:59 EST


Introduction 
~~~~~~~~~~~~~

Receive La Crosse TX4 weather sensor data with Arduino and send to
serial (USB) port.  Also calculates the dewpoint from current
temperature and relative humidity, and records indoor temperature from
a thermistor and barometric pressure from an onboard [BMP085 pressure sensor].  The Arduino does not output the time of measurements, so a
timestamp should be added when the data are logged by a computer.  A
sample logging script is included.

Pressure is reduced in the plotting script to sea level using the
equation given in the BMP085 [datasheet]:
p0 = p/(1 - altitude/44330)^5.255

My elevation is 139 m.

This project is based on the [Weather Station Receiver] from the book
[Practical Arduino] by Jon Oxer and Hugh Blemings, and uses
some of their original code, which may be found at [GitHub].  Further
help in decoding data packets came from [Jean-Paul Roubelat's page on LaCrosse sensors]. BMP085 pressure sensor code is based on code from
[Interactive Matter] (used and relicensed under the GPL with
permission).

Dewpoint formula is from :

Lawrence, M., The relationship between relative humidity and the
   dewpoint temperature in moist air: A simple conversion and
   applications, /Bulletin of the American Meteorological Society/,
   *86*, 225--233, [doi:10.1175/BAMS-86-2-225], 2005

More information is at [http://mysite.verizon.net/kajordahl/weather.html].

These programs are released under the GPLv3.  Please see the file COPYING
or [http://www.gnu.org/licenses] for details.

Kelsey Jordahl
kjordahl@alum.mit.edu

Time-stamp: <Sat Feb 19 15:15:59 EST 2011>


[BMP085 pressure sensor]: http://www.sparkfun.com/products/9694
[datasheet]: http://www.bosch-sensortec.com/content/language1/downloads/BST-BMP085-DS000-05.pdf
[Weather Station Receiver]: http://www.practicalarduino.com/projects/weather-station-receiver
[Practical Arduino]: http://www.practicalarduino.com/about
[GitHub]: http://github.com/practicalarduino/WeatherStationReceiver
[Jean-Paul Roubelat's page on LaCrosse sensors]: http://www.f6fbb.org/domo/sensors/tx3_th.php
[Interactive Matter]: http://interactive-matter.org/2009/12/arduino-barometric-pressure-sensor-bmp085
[doi:10.1175/BAMS-86-2-225]: http://dx.doi.org/10.1175/BAMS-86-2-225

CONTENTS 
~~~~~~~~~
`README':            This information file
`lacrosse.pde': Arduino code
`logserial.pl': example Perl script to log from serial port and add timestamp
`plotweather.py': python script for plotting and uploading data to website
`template_py.html': blank HTML file used as template by `plotweather.py'
`seriallogrotate': shell script to rotate serial log files (run by
     `cron' daemon)
`logserial.conf': file for `/etc/init' to start `logserial.pl'
                    automatically (for upstart daemon used by Ubuntu
                    and Debian Linux distributions)

INSTALL 
~~~~~~~~

Required hardware for this project is an Arduino-compatible platform
with a 434 MHz RF receiver connected to digital pin 8, a 10k themistor
on analog pin 1, and a BMP085 pressure sensor connected to analog pins
4 and 5.  A compatible 434 MHz temperature sensor (e.g., La Crosse
TX4) is also assumed.  Please see the references above for details for
details on hooking up these components.

The Arduino sketch `lacrosse.pde' will, when uploaded to the Arduino,
send output to the USB serial port of an attached computer.  For
automatic logging and plotting, use the included files (which have
been tested on an Ubuntu 10.10 system).  Copy the files `logserial.pl', and
`plotweather.py' to `/usr/local/bin' or another directory in your
path.  The HTML template `template_py.html' should be kept in a
directory that will be updated with the static web page and plot
(e.g. `/home/user/html/weather').  To run the scripts automatically,
copy `logserial.conf' to `/etc/init' and seriallogrotate to
`/etc/cron.weekly'.  To run the plotting script every 15 minutes, you
may wish to edit your user `crontab' file to the following:
1,16,31,46 * * * *  /usr/local/bin/plotweather.py -u
You will probably need to edit the scripts to the desired paths for
logging and HTML files on your system.

Changelog 
~~~~~~~~~~

v1.0.6 (19 Feb 2011): `plotweather.py' takes optional arguments;
     this README file reformatted in Emacs `org-mode'
v1.0.5 (7 Jan 2011): Add files and instructions for automatic
     logging and plotting
v1.0.4 (15 Dec 2010): change to more robust python script for plotting
v1.0.3 (3 Sep 2010): improve plotting, including pressure and
     better autoranging
v1.0 (14 Aug 2010): Release full version
v0.9.9 (3 Aug 2010): Added support for BMP085 pressure sensor on board
v0.9.2 (18 April 2010): Update plotting scripts for daily high & low
               temperatures (in Fahrenheit).
v0.9.1 (14 March 2010): Add GMT plotting scripts and HTML template
v0.9 (9 March 2010): Initial release of Arduino script
