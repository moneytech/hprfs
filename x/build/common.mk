
#
# Define a few useful variables and functions.
#
x_name    := x
x_info     = $(info $(x_name): $1 $2 $3 $4 $5)
x_warning  = $(warning $(x_name): $1 $2 $3 $4 $5)
x_error    = $(error $(x_name): $1 $2 $3 $4 $5)

# -----------------------------------------------------------------------------
# Function : x_log
# Arguments: 1: text to print when X_LOG is defined
# Returns  : None
# Usage    : $(call x_log,<some text>)
# -----------------------------------------------------------------------------
ifdef X_LOG
x_log = $(info $(x_name): $1)
else
x_log :=
endif

#
# Host system auto-detection.
# Determine host system and architecture from the environment
#
HOST_OS := $(strip $(HOST_OS))
ifndef HOST_OS
    # On all modern variants of Windows (including Cygwin and Wine)
    # the OS environment variable is defined to 'Windows_NT'
    #
    # The value of PROCESSOR_ARCHITECTURE will be x86 or AMD64
    #
    ifeq ($(OS),Windows_NT)
        HOST_OS := windows
    else
        # For other systems, use the `uname` output
        UNAME := $(shell uname -s)
        ifneq (,$(findstring Linux,$(UNAME)))
            HOST_OS := linux
        endif
        ifneq (,$(findstring Darwin,$(UNAME)))
            HOST_OS := darwin
        endif
        # We should not be there, but just in case !
        ifneq (,$(findstring CYGWIN,$(UNAME)))
            HOST_OS := windows
        endif
        ifeq ($(HOST_OS),)
            $(call __ndk_info,Unable to determine HOST_OS from uname -s: $(UNAME))
            $(call __ndk_info,Please define HOST_OS in your environment.)
            $(call __ndk_error,Aborting.)
        endif
    endif
    $(call x_log,Host OS was auto-detected: $(HOST_OS))
else
    $(call x_log,Host OS from environment: $(HOST_OS))
endif


ifeq ($(HOST_OS),windows)
# On Windows, defining host-dir-parent is a bit more tricky because the
# GNU Make $(dir ...) function doesn't return an empty string when it
# reaches the top of the directory tree, and we want to enforce this to
# avoid infinite loops.
#
#   $(dir C:)     -> C:       (empty expected)
#   $(dir C:/)    -> C:/      (empty expected)
#   $(dir C:\)    -> C:\      (empty expected)
#   $(dir C:/foo) -> C:/      (correct)
#   $(dir C:\foo) -> C:\      (correct)
#
host-dir-parent = $(strip \
    $(eval __host_dir_node := $(patsubst %/,%,$(subst \,/,$1)))\
    $(eval __host_dir_parent := $(dir $(__host_dir_node)))\
    $(filter-out $1,$(__host_dir_parent))\
    )
else
host-dir-parent = $(patsubst %/,%,$(dir $1))
endif

# For all systems, we will have HOST_OS_BASE defined as
# $(HOST_OS), except on Cygwin where we will have:
#
#  HOST_OS      == cygwin
#  HOST_OS_BASE == windows
#
# Trying to detect that we're running from Cygwin is tricky
# because we can't use $(OSTYPE): It's a Bash shell variable
# that is not exported to sub-processes, and isn't defined by
# other shells (for those with really weird setups).
#
# Instead, we assume that a program named /bin/uname.exe
# that can be invoked and returns a valid value corresponds
# to a Cygwin installation.
#
HOST_OS_BASE := $(HOST_OS)

ifeq ($(HOST_OS),windows)
    ifneq (,$(strip $(wildcard /bin/uname.exe)))
        $(call x_log,Found /bin/uname.exe on Windows host, checking for Cygwin)
        # NOTE: The 2>NUL here is for the case where we're running inside the
        #       native Windows shell. On cygwin, this will create an empty NUL file
        #       that we're going to remove later (see below).
        UNAME := $(shell /bin/uname.exe -s 2>NUL)
        $(call x_log,uname -s returned: $(UNAME))
        ifneq (,$(filter CYGWIN%,$(UNAME)))
            $(call x_log,Cygwin detected: $(shell uname -a))
            HOST_OS := cygwin
            DUMMY := $(shell rm -f NUL) # Cleaning up
        else
            ifneq (,$(filter MINGW32%,$(UNAME)))
                $(call x_log,MSys detected: $(shell uname -a))
                HOST_OS := cygwin
            else
                $(call x_log,Cygwin *not* detected!)
            endif
        endif
    endif
