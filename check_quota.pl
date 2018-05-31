#!/usr/bin/perl -w

# vim: softtabstop=2 tabstop=2 shiftwidth=2 expandtab

# check_quota.pl - nagios plugin to check Linux filesystem quotas using repquota
#
# (c) 2011,2018 by Frederic Krueger / fkrueger-dev-checkquota@holics.at
#
# Licensed under the Apache License, Version 2.0
# There is no warranty of any kind, explicit or implied, for anything this software does or does not do.
#
# Updates for this piece of software could be available under the following URL:
#   GIT: https://github.com/fkrueger/check_quota
#   Home: http://dev.techno.holics.at/check_quota/
#


### uses
use strict;
use v5.10;
use Getopt::Std;
use POSIX qw (strftime);
use Data::Dumper;             # for debugging

use lib "/usr/lib/nagios/plugins";
use lib "/usr/lib64/nagios/plugins";
use lib "/srv/nagios/libexec";
# the following is not used anymore, because eval can't trap the errors when trying to "use utils;" in Windows or Linux -.-
#use utils qw (%ERRORS);


# remember to add your own homepath to this list, if it is not the default!
# use 4 backslashes for one (ie. C:\Foobar\Baz becomes "C:\\\\Foobar\\\\Baz")
# keep the regexp similar to the existing ones: the first match without the trailing \ is the path, the second match the username
# the first template entry is the one where the path is not being added to the label, the others will end up in a format akin to: username-C_Users et al
#
our @win_userhomepath_templates = ( "(T:)\\\\([^\\\\]*)", "(D:\\\\somestorage)\\\\([^\\\\]*)", "(C:\\\\Users)\\\\([^\\\\]*)", "(C:\\\\Documents and Settings)\\\\([^\\\\]*)", "(C:\\\\Benutzer)\\\\([^\\\\]*)", "(C:\\\\Dokumente und Einstellungen)\\\\([^\\\\]*)" );

# there is rarely a need to use the following:
our @win_grouphomepath_templates = ( "(S:)\\\\(.*)", "(R:)\\\\(.*)" );


# our inline-replacement for utils.pm:
our %ERRORS = ('UNKNOWN' ,-1,
       'OK'      , 0,
       'WARNING' , 1,
       'CRITICAL', 2
      );




###
### DONT EDIT BELOW HERE
###

our ($PROG_NAME, $PROG_VERSION, $PROG_EMAIL, $PROG_URL) = ("check_quota", "0.29", 'fkrueger-dev-checkquota@holics.at', 'http://dev.techno.holics.at/check_quota/');

## not a CHANGELOG:
## v0.26  started changelog
## v0.27  added quota-grace support, in-line use of sudo, short info and several other optimizations (thanks to Pavel V.R.)
##    added a few other "features" (incl. removing bugs and other inconveniences; use diff!)
## v0.28  added part of Pavel VR's proposed changes, as well as some Windows support of my own.
##      added Windows workaround (needs quota report created ie. via the task scheduler)
##      added perfdata output for users/groups on their status line instead of the main status line
##      added actual setup instructions to usage
##      added logfile handling via cmdline parameter
##      fixed a few minor bugs and logical hickups
##      added shortperfdata to get around the 4k limit on at least some systems
##      added exitcodealwaysok as feature for providing perfdata, but nothing else
##      added exclude-regexp parameter to exclude users/groups
##      fixed some bugs in the parse_linuxrepquota and convunitstobytes implementation
##          fixed a cutnpaste error in unit2bytes that was found and corrected by Paolo Miotto
## TODO  implement shortstatusinfo output
## TODO  sort long output list to show the lines in status order, ie. first critical, then warning, then ok (also part of the 4k limit avoidance thing)
## TODO  extend pnp4nagios-template (and maybe here) to allow for sorting by the percentage a user uses his quota (right now and in genera)
## TODO  Linux: add monitoring for inode limits
## TODO Windows: automatically remove known technical accounts on Windows systems from our output
## TODO  Windows: add warning levels provided in the quota report as softlimit(s)

our $detectedos = "Linux";
if (substr($^O, 0, 5) eq "MSWin") { $detectedos = "Windows"; }

our %cache = ();
our $cache_timeout = 300;

our $logfile;
our $loglvl_file;
our $loglvl_screen;

our $bin_repquota;
our $report_fpath;


# the following is used in the quota to bytes converter function(s), KB for windows, K for linux
our %units2bytes = ( '' => 1, 'B' => 1, 'K' => 1024, 'KB' => 1024, 'M' => 1024*1024, 'MB' => 1024*1024, 'G' => 1024*1024*1024, 'GB' => 1024*1024*1024, 'T' => 1024*1024*1024*1024, 'TB' => 1024*1024*1024*1024, 'P' => 1024*1024*1024*1024*1024, 'PB' => 1024*1024*1024*1024*1024 );
our @bytes2units = ( "b", "K", "M", "G", "T", "P" );



