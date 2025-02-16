# Upgrading

This guide provides instructions for upgrading Crystal from one release to the next.
Upgrades must be run sequentially, meaning you should not skip minor/major releases while upgrading.

Crystal commits to a backwards-compatibility guarantee that code should continue
to work with all future minor releases of the same major release series.

Still, even bug fixes introduce changes that may break existing code in some edge cases.
We're only listing the most relevant changes here that could have a relevant impact.

The [changelog](./CHANGELOG.md) contains more information about all changes in
a specific release.

## Crystal 1.14

* `Int128` and `UInt128`'s alignment is now 16 bytes instead of 8 bytes for all
  x86-64 targets, regardless of the compiler's LLVM version. This may affect the
  layout of lib and extern structs in subtle ways.

## Crystal 1.13

* `CRYSTAL_LIBRARY_RPATH` and the `preview_win32_delay_load` feature flag have
  been removed. Individual DLLs can be explicitly delay-loaded with the MSVC
  toolchain by using `/DELAYLOAD` as a linker flag. Similarly RPATH can be added
  with GCC or Clang toolchains by adding `-Wl,-rpath`.

## Crystal 1.9

* The implementation of the comparison operator `#<=>` between `Big*` (`BigDecimal`,
  `BigFloat`, `BigInt`, `BigRational`) and `Float` (`Float32`, `Float64`) number types
  is now nilable. When invoking these comparisons, `Nil` values must be handled.