endif

ifneq ($(HOST_OS),$(HOST_OS_BASE))
    $(call x_log, Host operating system detected: $(HOST_OS), base OS: $(HOST_OS_BASE))
else
    $(call x_log, Host operating system detected: $(HOST_OS))
endif

HOST_ARCH := $(strip $(HOST_ARCH))
ifndef HOST_ARCH
    ifeq ($(HOST_OS_BASE),windows)
        HOST_ARCH := $(PROCESSOR_ARCHITECTURE)
        ifeq ($(HOST_ARCH),AMD64)
            HOST_ARCH := x86
        endif
    else # HOST_OS_BASE != windows
        UNAME := $(shell uname -m)
        ifneq (,$(findstring 86,$(UNAME)))
            HOST_ARCH := x86
        endif
        # We should probably should not care at all
        ifneq (,$(findstring Power,$(UNAME)))
            HOST_ARCH := ppc
        endif
        ifeq ($(HOST_ARCH),)
            $(call __ndk_info,Unsupported host architecture: $(UNAME))
            $(call __ndk_error,Aborting)
        endif
    endif # HOST_OS_BASE != windows
    $(call x_log,Host CPU was auto-detected: $(HOST_ARCH))
else
    $(call x_log,Host CPU from environment: $(HOST_ARCH))
endif

HOST_TAG := $(HOST_OS_BASE)-$(HOST_ARCH)

ifeq ($(HOST_OS),windows)
host-mkdir = md $(subst /,\,"$1") >NUL 2>NUL || rem
else
host-mkdir = mkdir -p $1
endif

#
# Find project dir
#
find-project-dir = $(strip $(call find-project-dir-inner,$(abspath $1),$2))

find-project-dir-inner = \
    $(eval __found_project_path := )\
    $(eval __find_project_path := $1)\
    $(eval __find_project_file := $2)\
    $(call find-project-dir-inner-2)\
    $(__found_project_path)

find-project-dir-inner-2 = \
    $(call x_log,Looking for $(__find_project_file) in $(__find_project_path))\
    $(eval __find_project_manifest := $(strip $(wildcard $(__find_project_path)/$(__find_project_file))))\
    $(if $(__find_project_manifest),\
        $(call x_log,    Found it !)\
        $(eval __found_project_path := $(__find_project_path))\
        ,\
        $(eval __find_project_parent := $(call host-dir-parent,$(__find_project_path)))\
        $(if $(__find_project_parent),\
            $(eval __find_project_path := $(__find_project_parent))\
            $(call find-project-dir-inner-2)\
        )\
    )

# -----------------------------------------------------------------------------
# Function : host-path
# Arguments: 1: file path
# Returns  : file path, as understood by the host file system
# Usage    : $(call host-path,<path>)
# Rationale: This function is used to translate Cygwin paths into
#            Cygwin-specific ones. On other platforms, it will just
#            return its argument.
# -----------------------------------------------------------------------------
ifeq ($(HOST_OS),cygwin)
host-path = $(if $(strip $1),$(call cygwin-to-host-path,$1))
else
host-path = $1
endif

# -----------------------------------------------------------------------------
# Function : host-rm
# Arguments: 1: list of files
# Usage    : $(call host-rm,<files>)
# Rationale: This function expands to the host-specific shell command used
#            to remove some files.
# -----------------------------------------------------------------------------
ifeq ($(HOST_OS),windows)
host-rm = \
    $(eval __host_rm_files := $(foreach __host_rm_file,$1,$(subst /,\,$(wildcard $(__host_rm_file)))))\
    $(if $(__host_rm_files),del /f/q $(__host_rm_files) >NUL 2>NUL)
else
host-rm = rm -f $1
endif

# -----------------------------------------------------------------------------
# Function : host-rmdir
# Arguments: 1: list of files or directories
# Usage    : $(call host-rm,<files>)
# Rationale: This function expands to the host-specific shell command used
#            to remove some files _and_ directories.
# -----------------------------------------------------------------------------
ifeq ($(HOST_OS),windows)
host-rmdir = \
    $(eval __host_rmdir_files := $(foreach __host_rmdir_file,$1,$(subst /,\,$(wildcard $(__host_rmdir_file)))))\
    $(if $(__host_rmdir_files),del /f/s/q $(__host_rmdir_files) >NUL 2>NUL)