## func
sub usage
{
  my $msg = shift;
  $msg = "" if (!defined($msg));

  print "\nusage: check_quota.pl [-W <report-file>] [-u <username-regexp>]\n";
  print "           [-g <groupname-regexp>] [-m <mountpoint>] [-x <exclude-regexp>]\n";
  print "           [-Q] [-p] [-P] [-s] [-n] [-f <logfile>] [-l <0..5>] [-L <0..5>] [-h]\n";
  print "\n";
  print "   -u     check quota for a specific user (specify 'all' for all users)\n";
  print "   -g     check quota for a specific group (specify 'all' for all groups)\n";
  print "   -Q     show information on users/groups without a set quota as well\n";
  print "   -m     check quota only for a specific mountpoint (not used in Windows)\n";
  print "            default: 'all' for all mountpoints\n";
  print "   -W     do windows workaround (specify filepath to report file)\n";
  print "             default: '$report_fpath'\n";
  print "   -p     add perfdata\n";
  print "   -s     short output (hide user/group 'OK' status)\n";
  print "   -P     short perfdata (use human readable units instead of bytes numbers)\n";
  print "   -n     exitcode returned is always OK\n";
  print "   -x     exclude <exclude-regexp> from results\n";
  print "   -f     set logfile (default: './check_quota.log')\n";
  print "   -l     set loglevel for screen output (0..5, default: 0)\n";
  print "   -L     set loglevel for file output (0..5, default: 0)\n";

  print "   -h     this help\n";
  print "\n";
  print "This plugin allows you to check the quotas on your Linux and Windows systems\n";
  print "(maybe others, too).\n";
  print "\n";
  print "Detected OS: $detectedos ($^O) => using " .(($detectedos eq "Windows") ? "report in " .(($report_fpath eq "") ? "<not set>":$report_fpath) : $bin_repquota). "\n";
  print "\n";

  print "\n==========================================================================\n\n";

  if ($detectedos eq "Windows")
  {
  print "  Setup help for Windows:\n\n";
  print "     * Set up quota for some of your to-be-monitored directories.\n";
  print "     * Install this script in NSCP's scripts/ sub-directory (use v4.3+ !!).\n";
  print "     * Create a cyclical quota report for this script to parse\n";
  print "         (the onboard task scheduler comes to mind, ie. schtasks.exe).\n";
  print "         Make sure you are running the task with (domain)admin rights.\n";
  print "     * Provide the path to the quota report file using the -W parameter.\n";
  print "     * Remember that there are no user or group quotas on Windows,\n";
  print "         only directories with quota put on them.\n";
  print "     * Adapt \@win_(user|group)homepath_templates accordingly, if needed.\n\n";
  print "     * Additionally, here is a config snippet for NSCP (nsclient.ini):\n\n";
  print '[/settings/external scripts]
allow arguments = true
allow nasty characters = true

[/settings/external scripts/scripts/default]
ignore perfdata = true

[/settings/external scripts/scripts]
check_quota_user=perl.exe -- scripts\\check_quota.pl -W "C:\temp\check_quota-dirquota.log" -u "$ARG1$"
check_quota_group=perl.exe -- scripts\\check_quota.pl -W "C:\temp\check_quota-dirquota.log" -g "$ARG1$"
check_quota_user_shortver=perl.exe -- scripts\\check_quota.pl -W "C:\temp\check_quota-dirquota.log" -u "$ARG1$" -s
check_quota_group_shortver=perl.exe -- scripts\\check_quota.pl -W "C:\temp\check_quota-dirquota.log" -g "$ARG1$" -s
check_quota_user_wperfdata=perl.exe -- scripts\\check_quota.pl -W "C:\temp\check_quota-dirquota.log" -u "$ARG1$" -p
check_quota_group_wperfdata=perl.exe -- scripts\\check_quota.pl -W "C:\temp\check_quota-dirquota.log" -g "$ARG1$" -p
check_quota_user_wperfdata_alwaysok=perl.exe -- scripts\\check_quota.pl -W "C:\temp\check_quota-dirquota.log" -u "$ARG1$" -p -n
check_quota_group_wperfdata_alwaysok=perl.exe -- scripts\\check_quota.pl -W "C:\temp\check_quota-dirquota.log" -g "$ARG1$" -p -n
check_quota_user_wperfdata_shortver=perl.exe -- scripts\\check_quota.pl -L 3 -W "C:\temp\check_quota-dirquota.log" -u "$ARG1$" -s -p -P
check_quota_group_wperfdata_shortver=perl.exe -- scripts\\check_quota.pl -W "C:\temp\check_quota-dirquota.log" -g "$ARG1$" -s -p -P

';
    print "     * Example for a scheduler task running dirquota via schtasks.exe:\n\n";
  print 'schtasks.exe /Create /TN "quotareport_for_check_quota" /SD "' .strftime("%d/%m/%Y", localtime()). '" /DU "0:5" /SC "Minute" /RU "SYSTEM" /RL "HIGHEST" /TR "%SystemRoot%\System32\cmd.exe /c \'%SystemRoot%\System32\dirquota.exe quota list > ' .$report_fpath. '\'

';
    print "     * Then check the task created by the command above like this:\n";
  print "%SystemRoot%\\system32\\taskschd.msc /s\n\n";
  print "     * EnJoy!\n";
  }
  else
  {
    print "  Setup help for $detectedos:\n\n";
  print "     * Install the quota utilities for your OS (providing ie. repquota).\n";
  print "     * Set up mountpoints with quotas and add quotas to user\n";
  print "         and groups (edquota!).\n";
  print "     * Make sure repquota can be successfully run by nrpe\n";
  print "         (use sudo if needed).\n";
  }
  print "\n  \"UNKNOWN\" known problems:\n\n";
  print "     Sometimes (read: because of the 4kb output limit) it may be prudent to\n";
  print "     create two plugin calls: one with a short output and no perfdata\n";
  print "     (AKA just -s) and another with perfdata (AKA '-p' or '-p -P').\n";
  print "     Also you could split up your one call into many that check a low enough\n";
  print "     number of users each time to not hit the 4k limit.\n";
  print "\n";
  print "     One solution for this: Increase buffer sizes in NSCP/nrpe and check_nrpe.\n";
  print "       * In NSclient.ini set /settings/NRPE/Server/payload length to 16384\n";
  print "       * Get the sourcecode for check_nrpe (part of the nrpe package usually).\n";
  print "       * Change the following entries in include/common.h and recompile:\n";
  print "#define MAX_INPUT_BUFFER        16384\n";
  print "#define MAX_PACKETBUFFER_LENGTH 16384\n";
  print "       * Upload the changed version of check_nrpe to your Nagios server.\n";
  print "       * Use the changed version only for NSCP with the changed and fitting\n";
  print "         payload length.\n";
  print "  \n==========================================================================\n";
  print "\n";
  print "$PROG_NAME v$PROG_VERSION is licensed under the Apache License, Version 2.0 .\n";
  print "\n";
  print "There is no warranty of any kind, explicit or implied, for anything this\n";
  print "software does or does not do.

Website for the plugin: $PROG_URL

(c) 2011,2015 by Frederic Krueger / $PROG_EMAIL

";

  if ($msg ne "")
  {
    print "\n";
    print "Error: $msg\n";
    print "\n";
  }
  exit $ERRORS{'UNKNOWN'};
} # end sub usage


sub convbytestounits
{
  my $val = shift;
  my $shortnumbers = shift;
  $shortnumbers = 0  if (!defined($shortnumbers));
  $val = 0 if (!defined($val));
  my $origval = $val;

  my $out = "";
  my $cnt = 0;
  while ($val > 1023)
  {
    $val /= 1024;
    $cnt++;
  }
  if ($shortnumbers <= 0)
  {
    $out = sprintf ( (($cnt == 0)?"%i%s":"%.2f%s"), $val, $bytes2units[$cnt]);
  }
  else
  {
    $out = sprintf ( "%i%s", $val, $bytes2units[$cnt]);
  }

  logme ("Converted bytesval '$origval' to units '$out'", 5);
  return ($out);
} # end sub convbytestounits


