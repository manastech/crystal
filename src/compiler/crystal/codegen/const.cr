require "./codegen"

# Constants are represented with two LLVM global variables: one has the constant's
# value and the other has a flag that indicates whether the constant was already
# initialized.
#
# When the visitor goes through a `CONST = exp` node (assignment to constant),
# it first checks if the flag is set. If it's not set, it initializes it.
# Otherwise, it does nothing. This is needed because a constant can be read
# before it is declared (hoisting), which is valid because an early pass declares
# constant and the main pass only types them when they are used.
#
# This initialization also detects whether the constant is actually a real constant
# (a number, a string) and then stores that information in the Const type so that
# later reading it is a simple load (doesn't go through the function described below).
#
# When a visitor goes through a `CONST` node (read constant), it first check
# if the flag is set. If it's not set, it initializes it. Then it returns a pointer
# to the global variable. To avoid all this code being generated each time, a function
# is created for each constant and that function is invoked whenever a constant
# need to be read.
#
# In this way we can have main code and constant execute in the order that they
# are defined. Reading a constant before assigning a value to it should be pretty
# rare, but it's still handled here to avoid crashes.
#
# Finally, simple constants like numbers, chars and strings are declared in the
# beginning of the program because they don't involve a complex initialization
# and can be done in any order (they have no side effects).

class Crystal::CodeGenVisitor
  @const_mutex : LLVM::Value?

  # The special constants ARGC_UNSAFE and ARGV_UNSAFE (and others) need to be initialized
  # as soon as the program starts, because we have access to argc and argv
  # in the main function.
  def initialize_predefined_constants
    @program.predefined_constants.each do |const|
      initialize_no_init_flag_const(const)
    end
  end

  def declare_const(const)
    global_name = const.llvm_name
    global = @main_mod.globals[global_name]? ||
             @main_mod.globals.add(@main_llvm_typer.llvm_type(const.value.type), global_name)

    type = const.value.type
    # TODO: LLVM < 9.0.0 has a bug that prevents us from having internal globals of type i128 or u128:
    # https://bugs.llvm.org/show_bug.cgi?id=42932
    # so we just use global in that case.
    {% if compare_versions(Crystal::LLVM_VERSION, "9.0.0") < 0 %}
      if @single_module && !(type.is_a?(IntegerType) && (type.kind.i128? || type.kind.u128?))
        global.linkage = LLVM::Linkage::Internal
      end
    {% else %}
      global.linkage = LLVM::Linkage::Internal if @single_module
    {% end %}

    global
  end

  def declare_const_initialized_flag(const)
    initialized_flag_name = const.initialized_llvm_name
    initialized_flag = @main_mod.globals[initialized_flag_name]?
    unless initialized_flag
      initialized_flag = @main_mod.globals.add(@main_llvm_context.int1, initialized_flag_name)
      initialized_flag.initializer = @main_llvm_context.int1.const_int(0)
      initialized_flag.linkage = LLVM::Linkage::Internal if @single_module
    end
    initialized_flag
  end

  def declare_const_and_initialized_flag(const)
    {declare_const(const), declare_const_initialized_flag(const)}
  end

  def initialize_simple_const(const)
    set_current_debug_location const.locations.try &.first? if @debug.line_numbers?

    global = declare_const(const)
    request_value(const.value)

    const_type = const.value.type
    if const_type.passed_by_value?
      @last = load llvm_type(const_type), @last
    end

    global.initializer = @last
    global.global_constant = true

    if const_type.is_a?(PrimitiveType) || const_type.is_a?(EnumType)
      const.initializer = @last
    end
  end

  def initialize_no_init_flag_const(const)
    global = declare_const(const)

    with_cloned_context do
      # "self" in a constant is the constant's namespace
      context.type = const.namespace

      # Start with fresh variables
      context.vars = LLVMVars.new

      set_current_debug_location const.locations.try &.first? if @debug.line_numbers?

      alloca_vars const.fake_def.try(&.vars), const.fake_def
      request_value(const.value)
    end

    const_type = const.value.type
    if const_type.passed_by_value?
      @last = load llvm_type(const_type), @last
    end

    store @last, global

    global.initializer = @last.type.null

    global
  end

  def initialize_const(const)
    # If the constant wasn't read yet, we can initialize it right now and
    # avoid checking an "initialized" flag every time we read it.
    const.no_init_flag = true unless const.read?

    # Maybe the constant was simple and doesn't need a real initialization
    global, initialized_flag = declare_const_and_initialized_flag(const)
    return global if const.initializer

    init_function_name = "~#{const.initialized_llvm_name}"
    func = typed_fun?(@main_mod, init_function_name) || create_initialize_const_function(init_function_name, const)
    func = check_main_fun init_function_name, func

    set_current_debug_location const.locations.try &.first? if @debug.line_numbers?

    if const.no_init_flag?
      call func
    else
      run_once(initialized_flag, func)
    end
    global
  end

  def create_initialize_const_function(fun_name, const)
    global, initialized_flag = declare_const_and_initialized_flag(const)

    in_main do
      define_main_function(fun_name, ([] of LLVM::Type), llvm_context.void, needs_alloca: true) do |func|
        set_internal_fun_debug_location(func, fun_name, const.locations.try &.first?)

        with_cloned_context do
          # "self" in a constant is the constant's namespace
          context.type = const.namespace

          # Start with fresh variables
          context.vars = LLVMVars.new

          alloca_vars const.fake_def.try(&.vars), const.fake_def

          request_value(const.value)

          const_type = const.value.type
          if const_type.passed_by_value?
            @last = load llvm_type(const_type), @last
          end

          if @last.constant?
            global.initializer = @last
            global.global_constant = true

            if const_type.is_a?(PrimitiveType) || const_type.is_a?(EnumType)
              const.initializer = @last
            end
          else
            global.initializer = llvm_type(const_type).null
            unless const_type.nil_type? || const_type.void?
              store @last, global
            end
          end

          ret
        end
      end
    end
  end

  def read_const(const, node)
    # We inline constants. Otherwise we use an LLVM const global.
    @last =
      case value = const.compile_time_value
      when Bool    then int1(value ? 1 : 0)
      when Char    then int32(value.ord)
      when Int8    then int8(value)
      when Int16   then int16(value)
      when Int32   then int32(value)
      when Int64   then int64(value)
      when Int128  then int128(value)
      when UInt8   then int8(value)
      when UInt16  then int16(value)
      when UInt32  then int32(value)
      when UInt64  then int64(value)
      when UInt128 then int128(value)
      else
        set_current_debug_location node if @debug.line_numbers?
        last = read_const_pointer(const)
        to_lhs last, const.value.type
      end
  end

  def read_const_pointer(const)
    const.read = true

    if !const.needs_init_flag?
      global_name = const.llvm_name
      global = declare_const(const)

      if @llvm_mod != @main_mod
        global = @llvm_mod.globals[global_name]?
        global ||= @llvm_mod.globals.add(llvm_type(const.value.type), global_name)
      end

      return global
    end

    read_function_name = "~#{const.llvm_name}:const_read"
    func = typed_fun?(@main_mod, read_function_name) || create_read_const_function(read_function_name, const)
    func = check_main_fun read_function_name, func
    call func
  end

  def create_read_const_function(fun_name, const)
    in_main do
      define_main_function(fun_name, ([] of LLVM::Type), llvm_type(const.value.type).pointer) do |func|
        set_internal_fun_debug_location(func, fun_name, const.locations.try &.first?)
        global = initialize_const(const)
        ret global
      end
    end
  end
end
