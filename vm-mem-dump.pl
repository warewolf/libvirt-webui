#!/usr/bin/perl -w

# 2012-04-12, djenkins, initial

# Good stuff on Windows Kernel Version detection:
# Page #38: http://www.dtic.mil/dtic/tr/fulltext/u2/a499499.pdf

use strict;
use Sys::Virt;
use Sys::Virt::Domain;
#use XML::Simple;
#use Data::Dumper;
#use Getopt::Long;
use Data::HexDump;

# Super-duper global configs:
my $hostAddress = "qemu+tls://ostara/system";
my $flags = Sys::Virt::Domain::MEMORY_PHYSICAL;
my $blksize = (1024 * 64);	# Max memory peak size.
my $hexOffset = 0;
my $hexSize = 1024;

### Don't edit below this line.

my $vmm = Sys::Virt->new(address => $hostAddress) || die "Sys::Virt->new failed\n";

sub	binDump ($) {
	my ($dom) = @_;
	my $name = $dom->get_name();
	my $file = "/tmp/qemu-$name.bin";
	my $blocks = $dom->get_info()->{'maxMem'} * ($blksize / 1024);
	my $out;

	open ($out, ">", $file) || die ("ERROR: can't open '$file'\n");
	binmode ($out);

	$dom->suspend() && die ("ERROR: suspend($name) failed.\n");
	for (my $i = 0; $i < $blocks; $i++) {
		my $buf = $dom->memory_peek($i * $blksize, $blksize, $flags) || die ("ERROR: memory_peak($name) failed.\n");
		print $out $buf;
		print STDERR sprintf ("\r%8d of %8d  ", $i, $blksize);
	}

	$dom->resume() && die ("ERROR: resume($name) failed.\n");
	close ($out);
}

sub	hexDump ($) {
	my ($dom) = @_;
	my $name = $dom->get_name();
	my $file = "/tmp/qemu-$name.txt";
	my $out;

	open ($out, ">", $file) || die ("ERROR: can't open '$file'\n");
	my $buf = $dom->memory_peek($hexOffset, $hexSize, $flags) || die ("ERROR: memory_peak($name) failed.\n");
	my $hexer = new Data::HexDump;
	$hexer->data($buf);
	print $out $hexer->dump() . "\n";
	close ($out);
}

# Create a hex-dump of each running domain.
foreach my $dom ($vmm->list_domains()) {
	print STDERR "Processing: ", $dom->get_name(), "\n";
#	hexDump ($dom);
	binDump ($dom);
}
