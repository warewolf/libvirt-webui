#!/usr/bin/perl -w

# 2012-04-12, djenkins, initial
package libvirtWebui::main;

use strict;
use CGI qw/:standard :html3 tr td/;
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use Sys::Virt;
use Sys::Virt::Domain;
use XML::Simple;
use Data::Dumper;

# http://stackoverflow.com/questions/4363913/splitting-code-into-files-in-perl
use FindBin;
use lib "$FindBin::Bin/.";

use vm_debug;

# Super-duper global configs:
my $hostAddress = "qemu+tls://ostara/system";

# No user-servicable parts below this line.
$CGI::POST_MAX=1024 * 100;  # max 100K posts
$CGI::DISABLE_UPLOADS = 1;  # no uploads

our $appRoot = "/vm"; # $ENV{'SCRIPT_NAME'};
our $wwwRoot = "$appRoot/www";
our $ip = $ENV{'REMOTE_ADDR'} || "0.0.0.0";
our $user = $ENV{'REMOTE_USER'} || "";
our $vmm = Sys::Virt->new(address => $hostAddress) || die "Sys::Virt->new failed\n";
our $cgi = CGI->new();

my %domainState = (
	Sys::Virt::Domain::STATE_NOSTATE => "no state",
	Sys::Virt::Domain::STATE_RUNNING => "running",
	Sys::Virt::Domain::STATE_BLOCKED => "blocked",
	Sys::Virt::Domain::STATE_PAUSED => "paused",
	Sys::Virt::Domain::STATE_SHUTDOWN => "shutdown",
	Sys::Virt::Domain::STATE_SHUTOFF => "off",
	Sys::Virt::Domain::STATE_CRASHED => "crashed",
);

#my @ctrl_alt_del = ( 35, 18, 38, 38, 24, 57, 17, 24, 19, 38, 32, 28 );
my @ctrl_alt_del = ( 0x1d, 0x38, 0xd3,  );

# Order matters.
my @commandOrder1 = ('start', 'halt', 'reset', 'suspend', 'resume');
my @commandOrder2 = ('shutdown', 'reboot', 'ctrl-alt-del');

my %commandIcons = (
	'start' => 'control_play_blue.png',
	'halt' => 'cancel.png',
	'shutdown' => 'control_stop_blue.png',
	'reboot' => 'update.png',
	'reset' => 'update.png',
	'suspend' => 'control_pause_blue.png',
	'resume' => 'control_play_blue.png',
	'ctrl-alt-del' => 'keyboard.png',
);

# Maps each command to a set of states the command is valid for in a given domain.
my %validCommands = (
	'start' => {
		Sys::Virt::Domain::STATE_SHUTDOWN => 1,
		Sys::Virt::Domain::STATE_SHUTOFF => 1,
		Sys::Virt::Domain::STATE_CRASHED => 1
	},
	'halt' => {
		Sys::Virt::Domain::STATE_SHUTDOWN => 1,
		Sys::Virt::Domain::STATE_RUNNING => 1,
		Sys::Virt::Domain::STATE_BLOCKED => 1,
		Sys::Virt::Domain::STATE_PAUSED => 1,
		Sys::Virt::Domain::STATE_CRASHED => 1,
	},
	'shutdown' => {
		Sys::Virt::Domain::STATE_RUNNING => 1,
		Sys::Virt::Domain::STATE_BLOCKED => 1,
		Sys::Virt::Domain::STATE_PAUSED => 1,
		Sys::Virt::Domain::STATE_CRASHED => 1,
	},
	'reboot' => {
		Sys::Virt::Domain::STATE_RUNNING => 1,
		Sys::Virt::Domain::STATE_BLOCKED => 1,
		Sys::Virt::Domain::STATE_PAUSED => 1,
	},
	'reset' => {
		Sys::Virt::Domain::STATE_SHUTDOWN => 1,
		Sys::Virt::Domain::STATE_RUNNING => 1,
		Sys::Virt::Domain::STATE_BLOCKED => 1,
		Sys::Virt::Domain::STATE_PAUSED => 1,
		Sys::Virt::Domain::STATE_CRASHED => 1,
	},
	'suspend' => {
		Sys::Virt::Domain::STATE_RUNNING => 1,
	},
	'resume' => {
		Sys::Virt::Domain::STATE_PAUSED => 1,
	},
	'ctrl-alt-del' => {
		Sys::Virt::Domain::STATE_RUNNING => 1,
	}

);

