#!/bin/bash

# This file can be executed from the root of the working copy
#
# $ ./spec/debug/test.sh [lldb|gdb]
#
# The argument selects one of the debuggers, defaulting to LLDB.
#
# It will use the ./spec/debug/driver.cr program to execute
# the files explicitly listed at the end of this file.
#
# Those files have magic comments to build a script for a debugger session
# and a FileCheck file with assertions over that session.
#
# The magic comments interpreted by the driver are:
#
# * `# print: expr`
#   Prints the given expression in the debugger, e.g. a variable.
# * `# check: pattern`
#   Asserts that the debugger output matches the given FileCheck pattern.
# * `# xxx-check: pattern`
#   Like above, but only effective if `xxx` matches the debugger name. Has no
#   effect for the other debuggers.
#
# These comments should then be followed by a call to `debugger` which sets up
# the actual breakpoint.
#
# In ./tmp/debug you can find a dump of the session and the assertion file.

set -euo pipefail

SCRIPT_PATH="$(realpath "$0")"
SCRIPT_ROOT="$(dirname "$SCRIPT_PATH")"

BUILD_DIR=$SCRIPT_ROOT/../../.build
crystal=${CRYSTAL_SPEC_COMPILER_BIN:-$SCRIPT_ROOT/../../bin/crystal}
debugger=${1:-lldb}
driver=$BUILD_DIR/debug_driver
mkdir -p "$BUILD_DIR"
"$crystal" build "$SCRIPT_ROOT"/driver.cr -o "$driver"

$driver "$SCRIPT_ROOT"/top_level.cr "$debugger"
$driver "$SCRIPT_ROOT"/strings.cr "$debugger"
$driver "$SCRIPT_ROOT"/arrays.cr "$debugger"
$driver "$SCRIPT_ROOT"/blocks.cr "$debugger"
$driver "$SCRIPT_ROOT"/large_enums.cr "$debugger"
