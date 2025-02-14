require "./system/panic"

module Crystal
  # :nodoc:
  module Tracing
    @[Flags]
    enum Section
      GC
      Sched
      Evloop

      def self.from_id(slice) : self
        {% begin %}
          case slice
            {% for name in @type.constants %}
              when {{name.underscore.stringify}}.to_slice
                {{name}}
            {% end %}
          else
            None
          end
        {% end %}
      end

      def to_id : String
        {% begin %}
          case self
          {% for name in @type.constants %}
            when {{name}}
              {{name.underscore.stringify}}
          {% end %}
          else
            "???"
          end
        {% end %}
      end
    end
  end

  {% if flag?(:tracing) %}
    # :nodoc:
    module Tracing
      # IO-like object with a fixed capacity but dynamic size within the
      # buffer's capacity (i.e. `0 <= size <= N`). Stops writing to the internal
      # buffer when capacity is reached; further writes are skipped.
      struct BufferIO(N)
        getter size : Int32

        def initialize
          @buf = uninitialized UInt8[N]
          @size = 0
        end

        def write(value : Bytes) : Nil
          pos = @size
          remaining = N - pos
          return if remaining == 0

          n = value.size.clamp(..remaining)
          value.to_unsafe.copy_to(@buf.to_unsafe + pos, n)
          @size = pos + n
        end

        def write(value : String) : Nil
          write value.to_slice
        end

        def write(value : Char) : Nil
          chars = uninitialized UInt8[4]
          i = 0
          value.each_byte do |byte|
            chars[i] = byte
            i += 1
          end
          write chars.to_slice[0, i]
        end

        def write(value : Fiber) : Nil
          write value.as(Void*)
          write ':'
          write value.name || '?'
        end

        {% if flag?(:execution_context) %}
          def write(value : Fiber::ExecutionContext) : Nil
            write value.name
          end

          def write(value : Fiber::ExecutionContext::Scheduler) : Nil
            write value.name
          end
        {% end %}

        def write(value : Pointer) : Nil
          write "0x"
          System.to_int_slice(value.address, 16, true, 2) { |bytes| write(bytes) }
        end

        def write(value : Int::Signed) : Nil
          System.to_int_slice(value, 10, true, 2) { |bytes| write(bytes) }
        end

        def write(value : Int::Unsigned) : Nil
          System.to_int_slice(value, 10, false, 2) { |bytes| write(bytes) }
        end

        def write(value : Time::Span) : Nil
          write(value.seconds * Time::NANOSECONDS_PER_SECOND + value.nanoseconds)
        end

        def write(value : Bool) : Nil
          write value ? '1' : '0'
        end

        def write(value : Nil) : Nil
        end

        def to_slice : Bytes
          Bytes.new(@buf.to_unsafe, @size)
        end
      end

      @@sections = Section::None
      @@handle = uninitialized System::FileDescriptor::Handle

      @[AlwaysInline]
      def self.enabled?(section : Section) : Bool
        @@sections.includes?(section)
      end

      # Setup tracing.
      #
      # Parses the `CRYSTAL_TRACE` environment variable to enable the sections
      # to trace. See `Section`. By default no sections are enabled.
      #
      # Parses the `CRYSTAL_TRACE_FILE` environment variable to open the trace
      # file to write to. Exits with an error message when the file can't be
      # opened, created or truncated. Uses the standard error when unspecified.
      #
      # This should be the first thing called in main, maybe even before the GC
      # itself is initialized. The function assumes neither the GC nor ENV nor
      # anything is available and musn't allocate into the GC HEAP.
      def self.init : Nil
        @@sections = Section::None

        {% if flag?(:win32) %}
          buf = uninitialized UInt16[256]

          name = UInt16.static_array({% for chr in "CRYSTAL_TRACE".chars %}{{chr.ord}}, {% end %} 0)
          len = LibC.GetEnvironmentVariableW(name, buf, buf.size)
          parse_sections(buf.to_slice[0...len]) if len > 0

          name = UInt16.static_array({% for chr in "CRYSTAL_TRACE_FILE".chars %}{{chr.ord}}, {% end %} 0)
          len = LibC.GetEnvironmentVariableW(name, buf, buf.size)
          if len > 0
            @@handle = open_trace_file(buf.to_slice[0...len])
          else
            @@handle = LibC.GetStdHandle(LibC::STD_ERROR_HANDLE).address
          end
        {% else %}
          if ptr = LibC.getenv("CRYSTAL_TRACE")
            len = LibC.strlen(ptr)
            parse_sections(Slice.new(ptr, len)) if len > 0
          end

          if (ptr = LibC.getenv("CRYSTAL_TRACE_FILE")) && (LibC.strlen(ptr) > 0)
            @@handle = open_trace_file(ptr)
          else
            @@handle = 2
          end
        {% end %}
      end

      private def self.open_trace_file(filename)
        {% if flag?(:win32) %}
          handle = LibC.CreateFileW(filename, LibC::FILE_GENERIC_WRITE, LibC::DEFAULT_SHARE_MODE, nil, LibC::CREATE_ALWAYS, LibC::FILE_ATTRIBUTE_NORMAL, LibC::HANDLE.null)
          # not using LibC::INVALID_HANDLE_VALUE because it doesn't exist (yet)
          return handle.address unless handle == LibC::HANDLE.new(-1.to_u64!)

          syscall_name = "CreateFileW"
          error = WinError.value
        {% else %}
          fd = LibC.open(filename, LibC::O_CREAT | LibC::O_WRONLY | LibC::O_TRUNC | LibC::O_CLOEXEC, 0o644)
          return fd unless fd < 0

          syscall_name = "open"
          error = Errno.value
        {% end %}

        System.print_error "ERROR: failed to open "
        System.print_error filename
        System.print_error " for writing\n"

        System.panic(syscall_name, Errno.value)
      end

      private def self.parse_sections(slice)
        each_token(slice) do |token|
          @@sections |= Section.from_id(token)
        end
      end

      private def self.each_token(slice, delim = ',', &)
        while e = slice.index(delim.ord)
          yield slice[0, e]
          slice = slice[(e + 1)..]
        end
        yield slice[0..] unless slice.size == 0
      end

      # :nodoc:
      #
      # Formats and prints a log message to stderr. The generated message is
      # limited to 512 bytes (PIPE_BUF) after which it will be truncated. Being
      # below PIPE_BUF the message shall be written atomically to stderr,
      # avoiding interleaved or smashed traces from multiple threads.
      #
      # Windows may not have the same guarantees but the buffering should limit
      # these from happening.
      def self.log(section : String, operation : String, time : UInt64, **metadata) : Nil
        buf = BufferIO(512).new
        buf.write section
        buf.write "."
        buf.write operation
        buf.write " "
        buf.write time

        {% unless flag?(:wasm32) %}
          # WASM doesn't have threads (and fibers aren't implemented either)
          #
          # We also start to trace *before* Thread.current and other objects have
          # been allocated, they're lazily allocated and since we trace GC.malloc we
          # must skip the objects until they're allocated (otherwise we hit infinite
          # recursion): malloc -> trace -> malloc -> trace -> ...
          thread = ::Thread.current?

          buf.write " thread="
          {% if flag?(:linux) %}
            buf.write Pointer(Void).new(thread ? thread.@system_handle : System::Thread.current_handle)
          {% else %}
            buf.write thread ? thread.@system_handle : System::Thread.current_handle
          {% end %}
          buf.write ":"
          buf.write thread.try(&.name) || "?"

          if thread && (fiber = thread.current_fiber?)
            buf.write " fiber="
            buf.write fiber
          end
        {% end %}

        metadata.each do |key, value|
          buf.write " "
          buf.write key.to_s
          buf.write "="
          buf.write value
        end

        buf.write "\n"
        System.print(@@handle, buf.to_slice)
      end
    end

    def self.trace(section : Tracing::Section, operation : String, time : UInt64? = nil, **metadata, &)
      if Tracing.enabled?(section)
        time ||= System::Time.ticks
        begin
          yield
        ensure
          duration = System::Time.ticks - time
          Tracing.log(section.to_id, operation, time, **metadata, duration: duration)
        end
      else
        yield
      end
    end

    def self.trace(section : Tracing::Section, operation : String, time : UInt64? = nil, **metadata) : Nil
      if Tracing.enabled?(section)
        Tracing.log(section.to_id, operation, time || System::Time.ticks, **metadata)
      end
    end
  {% else %}
    # :nodoc:
    module Tracing
      def self.init
      end

      def self.enabled?(section)
        false
      end

      def self.log(section : String, operation : String, time : UInt64, **metadata)
      end
    end

    def self.trace(section : Tracing::Section, operation : String, time : UInt64? = nil, **metadata, &)
      yield
    end

    def self.trace(section : Tracing::Section, operation : String, time : UInt64? = nil, **metadata)
    end
  {% end %}
end
