#	libvirt-webui/Makefile

APPDIR:=	/opt/libvirt-webui

#######################################################################
#######################################################################

DATE=		$(shell date '+%Y%m%d-%H%M%S')

.phoney:	all check clean install bounce bounce2

help:
		@echo -ne "\n\033[01;35mMakefile Targets:\033[0m\n"
		@for T in all clean check install bounce bounce2; \
			do echo -ne "\t\033[01;33m" $$T "\033[0m\n"; done
		@echo ""

clean:
#		rm -rf $(PFI_SQLITE) $(DATABASE) ./tmp

#######################################################################
#######################################################################

all:		dirs

# "check" -> Syntax check of perl scripts.
check:
		@ERROR=0; for SRC in `find . -name "*.p[ml]"`; do echo -ne "\033[01;31m$$SRC\033[0m  "; perl -cwT $$SRC; ((ERROR += $$?)); done; exit $$ERROR

install:	check
		install -m 755 -o root -g root -d $(APPDIR)
		install -m 755 -o root -g root -d $(APPDIR)/conf
		install -m 755 -o root -g root -d $(APPDIR)/cgi
		install -m 755 -o root -g root -d $(APPDIR)/www
		install -m 644 -o root -g root ./apache2.conf $(APPDIR)/conf/apache2.conf
		install -m 755 -o root -g root ./vm.pl $(APPDIR)/cgi/vm.pl
		install -m 644 -o root -g root ./vm.css $(APPDIR)/www/vm.css

bounce:
		/etc/init.d/apache2 configtest
		/etc/init.d/apache2 reload

bounce2:
		/etc/init.d/apache2 restart