#print STDERR Dumper (\%validCommands); exit (0);

sub	doSendCtrlAltDel ($) {
	my ($dom) = @_;
	$dom->send_key(Sys::Virt::Domain::KEYCODE_SET_LINUX, 100, \@ctrl_alt_del);
}

sub	isValidCommand ($$) {
	my ($state, $command) = @_;
	return defined ($validCommands{$command}->{$state});
}

sub	makeButton ($$) {
	my ($uuid, $cmd) = @_;

	my $img = (defined $commandIcons{$cmd}) ? ($wwwRoot . "/" . $commandIcons{$cmd}) : "";

	return 	$cgi->start_form(-method => 'POST', -class => 'buttons') .
		$cgi->hidden (-name => "vm_uuid", -value => $uuid, -force => 1) .
		$cgi->hidden (-name => "command", -value => $cmd, -force => 1) .
		$cgi->image_button (-name => "submit", -alt => $cmd, -title => $cmd, -src => $img) .
		$cgi->end_form();
}

sub	makeButtonSet ($$) {
	my ($cmdSet, $dom) = @_;
	my $html;

	foreach my $cmd (@$cmdSet) {
		my ($state, $reason) = $dom->get_state();
		my $uuid = $dom->get_uuid_string();
		my $btn = isValidCommand ($state, $cmd) ? makeButton ($uuid, $cmd) : "";
		$html .= $cgi->li($cgi->div ({-class => 'button'}, $btn));
	}

	return $cgi->ul({-class => 'control'}, $html);
}

sub	makeDomainRow ($$) {
	my ($dom, $idx) = @_;

	my $xmlStr = $dom->get_xml_description (0);
	my $xs = new XML::Simple (ForceArray => 1);
	my $xml = $xs->XMLin($xmlStr);
#	print STDERR "\n\n", $dom->get_name(), "\n\n", Dumper($xml), "\n"; exit (0);

	my $macAddr = $xml->{'devices'}[0]->{'interface'}[0]->{'mac'}[0]->{'address'} || "n/a";
	$macAddr =~ s/^82:00:00:00/::/g;

	my $vncPort = $xml->{'devices'}[0]->{'graphics'}[0]->{'port'} || "n/a";

	my $vcpus = $dom->get_vcpus();
	$vcpus = "" if ($vcpus == -1);

	my $r = ($idx & 1) ? "r1" : "r0";
	my $uuid = $dom->get_uuid_string();
	my ($state, $reason) = $dom->get_state();

	return $cgi->tr({-class => $r},
		$cgi->td ($cgi->a ({-href=>"$appRoot/detail/$uuid"}, $dom->get_name())),
		$cgi->td ($domainState{$state}),
		$cgi->td ($dom->get_max_memory() / 1024),
		$cgi->td ($vcpus),
		$cgi->td ($macAddr),
		$cgi->td ($vncPort),
		$cgi->td (makeButtonSet (\@commandOrder1, $dom)),
		$cgi->td (makeButtonSet (\@commandOrder2, $dom)));
}

sub	makeDomainTable () {
	my @cols = ("Name", "State", "Mem", "vCPUs", "MAC Addr", "VNC Port", "Force", "Graceful");

	my $thead;
	foreach my $col (@cols) { $thead .= $cgi->th($col); }
	$thead = $cgi->thead($cgi->tr($thead));

	my $tbody;
	my $idx = 0;
	my @vmList = ($vmm->list_defined_domains(), $vmm->list_domains());
	@vmList = sort { $a->get_name() cmp $b->get_name() } @vmList;
	foreach my $dom (@vmList) { $tbody .= makeDomainRow ($dom, $idx++); }

	return $cgi->table($thead, $tbody);
}

