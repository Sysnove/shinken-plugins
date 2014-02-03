#!/usr/bin/perl -w
#
# check_mailstat.pl Copyright (C) 2010 By Curu Wong <prinbra[at]gmail[dot]com>
# 
# Nagios plugin to check mail server statistics exported by mailgraph 
#
# usage:
#     check_mailstat.pl -w 300:500:100:1000:10:100
#     This will emit a WARN when number of messages
#     sent/received/bounced/rejected/virus/spam
#     execeeds the threshold (unit: msgs per minute) 
#     300 /500     /100    /1000    /10   /100
#     respectively.
#     if you don't want to limit a specific counter, set it as 0, eg:
#     -w 300:500:0:0:0:0
#     will emit a WARN when msg sent/min > 300, or msg received/min > 500
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
#
use strict;
use lib qw(
	/usr/lib/nagios/plugins
	/usr/lib64/nagios/plugins 
	/usr/local/nagios/libexec); 

use utils qw($TIMEOUT %ERRORS &print_revision &support);

use Getopt::Long;

my $PROGNAME = "check_mailstat.pl";
my $VERSION = 0.9;

my($status, $state, $answer);
my($opt_V, $opt_w, $opt_c, $opt_h);
my @warn;
my @critical;

my $stat_file = '/var/tmp/mailstat';
my $stat_old = $stat_file. ".old";

sub usage;
sub get_counter;

sub stat_str{
	my @stat = @_;
	my $stat_str = sprintf "sent:%-6.2f received:%-6.2f bounced:%-6.2f rejected:%-6.2f virus:%-6.2f spam:%-6.2f", @stat;
}

sub check_threshold{
	my @threshold = @{+ shift };
	return 0 if @threshold != 6;
	for my $t (@threshold){
		return 0 if $t !~ /^\d+$/;
	};
	return 1;
}

#Option checking
$status = GetOptions(
	"V|version"	=> \$opt_V,
	"h|help"	=> \$opt_h, 
	"w|warning=s"	=> \$opt_w,
	"c|critical=s"	=> \$opt_c,);
		
if ($status == 0)
{
	print_help() ;
	exit $ERRORS{'OK'};
}


if ($opt_V) {
	print_revision($PROGNAME,$VERSION);
	exit $ERRORS{'OK'};
}

if ($opt_h) {
	print_help();
	exit $ERRORS{'OK'};
}

my @stat_counter = get_counter();
$answer = stat_str(@stat_counter);
my $perfdata = sprintf "sent=%-6.2f received=%-6.2f bounced=%-6.2f rejected=%-6.2f virus=%-6.2f spam=%-6.2f", @stat_counter;
$answer = "$answer |$perfdata";

if ($opt_c){
	@critical = split /:/, $opt_c;
	if(!check_threshold(\@critical)){
		print "You must specify all threshold(6 in total,all integer)\n";
		usage();
		exit $ERRORS{'UNKNOWN'};
	}
	for (my $i = 0; $i< @critical; $i++){
		#skip no limit threshold
		next if $critical[$i] == 0;
		if ($stat_counter[$i] > $critical[$i]){
			$state = 'CRITICAL';
			print "$state: $answer\n";
			exit $ERRORS{$state};
		}
	}
}

if ($opt_w){
	@warn = split /:/, $opt_w;
	if(!check_threshold(\@warn)){
		print "You must specify all threshold(6 in total,all integer)\n";
		usage();
		exit $ERRORS{'UNKNOWN'};
	}
	for (my $i = 0; $i<@warn; $i++){
		#skip no limit threshold
		next if $warn[$i] == 0;
		if ($stat_counter[$i] > $warn[$i]){
			$state = 'WARNING';
			print "$state: $answer\n";
			exit $ERRORS{$state};
		}

	}
}

if (!$opt_w && !$opt_c){
	usage();
	exit $ERRORS{'UNKNOWN'};
}

$state = 'OK';
print "$state: $answer\n";
exit $ERRORS{$state};

sub usage {
	print "\nUsage:\n";
	print "$PROGNAME -w <WARN THRESHOLD> -c <CRITICAL THRESHOLD> \n";
	print "THRESHOLD: sent:received:bounced:rejected:virus:spam\n";
	print "           if no threshold for a specific counter, set it to 0\n";
	print "           measured by messages per minute\n";
	print "Example:\n";
	print "Return WARN if msg sent/min > 300, Return CRITICAL if > 500\n";
	print "    $PROGNAME -w 300:0:0:0:0:0 -c 500:0:0:0:0:0\n";
	print "\n";
	print "Return WARN if SPAM msg/min > 10, or msg sent/min > 200\n";
	print "    $PROGNAME -w 200:0:0:0:0:10\n";
	print "\n\n";
}

sub print_help {
	print "check mail server statistics exported by mailgraph\n";
	print "\nOptions:\n";
	print "  -w,--warning=THRESHOLD  Return WARN if exceed the thresolds\n";
	print "  -c,--critical=THRESHOLD Retrun CRITICAL if exceed the thresholds\n";
	print "  -V (--Version)          Plugin version\n";
	print "  -v (--verbose)          Enable verbose output\n";
	print "  -h (--help)             Usage help \n\n";
	usage();
	print_revision($PROGNAME, $VERSION);
	
}

sub plugin_die{
	my $msg = shift;
	print "$msg\n;";
	exit $ERRORS{'UNKNOWN'};
}

sub get_counter{
	my $now = time();
	#read new status count
	my %stat = ( sent => 0, received => 0, bounced => 0, rejected => 0, virus => 0, spam => 0 );
	my %stat_new = ();
	open(my $stath, "<", $stat_file) or plugin_die "Can't open file : $stat_file $!";
	my $stat_line = <$stath>;
	chomp $stat_line;
	foreach my $s (split /\s+/, $stat_line){
		my ($k,$v) = split /:/, $s;
		$stat_new{$k} = $v;
	};
	close($stath);
	
	#read old stats count if exists,then caculate 
	if( -f $stat_old) {
		my %stat_old = ();
		#read old status count
		open(my $stath_old, "<", $stat_old) or plugin_die "Can't open file $stat_old to read: $!";
		my $stat_old_line = <$stath_old>;
		chomp $stat_old_line;
		my ($last_time, $stat_values) = split /:/, $stat_old_line, 2;
		foreach my $s (split /\s+/, $stat_values){
			my ($k,$v) = split /:/, $s;
			$stat_old{$k} = $v;
		};
		close($stath_old);

		#caculate the relative count 
		foreach my $k (keys %stat){
			my $msgs = $stat_new{$k} - $stat_old{$k};
			#this may happen if mailgraph restarted, and log file rotated.
			$msgs = 0 if $msgs < 0;
			#msgs per minute
			my $msgs_per_min = $msgs * 60 / ($now - $last_time);
			$stat{$k} = $msgs_per_min;
		}
	}
	
	#write new stat to old file
	open(my $stath_old, ">", $stat_old) or plugin_die "Can't open file $stat_old to write: $!";
	print $stath_old "$now:$stat_line\n";
	close($stath_old);
	
	return ($stat{sent},$stat{received},$stat{bounced},$stat{rejected},$stat{virus},$stat{spam});
}
