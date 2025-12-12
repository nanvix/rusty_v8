# Makefile for building Rusty V8 for Nanvix

# Shell configuration for better error handling
SHELL := /bin/bash
.SHELLFLAGS := -ec

#===================================================================================================
# Configuration Variables
#===================================================================================================

# Set this variable to the location where Nanvix is installed.
NANVIX_HOME ?= $(HOME)/nanvix

# Set this variable to the location where the Nanvix toolchain is installed.
NANVIX_TOOLCHAIN ?= /opt/nanvix

# Set this variable to the Rust toolchain to use for building Nanvix projects.
NANVIX_RUST_TOOLCHAIN ?= +nanvix-x86

# Set this variable 'yes' to build in release mode, or 'no' for debug mode.
RELEASE ?= yes

# Set this variable to 'yes' for verbose output, or 'no' for quiet mode.
VERBOSE ?= no

# Set this variable to 'yes' to build with Docker, or 'no' for native cargo.
DOCKER ?= yes

#===================================================================================================
# Internal Variables
#===================================================================================================

# Default make target.
.DEFAULT_GOAL := help

# Verbosity control.
ifeq ($(VERBOSE), no)
  Q := @
else
  Q :=
endif

# Target triple to build.
NANVIX_TARGET := i686-unknown-nanvix

# Build mode flag.
ifeq ($(RELEASE), yes)
  BUILD_MODE := release
else
  BUILD_MODE := debug
endif

# Flags to pass to Cargo.
CARGO_FLAGS := --target $(NANVIX_TARGET) -vv
ifeq ($(BUILD_MODE), release)
  CARGO_FLAGS += --release
endif

# Directory where build artifacts are stored.
TARGET_DIR := target/$(NANVIX_TARGET)/$(BUILD_MODE)

# Location of the libclang shared objects. We rely on the Nanvix toolchain bundle
# so native and container builds share the exact same Clang version.
LIBCLANG_DIR_HOST := $(abspath $(NANVIX_TOOLCHAIN))/lib
LIBCLANG_DIR_DOCKER := /opt/nanvix/lib

# Build command.
ifeq ($(DOCKER), yes)
  # NOTES
  # - We deprioritize Docker container scheduling to avoid resource starvation of other processes.
  # - We use --init to ensure proper signal handling (Ctrl-C stops the container).
  # - We fix permissions at the end to ensure all files are owned by the current user.
  CARGO_BUILD_CMD := docker run --rm \
	--init \
	--sig-proxy=true \
	--cpu-shares=256 \
	--cpus=$(shell echo $$(( $$(nproc) / 2 ))) \
	-v "$(shell pwd):/mnt" \
	-v "$(NANVIX_HOME):/root/nanvix" \
	-e NANVIX_HOME=/root/nanvix \
	-e NANVIX_TOOLCHAIN=/opt/nanvix \
	-e LIBCLANG_PATH=$(LIBCLANG_DIR_DOCKER) \
	-e V8_FROM_SOURCE=1 \
	-e USER_ID=$(shell id -u) \
	-e GROUP_ID=$(shell id -g) \
	nanvix/toolchain:latest \
	/bin/bash -l -c 'cd /mnt && exec cargo $(NANVIX_RUST_TOOLCHAIN) build $(CARGO_FLAGS); chown -R $$USER_ID:$$GROUP_ID /mnt/target /mnt/gen 2>/dev/null || true'
else
	# Native cargo build with low priority.
	CARGO_BUILD_CMD := nice -n 20 env NANVIX_HOME=$(NANVIX_HOME) V8_FROM_SOURCE=1 LIBCLANG_PATH=$(LIBCLANG_DIR_HOST) cargo $(NANVIX_RUST_TOOLCHAIN) build $(CARGO_FLAGS)
endif