sub	doCommand ($$) {
	my ($command, $uuid) = @_;

	my $dom = $vmm->get_domain_by_uuid ($uuid) || die ("ERROR: Unable to get VMM domain for UUID $uuid\n");

	my $name = $dom->get_name();
	print $cgi->p("Command = $command, $uuid, $name") if (defined $command);

	if ($command eq "start") {
		$dom->create (0);
	} elsif ($command eq "shutdown") {
		$dom->shutdown ();
	} elsif ($command eq "halt") {
		$dom->destroy ();
	} elsif ($command eq "reboot") {
		$dom->reboot ();
	} elsif ($command eq "reset") {
		$dom->reset ();
	} elsif ($command eq "suspend") {
		$dom->suspend ();
	} elsif ($command eq "resume") {
		$dom->resume ();
	} elsif ($command eq "ctrl-alt-del") {
		doSendCtrlAltDel ($dom);
	}
}

sub	debugVars () {
	print "<p>CGI vars:</p><ol>\n";
	my $vars = $cgi->Vars();
	foreach my $key (sort keys %$vars) {
		print "<li><b>$key</b> = " . $vars->{$key} . "</li>\n";
	}
	print "</ol>\n";

	print "<p>ENV vars:</p><ol>\n";
	foreach my $e (sort keys %ENV) {
		print "<li><b>$e</b> = " . $ENV{$e} . "</li>\n";
	}
	print "</ol>\n";
}

sub	drawMainHeader () {
	my @now = localtime (time ());
	my $ts = sprintf ("%04d-%02d-%02d %02d:%02d:%02d",
		$now[5] + 1900, $now[4] + 1, $now[3], $now[2], $now[1], $now[0]);

	print $cgi->div({-class=>'header'}, 
		$cgi->div({-class=>'hdr-left'},
			$cgi->p($cgi->span({-class=>'key'}, "Client IP:"),
				$cgi->span({-class=>'value'}, $ip),
			),
			$cgi->p($cgi->span({-class=>'key'}, "User:"),
				$cgi->span({-class=>'value'}, $user),
			),
			$cgi->p($cgi->span({-class=>'key'}, "Time:"),
				$cgi->span({-class=>'value'}, $ts),
			),
		),
		$cgi->div({-class=>'hdr-right'},
			$cgi->p($cgi->a({-href=>"$appRoot"},
				$cgi->img({-src => "$wwwRoot/house.png",
					-alt => "Reload VM List",
					-title => "Reload Page"}),
				),
			),
		),
	),
	$cgi->div({-class=>'clear'});
}

sub	doDetailPage ($) {
	my ($uuid) = @_;

	drawMainHeader();

	my $dom = $vmm->get_domain_by_uuid ($uuid) || die ("ERROR: Unable to get VMM domain for UUID $uuid\n");
	my $name = $dom->get_name();

	print $cgi->p("Details for $uuid, $name");

	my $xmlStr = $dom->get_xml_description (0);
	print $cgi->pre($cgi->escapeHTML($xmlStr));
}

sub	doPageMain () {
	drawMainHeader();

	my $command = $cgi->param('command');
	my $uuid = $cgi->param('vm_uuid');
	doCommand ($command, $uuid) if (defined $command);

	print makeDomainTable();
}

sub	doMain () {

	print $cgi->header;
	print $cgi->start_html(
		-title => 'Virtual Machines',
		-style => {-type => 'text/css', -src => "$wwwRoot/vm.css", -media => 'screen' },
	);

#	debugVars();

# Figure out what the request is for.
# "PATH_INFO" is in the form "/a/b/c/...."
	my @pathInfo = split (/\//, $ENV{'PATH_INFO'});

	if (0 == scalar @pathInfo) {
		doPageMain ();
	} elsif ($pathInfo[1] eq "detail") {
		doDetailPage ($pathInfo[2]);
	} else {
		print $cgi->p("ERROR: No handler for URL: <b>" . $ENV{'SCRIPT_URL'} . "</b>");
		drawMainHeader();
		print makeDomainTable();
	}

	print $cgi->end_html;
}

doMain();