sub convunitstobytes
{
  my $val = shift;
  $val = ""  if (!defined($val));

  my $bytes = -1;

  if ($val =~ m#^\s*([0-9,\.]+)\s*(\S+)(?:\s+.*|)$#i)
  {
    my $quotanum = $1; my $quotaunit = $2;
    $quotaunit = "B" if ((!defined($quotaunit)) or ($quotaunit eq "Bytes"));
    if ((defined($quotanum)) and (defined($quotaunit)))
    {
      if ($quotanum =~ /,/)    # if german number format
      {
        $quotanum =~ s/\.//sg;    # remove .
        $quotanum =~ s/,/./sg;    # convert , to . in numbers
      }
      $bytes = int($quotanum * $units2bytes{uc($quotaunit)});
    }
  }

  logme ("Converted unitsval '$val' to bytes '$bytes'", 5);
  return ($bytes);
} # end sub convunitstobytes





## the following is added for later usage.
sub getinfo
{
  my $fname = shift;
  $fname = "" if (!defined($fname));

  my $rc = "";

  # 1. delete old cache files
  if (defined($cache{$fname}))
  {
    if ($cache{$fname}{'timestamp'} > time-$cache_timeout)
    {
      delete ($cache{$fname});
    }
  }

  # 2. read files not in cache
  if (! defined($cache{$fname}))
  {
    if (open (A, "<$fname"))
    {
      my $content = "";
      { local $/ = undef; $content = <A>; };
      close(A);

      if (defined ($content))
      {
        $cache{$fname} = { 'timestamp' => time, 'content' => $content };
      }
    }
    else
    {
      logme ("getinfo($fname): Couldn't open fname '$fname': $!", 0);
    }
  }

  # 3. return info from cache
  if (defined($cache{$fname}))
  {
    $rc = $cache{$fname}{'content'};
  }

  return ($rc);
} # end sub getinfo



sub logme
{
  my $msg = shift;
  my $lvl = shift;
  $msg = "" if (!defined($msg));
  $lvl = 0 if (!defined($lvl));

  # remove trailing \n
  chomp ($msg);

  my $ts = "";
  if ($lvl <= $loglvl_screen)
  {
     $ts = strftime ("%Y-%m-%d %H:%M:%S", localtime());
     print "$ts $0\[$$\]: $msg\n";
  }
  if ($lvl <= $loglvl_file)
  {
    $ts = strftime ("%Y-%m-%d %H:%M:%S", localtime());
    if (open (LOG, ">>$logfile"))
    {
      print LOG "$ts $0\[$$\]: $msg\n";
      close (LOG);
    }
    else
    {
      usage ("Couldn't open logfile '$logfile': $!");
    }
  }
} # end sub logme



sub gracetohuman {
  my $grace = shift;
  my $weeks = int($grace / 604800);
  $grace -= $weeks * 604800;
  my $days  = int($grace / 86400);
  $grace -= $days * 86400;
  my $hours = int($grace / 3600);
  $grace -= $hours * 3600;
  my $min   = int($grace / 60);
  $grace -= $min * 60;
  return ("$weeks weeks" .(($days > 0) ? " $days days" : ""))  if ($weeks > 0);
  return ("$days days" .(($hours > 0) ? " $hours hours" : ""))  if ($days > 0);
  return ("$hours hours" .(($min > 0) ? " $min minutes" : ""))  if ($hours > 0);
  return ("$min minutes")          if ($min > 0);
  return ("$grace sec");
} # end sub gracetohuman


## the following two subs are used to check for quota mountpoint availability
sub get_active_mpflags
{
  my $mp = shift;
  my %mpflags = ( 'info-used' => 'NOT-SET', 'fstype' => '', 'mp-src' => '', 'mp-tgt' => '', 'mp-tgt-opts' => '' );
  $mp = ""  if ((!defined($mp)) or (! -d $mp));

  # if linux:
  my $mpinfo = "/proc/self/mountinfo";
  if (! -e $mpinfo) { $mpinfo = "/proc/mounts"; }
  if (! -e $mpinfo) { $mpinfo = "/etc/fstab"; }
  if (! -e $mpinfo) { $mpinfo = "NOT-SET"; }

  if (($mpinfo ne "NOT-SET") and (-e $mpinfo) and (-r $mpinfo))
  {
    $mpflags{'info-used'} = $mpinfo;
    if (open (MP, "<$mpinfo"))
    {
      while ( ((!defined($mpflags{'mp-tgt-opts'})) or ($mpflags{'mp-tgt-opts'} eq "")) and (defined(my $inp = <MP>)) )
      {
        chomp ($inp);
        my @t = split / /, $inp;
        logme ("MP>> infofile $mpinfo with ". ($#t+1) ." fields: " .join(";", @t), 4);

        my ($mp_fstype, $mp_tgt, $mp_tgt_opts, $mp_src) = ("","","","");
        if ($mpinfo eq "/proc/self/mountinfo")
        {

          ## /proc/self/mountinfo (< 10):
          # 0: num
          # 1: unknown 1
          # 2: bus-id
          # 3: mountpoint-parent
          # 4: mountpoint-target
          # 5: mountpoint-target fs-options
          # 6: unknown 2
          # 7: fstype
          # 8: mountpoint-source
          # 9: mountpoint-target active-options
          if ($#t < 10)
          {
            #25 21 8:33 / /chroot2 rw,relatime - ext4 /dev/sdc1 rw,barrier=1,data=ordered,usrquota,grpquota
            $mp_fstype = $t[7];
            $mp_tgt = $t[4];
            $mp_src = $t[8];
            $mp_tgt_opts = $t[9];
          }
          elsif ($#t < 11)
          {
            #86 66 253:2 / /mnt/quota rw,relatime shared:33 - ext4 /dev/mapper/vg_quota-lv_quota rw,seclabel,stripe=384,data=ordered,jqfmt=vfsv0,usrjquota=aquota.user,grpjquota=aquota.group
            $mp_fstype = $t[6];
            $mp_tgt = $t[4];
            $mp_src = $t[9];
            $mp_tgt_opts = $t[10];
          }
          else
          {
            logme ("MP>> Unknown format with " .($#t+1). " fields in $mpinfo: $inp", 1);
          }
        } # end if /proc/self/mountinfo

        if ($mpinfo eq "/proc/mounts")
        {
          ## /proc/mounts and /etc/fstab:
          # 0: mountpoint-source
          # 1: mountpoint-target
          # 2: fstype
          # 3: mountpoint-target active-options
          # 4: unknown 1 (dump?)
          # 5: unknown 2 (pass?)
          $mp_src = $t[0];
          $mp_tgt = $t[1];
          $mp_fstype = $t[2];
          $mp_tgt_opts = $t[3];
        } # end if /proc/mounts

        if (
          (defined($mp_fstype)) and (defined($mp_tgt)) and (defined($mp_tgt_opts)) and (defined($mp_src))
           and ($mp_fstype ne "") and ($mp_tgt ne "") and ($mp_tgt_opts ne "") and ($mp_src ne "")
            and ($mp_tgt eq $mp)
        )
        {
          logme ("MP>> got fstype '$mp_fstype', tgt '$mp_tgt', tgt-opts '$mp_tgt_opts', src '$mp_src'", 3);
          $mpflags{'fstype'} = $mp_fstype;
          $mpflags{'mp-tgt'} = $mp_tgt;
          $mpflags{'mp-tgt-opts'} = $mp_tgt_opts;
          $mpflags{'mp-src'} = $mp_src;
          # XXX after having been in here, the loop should end itself.
        } # end if got valid looking info
      } # end foreach info line
      close (MP);
    }
  } # end if couldnt find mount-info

  return ( { %mpflags } );
} # end sub get_active_mpflags


# rc:  1 => mp exists and has requested quota => all ok
# rc:  0 => mp exists but doesn't have requested quota
# rc: -1 => mp doesn't exist
sub mountpoint_with_quota_exists
{
  my $mp = shift;
  my $reqtype = shift;
  my $rc = 1;
  logme ("MP>> mountpoint_with_quota_exists called with mp '$mp', reqtype '$reqtype'", 4);

  $mp = ""  if (!defined($mp));
  $reqtype = ""  if (!defined($reqtype));

  $rc = -2  if ((! -e $mp) or (! -d $mp));
  if ($rc == 1)
  {
    my $mpflagsref = get_active_mpflags ($mp);
    my %cur_mpflags = %{$mpflagsref};
    logme ("rc is now $rc, " .$cur_mpflags{'mp-tgt'}. " (" .$cur_mpflags{'mp-tgt-opts'}. ")", 3);
    if ((!defined($cur_mpflags{'mp-tgt'})) or ($cur_mpflags{'mp-tgt'} ne $mp))
      { $rc = -1; }
    elsif ($cur_mpflags{'mp-tgt-opts'} !~ /${reqtype}j{0,1}quota/)
      { $rc = 0; }
    # else everything is ok, rc stays as is (ie. rc=1)
  }
  return ($rc);
} # end sub mountpoint_with_quota_exists

# rc is now 1, /mnt/data (/dev/mapper/vg_data-lv_data)
# MP>> 86 66 253:2 / /mnt/data rw,relatime shared:33 - ext4 /dev/mapper/vg_data-lv_data rw,seclabel,stripe=384,data=ordered,jqfmt=vfsv0,usrjquota=aquota.user,grpjquota=aquota.group



# input: file path to windows report file
#
# returns: hash with infos from that report file

sub parse_winreport
{
  my $report_fpath = shift;
  $report_fpath = "" if (!defined($report_fpath));
  my %repout = ();

  my $quotasparsed = 0;

  if (($report_fpath ne "") and (-r $report_fpath))
  {

    if (open (REP, "<$report_fpath"))
    {
      my $startfound = (0==1);
      my $justfoundblockend = (0==1);
      my $currentquota = "";
      my $namepd;
      while (my $inp = <REP>)
      {
        chomp ($inp);
        logme ("REP> $inp", 5);
        # convert german umlauts
        $inp =~ s/\x8E/Ae/sg;      $inp =~ s/\x84/ae/sg;
        $inp =~ s/\x99/Oe/sg;      $inp =~ s/\x94/oe/sg;
        $inp =~ s/\x9A/Ue/sg;      $inp =~ s/\x81/ue/sg;
        $inp =~ s/\xE1/ss/sg;
        if (! $startfound)
        {
          if ($inp =~ /^.*:/i)
          {
            logme ("Found end of header / page begin: $inp", 4);
            $startfound = (0==0);
          } # end if found begin of content
          else
          {
            logme ("Found other header stuff: $inp", 4);
          }
        } # end if we are still in the header

        else

        {
          if ($inp =~ /^\s*$/)
          {
            if (! $justfoundblockend)
            {
              logme ("Found block end.", 4);
              $justfoundblockend = (0==0);
              $currentquota = "";
            }
            else
            {
              logme ("Currently not in block, but end found: $inp", 4);
              $justfoundblockend = (0==1);    # so we stay true to the name
            }
          } # end if found new block
          elsif ($inp =~ m#^(?:Kontingentpfad|Quota path):\s+(\S.*)\s*$#i)
          {
            if ($justfoundblockend)
            {
              my $fpath = ((defined($1)) ? $1 : "");
              my $isuserquota = (0==1);
              my $isgroupquota = (0==1);
              my $namepart = "";
              my $dirpart = "";
              for (my $i = 0; $i <= $#win_userhomepath_templates; $i++)
              {
                if ($fpath =~ /^$win_userhomepath_templates[$i]/)
                {
                  $dirpart = $1; $namepart = $2;
                  $isuserquota = (0==0);

                  # if fpath is in a user-root, set currentquota to dirname (but strip the .V2 of v2 profiles)
                  $namepart =~ s/^([^\\]+)(?:\.V2|)?$/$1/ig;
                  # clear the dirpart for later usage in pnp4nagios
                  $dirpart =~ s/:[\\\/]/_/g;  $dirpart =~ s/[^a-zA-Z0-9\-_\ ]//g;
                  # and now create the final filename
                  $currentquota = $namepart . (($i == 0) ? "" : "-$dirpart");
                  next;
                } # end if fits win userhomepath pattern
                logme ("fpath '$fpath' => name '$namepart', dir '$dirpart'", 4);
              } # end foreach win userhomepath template supplied

              # if none of the above matched, try the group stuff:
              if (! $isuserquota)
              {
                for (my $i = 0; $i <= $#win_grouphomepath_templates; $i++)
                {
                  if ($fpath =~ /^$win_grouphomepath_templates[$i]/)
                  {
                    $dirpart = $1; $namepart = $2;
                    $namepart = ""  if (!defined($namepart));
                    $dirpart = ""  if (!defined($dirpart));
                    $isgroupquota = (0==0);

                    # if fpath is in a user-root, set currentquota to dirname (but strip the .V2 of v2 profiles)
                    $namepart =~ s/^([^\\]+)(?:\.V2|)?$/$1/ig;
                    # clear the dirpart for later usage in pnp4nagios
                    $dirpart =~ s/:[\\\/]/_/g;  $dirpart =~ s/[^a-zA-Z0-9\-_\ ]//g;
                    # and now create the final filename
                    if ($namepart ne "")
                    {
                      $currentquota = $namepart . (($i == 0) ? "" : "-$dirpart");
                    }
                    else
                    {
                      $currentquota = $dirpart;
                    }
                    next;
                  } # end if fits win grouphomepath pattern
                } # end foreach win grouphomepath template supplied
                logme ("fpath '$fpath' => name '$namepart', dir '$dirpart'", 4);
              }

              if (!defined($repout{$currentquota}))
              {
                logme ("Found new quotapath $currentquota (userquota? " .($isuserquota?"yes":"no"). ", groupquota? " .($isgroupquota?"yes":"no"). ", fpath: $fpath)", 2);

                $repout{$currentquota} = ();
                $repout{$currentquota}{'fpath'} = $fpath;
                $repout{$currentquota}{'grace'} = 0;        # we dont use grace, but just in case we add a fake value here
                $repout{$currentquota}{'isuserquota'} = (($isuserquota) ? 1 : 0);
                $repout{$currentquota}{'isgroupquota'} = (($isgroupquota) ? 1 : 0);
                $repout{$currentquota}{'name'} = $currentquota;
                # non implemented shite ;-)
                $repout{$currentquota}{'status'} = "OK";      # status is "OK" by default since there is no such thing as -+ on Windows ;-)
                $repout{$currentquota}{'softlimit'} = 0;      # there is no softlimit on Windows, unless we get around to implement supporting the % warning levels given in the report
                $repout{$currentquota}{'grace'} = 0;        # there is no grace at all in Windows, quite coincidentally. The puns literally write themselves ;-)

                if ($isuserquota)
                {
                  $namepd = $currentquota; $namepd =~ s/ /_/sg; $namepd =~ s/\./-/sg;  $namepd =~ s/_+$//g;
                  $repout{$currentquota}{'name-perfdata'} = $namepd;
                }
                else
                {
                  $namepd = $fpath;  $namepd =~ s/\:[\/\\]/_/isg;  $namepd =~ s/\./-/sg;  $namepd =~ s/[^a-zA-Z0-9\-_\+ ]//isg;  $namepd =~ s/ /_/sg;  $namepd =~ s/_+$//g;
                  $repout{$currentquota}{'name-perfdata'} = $namepd;
                }
                logme ("quotapath $currentquota has name-perfdata " .$repout{$currentquota}{'name-perfdata'}, 2);
              } # end if found new currentquota
              elsif (!defined($repout{$fpath}))
              {
                logme ("Found (tertiary) quotapath $currentquota (userquota? " .($isuserquota?"yes":"no"). ", groupquota? " .($isgroupquota?"yes":"no"). ", fpath: $fpath).. Skipping.", 2);
              } # end if found secondary entries, that have to be saved as filepaths
              else
              {
                logme ("!!! Found DUPE quotapath $currentquota (userquota? " .($isuserquota?"yes":"no"). ", groupquota? " .($isgroupquota?"yes":"no"). ", fpath: $fpath).. Skipping.", 1);
                $currentquota = "";
              } # end if found dupe currentquota
              $justfoundblockend = (0==1);
              $quotasparsed++;
            }
            else
            {
              logme ("Found in-block data: $inp", 3);
            }
          } # end if found begin of content
          elsif ($inp =~ m#^(?:Kontingentstatus|Quota state):\s+(\S+)(?:\s.*|)$#i)
          {
            my $quotastate = $1;
            # first set up a default (usually defined quotas are active, so we presume if nothing we recognize is found, it could still be active):
            $quotastate = "active"  if (!defined($quotastate));
            # then de-localize (for german):
            $quotastate = "Active"  if ($quotastate eq "Aktiviert");
            $quotastate = "Inactive"  if ($quotastate eq "Deaktiviert");
            if (defined($quotastate))
            {
              # then set the actual value:
              $quotastate = (($quotastate eq "Active") ? 1 : 0);
              if (defined($repout{$currentquota})) { $repout{$currentquota}{'active'} = $quotastate; }
              logme ("Found quota state: $quotastate", 3);
            }
          }
          elsif ($inp =~ m#^(?:Grenze|Limit):\s+([0-9,\.]+\s+\S+)(?:\s.*|)$#i)
          {
            # we don't have a softquota yet, so we set it to 0 until we get around to parsing the % warning levels
            if (defined($repout{$currentquota})) { $repout{$currentquota}{'hardlimit'} = convunitstobytes($1); }
            logme ("Found quota limit for $currentquota: $1 => " .$repout{$currentquota}{'hardlimit'}. " bytes", 3);
          }
          elsif ($inp =~ m#^(?:Verwendet|Used):\s+([0-9,\.]+\s+\S+)(?:\s.*|)$#i)
          {
            if (defined($repout{$currentquota})) { $repout{$currentquota}{'inuse'} = convunitstobytes($1); }
            logme ("Found quota used: $1 => " .$repout{$currentquota}{'inuse'}. " bytes", 3);
          }
          elsif ($inp =~ m#^(?:Verfuegbar|Available):\s+([0-9,\.]+\s+\S+)(?:\s.*|)$#i)
          {
           if (defined($repout{$currentquota})) { $repout{$currentquota}{'free'} = convunitstobytes($1); }
           logme ("Found quota available: $1 => " .$repout{$currentquota}{'free'}. " bytes", 3);
         }
         else
         {
           logme ("Found unused data: $inp", 4);
         }
       }  # end if we are in the content
     } # end foreach line in rename
     close (REP);
   }
   else
   {
     usage ("Couldn't open report $report_fpath for reading: $!\n");
   }
 }

 return ( { %repout } );
} # end sub parse_winreport



sub parse_linuxrepquota
{
  my $cmd = shift;
  $cmd = ""  if (!defined($cmd));
  my $isuserquota = shift;  if (!defined($isuserquota)) { $isuserquota = 0; }
  my $isgroupquota = shift;  if (!defined($isgroupquota)) { $isgroupquota = 0; }

  my $status;
  my @rqout = ();
  my %repout = ();
  if (defined($cmd))
  {
    logme ("executing cmd '$cmd'", 2);

    # create tempfile from sudo-call, just in case it goes wrong.. sudo returns 0 on success and 0 if not ;-)
    @rqout = split /\n/, `LC_ALL=C sudo -n -u root -- $cmd`;
    $status = $?;    # global $status from below
  }

  if ((defined($status)) and ($status != 0))
  {
    usage ("Unable to run repquota binary '$bin_repquota'.\n       Are we allowed to run (via sudo) '$cmd' ?\n\nYou might want to add the following to your /etc/sudoers:\n\n" .$ENV{'USER'}. " ALL=(root) NOPASSWD: $bin_repquota *");
    exit ($ERRORS{'UNKNOWN'});
  }

  else

  {
    @rqout = sort { $a cmp $b } @rqout;

    foreach my $line (@rqout)
    {
      logme ("REP> $line", 5);
      my @dat = split /\s+/, $line;
      next if (($#dat < 9) or ($dat[4] !~ /^\d+/));

      my ($quotaname, $quota_status, $quota_inuse, $quota_softlimit, $quota_hardlimit,$quota_grace) = ( $dat[0], $dat[1], $dat[2], $dat[3], $dat[4], $dat[5] );

      # remove the # in getpwnam output as 'user_#122', so rrdtool doesn't hiccup lateron.
      if ($quotaname =~ /#/)
      {
        $quotaname =~ s/#//g;
        $quotaname = "${quotaname}";
      }

      my $quotaname_perfdata = $quotaname;  $quotaname_perfdata =~ s/^uid /uid/g;

      # convert input \d+G by \d+M (but without the M)
      # XXX needs testing on a linux quota system
      $quota_inuse = convunitstobytes ($quota_inuse);
      $quota_softlimit = convunitstobytes ($quota_softlimit);
      $quota_hardlimit = convunitstobytes ($quota_hardlimit);
      #$quota_inuse = ($quota_inuse =~ /^(.*)[Gg]$/) ? $1*1024*1024*1024 : ($quota_inuse =~ /^(.*)[Mm]$/) ? $1*1024*1024 : ($quota_inuse =~ /^(.*)[Kk]$/) ? $1*1024 : $quota_inuse;
      #$quota_softlimit = ($quota_softlimit =~ /^(.*)[Gg]$/) ? $1*1024*1024*1024 : ($quota_softlimit =~ /^(.*)[Mm]$/) ? $1*1024*1024 : ($quota_softlimit =~ /^(.*)[Kk]$/) ? $1*1024 : $quota_softlimit;
      #$quota_hardlimit = ($quota_hardlimit =~ /^(.*)[Gg]$/) ? $1*1024*1024*1024 : ($quota_hardlimit =~ /^(.*)[Mm]$/) ? $1*1024*1024 : ($quota_hardlimit =~ /^(.*)[Kk]$/) ? $1*1024 : $quota_hardlimit;

      # now save the data in repinfos
      if (!defined($repout{$quotaname}))
      {
        logme ("Found new quotaname '$quotaname' (hardlimit:$quota_hardlimit,softlimit:$quota_softlimit,inuse:$quota_inuse,name-perfdata:$quotaname_perfdata)", 2);
        $repout{$quotaname} = ();
        $repout{$quotaname}{'isuserquota'} = $isuserquota;
        $repout{$quotaname}{'isgroupquota'} = $isgroupquota;
        $repout{$quotaname}{'hardlimit'} = $quota_hardlimit;
        $repout{$quotaname}{'softlimit'} = $quota_softlimit;
        $repout{$quotaname}{'inuse'} = $quota_inuse;
        $repout{$quotaname}{'free'} = ( ($quota_hardlimit - $quota_inuse > 0) ? ($quota_hardlimit - $quota_inuse) : 0 );
        $repout{$quotaname}{'grace'} = $quota_grace;
        $repout{$quotaname}{'active'} = 1;          # linux repquota entries are always active.
        $repout{$quotaname}{'status'} = $quota_status;
        $repout{$quotaname}{'name'} = $quotaname;
        $repout{$quotaname}{'name-perfdata'} = $quotaname_perfdata;
      } # end if is new quotaname
      else
      {
        logme ("!!! Found DUPE quotaname '$quotaname' (hardlimit:$quota_hardlimit,softlimit:$quota_softlimit,inuse:$quota_inuse).. Skipping.", 1);
      } # end if is dupe quotaname
    } # end foreach line from linux-repquota output
  } # end if status returned was 0 == OK

  return ( { %repout } );
} # end sub parse_linuxrepquota





## init
use vars qw($opt_g $opt_u $opt_v $opt_h $opt_p $opt_m $opt_Q $opt_W $opt_s $opt_l $opt_L $opt_f $opt_P $opt_n $opt_x
            $username $groupname $report_fpath $mountpoint $quota_status $quota_inuse $quota_softlimit $quota_hardlimit $quota_reqtype
      %ERRORS @rqout @outlist $out);

$username = "";
$groupname = "";
$mountpoint = "";
$quota_reqtype = "";
$report_fpath = "";

$bin_repquota = "/usr/sbin/repquota";
if ($detectedos ne "Windows")
{
  if ((!defined($bin_repquota)) or (! -e $bin_repquota))
    { $bin_repquota = `which repquota 2>/dev/null`;  chomp ($bin_repquota); }
}



## args
if ($#ARGV < 0)
{
  &usage;
}
else
{
  getopts('af:l:L:u:g:m:W:x:npPQhs');
}

# this is above the -h parameter, so the report_fpath can be shown in the usage info.
if ( (defined($opt_W)) and ($opt_W ne "") )
{
  $report_fpath = 'c:\temp\check_quota-dirquota.log';
  $report_fpath = $opt_W;
  if (! -e $report_fpath)
  {
    usage ("Provided report $report_fpath doesn't exist.. Please provide the correct filepath!");
  }
  elsif (! -r $report_fpath)
  {
    usage ("Provided report $report_fpath is not readable.. Please update the security permissions on the file!");
  }
}
else
{
  if ($detectedos eq "Windows")
  {
    usage ("You must provide the filepath to a quota report file (-W) on Windows.");
  }
}


## and the actual arg parsing
# first the actual plugin-internal parameters
$logfile = (($detectedos eq "Windows") ? '.\check_quota.log' : './check_quota.log');
if (defined($opt_f))
{
  $opt_f =~ s/[^a-zA-Z0-9\-\+\(\)\[\]_ \.\\\/'":]//sg;
  if ($opt_f ne "")
  {
    $logfile = $opt_f;
  }
  else
  {
    usage ("The logfile path can only contain these characters 'a-zA-Z0-9-+()[]_ \.\\'\":/' .");
  }
} # end if logfile path supplied

$loglvl_screen = 0;  # lots of stuff
if (defined($opt_l))
{
  if (($opt_l =~ /^[0-9]+$/) and ($opt_l == int ($opt_l)) and ($opt_l >= 0))
  {
    $loglvl_screen = abs(int($opt_l));
  }
  else
  {
    usage ("The screen-loglevel must be a number from 0..5");
  }
} # end if screen-loglevel supplied

$loglvl_file = 0;  # only defaults
if (defined($opt_L))
{
  if (($opt_L =~ /^[0-9]+$/) and ($opt_L == int ($opt_L)) and ($opt_L >= 0))
  {
    $loglvl_file = abs(int($opt_L));
  }
  else
  {
    usage ("The file-loglevel must be a number from 0..5");
  }
} # end if file-loglevel supplied

## since we have enough info for the logfile at this point, we do this here:
#logme ("Got arguments: " .join (",", @ARGV). ".", 5);

# show the help in between
if (defined($opt_h))
{
  usage();
}


# now the actual plugin-specific parameters
our $addperfdata = 0;  # dont add perfdata by default
if (defined($opt_p))
{
  $addperfdata = 1;
}

our $shownoquotaalso = 0;  # only show users/groups with quotas by default
if (defined($opt_Q))
{
  $shownoquotaalso = 1;
}

our $showonlynotok = 0;    # only show users/groups with quotas, that do not have status OK
if (defined($opt_s))
{
  $showonlynotok = 1;
}

our $shortperfdata = 0;    # show perfdata with humanreadables instead of bytes
if (defined($opt_P))
{
  $shortperfdata = 1;
}

our $exitcodealwaysok = 0;  # dont return anything but OK
if (defined($opt_n))
{
  $exitcodealwaysok = 1;
}

if ( (!defined($opt_u)) and (!defined($opt_g)) )
{
  usage ("You have to do at least -u (check users) or -g (check groups).");
}

if ( (defined($opt_u)) and ($opt_u ne "") )
{
  $username = $opt_u;
  $username =~ s/[^0-9_a-zA-Z\.\*\?\+\-\:\\\[\]]//isg;    # allow for crude regexps
  $quota_reqtype = "usr";
}
# it's either user or group, never both.
elsif ( (defined($opt_g)) and ($opt_g ne "") )
{
  $groupname = $opt_g;
  $username =~ s/[^0-9_a-zA-Z\.\*\?\+\-\:\\\[\]]//isg;    # allow for crude regexps
  $quota_reqtype = "grp";
}

our $excluderegexp = "";
if ( (defined($opt_x)) and ($opt_x ne "") )
{
  $excluderegexp = $opt_x;
  $excluderegexp =~ s/[^0-9_a-zA-Z\.\*\?\+\-\:\\\[\]]//isg;    # allow for crude regexps
}


if ( (defined($opt_m)) and ($opt_m ne "") )
{
  if ($detectedos ne "Windows")
  {
    if ($opt_m ne "all")
    {
      $opt_m =~ s#[/\\]+$##g;
      my $mp_rc = mountpoint_with_quota_exists ($opt_m, $quota_reqtype);
      if ($mp_rc == 0)
      {
        usage ("Supplied opt_m '$opt_m' does not have requested ${quota_reqtype} quotatype active.");
      } # end if mp doesnt have quota
      elsif ($mp_rc == -1)
      {
        usage ("Supplied opt_m '$opt_m' exists, but is not mounted.");
      } # end if mp doesnt exist
      elsif ($mp_rc == -2)
      {
        usage ("Supplied opt_m '$opt_m' does not exist.");
      } # end if mp doesnt exist
      else
      {
        $mountpoint = $opt_m;
      }
    } # end if is not all-mp
    else
    {
      $mountpoint = "all";
    }
  } # end if is not Windows
  else
  {
    usage ("There is no mountpoint-based quota-feature on Windows.");
  } # end if is Windows
} # end if opt_m defined

else # use "all" by default
{
  $mountpoint = "all";
}



logme ("Arg opt_u '" .(defined($opt_u) ? $opt_u : ""). "' => username '$username'", 3);
logme ("Arg opt_g '" .(defined($opt_g) ? $opt_g : ""). "' => groupname '$groupname'", 3);
logme ("Arg opt_m '" .(defined($opt_m) ? $opt_m : ""). "' => mountpoint '$mountpoint'", 3);
logme ("Arg opt_W '" .(defined($opt_W) ? $opt_W : ""). "' => report_fpath '$report_fpath'", 3);
logme ("Arg opt_p '" .(defined($opt_p) ? $opt_p : ""). "' => addperfdata '$addperfdata'", 3);
logme ("Arg opt_P '" .(defined($opt_P) ? $opt_P : ""). "' => shortperfdata '$shortperfdata'", 3);
logme ("Arg opt_s '" .(defined($opt_s) ? $opt_s : ""). "' => showonlynotok '$showonlynotok'", 3);
logme ("Arg opt_n '" .(defined($opt_n) ? $opt_n : ""). "' => exitcodealwaysok '$exitcodealwaysok'", 3);
logme ("Arg opt_x '" .(defined($opt_x) ? $opt_x : ""). "' => excluderegexp '$excluderegexp'", 3);
logme ("Arg opt_Q '" .(defined($opt_Q) ? $opt_Q : ""). "' => shownoquotaalso '$shownoquotaalso'", 3);
logme ("Arg opt_f '" .(defined($opt_f) ? $opt_f : ""). "' => logfile '$logfile'", 3);
logme ("Arg opt_l '" .(defined($opt_l) ? $opt_l : ""). "' => loglvl_screen '$loglvl_screen'", 3);
logme ("Arg opt_L '" .(defined($opt_L) ? $opt_L : ""). "' => loglvl_file '$loglvl_file'", 3);


###
### main
###

my $cmd = "";

if ($detectedos ne "Windows")
{
  # get the repquota info we want to check
  $cmd = "$bin_repquota -c -v -s -p ";
  if ((defined($username)) and ($username ne ""))
    { $cmd .= "-u "; }
  elsif ((defined($groupname)) and ($groupname ne ""))
    { $cmd .= "-g "; }
  else
    { usage(); }
} # end if is linux/non-windows
elsif ($detectedos eq "Windows")
{
  # nothing to do here, since we are parsing the report file below.
} # end if is windows
else
{
  usage ("Got unknown OS: $detectedos .");
} # end if is unknown os

my @rqout = ();
my %repinfos;
if ($cmd ne "")    # as of now, this only is being used in systems that are not Windows ;-)
{
  # since the mountpoint has already been checked above, there is no need to check it again at this point:
  if ($mountpoint eq "all")
    { $cmd .= "-a "; }
  else
    { $cmd .= "$mountpoint "; }

  my $riref = parse_linuxrepquota($cmd, ($username ne ""), ($groupname ne ""));
  %repinfos = %{$riref};
} # end if doing cmd route

if (($report_fpath ne "") and (-r $report_fpath))
{
  my $riref = parse_winreport ($report_fpath);
  %repinfos = %{$riref}
} # end if doing report route

logme ("%repinfos after import is: " .Dumper(%repinfos), 3);





# and parse the data into something more meaningful
my $perfdata = "";

my $nummatchingentities = 0;    # users/groups

my $last_exitcode = -1;
my $last_exitstatus = "UNKNOWN";
my $numoverquota = 0;

## now for the output creating:
foreach my $quotaname (sort keys %repinfos)
{
  logme ("Looking at $quotaname:\n" .Dumper($repinfos{$quotaname}), 3);
  if (defined($opt_u))
  {
    next if (($username eq "") or ($repinfos{$quotaname}{'isuserquota'} <= 0) or (($quotaname !~ /^$username$/) and ($username ne "all")));
    next if (($excluderegexp ne "") and ($quotaname =~ /^$excluderegexp$/));
  }
  elsif (defined($opt_g))
  {
    next if (($groupname eq "") or ($repinfos{$quotaname}{'isgroupquota'} <= 0) or (($quotaname !~ /^$groupname$/) and ($groupname ne "all")));
    next if (($excluderegexp ne "") and ($quotaname =~ /^$excluderegexp$/));
  }

  # skip if quota isnt active
  next if ((!defined($repinfos{$quotaname})) or ($repinfos{$quotaname}{'active'} <= 0));

  logme ("Found matching active quota $quotaname:\n" .Dumper($repinfos{$quotaname}). "\n", 1);

  # hardlimit > 1 only shows up for users that actually have a quota (via edquota)
  if ((defined($repinfos{$quotaname}{'status'})) and (
           ((defined($repinfos{$quotaname}{'hardlimit'})) and (($shownoquotaalso) or ($repinfos{$quotaname}{'hardlimit'} > 0)))
     ))
  {
    # Obviously the quota_status is set by what _you_ defined via edquota for the specific user/group
    #
    # XXX Thanks to Pavel V.R. there is now a more useful quota checking at this point, that includes quota gracetime (if active)
    # XXX Also, softlimit and hardlimits are now handled in a less pointless way below here.
    #
    # Message me if there is anything else you want and I might add it to the script. ;-)

    logme ("Found matching quota with non-zero hardlimit $quotaname\n", 3);
    my $retcode = $ERRORS {'UNKNOWN'};
    # first the repquota status codes
    if ($detectedos ne "Windows")
    {
      logme ("Found matching quota with non-zero hardlimit $quotaname on non-Windows.\n", 3);
      $repinfos{$quotaname}{'status'} = "OK"    if ($repinfos{$quotaname}{'status'} eq "--");
      $repinfos{$quotaname}{'status'} = "WARNING"  if ($repinfos{$quotaname}{'status'} eq "-+");
      $repinfos{$quotaname}{'status'} = "WARNING"  if ($repinfos{$quotaname}{'status'} eq "+-");
      $repinfos{$quotaname}{'status'} = "CRITICAL"  if ($repinfos{$quotaname}{'status'} eq "++");
      $repinfos{$quotaname}{'status'} = "CRITICAL"  if (($repinfos{$quotaname}{'status'} eq "WARNING") and ($repinfos{$quotaname}{'softlimit'} == 0));
      if ((defined($repinfos{$quotaname}{'grace'})) and ($repinfos{$quotaname}{'grace'} > 0))
      {
        $repinfos{$quotaname}{'grace'} -= time();
        $repinfos{$quotaname}{'status'} = "CRITICAL"  if ($repinfos{$quotaname}{'grace'} < 0);
      } # end if quota-gracetime.. is being graced.. by a gazelle, obviously.. yes, not every pun is a good pun or (at first writing) even intended ;-)
      logme ("Found matching quota with non-zero hardlimit $quotaname on non-Windows, status is now '" .$repinfos{$quotaname}{'status'}. "'.\n", 3);
    } # end if is running not windows, aka linux+repquota
    else
    {
      logme ("Found matching quota with non-zero hardlimit $quotaname on Windows.\n", 3);
      if ($repinfos{$quotaname}{'free'} < 1048576) { $repinfos{$quotaname}{'status'} = "CRITICAL"; }
      logme ("Found matching quota with non-zero hardlimit $quotaname on Windows, status is now '" .$repinfos{$quotaname}{'status'}. "'.\n", 3);
    } # end if is running on windows

    if ($exitcodealwaysok > 0)
      { $repinfos{$quotaname}{'status'} = "OK";  }

    $retcode = $ERRORS {$repinfos{$quotaname}{'status'}};

    my $inusevalue = convbytestounits ($repinfos{$quotaname}{'inuse'});
  # only show the yyy part of "xxxx / yyyy GB in use", if there is an yyyy
    my $maxvalue = -1;
    my $maxvalue_hr = "";
    if ($repinfos{$quotaname}{'softlimit'} > 0)
    {
      if ($repinfos{$quotaname}{'hardlimit'} > 0)
        { $maxvalue = $repinfos{$quotaname}{'hardlimit'}; }
      else
        { $maxvalue = $repinfos{$quotaname}{'softlimit'}; }
    } elsif ($repinfos{$quotaname}{'hardlimit'} > 0)
      { $maxvalue = $repinfos{$quotaname}{'hardlimit'}; }
    # else both are 0, so we dont care and leave it at ""
    else { $maxvalue = -1; }

    if ($maxvalue > 0)
      { $maxvalue_hr = convbytestounits ($maxvalue); }

    my $pd_softlimit = (($repinfos{$quotaname}{'softlimit'} > 0) ? (($shortperfdata <= 0) ? $repinfos{$quotaname}{'softlimit'} : convbytestounits($repinfos{$quotaname}{'softlimit'}, $shortperfdata)) : "");
    my $pd_hardlimit = (($repinfos{$quotaname}{'hardlimit'} > 0) ? (($shortperfdata <= 0) ? $repinfos{$quotaname}{'hardlimit'} : convbytestounits($repinfos{$quotaname}{'hardlimit'}, $shortperfdata)) : "");
    my $pd_inuse = (($repinfos{$quotaname}{'inuse'} > 0) ? (($shortperfdata <= 0) ? $repinfos{$quotaname}{'inuse'} : convbytestounits($repinfos{$quotaname}{'inuse'}, $shortperfdata)) : "");
    my $pd_label = ($shortperfdata <= 0) ? (defined($opt_u) ? "user":"group") : (defined($opt_u) ? "u":"g");

    # overall quota
    push @outlist, [ $retcode,
      $repinfos{$quotaname}{'status'},
      sprintf ( "%s - %s%s: %s%s%s",
        $repinfos{$quotaname}{'status'},
             ((defined($opt_u)) ? (($repinfos{$quotaname}{'name'} =~ /^\d+$/) ? "uid":"login") : "group") ." ",
             $repinfos{$quotaname}{'name'},
             convbytestounits($repinfos{$quotaname}{'inuse'}),
             (($maxvalue_hr ne "") ? " / $maxvalue_hr" : ""),
            (($repinfos{$quotaname}{'grace'} > 0) ? " (Grace: ".gracetohuman($repinfos{$quotaname}{'grace'}).")" : "")
      ),
      $pd_label ."_" .$repinfos{$quotaname}{'name-perfdata'}. "=$pd_inuse;$pd_softlimit;$pd_hardlimit;0; "
        ];
    $nummatchingentities++;
    $numoverquota++    if ($retcode != 0);
  } # end if got valid looking infos
} # end foreach entry in %repinfos

# this is the global summary for short output, that does not contain any extra infos:
if ($exitcodealwaysok <= 0)
{
  $perfdata = " num_" .((defined($opt_u)) ? "user":"group"). "s=$nummatchingentities;;;0; num_" .((defined($opt_u)) ? "user":"group"). "s_overquota=$numoverquota;;;0; ";
}

logme ("There are $numoverquota of $nummatchingentities entries over quota.", 2);


my $hadoutput = 0;
my $txtoutput = "";

foreach my $out (@outlist)
{
  $hadoutput = 1;
  if ($last_exitcode < $$out[0]) { $last_exitcode = $$out[0]; $last_exitstatus = $$out[1]; }
  if ($nummatchingentities > 1)
  {
    if ($showonlynotok <= 0) { $txtoutput .= $$out[2]; }
    elsif ($$out[1] ne "OK") { $txtoutput .= $$out[2]; }
    if ($detectedos ne "Windows")
    {
      if ($showonlynotok <= 0)  # => add perfdata to every entry each
      {
        $txtoutput .= ( (($addperfdata > 0) and ($showonlynotok <= 0)) ? " | " .$$out[3] : "" );
      }
      else      # if showonlynotok > 0 => add to global $perfdata all infos available
      {
        $perfdata .= ( ($addperfdata > 0) ? $$out[3] : "" );
      }
    }
    else # NSCP fucks up long plugin output, if perfdata is on every line, so we add it to the global $perfdata instead
    {
      $perfdata .= ( ($addperfdata > 0) ? $$out[3] : "" );
    }
    if (($showonlynotok <= 0) or ($$out[1] ne "OK")) { $txtoutput .= "\n"; }
  }
  logme ("got exitcode $$out[0] (status: $$out[1]) with data '$$out[2]'", 5);
}

# remove trailing space to not confuse nscp's perfdata parser; still PLEASE turn it off!
$perfdata =~ s/ $//g;

#print "txtout is now:\n$txtoutput\n-------------------------\n";

my $statusline = "";
if ($nummatchingentities > 1)
{
  if ($exitcodealwaysok > 0)
  {
    $statusline = "No checking done, perfdata only.";
  }
  else
  {
    if ($numoverquota > 0)
      { $statusline = "$last_exitstatus - $numoverquota of $nummatchingentities ".((defined($opt_u)) ? "users" : "groups")." are overquota." }
    else
      { $statusline = "$last_exitstatus - All $nummatchingentities ".((defined($opt_u)) ? "users" : "groups")." are ok." }
  }
  $statusline .= (($addperfdata > 0) ? " | $perfdata" : "");
} # end if many quotas checked

elsif ($nummatchingentities == 1)  # no statusline for only one result
{
  $perfdata = "$perfdata $outlist[0][3]";  # add single user's perfdata if there is just one result
  $statusline = $outlist[0][2] . (($addperfdata > 0) ? " | $perfdata" : "");
} # end if one quota checked

else

{
  my $entfound = 1;    # provide entityfound = yes, if all users or groups were chosen
  if (($username ne "all") and ($groupname ne "all"))
  {
    if ($detectedos ne "Windows")
    {
      $entfound = ((defined($opt_u)) ? (getpwnam ($username)) : (getgrnam ($groupname)));
    } # end if we are on non windows AKA linux
    else { }  # windows does not implement this in any way so we have to check the report's output for search hits instead.
    $entfound = 0 if (!defined($entfound));
  }

  if (defined($opt_u))
  {
    if ($entfound <= 0)
    {
      if ($username eq "all")
      {
        $statusline .= "UNKNOWN - No users could be found?!";
      }
      else
      {
        $statusline .= "UNKNOWN - No such user '$username'";
      }
    }
    else
    {
      if ($username eq "all")
      {
        $statusline .= "UNKNOWN - No quota for any user could be found?!";
      }
      else
      {
        $statusline .= "UNKNOWN - No quota for user '$username'";
      }
    }
  } # end if user
  elsif (defined($opt_g))
  {
    if ($entfound <= 0)
    {
      if ($groupname eq "all")
      {
        $statusline .= "UNKNOWN - No groups could be found.";
      }
      else
      {
        $statusline .= "UNKNOWN - No such group '$groupname'";
      }
    }
    else
    {
      if ($groupname eq "all")
      {
        $statusline .= "UNKNOWN - No quota for any group could be found?!";
      }
      else
      {
        $statusline .= "UNKNOWN - No quota for group '$groupname'";
      }
    }
  } # end if group
} # end if no quotas checked

logme ("statusline has " .length($statusline). "b length, txtoutput " .length($txtoutput). "b.", 2);
print "$statusline\n$txtoutput";
exit $last_exitcode;


