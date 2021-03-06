#!/usr/bin/perl -w

# 2012-04-12, djenkins, initial
package libvirtWebui::main;

use strict;
use warnings;
use CGI qw/:standard :html3 tr td/;
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use Sys::Virt;
use Sys::Virt::Domain;
use XML::Simple;
use Data::Dumper;
use FindBin;

# Our script is broken down into modules, for organizational purposes.
# We don't place the modules in "/usr/lib/perl/...."
# When running the script in our development directory, we
# want to use local modules (./modules).  When running "in production", we want
# to use the privately installed modules (/opt/libvirt-webui/modules/...)

my $modulesDir;
BEGIN {
	my $binDir = $FindBin::Bin;
	$binDir =~ /^(.*)$/;
	$binDir = $1;			# untaint value.
	push (@INC, "$binDir");
}

# Now we can load our private modules (Now that '@INC' is patched).
use modules::cgiDebug;
use modules::libvirtTables;

# Super-duper global configs:
my $hostAddress = "qemu+tls://ostara/system";
my $optDebug = 0;

# No user-servicable parts below this line.
$CGI::POST_MAX=1024 * 100;  # max 100K posts
$CGI::DISABLE_UPLOADS = 1;  # no uploads

our $appRoot = "/vm"; # $ENV{'SCRIPT_NAME'};
our $wwwRoot = "$appRoot/www";
our $ip = $ENV{'REMOTE_ADDR'} || "0.0.0.0";
our $user = $ENV{'REMOTE_USER'} || "";
our $vmm = Sys::Virt->new(address => $hostAddress) || die "Sys::Virt->new failed\n";
our $cgi = CGI->new();

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

	debugVars($cgi) if ($optDebug);

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
