require "c/stdio"
require "c/stdlib"
require "crystal/system/print_error"
require "exception/call_stack"

Exception::CallStack.skip(__FILE__)

private struct LEBReader
  def initialize(@data : UInt8*)
  end

  def data : UInt8*
    @data
  end

  def read_uint8 : UInt8
    value = @data.value
    @data += 1
    value
  end

  def read_uint32 : UInt32
    value = @data.as(UInt32*).value
    @data += 4
    value
  end

  def read_uleb128 : UInt64
    result = 0_u64
    shift = 0
    while true
      byte = read_uint8
      result |= ((0x7f_u64 & byte) << shift)
      break if (byte & 0x80_u8) == 0
      shift += 7
    end
    result
  end
end

private def traverse_eh_table(leb, start, ip, actions, &)
  # Ref: https://chromium.googlesource.com/native_client/pnacl-libcxxabi/+/master/src/cxa_personality.cpp

  throw_offset = ip - 1 - start
  # puts "Personality - actions : #{actions}, start: #{start}, ip: #{ip}, throw_offset: #{throw_offset}"

  lp_start_encoding = leb.read_uint8 # @LPStart encoding
  if lp_start_encoding != 0xff_u8
    Crystal::System.print_error "Unexpected encoding for LPStart: 0x%x\n", lp_start_encoding
    LibC.exit 1
  end

  if leb.read_uint8 != 0xff_u8 # @TType encoding
    leb.read_uleb128           # @TType base offset
  end

  cs_encoding = leb.read_uint8 # CS Encoding (1: uleb128, 3: uint32)
  if cs_encoding != 1 && cs_encoding != 3
    Crystal::System.print_error "Unexpected CS encoding: 0x%x\n", cs_encoding
    LibC.exit 1
  end

  cs_table_length = leb.read_uleb128 # CS table length
  cs_table_end = leb.data + cs_table_length

  while leb.data < cs_table_end
    cs_offset = cs_encoding == 3 ? leb.read_uint32 : leb.read_uleb128
    cs_length = cs_encoding == 3 ? leb.read_uint32 : leb.read_uleb128
    cs_addr = cs_encoding == 3 ? leb.read_uint32 : leb.read_uleb128
    action = leb.read_uleb128
    # puts "cs_offset: #{cs_offset}, cs_length: #{cs_length}, cs_addr: #{cs_addr}, action: #{action}"

    if cs_addr != 0
      if cs_offset <= throw_offset && throw_offset <= cs_offset + cs_length
        if actions.includes? LibUnwind::Action::SEARCH_PHASE
          # puts "found"
          return LibUnwind::ReasonCode::HANDLER_FOUND
        end

        if actions.includes? LibUnwind::Action::HANDLER_FRAME
          unwind_ip = start + cs_addr
          yield unwind_ip
          # puts "install"
          return LibUnwind::ReasonCode::INSTALL_CONTEXT
        end
      end
    end
  end

  nil
end

