#	libvirt-webui/Makefile

APPDIR:=	/opt/libvirt-webui

#######################################################################
#######################################################################

DATE=		$(shell date '+%Y%m%d-%H%M%S')

.phoney:	all check clean install bounce bounce2 taillogs

all:		probeOs

help:
		@echo -ne "\n\033[01;35mMakefile Targets:\033[0m\n"
		@for T in all clean check install bounce bounce2; \
			do echo -ne "\t\033[01;33m" $$T "\033[0m\n"; done
		@echo ""

clean:
#		rm -rf $(PFI_SQLITE) $(DATABASE) ./tmp

taillogs:
		tail -f /var/log/libvirt/libvirtd.log /var/log/libvirt/qemu/*

#######################################################################
#######################################################################

probeOs:	probeOs.c
		gcc -std=c99 -Wall -O2 -pipe $< -o $@ -lvirt

# "check" -> Syntax check of perl scripts.
check:
		@ERROR=0; for SRC in `find . -name "*.p[ml]"`; do echo -ne "\033[01;31m$$SRC\033[0m  "; perl -cwT $$SRC; ((ERROR += $$?)); done; exit $$ERROR

install:	check
		install -m 755 -o root -g root -d $(APPDIR)
		install -m 755 -o root -g root -d $(APPDIR)/conf
		install -m 755 -o root -g root -d $(APPDIR)/www
		install -m 755 -o root -g root -d $(APPDIR)/cgi
		install -m 755 -o root -g root -d $(APPDIR)/cgi/modules
		install -m 644 -o root -g root ./apache2.conf $(APPDIR)/conf/apache2.conf
		install -m 755 -o root -g root ./vm.pl $(APPDIR)/cgi/vm.pl
		install -m 644 -o root -g root ./modules/*.pm $(APPDIR)/cgi/modules
		install -m 644 -o root -g root ./vm.css $(APPDIR)/www/vm.css
		install -m 644 -o root -g root ./img/fatcow/16x16/*.png $(APPDIR)/www

bounce:
		/etc/init.d/apache2 configtest
		/etc/init.d/apache2 reload

bounce2:
		/etc/init.d/apache2 restart