else
host-rmdir = rm -rf $1
endif

# -----------------------------------------------------------------------------
# Function : host-mkdir
# Arguments: 1: directory path
# Usage    : $(call host-mkdir,<path>
# Rationale: This function expands to the host-specific shell command used
#            to create a path if it doesn't exist.
# -----------------------------------------------------------------------------
ifeq ($(HOST_OS),windows)
host-mkdir = md $(subst /,\,"$1") >NUL 2>NUL || rem
else
host-mkdir = mkdir -p $1
endif

# -----------------------------------------------------------------------------
# Function : host-cp
# Arguments: 1: source file
#            2: target file
# Usage    : $(call host-cp,<src-file>,<dst-file>)
# Rationale: This function expands to the host-specific shell command used
#            to copy a single file
# -----------------------------------------------------------------------------
ifeq ($(HOST_OS),windows)
host-cp = copy /b/y $(subst /,\,"$1" "$2") > NUL
else
host-cp = cp -f $1 $2
endif

# -----------------------------------------------------------------------------
# Function : host-install
# Arguments: 1: source file
#            2: target file
# Usage    : $(call host-install,<src-file>,<dst-file>)
# Rationale: This function expands to the host-specific shell command used
#            to install a file or directory, while preserving its timestamps
#            (if possible).
# -----------------------------------------------------------------------------
ifeq ($(HOST_OS),windows)
host-install = copy /b/y $(subst /,\,"$1" "$2") > NUL
else
host-install = install -p $1 $2
endif

# -----------------------------------------------------------------------------
# Function : host-c-includes
# Arguments: 1: list of file paths (e.g. "foo bar")
# Returns  : list of include compiler options (e.g. "-Ifoo -Ibar")
# Usage    : $(call host-c-includes,<paths>)
# Rationale: This function is used to translate Cygwin paths into
#            Cygwin-specific ones. On other platforms, it will just
#            return its argument.
# -----------------------------------------------------------------------------
ifeq ($(HOST_OS),cygwin)
host-c-includes = $(patsubst %,-I%,$(call host-path,$1))
else
host-c-includes = $(1:%=-I%)
endif

# -----------------------------------------------------------------------------
# Function : copy-if-differ
# Arguments: 1: source file
#            2: destination file
# Usage    : $(call copy-if-differ,<src-file>,<dst-file>)
# Rationale: This function copy source file to destination file if contents are
#            different.
# -----------------------------------------------------------------------------
ifeq ($(HOST_OS),windows)
copy-if-differ = $(HOST_CMP) -s $1 $2 > NUL || copy /b/y $(subst /,\,"$1" "$2") > NUL
else
copy-if-differ = $(HOST_CMP) -s $1 $2 > /dev/null 2>&1 || cp -f $1 $2
endif

# -----------------------------------------------------------------------------
# Function : generate-dir
# Arguments: 1: directory path
# Returns  : Generate a rule, but not dependency, to create a directory with
#            host-mkdir.
# Usage    : $(call generate-dir,<path>)
# -----------------------------------------------------------------------------
define ev-generate-dir
x_dir := $1
ifeq (,$$(x_dir_flag__$1))
x_dir_flag__$1 := true
$1:
	@$$(call host-mkdir,$$@)
endif
endef

generate-dir = $(eval $(call ev-generate-dir,$1))

# cmd-convert-deps
#
# On Cygwin, we need to convert the .d dependency file generated by
# the gcc toolchain by transforming any Windows paths inside it into
# Cygwin paths that GNU Make can understand (i.e. C:/Foo => /cygdrive/c/Foo)
#
# To do that, we will force the compiler to write the dependency file to
# <foo>.d.org, which will will later convert through a clever sed script
# that is auto-generated by our build system.
#
# The script is invoked with:
#
#    $(NDK_DEPENDENCIES_CONVERTER) foo.d
#
# It will look if foo.d.org exists, and if so, process it
# to generate foo.d, then remove the original foo.d.org.
#
# On other systems, we simply tell the compiler to write to the .d file directly.
#
# NOTE: In certain cases, no dependency file will be generated by the
#       compiler (e.g. when compiling an assembly file as foo.s)
#
# convert-deps is used to compute the name of the compiler-generated dependency file
# cmd-convert-deps is a command used to convert it to a Cygwin-specific path
#
ifeq ($(HOST_OS),cygwin)
convert-deps = $1.org
cmd-convert-deps = && $(NDK_DEPENDENCIES_CONVERTER) $1
else
convert-deps = $1
cmd-convert-deps = 
endif

