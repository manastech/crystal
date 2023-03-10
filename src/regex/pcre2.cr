require "./lib_pcre2"
require "crystal/thread_local_value"

# :nodoc:
module Regex::PCRE2
  @re : LibPCRE2::Code*
  @jit : Bool

  # :nodoc:
  def initialize(*, _source @source : String, _options @options)
    @re = PCRE2.compile(source, pcre2_options(options) | LibPCRE2::UTF | LibPCRE2::NO_UTF_CHECK | LibPCRE2::DUPNAMES | LibPCRE2::UCP) do |error_message|
      raise ArgumentError.new(error_message)
    end

    @jit = jit_compile
  end

  private def jit_compile : Bool
    ret = LibPCRE2.jit_compile(@re, LibPCRE2::JIT_COMPLETE)
    if ret < 0
      case error = LibPCRE2::Error.new(ret)
      when .jit_badoption?
        # okay
        return false
      else
        raise ArgumentError.new("Regex JIT compile error: #{error}")
      end
    end
    true
  end

  protected def self.compile(source, options, &)
    if res = LibPCRE2.compile(source, source.bytesize, options, out errorcode, out erroroffset, nil)
      res
    else
      message = String.new(256) do |buffer|
        bytesize = LibPCRE2.get_error_message(errorcode, buffer, 256)
        {bytesize, 0}
      end
      yield "#{message} at #{erroroffset}"
    end
  end

  private def pcre2_options(options)
    flag = 0
    Regex::Options.each do |option|
      if options.includes?(option)
        flag |= case option
                when .ignore_case?   then LibPCRE2::CASELESS
                when .multiline?     then LibPCRE2::DOTALL | LibPCRE2::MULTILINE
                when .extended?      then LibPCRE2::EXTENDED
                when .anchored?      then LibPCRE2::ANCHORED
                when .utf_8?         then LibPCRE2::UTF
                when .no_utf8_check? then LibPCRE2::NO_UTF_CHECK
                when .dupnames?      then LibPCRE2::DUPNAMES
                when .ucp?           then LibPCRE2::UCP
                else
                  raise "unreachable"
                end
        options &= ~option
      end
    end
    unless options.none?
      raise ArgumentError.new("Unknown Regex::Option value: #{options}")
    end
    flag
  end

  def finalize
    {% unless flag?(:interpreted) %}
      LibPCRE2.code_free @re
    {% end %}
  end

  protected def self.error_impl(source)
    code = PCRE2.compile(source, LibPCRE2::UTF | LibPCRE2::NO_UTF_CHECK | LibPCRE2::DUPNAMES | LibPCRE2::UCP) do |error_message|
      return error_message
    end

    LibPCRE2.code_free code

    nil
  end

  private def pattern_info(what)
    value = uninitialized UInt32
    pattern_info(what, pointerof(value))
    value
  end

  private def pattern_info(what, where)
    ret = LibPCRE2.pattern_info(@re, what, where)
    if ret != 0
      raise "error pattern_info #{what}: #{ret}"
    end
  end

  private def name_table_impl
    lookup = Hash(Int32, String).new

    each_capture_group do |capture_number, name_entry|
      lookup[capture_number] = String.new(name_entry.to_unsafe + 2)
    end

    lookup
  end

  # :nodoc:
  def each_capture_group(&)
    name_table = uninitialized UInt8*
    pattern_info(LibPCRE2::INFO_NAMETABLE, pointerof(name_table))

    name_entry_size = pattern_info(LibPCRE2::INFO_NAMEENTRYSIZE)

    name_count = pattern_info(LibPCRE2::INFO_NAMECOUNT)
    name_count.times do
      capture_number = (name_table[0] << 8) | name_table[1]

      yield capture_number, Slice.new(name_table, name_entry_size)

      name_table += name_entry_size
    end
  end

  private def capture_count_impl
    pattern_info(LibPCRE2::INFO_CAPTURECOUNT).to_i32
  end

  private def match_impl(str, byte_index, options)
    match_data = match_data(str, byte_index, options) || return

    ovector_count = LibPCRE2.get_ovector_count(match_data)
    ovector = Slice.new(LibPCRE2.get_ovector_pointer(match_data), ovector_count &* 2)

    # We need to dup the ovector because `match_data` is re-used for subsequent
    # matches (see `@match_data`).
    # Dup brings the ovector data into the realm of the GC.
    ovector = ovector.dup

    ::Regex::MatchData.new(self, @re, str, byte_index, ovector.to_unsafe, ovector_count.to_i32 &- 1)
  end

  private def matches_impl(str, byte_index, options)
    if match_data = match_data(str, byte_index, options)
      true
    else
      false
    end
  end

  class_getter match_context : LibPCRE2::MatchContext* do
    match_context = LibPCRE2.match_context_create(nil)
    LibPCRE2.jit_stack_assign(match_context, ->(_data) { Regex::PCRE2.jit_stack }, nil)
    match_context
  end

  # Returns a JIT stack that's shared in the current thread.
  #
  # Only a single `match` function can run per thread at any given time, so there
  # can't be any concurrent access to the JIT stack.
  @@jit_stack = Crystal::ThreadLocalValue(LibPCRE2::JITStack*).new

  def self.jit_stack
    @@jit_stack.get do
      LibPCRE2.jit_stack_create(32_768, 1_048_576, nil) || raise "Error allocating JIT stack"
    end
  end

  # Match data is shared per instance and thread.
  #
  # Match data contains a buffer for backtracking when matching in interpreted mode (non-JIT).
  # This buffer is heap-allocated and should be re-used for subsequent matches.
  @match_data = Crystal::ThreadLocalValue(LibPCRE2::MatchData*).new

  private def match_data
    @match_data.get do
      LibPCRE2.match_data_create_from_pattern(@re, nil)
    end
  end

  def finalize
    @match_data.consume_each do |match_data|
      LibPCRE2.match_data_free(match_data)
    end
  end

  private def match_data(str, byte_index, options)
    match_data = self.match_data
    match_count = LibPCRE2.match(@re, str, str.bytesize, byte_index, pcre2_options(options) | LibPCRE2::NO_UTF_CHECK, match_data, PCRE2.match_context)

    if match_count < 0
      case error = LibPCRE2::Error.new(match_count)
      when .nomatch?
        return
      else
        raise Exception.new("Regex match error: #{error}")
      end
    end

    match_data
  end

  def self.config(what, type : T.class) : T forall T
    value = uninitialized T
    LibPCRE2.config(what, pointerof(value))
    value
  end

  module MatchData
    # :nodoc:
    def initialize(@regex : Regex, @code : LibPCRE2::Code*, @string : String, @pos : Int32, @ovector : LibC::SizeT*, @group_size : Int32)
    end

    private def byte_range(n, &)
      n += size if n < 0
      range = Range.new(@ovector[n * 2].to_i32!, @ovector[n * 2 + 1].to_i32!, exclusive: true)
      if range.begin < 0 || range.end < 0
        yield n
      else
        range
      end
    end

    private def fetch_impl(group_name : String, &)
      selected_range = nil
      exists = false
      @regex.each_capture_group do |number, name_entry|
        if name_entry[2, group_name.bytesize]? == group_name.to_slice
          exists = true
          range = byte_range(number) { nil }
          if (range && selected_range && range.begin > selected_range.begin) || !selected_range
            selected_range = range
          end
        end
      end

      if selected_range
        @string.byte_slice(selected_range.begin, selected_range.end - selected_range.begin)
      else
        yield exists
      end
    end
  end
end
