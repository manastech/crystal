#!/bin/sh

if ! LLVM_CONFIG=$(command -v "$LLVM_CONFIG"); then
  llvm_config_version=$(llvm-config --version 2>/dev/null)
  for version in $(cat "$(dirname $0)/llvm-versions.txt"); do
    LLVM_CONFIG=$(
    ([ "${llvm_config_version#$version}" != "$llvm_config_version" ] && command -v llvm-config) || \
    command -v llvm-config-${version%.*} || \
    command -v llvm-config-$version || \
    command -v llvm-config${version%.*}${version#*.} || \
    command -v llvm-config${version%.*} || \
    command -v llvm-config$version || \
    command -v llvm${version%.*}-config)
    [ "$LLVM_CONFIG" ] && break
  done
fi

if [ "$LLVM_CONFIG" ]; then
  case "$(uname -s)" in
    MINGW32_NT*|MINGW64_NT*)
      printf "%s" "$(cygpath -w "$LLVM_CONFIG")"
      ;;
    *)
      printf "%s" "$LLVM_CONFIG"
      ;;
  esac
else
  printf "Error: Could not find location of llvm-config. Please specify path in environment variable LLVM_CONFIG.\n" >&2
  printf "Supported LLVM versions: $(cat "$(dirname $0)/llvm-versions.txt" | sed 's/\.0//g')\n" >&2
  exit 1
fi
