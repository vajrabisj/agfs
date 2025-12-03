CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -std=c11 -fPIC
LDFLAGS ?= -shared

TARGET = libskillsfs.so
OBJS = skillsfs.o yyjson.o

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $(OBJS)

skillsfs.o: skillsfs.c yyjson.h
	$(CC) $(CFLAGS) -c skillsfs.c -o $@

yyjson.o: yyjson.c yyjson.h
	$(CC) $(CFLAGS) -c yyjson.c -o $@

clean:
	rm -f $(TARGET) $(OBJS)
