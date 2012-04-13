#!/usr/bin/perl -w

# 2012-04-12

use strict;
use CGI ':html3';
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use Sys::Virt;
use Sys::Virt::Domain;
use XML::Simple;
use Data::Dumper;

# Super-duper global configs:
my $hostAddress = "qemu+tls://ostara/system";
my $appRoot = "/vm";
my $wwwRoot = "$appRoot/www";

sub	doList();

$CGI::POST_MAX=1024 * 100;  # max 100K posts
$CGI::DISABLE_UPLOADS = 1;  # no uploads

my $nLen = $ENV{'CONTENT_LENGTH'} || 0;
my $ip = $ENV{'REMOTE_ADDR'} || '0.0.0.0';
my $vmm =  Sys::Virt->new(address => $hostAddress) || die "Sys::Virt->new failed\n";
my $cgi = CGI->new();

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
my @commandOrder = ('start', 'halt', 'shutdown', 'reboot', 'reset', 'suspend', 'resume');
# disabled: 'ctrl-alt-del'

my %commandIcons = (
	'start' => 'control_play_blue.png',
	'halt' => 'cancel.png',
	'shutdown' => 'control_stop_blue.png',
	'reboot' => 'update.png',
	'reset' => 'update.png',
	'suspend' => 'control_pause_blue.png',
	'resume' => 'control_play_blue.png',
	'ctrl-alt-del' => 'keyboard',
);

# maps each command to a set of states the command is valid in for a given domain.
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

sub	isValidCommand ($$) {
	my ($state, $command) = @_;
	return defined ($validCommands{$command}->{$state});
}

sub	drawButton ($$) {
	my ($uuid, $text) = @_;

	my $img = "";
	$img = $wwwRoot . "/" . $commandIcons{$text} if (defined $commandIcons{$text});

	print $cgi->start_form(-method => 'POST', -class => 'buttons');
	print $cgi->hidden (-name => "vm_uuid", -value => $uuid, -force => 1);
	print $cgi->hidden (-name => "command", -value => $text, -force => 1);
	print $cgi->image_button (-name => "submit", -alt => $text, -src => $img);
	print $cgi->end_form(), "\n";
}

sub	doListDomain ($) {
	my ($dom) = @_;

	my $xmlStr = $dom->get_xml_description (0);
	my $xs = new XML::Simple (ForceArray => 1);
	my $xml = $xs->XMLin($xmlStr);
#	print STDERR "\n\n", $dom->get_name(), "\n\n", Dumper($xml), "\n"; exit (0);

	my $macAddr = $xml->{'devices'}[0]->{'interface'}[0]->{'mac'}[0]->{'address'} || "n/a";
	$macAddr =~ s/^82:00:00:00/::/g;

	my $vncPort = $xml->{'devices'}[0]->{'graphics'}[0]->{'port'} || "n/a";

	my $vcpus = $dom->get_max_vcpus();
	$vcpus = "" if ($vcpus == -1);

	my $uuid = $dom->get_uuid_string();
	print "<tr>";
	print "<td>", $dom->get_name(), "</td>";
	my ($state, $reason) = $dom->get_state();
	print "<td>", $domainState{$state}, "</td>";
	print "<td>", $dom->get_max_memory() / 1024, "</td>";

	print "<td>$vcpus</td>";
	print "<td>$macAddr</td>";
	print "<td>$vncPort</td>";

	print "<td><ul class='control'>";
	foreach my $cmd (@commandOrder) {
		print "<li><div class='button'>";
		if (isValidCommand ($state, $cmd)) {
			drawButton ($uuid, $cmd);
#		} else {
#			print "<span>&nbsp;</span>";
		}
		print "</div></li>";
	}
	print "</ul></td>";

	print "</tr>\n";
}

sub	doList () {
	print "<table><tr>";
	print "<th>Name</th>";
	print "<th>State</th>";
	print "<th>Mem</th>";
	print "<th>vCPUs</th>";
	print "<th>MAC Address</th>";
	print "<th>VNC Port</th>";
	print "<th>Actions</th>";
	print "</tr>\n";

	my @vmList = ($vmm->list_defined_domains(), $vmm->list_domains());
	@vmList = sort { $a->get_name() cmp $b->get_name() } @vmList;
	foreach my $dom (@vmList) { doListDomain ($dom); }

	print "</table>\n";
}

sub	doCommand ($$) {
	my ($command, $uuid) = @_;

	my $dom = $vmm->get_domain_by_uuid ($uuid);
	if (!defined $dom) {
		print $cgi->p("ERROR: Unable to get VMM domain for UUID $uuid");
		return;
	}

	print $cgi->p("Command = $command, $uuid") if (defined $command);

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
		$dom->send_key(Sys::Virt::Domain::KEYCODE_SET_LINUX, 100, \@ctrl_alt_del);
	}
}

sub	debugVars () {

	print "<ol>\n";
	my $vars = $cgi->Vars();
	foreach my $key (sort keys %$vars) {
		print "<li><b>$key</b> = " . $vars->{$key} . "</li>\n";
	}
	print "</ol>\n";
}

sub	doMain () {

	print $cgi->header;
	print $cgi->start_html(
		-title => 'Virtual Machines',
		-style => {-type => 'text/css', -src => "$wwwRoot/vm.css", -media => 'screen' },
	);
	print $cgi->h1({-align=>'center'}, 'Virtual Machines');
	print $cgi->h3({-align=>'center'}, "Your IP address is $ip");
	print $cgi->p($cgi->a({-href=>""}, "Reload VM List"));

#	debugVars();

	my $command = $cgi->param('command');
	my $uuid = $cgi->param('vm_uuid');
	doCommand ($command, $uuid) if (defined $command);

	doList();

	print $cgi->end_html;
}

doMain();
