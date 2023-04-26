require "./lib_wasi"
require "crystal/asyncify"

# This file serve as the entrypoint for WebAssembly applications compliant to the WASI spec.
# See https://github.com/WebAssembly/WASI/blob/snapshot-01/design/application-abi.md.

lib LibC
  # `__wasm_call_ctors` and `__wasm_call_dtors` are generated by the WebAssembly linker and they execute
  # functions marked with `attribute(constructor)` or `attribute(destructor)`, commonly used for global
  # initialization before/after main. LibC has constructor functions, for example.
  fun __wasm_call_ctors
  fun __wasm_call_dtors

  # Provided by wasi-libc to obtain argc/argv and call into `__main_argc_argv`.
  fun __main_void : Int32
end

# As part of the WASI Application ABI, a "command" program must export a `_start` function that takes no
# arguments and returns nothing. This function will be called from the environment once and returning from
# it signals the command finished successfully.
# TODO: "reactor" programs must export a `_initialize` function that is called once by the environment at
# load time. After that any other exported function can be called any number of times. These programs remain
# alive and ready until they are unloaded from memory.
fun _start
  LibC.__wasm_call_ctors
  status = LibC.__main_void
  LibC.__wasm_call_dtors
  LibWasi.proc_exit(status) if status != 0
end

# `__main_argc_argv` is called by wasi-libc's `__main_void` with the program arguments.
fun __main_argc_argv(argc : Int32, argv : UInt8**) : Int32
  ret = 0
  Crystal::Asyncify.wrap_main do
    ret = main(argc, argv)
  end
  ret
end