{% if flag?(:interpreted) %}
  # interpreter does not need `__crystal_personality`
{% elsif flag?(:win32) && !flag?(:gnu) %}
  require "exception/lib_unwind"

  {% begin %}
    @[Link({{ flag?(:static) ? "libvcruntime" : "vcruntime" }})]
  {% end %}
  lib LibC
    fun _CxxThrowException(ex : Void*, throw_info : Void*) : NoReturn
  end

  @[Primitive(:throw_info)]
  def throw_info : Void*
  end

  # :nodoc:
  @[Raises]
  fun __crystal_raise(unwind_ex : LibUnwind::Exception*) : NoReturn
    Crystal::System.print_error "EXITING: __crystal_raise called"
    LibC.exit(1)
  end
{% elsif flag?(:arm) %}
  # On ARM EHABI the personality routine is responsible for actually
  # unwinding a single stack frame before returning (ARM EHABI Sec. 6.1).
  private macro __crystal_continue_unwind
    if LibUnwind.__gnu_unwind_frame(ucb, context) != LibUnwind::ReasonCode::NO_REASON
      return LibUnwind::ReasonCode::FAILURE
    end
    # puts "continue"
    return LibUnwind::ReasonCode::CONTINUE_UNWIND
  end

  # :nodoc:
  fun __crystal_personality(state : LibUnwind::State, ucb : LibUnwind::ControlBlock*, context : LibUnwind::Context) : LibUnwind::ReasonCode
    # puts "\n__crystal_personality(#{state}, #{ucb}, #{context})"

    case LibUnwind::State.new(state.value & LibUnwind::State::ACTION_MASK.value)
    when LibUnwind::State::VIRTUAL_UNWIND_FRAME
      if state.force_unwind?
        __crystal_continue_unwind
      else
        actions = LibUnwind::Action::SEARCH_PHASE
      end
    when LibUnwind::State::UNWIND_FRAME_STARTING
      actions = LibUnwind::Action::HANDLER_FRAME
    when LibUnwind::State::UNWIND_FRAME_RESUME
      __crystal_continue_unwind
    else
      exit(-1)
    end

    if state.force_unwind?
      actions |= LibUnwind::Action::FORCE_UNWIND
    end

    start = __crystal_get_region_start(ucb)
    lsd = __crystal_get_language_specific_data(ucb)

    ip = __crystal_unwind_get_ip(context)
    leb = LEBReader.new(lsd)

    reason = traverse_eh_table(leb, start, ip, actions) do |unwind_ip|
      __crystal_unwind_set_gr(context, LibUnwind::EH_REGISTER_0, ucb.address.to_u32)
      __crystal_unwind_set_gr(context, LibUnwind::EH_REGISTER_1, ucb.value.exception_type_id.to_u32)
      __crystal_unwind_set_ip(context, unwind_ip)
    end
    return reason if reason

    __crystal_continue_unwind
  end
{% elsif flag?(:wasm32) %}
  # :nodoc:
  fun __crystal_personality
    Crystal::System.print_error "EXITING: __crystal_personality called"
    LibC.exit(1)
  end

  # :nodoc:
  @[Raises]
  fun __crystal_raise(ex : Void*) : NoReturn
    Crystal::System.print_error "EXITING: __crystal_raise called"
    LibC.exit(1)
  end

  # :nodoc:
  fun __crystal_get_exception(ex : Void*) : UInt64
    Crystal::System.print_error "EXITING: __crystal_get_exception called"
    LibC.exit(1)
    0u64
  end
{% else %}
  {% mingw = flag?(:win32) && flag?(:gnu) %}
  # :nodoc:
  fun {{ mingw ? "__crystal_personality_imp".id : "__crystal_personality".id }}(
    version : Int32, actions : LibUnwind::Action, exception_class : UInt64, exception_object : LibUnwind::Exception*, context : Void*,
  ) : LibUnwind::ReasonCode
    start = LibUnwind.get_region_start(context)
    ip = LibUnwind.get_ip(context)
    lsd = LibUnwind.get_language_specific_data(context)

    leb = LEBReader.new(lsd)
    reason = traverse_eh_table(leb, start, ip, actions) do |unwind_ip|
      LibUnwind.set_gr(context, LibUnwind::EH_REGISTER_0, exception_object.address)
      LibUnwind.set_gr(context, LibUnwind::EH_REGISTER_1, exception_object.value.exception_type_id)
      LibUnwind.set_ip(context, unwind_ip)
    end
    return reason if reason

    return LibUnwind::ReasonCode::CONTINUE_UNWIND
  end

  {% if mingw %}
    lib LibC
      alias EXCEPTION_DISPOSITION = Int
      alias DISPATCHER_CONTEXT = Void
    end

    # :nodoc:
    lib LibUnwind
      alias PersonalityFn = Int32, Action, UInt64, Exception*, Void* -> ReasonCode

      fun _GCC_specific_handler(ms_exc : LibC::EXCEPTION_RECORD64*, this_frame : Void*, ms_orig_context : LibC::CONTEXT*, ms_disp : LibC::DISPATCHER_CONTEXT*, gcc_per : PersonalityFn) : LibC::EXCEPTION_DISPOSITION
    end

    # :nodoc:
    fun __crystal_personality(ms_exc : LibC::EXCEPTION_RECORD64*, this_frame : Void*, ms_orig_context : LibC::CONTEXT*, ms_disp : LibC::DISPATCHER_CONTEXT*) : LibC::EXCEPTION_DISPOSITION
      LibUnwind._GCC_specific_handler(ms_exc, this_frame, ms_orig_context, ms_disp, ->__crystal_personality_imp)
    end
  {% end %}
{% end %}

