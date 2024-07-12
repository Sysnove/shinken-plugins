#!/usr/bin/env perl
# vim: se et ts=4:

#
# Copyright (C) 2012, Giacomo Montagner <giacomo@entirelyunlike.net>
#               2015, Yann Fertat, Romain Dessort, Jeff Palmer,
#                     Christophe Drevet-Droguet <dr4ke@dr4ke.net>
#               2023 Desmarest Julien (Start81) 
# This program is free software; you can redistribute it and/or modify it
# under the same terms as Perl 5.10.1.
# For more details, see http://dev.perl.org/licenses/artistic.html
#
# This program is distributed in the hope that it will be
# useful, but without any warranty; without even the implied
# warranty of merchantability or fitness for a particular purpose.
#

use strict;
use warnings;
use File::Basename;
use LWP::UserAgent;
use URI::URL;
use HTTP::Request;
use IO::Socket::SSL qw( SSL_VERIFY_NONE );
use IO::Socket::UNIX;
use MIME::Base64;
use Readonly;
use Monitoring::Plugin;
use Data::Dumper;

#open(STDERR, ">&STDOUT");
Readonly our $VERSION => "1.1.6";
# CHANGELOG:
#   1.0.0   - first release
#   1.0.1   - fixed empty message if all proxies are OK
#   1.0.2   - add perfdata
#   1.0.3   - redirect stderr to stdout
#   1.0.4   - fix undef vars
#   1.0.5   - fix thresholds
#   1.1.0   - support for HTTP interface
#   1.1.1   - drop perl 5.10 requirement
#   1.1.2   - add support for ignoring DRAIN state
#   1.1.3   - add support ignoring hosts matching a regex
#   1.1.4   - Update the check via url (Https only) Jdesmarest 16/01/2023
#   1.1.5   - Update implement Monitoring::Plugin Jdesmarest 18/01/2023
#   1.1.6   - BugFix With Haproxy demo page Add http support Jdesmarest 20/10/2023

my %check_statuses = (
    UNK     => "unknown",
    INI     => "initializing",
    SOCKERR => "socket error",
    L4OK    => "layer 4 check OK",
    L4CON   => "connection error",
    L4TMOUT => "layer 1-4 timeout",
    L6OK    => "layer 6 check OK",
    L6TOUT  => "layer 6 (SSL) timeout",
    L6RSP   => "layer 6 protocol error",
    L7OK    => "layer 7 check OK",
    L7OKC   => "layer 7 conditionally OK",
    L7TOUT  => "layer 7 (HTTP/SMTP) timeout",
    L7RSP   => "layer 7 protocol error",
    L7STS   => "layer 7 status error",
);
my $verb;
sub verb { my $t=shift; if ($verb) {print $t,"\n"}  ; return 0};

# Defaults
my $swarn = 80.0;
my $scrit = 90.0;
my $sock  = "/var/run/haproxy.sock";
my $url;
my $user = '';
my $pass = '';
my $dump;
my $ignore_maint;
my $ignore_drain;
my $ignore_regex;
my $proxy;
my $no_proxy;
my $slave;
my $me = basename($0);
my $license = "This program is free software; you can redistribute it and/or modify it\n"
. "under the same terms as Perl 5.10.1\n"
. "For more details, see http://dev.perl.org/licenses/artistic.html\n\n"
. "This program is distributed in the hope that it will be\n"
. "useful, but without any warranty; without even the implied\n"
. "warranty of merchantability or fitness for a particular purpose.\n";

