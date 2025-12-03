UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
    LIB_NAME = libsummaryfs.dylib
    CC_FLAGS = -dynamiclib -fPIC
else ifeq ($(UNAME_S),Linux)
    LIB_NAME = libsummaryfs.so
    CC_FLAGS = -shared -fPIC
else
    LIB_NAME = summaryfs.dll
    CC_FLAGS = -shared
endif

CC = gcc
CFLAGS = -Wall -O2 $(CC_FLAGS)
LDFLAGS = -lcurl
SRC = summaryfs.c yyjson.c

all: $(LIB_NAME)

$(LIB_NAME): $(SRC)
	$(CC) $(CFLAGS) -o $@ $(SRC) $(LDFLAGS)

clean:
	rm -f $(LIB_NAME)

install: $(LIB_NAME)
	mkdir -p ../../agfs-server/plugins
	cp $(LIB_NAME) ../../agfs-server/plugins/

.PHONY: all clean install
