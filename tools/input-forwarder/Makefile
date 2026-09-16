CFLAGS ?= -O2 -Wall -Wextra -Werror
ROOT := ../..

ifdef NDK
CC := $(NDK)/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android29-clang
endif

aurora-input-forwarder: input-forwarder.c $(ROOT)/graphics/input-forward-protocol.h
	$(CC) $(CFLAGS) -I$(ROOT)/graphics -o $@ input-forwarder.c

host: input-forwarder.c
	$(CC) $(CFLAGS) -I$(ROOT)/graphics -o aurora-input-forwarder-host input-forwarder.c

clean:
	rm -f aurora-input-forwarder aurora-input-forwarder-host

.PHONY: host clean
