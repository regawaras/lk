AS = as
LD = ld
ASFLAGS = --64 -g
LDFLAGS = -z noexecstack -z relro -z now

TARGET = lk
SRC = src/main.s
OBJ = build/main.o

all: $(TARGET)

$(TARGET): $(OBJ)
	$(LD) $(LDFLAGS) -o $(TARGET) $(OBJ)

$(OBJ): $(SRC)
	mkdir -p build
	$(AS) $(ASFLAGS) $(SRC) -o $(OBJ)

clean:
	rm -rf build $(TARGET)