# Clean command.
ifeq ($(DOCKER), yes)
  CARGO_CLEAN_CMD := docker run --rm \
	--cpu-shares=256 \
	-v "$(shell pwd):/mnt" \
	-v "$(NANVIX_HOME):/root/nanvix" \
	-e NANVIX_HOME=/root/nanvix \
	-e NANVIX_TOOLCHAIN=/opt/nanvix \
	-e LIBCLANG_PATH=$(LIBCLANG_DIR_DOCKER) \
	nanvix/toolchain:latest \
	/bin/bash -l -c 'cd /mnt && cargo $(NANVIX_RUST_TOOLCHAIN) clean'
else
  CARGO_CLEAN_CMD := cargo clean
endif

# Cross-platform command definitions.
CP := cp
MKDIR := mkdir -p
RM := rm -f
RMDIR := rm -rf

# Directory where artifacts are installed.
INSTALL_DIR := dist/nanvix
INSTALL_LIB_DIR := $(INSTALL_DIR)/lib
INSTALL_BIN_DIR := $(INSTALL_DIR)/bin
INSTALL_ETC_DIR := $(INSTALL_DIR)/etc

# Actual build artifacts.
RUSTY_V8_LIB := $(TARGET_DIR)/gn_out/obj/librusty_v8.a
BINDING_FILE := $(TARGET_DIR)/gn_out/src_binding.rs
HELLO_NANVIX_BINARY := $(TARGET_DIR)/examples/hello_nanvix.elf
HELLO_NANVIX_BINARY_ABS := $(abspath $(HELLO_NANVIX_BINARY))

#===================================================================================================
# Build Targets
#===================================================================================================

# Declare phony targets.
.PHONY: all all-rusty_v8 all-hello_nanvix install install-rusty_v8 install-hello_nanvix run clean clean-rusty_v8 clean-hello_nanvix help

# Validate that cargo is available.
ifeq ($(shell command -v cargo 2>/dev/null),)
  $(error "cargo not found. Please install Rust toolchain")
endif

# Prints help.
help:
	$(Q)echo "Available Make Targets"
	$(Q)echo "  help                Show this help message (default)"
	$(Q)echo "  all                 Build all V8 projects for Nanvix"
	$(Q)echo "  all-rusty_v8        Build prebuilt static library"
	$(Q)echo "  all-hello_nanvix    Build hello_nanvix example"
	$(Q)echo "  install             Install all artifacts"
	$(Q)echo "  install-rusty_v8    Install artifacts to dist directory"
	$(Q)echo "  install-hello_nanvix Install hello_nanvix example"
	$(Q)echo "  run                 Run hello_nanvix example using run-nanvixd.sh"
	$(Q)echo "  clean               Clean all build artifacts"
	$(Q)echo "  clean-rusty_v8      Clean rusty_v8 build artifacts"
	$(Q)echo "  clean-hello_nanvix  Clean hello_nanvix build artifacts"
	$(Q)echo ""
	$(Q)echo "Configuration Variables"
	$(Q)echo "  RELEASE=[yes|no]               Build mode (default: $(RELEASE))"
	$(Q)echo "  VERBOSE=[yes|no]               Verbose output (default: $(VERBOSE))"
	$(Q)echo "  DOCKER=[yes|no]                Use Docker for building (default: $(DOCKER))"
	$(Q)echo "  NANVIX_TOOLCHAIN=<path>        Nanvix toolchain location (default: $(NANVIX_TOOLCHAIN))"
	$(Q)echo "  NANVIX_RUST_TOOLCHAIN=<name>   Rust toolchain (default: $(NANVIX_RUST_TOOLCHAIN))"

# Builds all artifacts.
all: all-rusty_v8 all-hello_nanvix
	$(Q)echo "✓ All rusty_v8 built successfully!"

# Creates installation directory.
$(INSTALL_DIR):
	$(Q)$(MKDIR) $(INSTALL_DIR)

# Builds example.
all-hello_nanvix:
	$(Q)echo "=== Building hello_nanvix example ==="
	$(Q)$(CARGO_BUILD_CMD) --example hello_nanvix
	$(Q)echo "✓ hello_nanvix build completed successfully!"

