#!/usr/bin/perl -wt

package modules::libvirtTables;

use strict;
use warnings FATAL => 'all';
use Sys::Virt;
use vars qw ($VERSION @ISA @EXPORT);
use Exporter;

our $VERSION = '0.1';
our @ISA = qw(Exporter);
our @EXPORT = qw(%domainState @ctrl_alt_del @commandOrder1 @commandOrder2 %commandIcons %validCommands);


our %domainState = (
	Sys::Virt::Domain::STATE_NOSTATE => "no state",
	Sys::Virt::Domain::STATE_RUNNING => "running",
	Sys::Virt::Domain::STATE_BLOCKED => "blocked",
	Sys::Virt::Domain::STATE_PAUSED => "paused",
	Sys::Virt::Domain::STATE_SHUTDOWN => "shutdown",
	Sys::Virt::Domain::STATE_SHUTOFF => "off",
	Sys::Virt::Domain::STATE_CRASHED => "crashed",
);

#our @ctrl_alt_del = ( 35, 18, 38, 38, 24, 57, 17, 24, 19, 38, 32, 28 );
our @ctrl_alt_del = ( 0x1d, 0x38, 0xd3,  );

# Order matters.
our @commandOrder1 = ('start', 'halt', 'reset', 'suspend', 'resume');
our @commandOrder2 = ('shutdown', 'reboot', 'ctrl-alt-del');

our %commandIcons = (
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
our %validCommands = (
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

1;