my $np = Monitoring::Plugin->new(  usage => "Usage: %s [-U <URL> [-u <User> -P <password>]]  [-p <proxy>] [-x <proxy>] [-m] [-n] [-s <servers>] [-i <REGEX>] [-w <threshold> ] [-c <threshold> ]  [-t <timeout>]  \n",
    plugin => $me,
    shortname => $me,
    blurb => "$me is a Nagios check for Haproxy using the statistics page via local socket or http(s) ",
    version => $VERSION,
    timeout => 30,
    license => $license,
);
$np->add_arg(
    spec => 'url|U=s',
    help => "-U, --url=STRING\n"
          . "  Use HTTPS Statistics URL instead of socket the url is used like this " . 'https://$url;csv',
    required => 0
);
$np->add_arg(
    spec => 'socket|S=s',
    help => "-S, --socket=STRING\n"
          . "  Use named UNIX socket instead of default (/var/run/haproxy.sock) ",
    required => 0
);
$np->add_arg(
    spec => 'ignoremaint|m',
    help => "-m, --ignoremaint\n"
          . " Assume servers in MAINT state to be ok. ",
    required => 0
);
$np->add_arg(
    spec => 'ignoredrain|n',
    help => "-n, --ignoredrain\n"
          . "  Assume servers in DRAIN state to be ok. ",
    required => 0
);
$np->add_arg(
    spec => 'ignoreregex|i=s',
    help => "-i, --ignoreregex=STRING\n"
          . "  Ignore servers that match the given regex. ",
    required => 0
);
$np->add_arg(
    spec => 'proxy|p=s',
    help => "-p, --proxy=STRING\n"
          . "  Check only named proxies, not every one. Use comma to separate proxies in list. ",
    required => 0
);
$np->add_arg(
    spec => 'noproxy|x=s',
    help => "-P, --noproxy=STRING\n"
          . "  Do not check named proxies. Use comma to separate proxies in list. ",
    required => 0
);
$np->add_arg(
    spec => 'user|u=s',
    help => "-u, --user=STRING\n"
          . "  User name  for the HTTPS URL",
    required => 0,
);
$np->add_arg(
    spec => 'Password|P=s',
    help => "-P, --Password=STRING\n"
          . "  User password for the HTTPS URL",
    required => 0,
);
$np->add_arg(
    spec => 'warning|w=s',
    help => "-w, --warning=threshold\n" 
          . "   See https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT for the threshold format.",
    required => 0,
);
$np->add_arg(
    spec => 'critical|c=s',
    help => "-c, --critical=threshold\n"  
          . "   See https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT for the threshold format.",
    required => 0,
);
$np->add_arg(
    spec => 'raw|r',
    help => "-r, --raw\n"  
          . '   Just dump haproxy stats and exit',
    required => 0,
);
$np->add_arg(
    spec => 'slave|s=s',
    help => "-s, --slave\n"  
          . '   Check if the named serveur have no connexion Use comma to separate serveur in list .',
    required => 0,
);
$np->add_arg(
    spec => 'ssl|S',
    help => "-S, --ssl\n The statistics page use SSL",
    required => 0
);
$np->getopts;

#Check parameters
if (defined $np->opts->url) {
    $url = $np->opts->url;
    if (( $np->opts->Password) and ($np->opts->user)) {
       $user = $np->opts->user;
       $pass= $np->opts->Password;
    }
    
}

#Get parameters
$swarn  = $np->opts->warning if (defined $np->opts->warning );
$scrit  = $np->opts->critical if (defined $np->opts->critical );
$dump = $np->opts->raw if (defined $np->opts->raw);
$ignore_maint = $np->opts->ignoremaint if (defined $np->opts->ignoremaint);
$ignore_drain = $np->opts->ignoredrain if (defined $np->opts->ignoredrain);
$ignore_regex = $np->opts->ignoreregex if (defined $np->opts->ignoreregex);
$proxy = $np->opts->proxy if (defined $np->opts->proxy);
$no_proxy = $np->opts->noproxy if (defined $np->opts->noproxy);
$verb = $np->opts->verbose ;
my $o_use_ssl = 0;
$o_use_ssl = $np->opts->ssl if (defined $np->opts->ssl);
$slave = $np->opts->slave  if (defined $np->opts->slave);
my $o_timeout = $np->opts->timeout;
if ($o_timeout > 60){
    $np->plugin_die("Invalid time-out");
}
alarm($o_timeout);

my $haproxy;


if ($url) {
    verb ($url);
    #Web client init
	my $tmp_uri = "http://" . $url . ';csv';
    $tmp_uri = "https://" . $url . ';csv' if ($o_use_ssl);
    my $ua = LWP::UserAgent->new(
            timeout  => 15,
            ssl_opts => {
                verify_hostname => 0,
                SSL_verify_mode => SSL_VERIFY_NONE,
            },
    );
    verb ($tmp_uri);
    
    my $basic_auth ='Basic ' . encode_base64("$user:$pass");
    verb($basic_auth);
    my $hdrs = HTTP::Headers->new (
        'Accept'     => 'text/plain',
        'User-Agent' => 'STAMPBrowser/1.0',
        'Cache-Control' => 'no-cache',
        'Authorization' => $basic_auth
    );
 
    my $uri  = URI::URL->new($tmp_uri);
    my $req  = HTTP::Request->new( 'GET', $uri, $hdrs );
    my $resp = $ua->request($req);
    #Getting stats
    $haproxy = $resp->content;
    if (!$resp->is_success) {
        $np->plugin_exit('UNKNOWN', $resp->status_line);
    }
} else {
    # Connect to haproxy socket and get stats
    my $haproxyio = IO::Socket::UNIX->new (
        Peer => $sock,
        Type => SOCK_STREAM,
    );
    $np->plugin_exit('UNKNOWN',"Unable to connect to haproxy socket: $sock\n$@")  unless $haproxyio;
    print $haproxyio "show stat\n" or $np->plugin_exit('UNKNOWN',"Print to socket failed: $!");
    $haproxy = '';
    while (<$haproxyio>) {
        $haproxy .= $_;
    }
    close($haproxyio);
}

# Dump stats and exit if requested
if ($dump) {
    print($haproxy);
    exit 0;
}

