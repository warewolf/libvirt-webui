#!/usr/bin/perl -w

# 2012-04-12, djenkins, initial
# 2012-04-25, djenkins, updated.

use strict;
use Sys::Virt;
use Sys::Virt::Domain;
use Getopt::Long;

# Super-duper global configs:
my $hostAddress = "qemu+tls://ostara/system";
my $flags = Sys::Virt::Domain::MEMORY_PHYSICAL;
my $blksize = (1024 * 64);	# Max memory peak size.

### Don't edit below this line.

my $vmm = Sys::Virt->new(address => $hostAddress) || die "Sys::Virt->new failed\n";

sub	binDump ($) {
	my ($dom) = @_;
	my $name = $dom->get_name();
	my $file = "/tmp/qemu-$name.bin";
	my $blocks = $dom->get_info()->{'maxMem'} / ($blksize / 1024);
	my $out;

# cap at 32MB
	$blocks = 32768 / ($blksize / 1024);

	open ($out, ">", $file) || die ("ERROR: can't open '$file'\n");
	binmode ($out);

	$dom->suspend() && die ("ERROR: suspend($name) failed.\n");
	for (my $i = 0; $i < $blocks; $i++) {
		my $buf = $dom->memory_peek($i * $blksize, $blksize, $flags) || die ("ERROR: memory_peak($name) failed.\n");
		print $out $buf;
		print STDERR sprintf ("\r%8d of %8d  (%s)", $i, $blocks, $name);
	}

	$dom->resume() && die ("ERROR: resume($name) failed.\n");
	close ($out);
	print STDERR "\n";
}

sub	dumpAll () {
	foreach my $dom ($vmm->list_domains()) {
		binDump ($dom);
	}
}

sub	dumpOne ($) {
	my ($id) = @_;
	my $dom;

	$dom = $vmm->get_domain_by_id ($id) if ($id =~ /^[\d]+$/);
	$dom = $vmm->get_domain_by_name ($id) unless (defined $dom);
	$dom = $vmm->get_domain_by_uuid ($id) unless (defined $dom);

	binDump ($dom) if (defined $dom);
}

dumpOne ("dwj-lnx-test");
