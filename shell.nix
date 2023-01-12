# This nix-shell script can be used to get a complete development environment
# for the Crystal compiler.
#
# You can choose which llvm version use and, on Linux, choose to use musl.
#
# $ nix-shell --pure
# $ nix-shell --pure --arg llvm 10
# $ nix-shell --pure --arg llvm 10 --arg musl true
# $ nix-shell --pure --arg llvm 9
# $ nix-shell --pure --arg llvm 9 --argstr system i686-linux
# ...
# $ nix-shell --pure --arg llvm 6
#
# If needed, you can use https://app.cachix.org/cache/crystal-ci to avoid building
# packages that are not available in Nix directly. This is mostly useful for musl.
#
# $ nix-env -iA cachix -f https://cachix.org/api/v1/install
# $ cachix use crystal-ci
# $ nix-shell --pure --arg musl true
#

{llvm ? 11, musl ? false, system ? builtins.currentSystem}:

let
  nixpkgs = import (builtins.fetchTarball {
    name = "nixpkgs-22.05";
    url = "https://github.com/NixOS/nixpkgs/archive/22.05.tar.gz";
    sha256 = "0d643wp3l77hv2pmg2fi7vyxn4rwy0iyr8djcw1h5x72315ck9ik";
  }) {
    inherit system;
  };

  pkgs = if musl then nixpkgs.pkgsMusl else nixpkgs;

  genericBinary = { url, sha256 }:
    pkgs.stdenv.mkDerivation rec {
      name = "crystal-binary";
      src = builtins.fetchTarball { inherit url sha256; };

      # Extract only the compiler binary
      buildCommand = ''
        mkdir -p $out/bin

        # Darwin packages use embedded/bin/crystal
        [ ! -f "${src}/embedded/bin/crystal" ] || cp ${src}/embedded/bin/crystal $out/bin/

        # Linux packages use lib/crystal/bin/crystal
        [ ! -f "${src}/lib/crystal/bin/crystal" ] || cp ${src}/lib/crystal/bin/crystal $out/bin/
      '';
    };

  # Hashes obtained using `nix-prefetch-url --unpack <url>`
  latestCrystalBinary = genericBinary ({
    x86_64-darwin = {
      url = "https://github.com/crystal-lang/crystal/releases/download/1.7.0/crystal-1.7.0-1-darwin-universal.tar.gz";
      sha256 = "sha256:1wpghg24xjr27xqh3q3avpk04fxxm6salar85v672k4s3xf5rjrz";
    };

    aarch64-darwin = {
      url = "https://github.com/crystal-lang/crystal/releases/download/1.7.0/crystal-1.7.0-1-darwin-universal.tar.gz";
      sha256 = "sha256:1wpghg24xjr27xqh3q3avpk04fxxm6salar85v672k4s3xf5rjrz";
    };

    x86_64-linux = {
      url = "https://github.com/crystal-lang/crystal/releases/download/1.7.0/crystal-1.7.0-1-linux-x86_64.tar.gz";
      sha256 = "sha256:1d4wcggd32a3h3f7fzkfwlfanwp9lljmh2x5a9gwdf6lblllmkfy";
    };
  }.${pkgs.stdenv.system});

  pkgconfig = pkgs.pkgconfig;

  llvm_suite = ({
    llvm_14 = {
      llvm = pkgs.llvm_14;
      extra = [ pkgs.lld_14 ]; # lldb marked as broken
    };
    llvm_13 = {
      llvm = pkgs.llvm_13;
      extra = [ pkgs.lld_13 ]; # lldb marked as broken
    };
    llvm_12 = {
      llvm = pkgs.llvm_12;
      extra = [ pkgs.lld_12 pkgs.lldb_12 ];
    };
    llvm_11 = {
      llvm = pkgs.llvm_11;
      extra = [ pkgs.lld_11 pkgs.lldb_11 ];
    };
    llvm_10 = {
      llvm = pkgs.llvm_10;
      extra = [ pkgs.lld_10 pkgs.lldb_10 ];
    };
    llvm_9 = {
      llvm = pkgs.llvm_9;
      extra = [ pkgs.lld_9 ]; # lldb marked as broken
    };
    llvm_8 = {
      llvm = pkgs.llvm_8;
      extra = [ pkgs.lld_8 ]; # lldb marked as broken
    };
    llvm_7 = {
      llvm = pkgs.llvm_7;
      extra = [ pkgs.lld_7 ]; # lldb it fails to compile on Darwin
    };
    llvm_6 = {
      llvm = pkgs.llvm_6;
      extra = [ pkgs.lld_6 ]; # lldb it fails to compile on Darwin
    };
  }."llvm_${toString llvm}");

  boehmgc = pkgs.stdenv.mkDerivation rec {
    pname = "boehm-gc";
    version = "8.2.0";

    src = builtins.fetchTarball {
      url = "https://github.com/ivmai/bdwgc/releases/download/v${version}/gc-${version}.tar.gz";
      sha256 = "0f3m27sfc4wssdvk32vivdg64b04ydw0slxm45zdv23qddrihxq4";
    };

    configureFlags = [
      "--disable-debug"
      "--disable-dependency-tracking"
      "--disable-shared"
      "--enable-large-config"
    ];

    enableParallelBuilding = true;
  };

  stdLibDeps = with pkgs; [
      boehmgc gmp libevent libiconv libxml2 libyaml openssl pcre zlib
    ] ++ lib.optionals stdenv.isDarwin [ libiconv ];

  tools = [ pkgs.hostname pkgs.git llvm_suite.extra ];
in

pkgs.stdenv.mkDerivation rec {
  name = "crystal-dev";

  buildInputs = tools ++ stdLibDeps ++ [
    latestCrystalBinary
    pkgconfig
    llvm_suite.llvm
    pkgs.libffi
  ];

  LLVM_CONFIG = "${llvm_suite.llvm.dev}/bin/llvm-config";

  MACOSX_DEPLOYMENT_TARGET = "10.11";
}
