TARGET ?= minieval
SRC_DIR := src
INC_DIR := include
CLI_DIR := cli
TEST_DIR := tests
BASE_OBJ_DIR ?= build
BASE_BIN_DIR ?= bin

CC := clang
LD := $(CC)
AR := llvm-ar

MODE ?= dev
OBJ_DIR := $(BASE_OBJ_DIR)/$(MODE)
BIN_DIR := $(BASE_BIN_DIR)/$(MODE)
FILTER ?=

CPPFLAGS := -I$(INC_DIR)
CFLAGS := -pipe -Wall -Wextra -std=gnu17
LDFLAGS := -fuse-ld=lld

RELEASE_FLAGS := -O3 -flto=thin
RELEASE_CFLAGS := $(RELEASE_FLAGS) -DNDEBUG -ffunction-sections -fdata-sections
RELEASE_LDFLAGS := $(RELEASE_FLAGS) -Wl,--as-needed -Wl,--gc-sections
NATIVE_FLAGS := -march=native -mtune=native

ifeq ($(MODE),dev)
  CFLAGS += -Og -g3
else ifeq ($(MODE),debug)
  CFLAGS += -O0 -g3 -fno-omit-frame-pointer
  TEST_SANITIZERS := -fsanitize=address,undefined,leak
else ifeq ($(MODE),release)
  CFLAGS += $(RELEASE_CFLAGS)
  LDFLAGS += $(RELEASE_LDFLAGS)
else ifeq ($(MODE),native)
  CFLAGS += $(RELEASE_CFLAGS) $(NATIVE_FLAGS)
  LDFLAGS += $(RELEASE_LDFLAGS) $(NATIVE_FLAGS)
else
  $(error unknown mode '$(MODE)' (expected dev, debug, release or native))
endif

MAKEFILE := $(lastword $(MAKEFILE_LIST))
ifneq ($(wildcard $(SRC_DIR)/.),)
  SOURCES := $(sort $(shell find $(SRC_DIR) -name '*.c' -type f))
  SOURCE_DIRS := $(shell find $(SRC_DIR) -type d)
endif
ifneq ($(wildcard $(CLI_DIR)/.),)
  CLI_SOURCES := $(sort $(shell find $(CLI_DIR) -name '*.c' -type f))
  CLI_SOURCE_DIRS := $(shell find $(CLI_DIR) -type d)
endif
ifneq ($(wildcard $(TEST_DIR)/.),)
  TEST_SOURCES := $(sort $(shell find $(TEST_DIR) -name '*.c' -type f))
  TEST_SOURCE_DIRS := $(shell find $(TEST_DIR) -type d)
endif
OBJECTS := $(patsubst $(SRC_DIR)/%.c,$(OBJ_DIR)/core/%.o,$(SOURCES))
PIC_OBJECTS := $(patsubst $(SRC_DIR)/%.c,$(OBJ_DIR)/pic/%.o,$(SOURCES))
CLI_OBJECTS := $(patsubst $(CLI_DIR)/%.c,$(OBJ_DIR)/cli/%.o,$(CLI_SOURCES))
TEST_OBJECTS := $(patsubst $(TEST_DIR)/%.c,$(OBJ_DIR)/tests/%.o,$(TEST_SOURCES))
LIB := $(BIN_DIR)/lib$(TARGET).a
SHARED_LIB := $(BIN_DIR)/lib$(TARGET).so
CLI_EXEC := $(BIN_DIR)/$(TARGET)
TEST_EXEC := $(BIN_DIR)/$(TARGET)-test
TEST_CORE := $(LIB)
DEPS := $(OBJECTS:.o=.d) $(PIC_OBJECTS:.o=.d) $(CLI_OBJECTS:.o=.d) $(TEST_OBJECTS:.o=.d)

ifeq ($(MODE),debug)
  TEST_CORE := $(patsubst $(SRC_DIR)/%.c,$(OBJ_DIR)/test-core/%.o,$(SOURCES))
  DEPS += $(TEST_CORE:.o=.d)
endif

all: lib-static lib-shared cli

