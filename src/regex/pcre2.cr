require "./lib_pcre2"
require "crystal/system/thread_local"

# :nodoc:
module Regex::PCRE2
  @re : LibPCRE2::Code*
  @jit : Bool

  def self.version : String
    String.new(24) do |pointer|
      size = LibPCRE2.config(LibPCRE2::CONFIG_VERSION, pointer)
      {size - 1, size - 1}
    end
  end

  class_getter version_number : {Int32, Int32} do
    version = self.version
    dot = version.index('.') || raise RuntimeError.new("Invalid libpcre2 version")
    space = version.index(' ', dot) || raise RuntimeError.new("Invalid libpcre2 version")
    # PCRE2 versions can contain -RC{N} which would make `.to_i` fail unless strict is set to false
    {version.byte_slice(0, dot).to_i, version.byte_slice(dot + 1, space - dot - 1).to_i(strict: false)}
  end

  # :nodoc:
  def initialize(*, _source @source : String, _options @options)
    options = pcre2_compile_options(options) | LibPCRE2::UTF | LibPCRE2::DUPNAMES | LibPCRE2::UCP
    @re = PCRE2.compile(source, options) do |error_message|
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
      message = get_error_message(errorcode)
      yield "#{message} at #{erroroffset}"
    end
  end

  protected def self.get_error_message(errorcode)
    String.new(256) do |buffer|
      bytesize = LibPCRE2.get_error_message(errorcode, buffer, 256)
      {bytesize, 0}
    end
  end

  private def pcre2_compile_options(options)
    flag = 0
    Regex::CompileOptions.each do |option|
      if options.includes?(option)
        flag |= case option
                when .ignore_case?       then LibPCRE2::CASELESS
                when .multiline?         then LibPCRE2::MULTILINE | LibPCRE2::DOTALL
                when .multiline_only?    then LibPCRE2::MULTILINE
                when .dotall?            then LibPCRE2::DOTALL
                when .extended?          then LibPCRE2::EXTENDED
                when .anchored?          then LibPCRE2::ANCHORED
                when .dollar_endonly?    then LibPCRE2::DOLLAR_ENDONLY
                when .firstline?         then LibPCRE2::FIRSTLINE
                when .utf_8?             then LibPCRE2::UTF
                when .no_utf_check?      then LibPCRE2::NO_UTF_CHECK
                when .dupnames?          then LibPCRE2::DUPNAMES
                when .ucp?               then LibPCRE2::UCP
                when .endanchored?       then LibPCRE2::ENDANCHORED
                when .match_invalid_utf? then LibPCRE2::MATCH_INVALID_UTF
                else
                  raise "Unreachable"
                end
        options &= ~option
      end
    end
    unless options.none?
      raise ArgumentError.new("Unknown Regex::Option value: #{options}")
    end
    flag
  end

  def self.supports_compile_flag?(options)
    true
  end

  private def pcre2_match_options(options)
    flag = 0
    Regex::Options.each do |option|
      if options.includes?(option)
        flag |= case option
                when .ignore_case?    then raise ArgumentError.new("Invalid regex option IGNORE_CASE for `pcre2_match`")
                when .multiline?      then raise ArgumentError.new("Invalid regex option MULTILINE for `pcre2_match`")
                when .dotall?         then raise ArgumentError.new("Invalid regex option DOTALL for `pcre2_match`")
                when .extended?       then raise ArgumentError.new("Invalid regex option EXTENDED for `pcre2_match`")
                when .anchored?       then LibPCRE2::ANCHORED
                when .dollar_endonly? then raise ArgumentError.new("Invalid regex option DOLLAR_ENDONLY for `pcre2_match`")
                when .firstline?      then raise ArgumentError.new("Invalid regex option FIRSTLINE for `pcre2_match`")
                when .utf_8?          then raise ArgumentError.new("Invalid regex option UTF_8 for `pcre2_match`")
                when .no_utf_check?   then LibPCRE2::NO_UTF_CHECK
                when .dupnames?       then raise ArgumentError.new("Invalid regex option DUPNAMES for `pcre2_match`")
                when .ucp?            then raise ArgumentError.new("Invalid regex option UCP for `pcre2_match`")
                when .endanchored?    then LibPCRE2::ENDANCHORED
                else
                  raise "Unreachable"
                end
        options &= ~option
      end
    end
    unless options.none?
      raise ArgumentError.new("Unknown Regex::Option value: #{options}")
    end
    flag
  end

  private def pcre2_match_options(options : Regex::MatchOptions)
    flag = 0
    Regex::MatchOptions.each do |option|
      if options.includes?(option)
        flag |= case option
                when .anchored?     then LibPCRE2::ANCHORED
                when .endanchored?  then LibPCRE2::ENDANCHORED
                when .no_jit?       then LibPCRE2::NO_JIT
                when .no_utf_check? then LibPCRE2::NO_UTF_CHECK
                else
                  raise "Unreachable"
                end
        options &= ~option
      end
    end
    unless options.none?
      raise ArgumentError.new("Unknown Regex::MatchOption value: #{options}")
    end
    flag
  end

  def self.supports_match_flag?(options)
    true
  end

  protected def self.error_impl(source)
    code = PCRE2.compile(source, LibPCRE2::UTF | LibPCRE2::DUPNAMES | LibPCRE2::UCP) do |error_message|
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
      raise "Error pattern_info #{what}: #{ret}"
    end
  end

  private def name_table_impl
    lookup = Hash(Int32, String).new

    each_named_capture_group do |capture_number, name_entry|
      lookup[capture_number] = String.new(name_entry.to_unsafe + 2)
    end

    lookup
  end

  # :nodoc:
  def each_named_capture_group(&)
    name_table = uninitialized UInt8*
    pattern_info(LibPCRE2::INFO_NAMETABLE, pointerof(name_table))

    name_entry_size = pattern_info(LibPCRE2::INFO_NAMEENTRYSIZE)

    name_count = pattern_info(LibPCRE2::INFO_NAMECOUNT)
    name_count.times do
      capture_number = (name_table[0].to_i << 8) | name_table[1]

      yield capture_number, Slice.new(name_table, name_entry_size)

      name_table += name_entry_size
    end
  end

  private def capture_count_impl
    pattern_info(LibPCRE2::INFO_CAPTURECOUNT).to_i32
  end

  private def match_impl(str, byte_index, options)
    match_data = match_data(str, byte_index, options) || return

    # we reuse the same matchdata allocation, so we must "reimplement" the
    # behavior of pcre2_match_data_create_from_pattern (get_ovector_count always
    # returns 65535, aka the maximum):
    ovector_count = capture_count_impl &+ 1
    ovector = Slice.new(LibPCRE2.get_ovector_pointer(match_data), ovector_count &* 2)

    # We need to dup the ovector because `match_data` is re-used for subsequent
    # matches. Dup brings the ovector data into the realm of the GC.
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

  @@jit_stack = Crystal::System::ThreadLocal(LibPCRE2::JITStack*).new do |jit_stack|
    LibPCRE2.jit_stack_free(jit_stack)
  end

  @@match_datas = Crystal::System::ThreadLocal(LibPCRE2::MatchData*).new do |match_data|
    LibPCRE2.match_data_free(match_data)
  end

  class_getter match_context : LibPCRE2::MatchContext* do
    match_context = LibPCRE2.match_context_create(nil)
    LibPCRE2.jit_stack_assign(match_context, ->(_data) {
      @@jit_stack.get do
        LibPCRE2.jit_stack_create(32_768, 1_048_576, nil) || raise "Error allocating JIT stack"
      end
    }, nil)
    match_context
  end

  def finalize
    LibPCRE2.code_free(@re)
  end

  private def match_data(str, byte_index, options)
    match_data = @@match_datas.get { LibPCRE2.match_data_create(65_535, nil) }
    match_count = LibPCRE2.match(@re, str, str.bytesize, byte_index, pcre2_match_options(options), match_data, PCRE2.match_context)

    if match_count < 0
      case error = LibPCRE2::Error.new(match_count)
      when .nomatch?
        return
      when .badutfoffset?, .utf8_validity?
        error_message = PCRE2.get_error_message(error)
        raise ArgumentError.new("Regex match error: #{error_message}")
      else
        error_message = PCRE2.get_error_message(error)
        raise Regex::Error.new("Regex match error: #{error_message}")
      end
    end

    match_data
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
      @regex.each_named_capture_group do |number, name_entry|
        if name_entry[2, group_name.bytesize]? == group_name.to_slice && name_entry[2 + group_name.bytesize].zero?
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
