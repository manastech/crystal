{% skip_file if flag?(:win32) %}

require "c/dlfcn"
require "c/stdio"
require "c/string"
require "./lib_unwind"

{% if flag?(:darwin) || flag?(:bsd) || flag?(:linux) %}
  require "./call_stack/dwarf"
{% else %}
  require "./call_stack/null"
{% end %}

# Returns the current execution stack as an array containing strings
# usually in the form file:line:column or file:line:column in 'method'.
def caller : Array(String)
  Exception::CallStack.new.printable_backtrace
end

# :nodoc:
struct Exception::CallStack
  record Frame,
    file : String?,
    line : Int32?,
    column : Int32?,
    name : String?,
    sname : String?,
    ip_address : UInt64 do
    def to_s(*, full_info : Bool = false) : String
      String.build do |io|
        to_s io, full_info: full_info
      end
    end

    def to_s(io : IO, *, full_info : Bool = false) : Nil
      function = name || "???"
      function = sname if full_info && sname

      if file
        io << file
        if line && column
          io << ':' << line << ':' << column
        elsif line
          io << ':' << line
        end
        io << " in '" << function << '\''
      else
        io << function
      end

      if full_info
        io << " at 0x" << ip_address.to_s(16)
      end
    end
  end

  # Compute current directory at the beginning so filenames
  # are always shown relative to the *starting* working directory.
  CURRENT_DIR = begin
    dir = Process::INITIAL_PWD
    dir += File::SEPARATOR unless dir.ends_with?(File::SEPARATOR)
    dir
  end

  @@skip = [] of String

  def self.skip(filename)
    @@skip << filename
  end

  skip(__FILE__)

  @callstack : Array(Void*)
  getter frames : Array(Frame) { decode_frames }

  def initialize
    @callstack = CallStack.unwind
  end

  def printable_backtrace : Array(String)
    full_info = ENV["CRYSTAL_CALLSTACK_FULL_INFO"]? == "1"

    frames.map do |frame|
      frame.to_s(full_info: full_info)
    end
  end

  {% if flag?(:gnu) && flag?(:i386) %}
    # This is only used for the workaround described in `Exception.unwind`
    @@makecontext_range : Range(Void*, Void*)?

    def self.makecontext_range
      @@makecontext_range ||= begin
        makecontext_start = makecontext_end = LibC.dlsym(LibC::RTLD_DEFAULT, "makecontext")

        while true
          ret = LibC.dladdr(makecontext_end, out info)
          break if ret == 0 || info.dli_sname.null?
          break unless LibC.strcmp(info.dli_sname, "makecontext") == 0
          makecontext_end += 1
        end

        (makecontext_start...makecontext_end)
      end
    end
  {% end %}

  protected def self.unwind
    callstack = [] of Void*
    backtrace_fn = ->(context : LibUnwind::Context, data : Void*) do
      bt = data.as(typeof(callstack))

      ip = {% if flag?(:arm) %}
             Pointer(Void).new(__crystal_unwind_get_ip(context))
           {% else %}
             Pointer(Void).new(LibUnwind.get_ip(context))
           {% end %}
      bt << ip

      {% if flag?(:gnu) && flag?(:i386) %}
        # This is a workaround for glibc bug: https://sourceware.org/bugzilla/show_bug.cgi?id=18635
        # The unwind info is corrupted when `makecontext` is used.
        # Stop the backtrace here. There is nothing interest beyond this point anyway.
        if CallStack.makecontext_range.includes?(ip)
          return LibUnwind::ReasonCode::END_OF_STACK
        end
      {% end %}

      LibUnwind::ReasonCode::NO_REASON
    end

    LibUnwind.backtrace(backtrace_fn, callstack.as(Void*))
    callstack
  end

  struct RepeatedFrame
    getter ip : Void*, count : Int32

    def initialize(@ip : Void*)
      @count = 0
    end

    def incr
      @count += 1
    end
  end

  def self.print_backtrace
    backtrace_fn = ->(context : LibUnwind::Context, data : Void*) do
      last_frame = data.as(RepeatedFrame*)

      ip = {% if flag?(:arm) %}
             Pointer(Void).new(__crystal_unwind_get_ip(context))
           {% else %}
             Pointer(Void).new(LibUnwind.get_ip(context))
           {% end %}

      if last_frame.value.ip == ip
        last_frame.value.incr
      else
        print_frame(last_frame.value) unless last_frame.value.ip.address == 0
        last_frame.value = RepeatedFrame.new ip
      end
      LibUnwind::ReasonCode::NO_REASON
    end

    rf = RepeatedFrame.new(Pointer(Void).null)
    LibUnwind.backtrace(backtrace_fn, pointerof(rf).as(Void*))
    print_frame(rf)
  end

  private def self.print_frame(repeated_frame)
    {% if flag?(:debug) %}
      if @@dwarf_loaded
        if name = decode_function_name(repeated_frame.ip.address)
          file, line, column = Exception::CallStack.decode_line_number(repeated_frame.ip.address)
          if file
            line ||= 0
            column ||= 0

            if repeated_frame.count == 0
              Crystal::System.print_error "[0x%lx] %s at %s:%ld:%i\n", repeated_frame.ip, name, file, line, column
            else
              Crystal::System.print_error "[0x%lx] %s at %s:%ld:%i (%ld times)\n", repeated_frame.ip, name, file, line, column, repeated_frame.count + 1
            end
            return
          end
        end
      end
    {% end %}

    frame = decode_frame(repeated_frame.ip)
    if frame
      offset, sname = frame
      if repeated_frame.count == 0
        Crystal::System.print_error "[0x%lx] %s +%ld\n", repeated_frame.ip, sname, offset
      else
        Crystal::System.print_error "[0x%lx] %s +%ld (%ld times)\n", repeated_frame.ip, sname, offset, repeated_frame.count + 1
      end
    else
      if repeated_frame.count == 0
        Crystal::System.print_error "[0x%lx] ???\n", repeated_frame.ip
      else
        Crystal::System.print_error "[0x%lx] ??? (%ld times)\n", repeated_frame.ip, repeated_frame.count + 1
      end
    end
  end

  private def decode_frames : Array(Frame)
    @callstack.compact_map do |ip|
      pc = CallStack.decode_address(ip)

      file, line, column = CallStack.decode_line_number(pc)

      if file
        next if @@skip.includes?(file)

        # Turn to relative to the current dir, if possible
        file = file.lchop(CURRENT_DIR)
      end

      if name = CallStack.decode_function_name(pc)
        function_name = name
      end

      if frame = CallStack.decode_frame(ip)
        _, sname = frame
        sname = String.new(sname)

        # Crystal methods (their mangled name) start with `*`, so
        # we remove that to have less clutter in the output.
        sname = sname.lchop('*')
      end

      Frame.new(file, line, column, function_name, sname, ip.address)
    end
  end

  protected def self.decode_frame(ip, original_ip = ip)
    if LibC.dladdr(ip, out info) != 0
      offset = original_ip - info.dli_saddr

      if offset == 0
        return decode_frame(ip - 1, original_ip)
      end

      unless info.dli_sname.null?
        {offset, info.dli_sname}
      end
    end
  end
end
