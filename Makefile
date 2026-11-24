BINDIR ?= apps/bin
CFLAGS ?= -O2
QUICKJS_DIR ?=

BOOTSTRAP := bootstrap/volt-linux-x86_64
COMPILER_SOURCE := compiler/volt_main.volt
VOLT_STDLIB := $(wildcard vstd/*.volt)
COMPILER_SOURCES := $(wildcard compiler/*.volt) $(VOLT_STDLIB)

.PHONY: browser browser-js browser-js-modern browser-media compiler verify-bootstrap
browser: $(BINDIR)/browser

browser-js: $(BINDIR)/browser $(BINDIR)/volt-js
browser-js-modern: $(BINDIR)/browser
	@test -n "$(QUICKJS_DIR)" && test -r "$(QUICKJS_DIR)/quickjs.h" && test -r "$(QUICKJS_DIR)/quickjs-amalgam.c" || { echo "Set QUICKJS_DIR to an extracted QuickJS-NG amalgam (quickjs.h and quickjs-amalgam.c)." >&2; exit 1; }
	$(CC) $(CPPFLAGS) $(CFLAGS) -D_GNU_SOURCE -funsigned-char -c "$(QUICKJS_DIR)/quickjs-amalgam.c" -o $(BINDIR)/quickjs-ng.o
	$(CC) $(CPPFLAGS) $(CFLAGS) -Wall -Wextra -Werror -DVOLT_QUICKJS -isystem "$(QUICKJS_DIR)" apps/browser_js_worker.c $(BINDIR)/quickjs-ng.o -o $(BINDIR)/volt-js-modern $(LDFLAGS) -lseccomp -lm -pthread
browser-media: $(BINDIR)/browser $(BINDIR)/volt-media

compiler: volt

volt: $(BOOTSTRAP) $(COMPILER_SOURCES) Makefile
	./$(BOOTSTRAP) $(COMPILER_SOURCE) -o $@

verify-bootstrap:
	mkdir -p compiler/.build
	PATH= ./$(BOOTSTRAP) $(COMPILER_SOURCE) -o compiler/.build/volt-first
	PATH= ./compiler/.build/volt-first $(COMPILER_SOURCE) -o compiler/.build/volt-second
	cmp compiler/.build/volt-first compiler/.build/volt-second

$(BINDIR)/browser: apps/browser.volt volt $(VOLT_STDLIB)
	mkdir -p $(BINDIR)
	./volt apps/browser.volt -o $@

$(BINDIR)/volt-js: apps/browser_js_worker.c
	mkdir -p $(BINDIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -Wall -Wextra -Werror $< -o $@ $(LDFLAGS) -lduktape -lseccomp

$(BINDIR)/volt-media: apps/browser_media_worker.c
	mkdir -p $(BINDIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -Wall -Wextra -Werror $< -o $@ $(LDFLAGS) $$(pkg-config --cflags --libs libavformat libavcodec libavutil libswscale libswresample libseccomp)
