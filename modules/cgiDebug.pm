#!/usr/bin/perl

package libvirtWebui;

use strict;
use warnings FATAL => 'all';
use vars qw ($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;

@ISA = qw(Exporter AutoLoader);
$VERSION = '0.1';
@EXPORT  = qw(debugVars);

sub	debugVars ($) {
	my ($cgi) = @_;

	print "<p>\@INC:<ol>\n";
	foreach my $inc (@INC) {
		print $cgi->li($inc);
	}
	print "</ol></p>\n";

	print "<p>CGI vars:<ol>\n";
	my $vars = $cgi->Vars();
	foreach my $key (sort keys %$vars) {
		print $cgi->li($cgi->b($key), " = ", $vars->{$key});
	}
	print "</ol></p>\n";

	print "<p>ENV vars:<ol>\n";
	foreach my $e (sort keys %ENV) {
		print $cgi->li($cgi->b($e), " = ", $ENV{$e});
	}
	print "</ol></p>\n";
}


1;

