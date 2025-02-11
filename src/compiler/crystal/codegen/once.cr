require "./codegen"

class Crystal::CodeGenVisitor
  ONCE_STATE = "~ONCE_STATE"

  def once_init
    if once_init_fun = typed_fun?(@main_mod, ONCE_INIT)
      # legacy (kept for backward compatibility): the compiler must save the
      # state returned by __crystal_once_init
      once_init_fun = check_main_fun ONCE_INIT, once_init_fun

      once_state_global = @main_mod.globals.add(once_init_fun.type.return_type, ONCE_STATE)
      once_state_global.linkage = LLVM::Linkage::Internal if @single_module
      once_state_global.initializer = once_init_fun.type.return_type.null

      state = call once_init_fun
      store state, once_state_global
    end
  end

  def run_once(flag, func : LLVMTypedFunction)
    once_fun = main_fun(ONCE)
    once_fun_params = once_fun.func.params
    once_initializer_type = once_fun_params.last.type # must be Void*
    initializer = pointer_cast(func.func.to_value, once_initializer_type)

    if once_fun_params.size == 2
      args = [flag, initializer]
    else
      # legacy (kept for backward compatibility): the compiler must pass the
      # state returned by __crystal_once_init to __crystal_once as the first
      # argument
      once_init_fun = main_fun(ONCE_INIT)
      once_state_type = once_init_fun.type.return_type # must be Void*

      once_state_global = @llvm_mod.globals[ONCE_STATE]? || begin
        global = @llvm_mod.globals.add(once_state_type, ONCE_STATE)
        global.linkage = LLVM::Linkage::External
        global
      end

      state = load(once_state_type, once_state_global)
      args = [state, flag, initializer]
    end

    call once_fun, args
  end
end