# Builds rusty_v8 library for Nanvix
all-rusty_v8:
	$(Q)echo "=== Building rusty_v8 library for Nanvix ==="
	$(Q)$(CARGO_BUILD_CMD)
	$(Q)echo "✓ rusty_v8 library built successfully"

# Installs all artifacts
install: install-rusty_v8 install-hello_nanvix
	$(Q)echo "✓ All artifacts installed under $(INSTALL_DIR)"

# Installs rusty_v8 artifacts to dist directory
install-rusty_v8: all-rusty_v8 $(INSTALL_DIR)
	$(Q)echo "=== Installing rusty_v8 artifacts ==="
	$(Q)$(MKDIR) "$(INSTALL_LIB_DIR)" "$(INSTALL_ETC_DIR)"
	$(Q)echo "Copying static library to $(INSTALL_LIB_DIR)..."
	$(Q)test -f "$(RUSTY_V8_LIB)" || (echo "Error: $(RUSTY_V8_LIB) not found" && exit 1)
	$(Q)$(CP) "$(RUSTY_V8_LIB)" "$(INSTALL_LIB_DIR)/"
	$(Q)echo "Copying binding file to $(INSTALL_ETC_DIR)..."
	$(Q)test -f "$(BINDING_FILE)" || (echo "Error: $(BINDING_FILE) not found" && exit 1)
	$(Q)$(CP) "$(BINDING_FILE)" "$(INSTALL_ETC_DIR)/"
	$(Q)echo "✓ Prebuilt static library created at $(INSTALL_LIB_DIR)/librusty_v8.a"
	$(Q)echo "✓ Binding file created at $(INSTALL_ETC_DIR)/src_binding.rs"

# Installs hello_nanvix example binary
install-hello_nanvix: all-hello_nanvix $(INSTALL_DIR)
	$(Q)echo "=== Installing hello_nanvix example ==="
	$(Q)$(MKDIR) "$(INSTALL_BIN_DIR)"
	$(Q)test -f "$(HELLO_NANVIX_BINARY)" || (echo "Error: $(HELLO_NANVIX_BINARY) not found" && exit 1)
	$(Q)$(CP) "$(HELLO_NANVIX_BINARY)" "$(INSTALL_BIN_DIR)/"
	$(Q)echo "✓ hello_nanvix installed at $(INSTALL_BIN_DIR)/hello_nanvix"

# Runs hello_nanvix example using run-nanvixd.sh script
run: all-hello_nanvix
	$(Q)echo "=== Running hello_nanvix example ==="
	$(Q)test -f "$(NANVIX_HOME)/etc/scripts/run-nanvixd.sh" || (echo "Error: run-nanvixd.sh not found at $(NANVIX_HOME)/etc/scripts/" && exit 1)
	$(Q)test -f "$(HELLO_NANVIX_BINARY)" || (echo "Error: $(HELLO_NANVIX_BINARY) not found" && exit 1)
	$(Q)cd "$(NANVIX_HOME)" && etc/scripts/run-nanvixd.sh "$(HELLO_NANVIX_BINARY_ABS)"

# Cleans all build artifact.
clean:
	$(Q)echo "=== Cleaning all build artifacts ==="
	$(Q)$(CARGO_CLEAN_CMD)
	$(Q)$(RMDIR) "$(INSTALL_DIR)"
	$(Q)echo "✓ Clean completed successfully!"

# Cleans only rusty_v8 build artifact.
clean-rusty_v8:
	$(Q)echo "=== Cleaning rusty_v8 build artifacts ==="
	$(Q)$(RMDIR) "$(TARGET_DIR)/gn_out"
	$(Q)echo "✓ rusty_v8 artifacts cleaned!"

# Cleans only example artifact.
clean-hello_nanvix:
	$(Q)echo "=== Cleaning hello_nanvix build artifacts ==="
	$(Q)$(RM) "$(HELLO_NANVIX_BINARY)"
	$(Q)echo "✓ hello_nanvix artifacts cleaned!"
