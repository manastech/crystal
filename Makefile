all:

-include Makefile.local # for optional local options e.g. threads

# Recipes for this Makefile

## Build the compiler
##   $ make
## Build the compiler with progress output
##   $ make progress=1
## Clean up built files then build the compiler
##   $ make clean crystal
## Build the compiler in release mode
##   $ make crystal release=1 interpreter=1
## Run tests
##   $ make test
## Run stdlib tests
##   $ make std_spec
## Run compiler tests
##   $ make compiler_spec
## Run generators (Unicode, SSL config, ...)
##   $ make -B generate_data

CRYSTAL ?= crystal## which previous crystal compiler use
LLVM_CONFIG ?=     ## llvm-config command path to use

release ?=        ## Compile in release mode
stats ?=          ## Enable statistics output
progress ?=       ## Enable progress output
threads ?=        ## Maximum number of threads to use
debug ?=          ## Add symbolic debug info
verbose ?=        ## Run specs in verbose mode
junit_output ?=   ## Path to output junit results
static ?=         ## Enable static linking
target ?=         ## Cross-compilation target
interpreter ?=    ## Enable interpreter feature
check ?=          ## Enable only check when running format
order ?=random    ## Enable order for spec execution (values: "default" | "random" | seed number)
deref_symlinks ?= ## Deference symbolic links for `make install`

O := .build
SOURCES := $(shell find src -name '*.cr')
SPEC_SOURCES := $(shell find spec -name '*.cr')
override FLAGS += -D strict_multi_assign -D preview_overload_order $(if $(release),--release )$(if $(stats),--stats )$(if $(progress),--progress )$(if $(threads),--threads $(threads) )$(if $(debug),-d )$(if $(static),--static )$(if $(LDFLAGS),--link-flags="$(LDFLAGS)" )$(if $(target),--cross-compile --target $(target) )$(if $(interpreter),,-Dwithout_interpreter )
SPEC_WARNINGS_OFF := --exclude-warnings spec/std --exclude-warnings spec/compiler --exclude-warnings spec/primitives
override SPEC_FLAGS += $(if $(verbose),-v )$(if $(junit_output),--junit_output $(junit_output) )$(if $(order),--order=$(order) )
CRYSTAL_CONFIG_LIBRARY_PATH := '$$ORIGIN/../lib/crystal'
CRYSTAL_CONFIG_BUILD_COMMIT ?= $(shell git rev-parse --short HEAD 2> /dev/null)
CRYSTAL_CONFIG_PATH := '$$ORIGIN/../share/crystal/src'
CRYSTAL_VERSION ?= $(shell cat src/VERSION)
SOURCE_DATE_EPOCH ?= $(shell (cat src/SOURCE_DATE_EPOCH || (git show -s --format=%ct HEAD || stat -c "%Y" Makefile || stat -f "%m" Makefile)) 2> /dev/null)
check_lld := command -v ld.lld >/dev/null && case "$$(uname -s)" in MINGW32*|MINGW64*|Linux) echo 1;; esac
ifeq ($(shell $(check_lld)),1)
  EXPORT_CC ?= CC="$(CC) -fuse-ld=lld"
endif
override EXPORTS += \
  CRYSTAL_CONFIG_BUILD_COMMIT="$(CRYSTAL_CONFIG_BUILD_COMMIT)" \
	CRYSTAL_CONFIG_PATH=$(CRYSTAL_CONFIG_PATH) \
	SOURCE_DATE_EPOCH="$(SOURCE_DATE_EPOCH)"
override EXPORTS_BUILD += \
	$(EXPORT_CC) \
	CRYSTAL_CONFIG_LIBRARY_PATH=$(CRYSTAL_CONFIG_LIBRARY_PATH)
SHELL = sh
LLVM_CONFIG := $(shell src/llvm/ext/find-llvm-config)
LLVM_VERSION := $(if $(LLVM_CONFIG),$(shell "$(LLVM_CONFIG)" --version 2> /dev/null))
LLVM_EXT_DIR = src/llvm/ext
LLVM_EXT_OBJ = $(LLVM_EXT_DIR)/llvm_ext.o
CXXFLAGS += $(if $(debug),-g -O0)