lib-static: $(LIB)
lib-shared: $(SHARED_LIB)
cli: $(CLI_EXEC)

ifeq ($(SOURCES),)
  EMPTY_TARGETS := $(LIB) $(SHARED_LIB)
$(LIB) $(SHARED_LIB):
	$(error no c sources in $(SRC_DIR))
else
$(LIB): $(OBJECTS) $(SOURCE_DIRS) $(MAKEFILE) | $(BIN_DIR)
	@tmp=$$(mktemp -d "$(@D)/.lib$(TARGET).XXXXXX") && trap '$(RM) -r -- "$$tmp"' 0 && $(AR) rcs "$$tmp/$(@F)" $(OBJECTS) && $(LD) $(LDFLAGS) -nostdlib -r -Wl,--no-gc-sections,--whole-archive "$$tmp/$(@F)" -Wl,--no-whole-archive -o "$$tmp/core.o" && $(LD) $(LDFLAGS) -nostdlib -static -Wl,--no-gc-sections,-e,0 "$$tmp/core.o" -o "$$tmp/check" && mv -f -- "$$tmp/$(@F)" "$@"

$(SHARED_LIB): $(PIC_OBJECTS) $(SOURCE_DIRS) $(MAKEFILE) | $(BIN_DIR)
	$(LD) $(LDFLAGS) -nostdlib -shared -Wl,-z,defs,-soname,$(@F) $(PIC_OBJECTS) -o $@
endif

ifeq ($(CLI_SOURCES),)
  EMPTY_TARGETS += $(CLI_EXEC)
$(CLI_EXEC):
	$(error no c sources in $(CLI_DIR))
else
$(CLI_EXEC): $(CLI_OBJECTS) $(LIB) $(CLI_SOURCE_DIRS) $(MAKEFILE) | $(BIN_DIR)
	$(LD) $(LDFLAGS) $(CLI_OBJECTS) $(LIB) $(LDLIBS) -o $@
endif

test: $(TEST_EXEC)
	$(TEST_EXEC) "$(FILTER)"

$(TEST_EXEC): $(TEST_OBJECTS) $(LIB) $(TEST_CORE) $(TEST_SOURCE_DIRS) $(MAKEFILE) | $(BIN_DIR)
	$(LD) $(LDFLAGS) $(TEST_SANITIZERS) $(TEST_OBJECTS) $(TEST_CORE) $(LDLIBS) -o $@

$(OBJ_DIR)/core/%.o: $(SRC_DIR)/%.c $(MAKEFILE)
	@mkdir -p $(dir $@)
	$(CC) $(CPPFLAGS) $(CFLAGS) -ffreestanding -MMD -MP -c $< -o $@

$(OBJ_DIR)/pic/%.o: $(SRC_DIR)/%.c $(MAKEFILE)
	@mkdir -p $(dir $@)
	$(CC) $(CPPFLAGS) $(CFLAGS) -ffreestanding -fPIC -MMD -MP -c $< -o $@

$(OBJ_DIR)/cli/%.o: $(CLI_DIR)/%.c $(MAKEFILE)
	@mkdir -p $(dir $@)
	$(CC) $(CPPFLAGS) $(CFLAGS) -MMD -MP -c $< -o $@

ifeq ($(MODE),debug)
$(OBJ_DIR)/test-core/%.o: $(SRC_DIR)/%.c $(MAKEFILE)
	@mkdir -p $(dir $@)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(TEST_SANITIZERS) -ffreestanding -MMD -MP -c $< -o $@
endif

$(OBJ_DIR)/tests/%.o: $(TEST_DIR)/%.c $(MAKEFILE)
	@mkdir -p $(dir $@)
	$(CC) $(CPPFLAGS) -I$(TEST_DIR) $(CFLAGS) $(TEST_SANITIZERS) -MMD -MP -c $< -o $@

$(BIN_DIR):
	@mkdir -p $@

clean:
	$(RM) -r -- "$(BASE_OBJ_DIR)" "$(BASE_BIN_DIR)"

-include $(DEPS)

.DELETE_ON_ERROR:
.PHONY: all lib-static lib-shared cli test clean $(EMPTY_TARGETS)