# -----------------------------------------------------------------------------
# Function : generate-file-dir
# Arguments: 1: file path
# Returns  : Generate a dependency and a rule to ensure that the parent
#            directory of the input file path will be created before it.
#            This is used to enforce a call to host-mkdir.
# Usage    : $(call generate-file-dir,<file>)
# Rationale: Many object files will be stored in the same output directory.
#            Introducing a dependency on the latter avoids calling mkdir -p
#            for every one of them.
#
# -----------------------------------------------------------------------------

define ev-generate-file-dir
x_file_dir := $(call parent-dir,$1)
$$(call generate-dir,$$(x_file_dir))
$1: $$(x_file_dir)
endef

generate-file-dir = $(eval $(call ev-generate-file-dir,$1))

# This assumes that many variables have been pre-defined:
# _SRC: source file
# _OBJ: destination file
# _CC: 'compiler' command
# _FLAGS: 'compiler' flags
# _TEXT: Display text (e.g. "Compile++ thumb", must be EXACTLY 15 chars long)
#
define ev-build-file
$$(_OBJ): PRIVATE_SRC      := $$(_SRC)
$$(_OBJ): PRIVATE_OBJ      := $$(_OBJ)
$$(_OBJ): PRIVATE_DEPS     := $$(call host-path,$$(_OBJ).d)
$$(_OBJ): PRIVATE_MODULE   := $$(LOCAL_MODULE)
$$(_OBJ): PRIVATE_TEXT     := "$$(_TEXT)"
$$(_OBJ): PRIVATE_CC       := $$(_CC)
$$(_OBJ): PRIVATE_CFLAGS   := $$(_FLAGS)

ifeq ($$(LOCAL_SHORT_COMMANDS),true)
_OPTIONS_LISTFILE := $$(_OBJ).cflags
$$(_OBJ): $$(call generate-list-file,$$(_FLAGS),$$(_OPTIONS_LISTFILE))
$$(_OBJ): PRIVATE_CFLAGS := @$$(call host-path,$$(_OPTIONS_LISTFILE))
$$(_OBJ): $$(_OPTIONS_LISTFILE)
endif

$$(call generate-file-dir,$$(_OBJ))

$$(_OBJ): $$(_SRC) $$(LOCAL_MAKEFILE) $$(X_MK) $$(X_DEPENDENCIES_CONVERTER)
	@$$(HOST_ECHO) "$$(PRIVATE_TEXT)  : $$(PRIVATE_MODULE) <= $$(notdir $$(PRIVATE_SRC))"
	$$(hide) $$(PRIVATE_CC) -MMD -MP -MF $$(call convert-deps,$$(PRIVATE_DEPS)) $$(PRIVATE_CFLAGS) $$(call host-path,$$(PRIVATE_SRC)) -o $$(call host-path,$$(PRIVATE_OBJ)) \
	$$(call cmd-convert-deps,$$(PRIVATE_DEPS))
endef

# Function ev-build-source-file
# This assumes the same things than ev-build-file, but will handle
# the definition of LOCAL_FILTER_ASM as well.
define ev-build-source-file
LOCAL_DEPENDENCY_DIRS += $$(dir $$(_OBJ))
ifndef LOCAL_FILTER_ASM
  # Trivial case: Directly generate an object file
  $$(eval $$(call ev-build-file))