# MSYS2 support (native Windows should use `Makefile.win` instead)
ifeq ($(OS),Windows_NT)
  EXE := .exe
  WINDOWS := 1
else
  EXE :=
  WINDOWS :=
endif
CRYSTAL_BIN := crystal$(EXE)

DESTDIR ?=
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
MANDIR ?= $(DATADIR)/man
LIBDIR ?= $(PREFIX)/lib
DATADIR ?= $(PREFIX)/share
INSTALL ?= /usr/bin/install

ifeq ($(or $(TERM),$(TERM),dumb),dumb)
  colorize = $(shell printf "%s" "$1" >&2)
else
  colorize = $(shell printf "\033[33m%s\033[0m\n" "$1" >&2)
endif

DEPS = $(LLVM_EXT_OBJ)
ifneq ($(LLVM_VERSION),)
  ifeq ($(shell test $(firstword $(subst ., ,$(LLVM_VERSION))) -ge 18; echo $$?),0)
    DEPS =
  endif
endif

check_llvm_config = $(eval \
	check_llvm_config := $(if $(LLVM_VERSION),\
	  $(call colorize,Using $(LLVM_CONFIG) [version=$(LLVM_VERSION)]),\
	  $(error "Could not locate compatible llvm-config, make sure it is installed and in your PATH, or set LLVM_CONFIG. Compatible versions: $(shell cat src/llvm/ext/llvm-versions.txt)))\
	)

.PHONY: all
all: crystal ## Build all files (currently crystal only) [default]

.PHONY: test
test: spec ## Run tests

.PHONY: spec
spec: std_spec primitives_spec compiler_spec

.PHONY: std_spec
std_spec: $(O)/std_spec$(EXE) ## Run standard library specs
	$(O)/std_spec$(EXE) $(SPEC_FLAGS)

.PHONY: compiler_spec
compiler_spec: $(O)/compiler_spec$(EXE) ## Run compiler specs
	$(O)/compiler_spec$(EXE) $(SPEC_FLAGS)

.PHONY: primitives_spec
primitives_spec: $(O)/primitives_spec$(EXE) ## Run primitives specs
	$(O)/primitives_spec$(EXE) $(SPEC_FLAGS)

.PHONY: interpreter_spec
interpreter_spec: $(O)/interpreter_spec$(EXE) ## Run interpreter specs
	$(O)/interpreter_spec$(EXE) $(SPEC_FLAGS)

.PHONY: smoke_test
smoke_test: ## Build specs as a smoke test
smoke_test: $(O)/std_spec$(EXE) $(O)/compiler_spec$(EXE) $(O)/$(CRYSTAL_BIN)

.PHONY: all_spec
all_spec: $(O)/all_spec$(EXE) ## Run all specs (note: this builds a huge program; `test` recipe builds individual binaries and is recommended for reduced resource usage)
	$(O)/all_spec$(EXE) $(SPEC_FLAGS)

.PHONY: samples
samples: ## Build example programs
	$(MAKE) -C samples

.PHONY: docs
docs: ## Generate standard library documentation
	$(call check_llvm_config)
	./bin/crystal docs src/docs_main.cr $(DOCS_OPTIONS) --project-name=Crystal --project-version=$(CRYSTAL_VERSION) --source-refname=$(CRYSTAL_CONFIG_BUILD_COMMIT)
	cp -R -P -p doc/ docs/

.PHONY: crystal
crystal: $(O)/$(CRYSTAL_BIN) ## Build the compiler

.PHONY: deps llvm_ext
deps: $(DEPS) ## Build dependencies
llvm_ext: $(LLVM_EXT_OBJ)

.PHONY: format
format: ## Format sources
	./bin/crystal tool format$(if $(check), --check) src spec samples scripts

.PHONY: generate_data
generate_data: ## Run generator scripts for Unicode, SSL config, ...
	$(MAKE) -B -f scripts/generate_data.mk

.PHONY: install
install: $(O)/$(CRYSTAL_BIN) man/crystal.1.gz ## Install the compiler at DESTDIR
	$(INSTALL) -d -m 0755 "$(DESTDIR)$(BINDIR)/"
	$(INSTALL) -m 0755 "$(O)/$(CRYSTAL_BIN)" "$(DESTDIR)$(BINDIR)/$(CRYSTAL_BIN)"

	$(INSTALL) -d -m 0755 $(DESTDIR)$(DATADIR)/crystal
	cp -R -p $(if $(deref_symlinks),-L,-P) src "$(DESTDIR)$(DATADIR)/crystal/src"
	rm -rf "$(DESTDIR)$(DATADIR)/crystal/$(LLVM_EXT_OBJ)" # Don't install llvm_ext.o

	$(INSTALL) -d -m 0755 "$(DESTDIR)$(MANDIR)/man1/"
	$(INSTALL) -m 644 man/crystal.1.gz "$(DESTDIR)$(MANDIR)/man1/crystal.1.gz"
	$(INSTALL) -d -m 0755 "$(DESTDIR)$(DATADIR)/licenses/crystal/"
	$(INSTALL) -m 644 LICENSE "$(DESTDIR)$(DATADIR)/licenses/crystal/LICENSE"

	$(INSTALL) -d -m 0755 "$(DESTDIR)$(DATADIR)/bash-completion/completions/"
	$(INSTALL) -m 644 etc/completion.bash "$(DESTDIR)$(DATADIR)/bash-completion/completions/crystal"
	$(INSTALL) -d -m 0755 "$(DESTDIR)$(DATADIR)/zsh/site-functions/"
	$(INSTALL) -m 644 etc/completion.zsh "$(DESTDIR)$(DATADIR)/zsh/site-functions/_crystal"
	$(INSTALL) -d -m 0755 "$(DESTDIR)$(DATADIR)/fish/vendor_completions.d/"
	$(INSTALL) -m 644 etc/completion.fish "$(DESTDIR)$(DATADIR)/fish/vendor_completions.d/crystal.fish"

ifeq ($(WINDOWS),1)
.PHONY: install_dlls
install_dlls: $(O)/$(CRYSTAL_BIN) ## Install the compiler's dependent DLLs at DESTDIR (Windows only)
	$(INSTALL) -d -m 0755 "$(DESTDIR)$(BINDIR)/"
	@ldd $(O)/$(CRYSTAL_BIN) | grep -iv ' => /c/windows/system32' | sed 's/.* => //; s/ (.*//' | xargs -t -i $(INSTALL) -m 0755 '{}' "$(DESTDIR)$(BINDIR)/"
endif

.PHONY: uninstall
uninstall: ## Uninstall the compiler from DESTDIR
	rm -f "$(DESTDIR)$(BINDIR)/$(CRYSTAL_BIN)"

	rm -rf "$(DESTDIR)$(DATADIR)/crystal/src"

	rm -f "$(DESTDIR)$(MANDIR)/man1/crystal.1.gz"
	rm -f "$(DESTDIR)$(DATADIR)/licenses/crystal/LICENSE"

	rm -f "$(DESTDIR)$(DATADIR)/bash-completion/completions/crystal"
	rm -f "$(DESTDIR)$(DATADIR)/zsh/site-functions/_crystal"
	rm -f "$(DESTDIR)$(DATADIR)/fish/vendor_completions.d/crystal.fish"

.PHONY: install_docs
install_docs: docs ## Install docs at DESTDIR
	$(INSTALL) -d -m 0755 $(DESTDIR)$(DATADIR)

	cp -R -P -p docs "$(DESTDIR)$(DATADIR)/docs"
	cp -R -P -p samples "$(DESTDIR)$(DATADIR)/examples"

.PHONY: uninstall_docs
uninstall_docs: ## Uninstall docs from DESTDIR
	rm -rf "$(DESTDIR)$(DATADIR)/docs"
	rm -rf "$(DESTDIR)$(DATADIR)/examples"

$(O)/all_spec$(EXE): $(DEPS) $(SOURCES) $(SPEC_SOURCES)
	$(call check_llvm_config)
	@mkdir -p $(O)
	$(EXPORT_CC) $(EXPORTS) ./bin/crystal build $(FLAGS) $(SPEC_WARNINGS_OFF) -o $@ spec/all_spec.cr

$(O)/std_spec$(EXE): $(DEPS) $(SOURCES) $(SPEC_SOURCES)
	$(call check_llvm_config)
	@mkdir -p $(O)
	$(EXPORT_CC) ./bin/crystal build $(FLAGS) $(SPEC_WARNINGS_OFF) -o $@ spec/std_spec.cr

$(O)/compiler_spec$(EXE): $(DEPS) $(SOURCES) $(SPEC_SOURCES)
	$(call check_llvm_config)
	@mkdir -p $(O)
	$(EXPORT_CC) $(EXPORTS) ./bin/crystal build $(FLAGS) $(SPEC_WARNINGS_OFF) -o $@ spec/compiler_spec.cr --release

$(O)/primitives_spec$(EXE): $(O)/$(CRYSTAL_BIN) $(DEPS) $(SOURCES) $(SPEC_SOURCES)
	@mkdir -p $(O)
	$(EXPORT_CC) ./bin/crystal build $(FLAGS) $(SPEC_WARNINGS_OFF) -o $@ spec/primitives_spec.cr

$(O)/interpreter_spec$(EXE): $(DEPS) $(SOURCES) $(SPEC_SOURCES)
	$(eval interpreter=1)
	@mkdir -p $(O)
	$(EXPORT_CC) ./bin/crystal build $(FLAGS) $(SPEC_WARNINGS_OFF) -o $@ spec/compiler/interpreter_spec.cr

$(O)/$(CRYSTAL_BIN): $(DEPS) $(SOURCES)
	$(call check_llvm_config)
	@mkdir -p $(O)
	@# NOTE: USE_PCRE1 is only used for testing compatibility with legacy environments that don't provide libpcre2.
	@# Newly built compilers should never be distributed with libpcre to ensure syntax consistency.
	$(EXPORTS) $(EXPORTS_BUILD) ./bin/crystal build $(FLAGS) -o $(if $(WINDOWS),$(O)/crystal-next.exe,$@) src/compiler/crystal.cr -D without_openssl -D without_zlib $(if $(USE_PCRE1),-D use_pcre,-D use_pcre2)
	@# NOTE: on MSYS2 it is not possible to overwrite a running program, so the compiler must be first built with
	@# a different filename and then moved to the final destination.
	$(if $(WINDOWS),mv $(O)/crystal-next.exe $@)

$(LLVM_EXT_OBJ): $(LLVM_EXT_DIR)/llvm_ext.cc
	$(call check_llvm_config)
	$(CXX) -c $(CXXFLAGS) -o $@ $< $(shell $(LLVM_CONFIG) --cxxflags)

man/%.gz: man/%
	gzip -c -9 $< > $@

.PHONY: clean
clean: clean_crystal ## Clean up built directories and files
	rm -rf $(LLVM_EXT_OBJ)
	rm -rf man/*.gz

.PHONY: clean_crystal
clean_crystal: ## Clean up crystal built files
	rm -rf $(O)
	rm -rf ./docs

.PHONY: clean_cache
clean_cache: ## Clean up CRYSTAL_CACHE_DIR files
	rm -rf $(shell ./bin/crystal env CRYSTAL_CACHE_DIR)

.PHONY: help
help: ## Show this help
	@echo
	@printf '\033[34mtargets:\033[0m\n'
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) |\
		sort |\
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo
	@printf '\033[34moptional variables:\033[0m\n'
	@grep -hE '^[a-zA-Z_-]+ \?=.*?## .*$$' $(MAKEFILE_LIST) |\
		sort |\
		awk 'BEGIN {FS = " \\?=.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo
	@printf '\033[34mrecipes:\033[0m\n'
	@grep -hE '^##.*$$' $(MAKEFILE_LIST) |\
		awk 'BEGIN {FS = "## "}; /^## [a-zA-Z_-]/ {printf "  \033[36m%s\033[0m\n", $$2}; /^##  / {printf "  %s\n", $$2}'