{% unless flag?(:interpreted) || (flag?(:win32) && !flag?(:gnu)) || flag?(:wasm32) %}
  # :nodoc:
  @[Raises]
  fun __crystal_raise(unwind_ex : LibUnwind::Exception*) : NoReturn
    ret = LibUnwind.raise_exception(unwind_ex)
    Crystal::System.print_error "Failed to raise an exception: %s\n", ret.to_s
    Exception::CallStack.print_backtrace
    Crystal::System.print_exception("\nTried to raise:", unwind_ex.value.exception_object.as(Exception))
    LibC.exit(ret)
  end

  # :nodoc:
  fun __crystal_get_exception(unwind_ex : LibUnwind::Exception*) : UInt64
    unwind_ex.value.exception_object.address
  end
{% end %}

{% if flag?(:wasm32) %}
  def raise(exception : Exception) : NoReturn
    Crystal::System.print_error "EXITING: Attempting to raise:\n%s\n", exception.inspect_with_backtrace
    LibIntrinsics.debugtrap
    LibC.exit(1)
  end
{% else %}
  # Raises the *exception*.
  #
  # This will set the exception's callstack if it hasn't been already.
  # Re-raising a previously caught exception won't replace the callstack.
  def raise(exception : Exception) : NoReturn
    {% if flag?(:debug_raise) %}
      STDERR.puts
      STDERR.puts "Attempting to raise: "
      exception.inspect_with_backtrace(STDERR)
    {% end %}

    exception.callstack ||= Exception::CallStack.new
    raise_without_backtrace(exception)
  end
{% end %}

# Raises an Exception with the *message*.
def raise(message : String) : NoReturn
  raise Exception.new(message)
end

{% if flag?(:win32) && !flag?(:gnu) %}
  # :nodoc:
  {% if flag?(:interpreted) %} @[Primitive(:interpreter_raise_without_backtrace)] {% end %}
  def raise_without_backtrace(exception : Exception) : NoReturn
    LibC._CxxThrowException(pointerof(exception).as(Void*), throw_info)
  end
{% else %}
  # :nodoc:
  {% if flag?(:interpreted) %} @[Primitive(:interpreter_raise_without_backtrace)] {% end %}
  def raise_without_backtrace(exception : Exception) : NoReturn
    unwind_ex = Pointer(LibUnwind::Exception).malloc
    unwind_ex.value.exception_class = LibC::SizeT.zero
    unwind_ex.value.exception_cleanup = LibC::SizeT.zero
    unwind_ex.value.exception_object = exception.as(Void*)
    unwind_ex.value.exception_type_id = exception.crystal_type_id
    __crystal_raise(unwind_ex)
  end
{% end %}

# :nodoc:
fun __crystal_raise_string(message : UInt8*)
  raise String.new(message)
end

# :nodoc:
fun __crystal_raise_overflow : NoReturn
  raise OverflowError.new
end

{% if flag?(:interpreted) %}
  # :nodoc:
  def __crystal_raise_cast_failed(obj, type_name : String, location : String)
    raise TypeCastError.new("Cast from #{obj.class} to #{type_name} failed, at #{location}")
  end
{% end %}