else
  # This is where things get hairy, we first transform
  # the source into an assembler file, send it to the
  # filter, then generate a final object file from it.
  #

  # First, remember the original settings and compute
  # the location of our temporary files.
  #
  _ORG_SRC := $$(_SRC)
  _ORG_OBJ := $$(_OBJ)
  _ORG_FLAGS := $$(_FLAGS)
  _ORG_TEXT  := $$(_TEXT)

  _OBJ_ASM_ORIGINAL := $$(patsubst %.o,%.s,$$(_ORG_OBJ))
  _OBJ_ASM_FILTERED := $$(patsubst %.o,%.filtered.s,$$(_ORG_OBJ))

  # If the source file is a plain assembler file, we're going to
  # use it directly in our filter.
  ifneq (,$$(filter %.s,$$(_SRC)))
    _OBJ_ASM_ORIGINAL := $$(_SRC)
  endif

  #$$(info SRC=$$(_SRC) OBJ=$$(_OBJ) OBJ_ORIGINAL=$$(_OBJ_ASM_ORIGINAL) OBJ_FILTERED=$$(_OBJ_ASM_FILTERED))

  # We need to transform the source into an assembly file, instead of
  # an object. The proper way to do that depends on the file extension.
  #
  # For C and C++ source files, simply replace the -c by an -S in the
  # compilation command (this forces the compiler to generate an
  # assembly file).
  #
  # For assembler templates (which end in .S), replace the -c with -E
  # to send it to the preprocessor instead.
  #
  # Don't do anything for plain assembly files (which end in .s)
  #
  ifeq (,$$(filter %.s,$$(_SRC)))
    _OBJ   := $$(_OBJ_ASM_ORIGINAL)
    ifneq (,$$(filter %.S,$$(_SRC)))
      _FLAGS := $$(patsubst -c,-E,$$(_ORG_FLAGS))
    else
      _FLAGS := $$(patsubst -c,-S,$$(_ORG_FLAGS))
    endif
    $$(eval $$(call ev-build-file))
  endif

  # Next, process the assembly file with the filter
  $$(_OBJ_ASM_FILTERED): PRIVATE_SRC    := $$(_OBJ_ASM_ORIGINAL)
  $$(_OBJ_ASM_FILTERED): PRIVATE_DST    := $$(_OBJ_ASM_FILTERED)
  $$(_OBJ_ASM_FILTERED): PRIVATE_FILTER := $$(LOCAL_FILTER_ASM)
  $$(_OBJ_ASM_FILTERED): PRIVATE_MODULE := $$(LOCAL_MODULE)
  $$(_OBJ_ASM_FILTERED): $$(_OBJ_ASM_ORIGINAL)
	@$$(HOST_ECHO) "AsmFilter      : $$(PRIVATE_MODULE) <= $$(notdir $$(PRIVATE_SRC))"
	$$(hide) $$(PRIVATE_FILTER) $$(PRIVATE_SRC) $$(PRIVATE_DST)

  # Then, generate the final object, we need to keep assembler-specific
  # flags which look like -Wa,<option>:
  _SRC   := $$(_OBJ_ASM_FILTERED)
  _OBJ   := $$(_ORG_OBJ)
  _FLAGS := $$(filter -Wa%,$$(_ORG_FLAGS)) -c
  _TEXT  := "Assembly     "
  $$(eval $$(call ev-build-file))
endif
endef

# -----------------------------------------------------------------------------
# Template  : ev-compile-c-source
# Arguments : 1: single C source file name (relative to LOCAL_PATH)
#             2: target object file (without path)
# Returns   : None
# Usage     : $(eval $(call ev-compile-c-source,<srcfile>,<objfile>)
# Rationale : Internal template evaluated by compile-c-source and
#             compile-s-source
# -----------------------------------------------------------------------------
define  ev-compile-c-source
_SRC:=$$(LOCAL_PATH)/$(1)
_OBJ:=$$(LOCAL_OBJS_DIR)/$(2)

_FLAGS := $$($$(my)CFLAGS) \
          $$(call get-src-file-target-cflags,$(1)) \
          $$(call host-c-includes,$$(LOCAL_C_INCLUDES) $$(LOCAL_PATH)) \
          $$(LOCAL_CFLAGS) \
          $$(NDK_APP_CFLAGS) \
          $$(call host-c-includes,$$($(my)C_INCLUDES)) \
          -c

_TEXT := "Compile $$(call get-src-file-text,$1)"
_CC   := $$(NDK_CCACHE) $$(TARGET_CC)

$$(eval $$(call ev-build-source-file))
endef

# -----------------------------------------------------------------------------
# Function  : compile-c-source
# Arguments : 1: single C source file name (relative to LOCAL_PATH)
#             2: object file
# Returns   : None
# Usage     : $(call compile-c-source,<srcfile>,<objfile>)
# Rationale : Setup everything required to build a single C source file
# -----------------------------------------------------------------------------
compile-c-source = $(eval $(call ev-compile-c-source,$1,$2))
