#!/usr/bin/perl -w

# Use fink perl on OS X:
# #!/sw/bin/perl5.8.8
#
# log data from serial port with time stamp
# Used for logging real time Arduino data

# requires Device::SerialPort
# OS X: fink install device-serialport-pm588
# Debian/Ubuntu: apt-get install libdevice-serialport-perl
# CPAN: http://search.cpan.org/dist/Device-SerialPort/SerialPort.pm

# based on file geiger.pl by David Drake
# <http://www.perlmonks.org/?node_id=276111>
# see also <http://www.arduino.cc/playground/Interfacing/PERL>

# Kelsey Jordahl
# Time-stamp: <Fri Feb 12 15:31:13 EST 2010>

use Device::SerialPort;
my @dayofweek = (qw(Sun Mon Tue Wed Thu Fri Sat));
my @monthnames = (qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec));
my @tzname = (qw(EST EDT));

$LOGDIR    = "/home/kels/lacrosse";             # path to data file
$LOGFILE   = "serial.log";              # file name to output to
$PORT      = "/dev/ttyUSB0";              # Linux port
#$PORT      = "/dev/tty.usbserial-A9007VF5";              # OS X port

# make the serial port object
$ob = Device::SerialPort->new ($PORT) || die "Can't Open $PORT: $!";

# set port baud rate, 81N
$ob->baudrate(9600)    || die "failed setting baudrate";
$ob->databits(8)       || die "failed setting databits";
$ob->stopbits(1)       || die "failed setting stopbits";
$ob->parity("none")    || die "failed setting parity";
$ob->write_settings    || die "no settings";

# append to, don't overwrite, the log file
open(LOG,">>${LOGDIR}/${LOGFILE}")
  ||die "can't open file $LOGDIR/$LOGFILE for append: $SUB $!\n";

select(LOG), $| = 1;    # set nonbuffered mode, gets the chars out NOW

# open port
open(DEV, "<$PORT") || die "Cannot open $PORT: $_";

#
# format will be human readable date (local time),
# followed by Unix time stamp (UTC), then serial data on each line

while($_ = <DEV>){        # print input device to file
	$t=time();		# Unix time
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($t);
	printf LOG "%s %s %02d %02d:%02d:%02d %s %d %s",$dayofweek[$wday],$monthnames[$mon],$mday,$hour,$min,$sec,$tzname[$isdst],$t,$_
}


undef $ob;
