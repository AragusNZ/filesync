PREFIX ?= /usr/local
DESTDIR ?=

.PHONY: install uninstall install-deps-check

# Skip with: make install SKIP_INSTALL_DEPS_CHECK=1
# Omitted automatically when DESTDIR is set (packaging/staged installs).
install-deps-check:
	@if [ -z "$(SKIP_INSTALL_DEPS_CHECK)" ] && [ -z "$(DESTDIR)" ]; then \
		bash "$(CURDIR)/scripts/check-install-deps.sh"; \
	fi

install: install-deps-check
	install -d $(DESTDIR)$(PREFIX)/lib/filesync/bin
	install -d $(DESTDIR)$(PREFIX)/lib/filesync/commands
	install -d $(DESTDIR)$(PREFIX)/lib/filesync/lib
	install -d $(DESTDIR)$(PREFIX)/lib/filesync/share/defaults
	install -m755 bin/filesync $(DESTDIR)$(PREFIX)/lib/filesync/bin/filesync
	install -m755 commands/*.sh $(DESTDIR)$(PREFIX)/lib/filesync/commands/
	install -m644 lib/*.sh $(DESTDIR)$(PREFIX)/lib/filesync/lib/
	install -m644 share/defaults/preferences.default.json $(DESTDIR)$(PREFIX)/lib/filesync/share/defaults/
	install -m644 share/VERSION $(DESTDIR)$(PREFIX)/lib/filesync/share/VERSION
	install -d $(DESTDIR)$(PREFIX)/share/man/man1
	install -m644 man/filesync.1 $(DESTDIR)$(PREFIX)/share/man/man1/filesync.1
	install -d $(DESTDIR)$(PREFIX)/bin
	ln -snf ../lib/filesync/bin/filesync $(DESTDIR)$(PREFIX)/bin/filesync

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/filesync
	rm -rf $(DESTDIR)$(PREFIX)/lib/filesync
	rm -f $(DESTDIR)$(PREFIX)/share/man/man1/filesync.1 \
		$(DESTDIR)$(PREFIX)/share/man/man1/filesync.1.gz
