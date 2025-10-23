.PHONY: help clean distclean all test

VERSIONS := 2.23 2.24 2.27 2.31 2.32 2.33 2.34 2.35 2.36 2.37 2.38 2.39 2.40 2.41
TECH_BINS := $(patsubst %.c,%,$(wildcard glibc_*/*.c))
BASE_BINS := $(patsubst %.c,%,$(wildcard *.c))
DOWNLOADED := glibc-all-in-one/libs glibc-all-in-one/debs
BINS := $(TECH_BINS) $(BASE_BINS)
ARCH := amd64

# Custom glibc base path
CUSTOM_GLIBC_BASE ?= /home/bogon/workSpaces/glibc-all-in-one/glibc

# Compilation mode control: AIO(glibc-all-in-one)/CUSTOM(custom path)
ifeq ($(H2H_LIBC_MODE),)
H2H_LIBC_MODE := CUSTOM
endif

help:
	@echo 'make help                    - show this message'
	@echo 'make base                    - build all base binaries'
	@echo 'make <version>               - build techniques for specific version. e.g. `make v2.39`'
	@echo 'make clean                   - remove all built binaries'
	@echo 'make distclean               - remove all built binaries and downloaded libcs'
	@echo 'make all                     - build all binaries'
	@echo 'make test version=<version>  - test techniques for specific version. e.g. `make test version=2.39`'
	@echo ''
	@echo 'Libc configuration options (via H2H_LIBC_MODE environment variable):'
	@echo '  CUSTOM mode (default): use custom path libc, make H2H_LIBC_MODE=CUSTOM v2.23'
	@echo '  AIO mode: use glibc-all-in-one libraries, make H2H_LIBC_MODE=AIO v2.23'

CFLAGS += -std=c99 -g -Wno-unused-result -Wno-free-nonheap-object
LDLIBS += -ldl

base: $(BASE_BINS)

# Initialize glibc-all-in-one
libc_ready:
	git submodule update --init --recursive
	cd glibc-all-in-one && ./update_list

# Populate the download_glibc_<version> rules
$(addprefix download_glibc_, $(VERSIONS)): libc_ready
	@echo $@
	version=$(patsubst download_glibc_%,%,$@); \
	libc=$$(cat glibc-all-in-one/list | grep "$$version" | grep "$(ARCH)" | head -n 1); \
	old_libc=$$(cat glibc-all-in-one/old_list | grep "$$version" | grep "$(ARCH)" | head -n 1); \
	if [ -z $$libc ]; then libc=$$old_libc; script="download_old"; else libc=$$libc; script="download"; fi; \
	cd glibc-all-in-one; \
	rm -rf libs/$$libc; \
	./$$script $$libc

# Only add download_glibc_ dependency when in AIO mode
ifeq ($(H2H_LIBC_MODE),CUSTOM)
$(foreach version,$(VERSIONS),$(eval v$(version): $(patsubst %.c,%,$(wildcard glibc_$(version)/*.c))))
else
$(foreach version,$(VERSIONS),$(eval v$(version): download_glibc_$(version) $(patsubst %.c,%,$(wildcard glibc_$(version)/*.c)) ))
endif

%: %.c
	version=$(word 1, $(subst /, ,$(patsubst glibc_%,%,$@))); \
	if [ "$(H2H_LIBC_MODE)" = "CUSTOM" ]; then \
		GLIBC_PATH="$(CUSTOM_GLIBC_BASE)/$$version/$(ARCH)/lib"; \
		if [ -d "$$GLIBC_PATH" ]; then \
			echo "Building with custom glibc: $@ (path: $$GLIBC_PATH)"; \
			$(CC) $(CFLAGS) $(DIR_CFLAGS_$(@D)) $^ -o $@ $(LDLIBS) \
			-Xlinker -rpath="$$GLIBC_PATH" \
			-Xlinker -I"$$GLIBC_PATH/ld-linux-x86-64.so.2" \
			-Xlinker "$$GLIBC_PATH/libc.so.6" \
			-Xlinker "$$GLIBC_PATH/libdl.so.2"; \
		else \
			echo "Error: Custom glibc path $$GLIBC_PATH not found"; \
			echo "Please ensure the glibc is installed at the correct path or switch to AIO mode"; \
			exit 1; \
		fi; \
	else \
		GLIBC_AIO_PATH=$$(realpath glibc-all-in-one/libs/$$version* 2>/dev/null); \
		if [ -n "$$GLIBC_AIO_PATH" ] && [ -f "$$GLIBC_AIO_PATH/ld-linux-x86-64.so.2" ]; then \
			echo "Building with glibc-all-in-one: $@ (path: $$GLIBC_AIO_PATH)"; \
			$(CC) $(CFLAGS) $(DIR_CFLAGS_$(@D)) $^ -o $@ $(LDLIBS) \
			-Xlinker -rpath="$$GLIBC_AIO_PATH" \
			-Xlinker -I"$$GLIBC_AIO_PATH/ld-linux-x86-64.so.2" \
			-Xlinker "$$GLIBC_AIO_PATH/libc.so.6" \
			-Xlinker "$$GLIBC_AIO_PATH/libdl.so.2"; \
		else \
			echo "Error: glibc-all-in-one path for version $$version not found or missing library files"; \
			echo "Please run 'make download_glibc_$$version' first and ensure libraries exist"; \
			exit 1; \
		fi; \
	fi

all: $(BINS)

clean:
	@rm -f $(BINS)
	@echo "All built binaries have been removed."

distclean:
	@rm -f $(BINS)
	@rm -rf $(DOWNLOADED)
	@echo "All built binaries and downloaded libcs have been removed."

define test_poc =
echo "Testing $(poc)"
for i in $$(seq 0 20);\
do\
	LIBC_FATAL_STDERR_=1 $(poc) 1>/dev/null 2>&1 0>&1;\
	if [ "$$?" = "0" ]; then break; fi;\
	if [ "$$i" = "20" ]; then exit 1; fi;\
done
echo "success"
endef

test: v$(version)
	@$(foreach poc,$(patsubst %.c,%,$(wildcard glibc_$(version)/*.c)),$(call test_poc,$(poc));)