#Stats parsing
# Get labels from first output line and map them to their position in the line
my @hastats = ( split /\n/, $haproxy );
my $labels = $hastats[0];
$np->plugin_exit('UNKNOWN',"Unable to retrieve haproxy stats") unless $labels;
chomp($labels);
$labels =~ s/^# // or $np->plugin_exit('UNKNOWN',"Data format not supported.");
verb ($labels);
my @labels = split /,/, $labels;
{
    no strict "refs";
    my $idx = 0;
    map { $$_ = $idx++ } @labels;
}

# Variables I will use from here on:
my @criticals = ();
my @warnings = ();
my @ok = ();
our $pxname;
our $svname;
our $status;
our $slim;
our $scur;
my @proxies;
@proxies = split ',', $proxy if $proxy;
my @no_proxies; 
@no_proxies = split ',', $no_proxy if $no_proxy;

my $exitcode = 0;
my $msg;
my $checked = 0;
my $perfdata = "";
my $probe_name = "";
my $perf_warn;
my $perf_crit;
my $compare_status;

# Remove excluded proxies from the list if both -p and -P options are
# specified.
my %hash;
@hash{@no_proxies} = undef;
@proxies = grep{ not exists $hash{$_} } @proxies;

foreach (@hastats) {
    chomp;
    next if /^#/;
    next if /^[[:space:]]*$/;
    my @data = split /,/, $_;
    if (@proxies) { next unless grep {$data[$pxname] eq $_} @proxies; };
    if (@no_proxies) { next if grep {$data[$pxname] eq $_} @no_proxies; };
    # Is session limit enforced?
    if ($data[$slim]) {
        $probe_name = $data[$pxname] . '-' .  $data[$svname];
        $perf_warn = $swarn * $data[$slim] / 100;
        $perf_crit = $scrit * $data[$slim] / 100;
        $np->add_perfdata(label => $probe_name, value => $data[$scur] , warning => $perf_warn, critical=> $perf_crit, min => 0, max=> $data[$slim]);
        # Check current session # against limit
        my $sratio = ($data[$scur]/$data[$slim]);
        $np->set_thresholds(warning => $swarn/100 , critical => $scrit/100);
        $compare_status = $np->check_threshold($sratio);
        if ($compare_status != 0) {
            $exitcode = $compare_status == 2 ? 2 :  $exitcode < 2 ? $compare_status : $exitcode;
            push(@warnings,sprintf "%s:%s sessions: %.2f%%; ", $data[$pxname], $data[$svname], $sratio * 100) if ($compare_status==1);
            push(@criticals,sprintf "%s:%s sessions: %.2f%%; ", $data[$pxname], $data[$svname], $sratio * 100) if ($compare_status==2);

        }
        ++$checked;
    }

    # Check of BACKENDS
    if ($data[$svname] eq 'BACKEND') {
        next if ($ignore_regex && $data[$pxname] =~ ".*${ignore_regex}.*");
        if ($data[$status] ne 'UP') {
            push(@criticals,sprintf "BACKEND: %s is %s; ", $data[$pxname], $data[$status]);

        }
    # Check of FRONTENDS
    } elsif ($data[$svname] eq 'FRONTEND') {
        if ($data[$status] ne 'OPEN') {
            push(@criticals,sprintf "FRONTEND: %s is %s; ", $data[$pxname], $data[$status]);

        }
    # Check of servers
    } else { 
        if (($data[$status] ne 'UP') and ($data[$status] ne 'OPEN')) {
            next if ($ignore_maint && $data[$status] eq 'MAINT');
            next if ($ignore_drain && $data[$status] eq 'DRAIN');
            next if ($ignore_regex && $data[$svname] =~ ".*${ignore_regex}.*");
            next if $data[$status] eq 'no check';   # Ignore server if no check is configured to be run
            next if $data[$svname] eq 'sock-1';
            our $check_status;
            $msg .= sprintf "server: %s:%s is %s", $data[$pxname], $data[$svname], $data[$status];
            $msg .= sprintf " (check status: %s)", $check_statuses{$data[$check_status]} if $check_statuses{$data[$check_status]};
            $msg .= "; ";
            push(@criticals,$msg);
        } else {
            #Check if spare server is in use
            if ($slave) { 
                if (index($slave,$data[$svname]) != - 1) { 
                    if ($data[$scur] > 0 ) {
                        $msg .= sprintf "server: %s:%s is %s sessions: %u" , $data[$pxname], $data[$svname], $data[$status],$data[$scur];
                        push(@criticals,$msg);
                    }
                }
            }

        }
    }
    
}

$np->plugin_exit('CRITICAL', join(', ', @criticals)) if (scalar @criticals > 0);
$np->plugin_exit('WARNING', join(', ', @warnings)) if (scalar @warnings > 0);

$msg = @proxies ? sprintf("checked proxies: %s", join ', ', sort @proxies) : "checked $checked proxies.";
if ($checked) {
    $np->plugin_exit('OK', $msg ) ;
} else {
    $np->plugin_exit('UNKNOWN', "no proxy found" );
}
