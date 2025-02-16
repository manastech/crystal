{% skip_file unless flag?(:docs) %}

# Defines string related macro methods.
#
# Many `StringLiteral` methods can be called from `SymbolLiteral` and `MacroId`,
# because they are delegated to `StringLiteral`.
# So, their documentations should be shared between `StringLiteral` and others.
private macro def_string_methods(klass)
  # Returns a `MacroId` for this string's contents.
  def id : MacroId
  end

  # Similar to `String#[]`.
  def [](range : RangeLiteral) : {{klass}}
  end

  # Similar to `String#=~`.
  def =~(range : RegexLiteral) : BoolLiteral
  end

  # Similar to `String#+`.
  def +(other : StringLiteral | CharLiteral) : {{klass}}
  end

  # Similar to `String#camelcase`.
  def camelcase(*, lower : BoolLiteral = false) : {{klass}}
  end

  # Similar to `String#capitalize`.
  def capitalize : {{klass}}
  end

  # Similar to `String#chars`.
  def chars : ArrayLiteral(CharLiteral)
  end

  # Similar to `String#chomp`.
  def chomp : {{klass}}
  end

  # Similar to `String#count`.
  def count(other : CharLiteral) : NumberLiteral
  end

  # Similar to `String#downcase`.
  def downcase : {{klass}}
  end

  # Similar to `String#empty?`.
  def empty? : BoolLiteral
  end

  # Similar to `String#ends_with?`.
  def ends_with?(other : StringLiteral | CharLiteral) : BoolLiteral
  end

  # Similar to `String#gsub`.
  def gsub(regex : RegexLiteral, replacement : StringLiteral) : {{klass}}
  end

  # Similar to `String#includes?`.
  def includes?(search : StringLiteral | CharLiteral) : BoolLiteral
  end

  # Returns an array of capture hashes for each match of *regex* in this string.
  #
  # Capture hashes have the same form as `Regex::MatchData#to_h`.
  def scan(regex : RegexLiteral) : ArrayLiteral(HashLiteral(NumberLiteral | StringLiteral), StringLiteral | NilLiteral)
  end

  # Similar to `String#size`.
  def size : NumberLiteral
  end

  # Similar to `String#lines`.
  def lines : ArrayLiteral(StringLiteral)
  end

  # Similar to `String#split`.
  def split : ArrayLiteral(StringLiteral)
  end

  # Similar to `String#split`.
  def split(node : ASTNode) : ArrayLiteral(StringLiteral)
  end

  # Similar to `String#starts_with?`.
  def starts_with?(other : StringLiteral | CharLiteral) : BoolLiteral
  end

  # Similar to `String#strip`.
  def strip : {{klass}}
  end

  # Similar to `String#titleize`.
  def titleize : {{klass}}
  end

  # Similar to `String#to_i`.
  def to_i(base = 10)
  end

  # Similar to `String#tr`.
  def tr(from : StringLiteral, to : StringLiteral) : {{klass}}
  end

  # Similar to `String#underscore`.
  def underscore : {{klass}}
  end

  # Similar to `String#upcase`.
  def upcase : {{klass}}
  end
end

# The `Macros` module is a fictitious module used to document macros
# and macro methods.
#
# You can invoke a **fixed subset** of methods on AST nodes at compile-time. These methods
# are documented on the classes in this module. Additionally, methods of the
# `Macros` module are top-level methods that you can invoke, like `puts` and `run`.
module Crystal::Macros
  # Compares two [semantic versions](http://semver.org/).
  #
  # Returns `-1`, `0` or `1` depending on whether *v1* is lower than *v2*,
  # equal to *v2* or greater than *v2*.
  #
  # ```
  # {{ compare_versions("1.10.0", "1.2.0") }} # => 1
  # ```
  def compare_versions(v1 : StringLiteral, v2 : StringLiteral) : NumberLiteral
  end

  # Outputs the current macro's buffer to the standard output. Useful for debugging
  # a macro to see what's being generated.
  #
  # By default, the output is tried to be formatted using Crystal's
  # formatter, but you can disable this by passing `false` to this method.
  def debug(format = true) : Nop
  end

  # Gets the value of an environment variable at compile-time, or `nil` if it doesn't exist.
  def env(name) : StringLiteral | NilLiteral
  end

  # Returns whether a [compile-time flag](https://crystal-lang.org/docs/syntax_and_semantics/compile_time_flags.html) is set.
  #
  # ```
  # {{ flag?(:x86_64) }} # true or false
  # ```
  def flag?(name) : BoolLiteral
  end

  # Returns whether a [compile-time flag](https://crystal-lang.org/docs/syntax_and_semantics/compile_time_flags.html)
  # is set for the *host* platform, which can differ from the target platform
  # (`flag?`) during cross-compilation.
  #
  # ```
  # {{ host_flag?(:win32) }} # true or false
  # ```
  def host_flag?(name) : BoolLiteral
  end

  # Parses *type_name* into a `Path`, `Generic` (also used for unions), `ProcNotation`, or `Metaclass`.
  #
  # The `#resolve` method could then be used to resolve the value into a `TypeNode`, if the *type_name* represents a type,
  # otherwise the value of the constant.
  #
  # A compile time error is raised if the type/constant does not actually exist,
  # or if a required generic argument was not provided.
  #
  # ```
  # class Foo; end
  #
  # struct Some::Namespace::Foo; end
  #
  # module Bar(T); end
  #
  # MY_CONST = 1234
  #
  # {{ parse_type("Foo").resolve.class? }}                                   # => true
  # {{ parse_type("Some::Namespace::Foo").resolve.struct? }}                 # => true
  # {{ parse_type("Foo|Some::Namespace::Foo").resolve.union_types.size }}    # => 2
  # {{ parse_type("Bar(Int32)|Foo").resolve.union_types[0].type_vars.size }} # => 1
  # {{ parse_type("MY_CONST").resolve }}                                     # => 1234
  #
  # {{ parse_type("MissingType").resolve }}   # Error: undefined constant MissingType
  # {{ parse_type("UNKNOWN_CONST").resolve }} # Error: undefined constant UNKNOWN_CONST
  # ```
  def parse_type(type_name : StringLiteral) : Path | Generic | ProcNotation | Metaclass
  end

  # Prints AST nodes at compile-time. Useful for debugging macros.
  def puts(*expressions) : Nop
  end

  # Prints AST nodes at compile-time. Useful for debugging macros.
  def print(*expressions) : Nop
  end

  # Same as `puts`.
  def p(*expressions) : Nop
  end

  # Same as `puts`.
  def pp(*expressions) : Nop
  end

  # Prints macro expressions together with their values at compile-time. Useful for debugging macros.
  def p!(*expressions) : Nop
  end

  # Same as `p!`
  def pp!(*expressions) : Nop
  end

  # Executes a system command and returns the output as a `MacroId`.
  # Gives a compile-time error if the command failed to execute.
  #
  # It is impossible to call this method with any regular call syntax. There is an associated literal type which calls the method with the literal content as command:
  #
  # ```
  # {{ `echo hi` }} # => "hi\n"
  # ```
  #
  # See [`Command` literals](https://crystal-lang.org/reference/syntax_and_semantics/literals/command.html) in the language reference.
  def `(command) : MacroId
  end

  # Executes a system command and returns the output as a `MacroId`.
  # Gives a compile-time error if the command failed to execute.
  #
  # ```
  # {{ system("echo hi") }} # => "hi\n"
  # ```
  def system(command) : MacroId
  end

  # Gives a compile-time error with the given *message*.
  def raise(message) : NoReturn
  end

  # Emits a compile-time warning with the given *message*.
  def warning(message : StringLiteral) : NilLiteral
  end

  # Returns `true` if the given *filename* exists, `false` otherwise.
  def file_exists?(filename) : BoolLiteral
  end

  # Reads a file and returns a `StringLiteral` with its contents.
  #
  # Gives a compile-time error if the file doesn't exist or if
  # reading the file fails.
  #
  # To read a file relative to where the macro is defined, use:
  #
  # ```
  # read_file("#{__DIR__}/some_file.txt")
  # ```
  #
  # NOTE: Relative paths are resolved to the current working directory.
  def read_file(filename) : StringLiteral
  end

  # Same as `read_file`, except that `nil` is returned on any I/O failure
  # instead of issuing a compile-time failure.
  def read_file?(filename) : StringLiteral | NilLiteral
  end

  # Compiles and execute a Crystal program and returns its output
  # as a `MacroId`.
  #
  # The file denoted by *filename* must be a valid Crystal program.
  # This macro invocation passes *args* to the program as regular
  # program arguments. This output is the result of this macro invocation,
  # as a `MacroId`.
  #
  # The `run` macro is useful when the subset of available macro methods
  # are not enough for your purposes and you need something more powerful.
  # With `run` you can read files at compile time, connect to the internet
  # or to a database.
  #
  # A simple example:
  #
  # ```
  # # read.cr
  # puts File.read(ARGV[0])
  # ```
  #
  # ```
  # # main.cr
  # macro read_file_at_compile_time(filename)
  #   {{ run("./read", filename).stringify }}
  # end
  #
  # puts read_file_at_compile_time("some_file.txt")
  # ```
  #
  # The above generates a program that will have the contents of `some_file.txt`.
  # The file, however, is read at compile time and will not be needed at runtime.
  #
  # NOTE: the compiler is allowed to cache the executable generated for
  # *filename* and only recompile it if any of the files it depends on changes
  # (their modified time). This is why it's **strongly discouraged** to use a program
  # for `run` that changes in subsequent compilations (for example, if it executes
  # shell commands at compile time, or other macro run programs). It's also strongly
  # discouraged to have a macro run program take a lot of time, because this will
  # slow down compilation times. Reading files is OK, opening an HTTP connection
  # at compile-time will most likely result in very slow compilations.
  def run(filename, *args) : MacroId
  end

  # Skips the rest of the file from which it is executed.
  # Typical usage is to skip files that have platform specific code,
  # without having to surround the most relevant code in `{% if flag?(...) %} ... {% end %}` macro blocks.
  #
  # Example:
  #
  # ```
  # # sth_for_osx.cr
  # {% skip_file unless flag?(:darwin) %}
  #
  # # Class FooForMac will only be defined if we're compiling on OS X
  # class FooForMac
  # end
  # ```
  def skip_file : Nop
  end

  # This is the base class of all AST nodes. This methods are
  # available to all AST nodes.
  abstract class ASTNode
    # Returns this node as a `MacroId`. Useful when you need an identifier
    # out of a `StringLiteral`, `SymbolLiteral`, `Var` or `Call`.
    #
    # ```
    # macro define_method(name, content)
    #   def {{name.id}}
    #     {{content}}
    #   end
    # end
    #
    # define_method :foo, 1
    # define_method "bar", 2
    # define_method baz, 3
    #
    # puts foo # => prints 1
    # puts bar # => prints 2
    # puts baz # => prints 3
    # ```
    def id : MacroId
    end

    # Returns a `StringLiteral` that contains this node's textual representation.
    # Note that invoking stringify on a string literal will return a `StringLiteral`
    # that contains a string literal.
    #
    # ```
    # macro test
    #   {{ "foo".stringify }}
    # end
    #
    # puts test # prints "foo" (including the double quotes)
    # ```
    def stringify : StringLiteral
    end

    # Returns a `SymbolLiteral` that contains this node's textual representation.
    #
    # ```
    # {{ "foo".id.symbolize }} # => :foo
    # ```
    def symbolize : SymbolLiteral
    end

    # Returns a `StringLiteral` that contains this node's name.
    #
    # ```
    # macro test
    #   {{ "foo".class_name }}
    # end
    #
    # puts test # => prints StringLiteral
    # ```
    def class_name : StringLiteral
    end

    # Returns the filename where this node is located.
    # Might return `nil` if the location is not known.
    def filename : StringLiteral | NilLiteral
    end

    # Returns the line number where this node begins.
    # Might return `nil` if the location is not known.
    #
    # The first line number in a file is 1.
    def line_number : StringLiteral | NilLiteral
    end

    # Returns the column number where this node begins.
    # Might return `nil` if the location is not known.
    #
    # The first column number in a line is `1`.
    def column_number : StringLiteral | NilLiteral
    end

    # Returns the line number where this node ends.
    # Might return `nil` if the location is not known.
    #
    # The first line number in a file is `1`.
    def end_line_number : StringLiteral | NilLiteral
    end

    # Returns the column number where this node ends.
    # Might return `nil` if the location is not known.
    #
    # The first column number in a line is `1`.
    def end_column_number : StringLiteral | NilLiteral
    end

    # Returns `true` if this node's textual representation is the same as
    # the *other* node.
    def ==(other : ASTNode) : BoolLiteral
    end

    # Returns `true` if this node's textual representation is not the same as
    # the *other* node.
    def !=(other : ASTNode) : BoolLiteral
    end

    # Gives a compile-time error with the given *message*.
    # This will highlight this node in the error message.
    def raise(message) : NoReturn
    end

    # Emits a compile-time warning with the given *message*.
    # This will highlight this node in the warning message.
    def warning(message : StringLiteral) : NilLiteral
    end

    # Returns a `StringLiteral` that contains the documentation comments attached to this node, or an empty string if there are none.
    #
    # WARNING: The return value will be an empty string when executed outside of the `crystal docs` command.
    def doc : StringLiteral
    end

    # Returns a `MacroId` that contains the documentation comments attached to this node, or an empty `MacroId` if there are none.
    # Each line is prefixed with a `#` character to allow the output to be used directly within another node's documentation comment.
    #
    # A common use case is combining this method with the `@caller` macro instance variable in order to allow [merging macro expansion and call comments](https://crystal-lang.org/reference/syntax_and_semantics/macros/index.html#merging-expansion-and-call-comments).
    #
    # WARNING: The return value will be empty when executed outside of the `crystal docs` command.
    def doc_comment : MacroId
    end

    # Returns `true` if this node's type is the given *type* or any of its
    # subclasses.
    #
    # *type* always refers to an AST node type, never a type in the program.
    #
    # ```
    # {{ 1.is_a?(NumberLiteral) }} # => true
    # {{ 1.is_a?(BoolLiteral) }}   # => false
    # {{ 1.is_a?(ASTNode) }}       # => true
    # {{ 1.is_a?(Int32) }}         # => false
    # ```
    def __crystal_pseudo_is_a?(type : TypeNode) : BoolLiteral
    end

    # Returns `true` if this node is a `NilLiteral` or `Nop`.
    def __crystal_pseudo_nil? : BoolLiteral
    end
  end

  # The empty node. Similar to a `NilLiteral` but its textual representation
  # is the empty string. This corresponds, for example, to the missing `else` branch of
  # an `if` without an `else`.
  class Nop < ASTNode
  end

  # The nil literal.
  class NilLiteral < ASTNode
  end

  # A bool literal.
  class BoolLiteral < ASTNode
  end

  # Any number literal.
  class NumberLiteral < ASTNode
    # Compares this node's value to another node's value.
    def <(other : NumberLiteral) : BoolLiteral
    end

    # :ditto:
    def <=(other : NumberLiteral) : BoolLiteral
    end

    # :ditto:
    def >(other : NumberLiteral) : BoolLiteral
    end

    # :ditto:
    def >=(other : NumberLiteral) : BoolLiteral
    end

    # :ditto:
    def <=>(other : NumberLiteral) : NumberLiteral
    end

    # Same as `Number#+`
    def +(other : NumberLiteral) : NumberLiteral
    end

    # Same as `Number#-`
    def -(other : NumberLiteral) : NumberLiteral
    end

    # Same as `Number#*`
    def *(other : NumberLiteral) : NumberLiteral
    end

    # MathInterpreter only works with Integer and Number#/ : Float
    #
    # # Same as `Number#/`
    # def /(other : NumberLiteral) : NumberLiteral
    # end

    # Same as `Number#//`
    def //(other : NumberLiteral) : NumberLiteral
    end

    # Same as `Number#%`
    def %(other : NumberLiteral) : NumberLiteral
    end

    # Same as `Number#&`
    def &(other : NumberLiteral) : NumberLiteral
    end

    # Same as `Number#|`
    def |(other : NumberLiteral) : NumberLiteral
    end

    # Same as `Number#^`
    def ^(other : NumberLiteral) : NumberLiteral
    end

    # Same as `Number#**`
    def **(other : NumberLiteral) : NumberLiteral
    end

    # Same as `Number#<<`
    def <<(other : NumberLiteral) : NumberLiteral
    end

    # Same as `Number#>>`
    def >>(other : NumberLiteral) : NumberLiteral
    end

    # Same as `Number#+`
    def + : NumberLiteral
    end

    # Same as `Number#-`
    def - : NumberLiteral
    end

    # Same as `Number#~`
    def ~ : NumberLiteral
    end

    # The type of the literal: `:i32`, `:u16`, `:f32`, `:f64`, etc.
    def kind : SymbolLiteral
    end

    # Returns the value of this number without a type suffix.
    def to_number : MacroId
    end
  end

  # A character literal.
  class CharLiteral < ASTNode
    # Returns a `MacroId` for this character's contents.
    def id : MacroId
    end

    # Similar to `Char#ord`.
    def ord : NumberLiteral
    end
  end

  # A string literal.
  class StringLiteral < ASTNode
    def_string_methods StringLiteral

    # Similar to `String#>`
    def >(other : StringLiteral | MacroId) : BoolLiteral
    end

    # Similar to `String#<`
    def <(other : StringLiteral | MacroId) : BoolLiteral
    end
  end

  # An interpolated string like `"Hello, #{name}!"`.
  class StringInterpolation < ASTNode
    # Returns a list of expressions that comprise the interpolated string.
    #
    # These alternate between `StringLiteral` for the plaintext parts and
    # `ASTNode`s of any type for the interpolated expressions.
    def expressions : ArrayLiteral(ASTNode)
    end
  end

  # A symbol literal.
  class SymbolLiteral < ASTNode
    def_string_methods SymbolLiteral
  end

  # An array literal.
  class ArrayLiteral < ASTNode
    # Similar to `Enumerable#any?`
    def any?(&) : BoolLiteral
    end

    # Similar to `Enumerable#all?`
    def all?(&) : BoolLiteral
    end

    # Returns a `MacroId` with all of this array's elements joined
    # by commas.
    #
    # If *trailing_string* is given, it will be appended to
    # the result unless this array is empty. This lets you
    # splat an array and optionally write a trailing comma
    # if needed.
    def splat(trailing_string : StringLiteral = nil) : MacroId
    end

    # Similar to `Array#clear`
    def clear : ArrayLiteral
    end

    # Similar to `Array#empty?`
    def empty? : BoolLiteral
    end

    # Similar to `Enumerable#find`
    def find(&) : ASTNode | NilLiteral
    end

    # Similar to `Array#first`, but returns a `NilLiteral` if the array is empty.
    def first : ASTNode | NilLiteral
    end

    # Similar to `Enumerable#includes?(obj)`.
    def includes?(node : ASTNode) : BoolLiteral
    end

    # Similar to `Enumerable#join`
    def join(separator) : StringLiteral
    end

    # Similar to `Array#last`, but returns a `NilLiteral` if the array is empty.
    def last : ASTNode | NilLiteral
    end

    # Similar to `Array#size`
    def size : NumberLiteral
    end

    # Similar to `Enumerable#map`
    def map(&) : ArrayLiteral
    end

    # Similar to `Enumerable#map_with_index`
    def map_with_index(&) : ArrayLiteral
    end

    # Similar to `Array#each`
    def each(&) : Nil
    end

    # Similar to `Enumerable#each_with_index`
    def each_with_index(&) : Nil
    end

    # Similar to `Enumerable#select`
    def select(&) : ArrayLiteral
    end

    # Similar to `Enumerable#reject`
    def reject(&) : ArrayLiteral
    end

    # Similar to `Enumerable#reduce`
    def reduce(&) : ASTNode
    end

    # Similar to `Enumerable#reduce`
    def reduce(memo : ASTNode, &) : ASTNode
    end

    # Similar to `Array#shuffle`
    def shuffle : ArrayLiteral
    end

    # Similar to `Array#sort`
    def sort : ArrayLiteral
    end

    # Similar to `Array#sort_by`
    def sort_by(&) : ArrayLiteral
    end

    # Similar to `Array#uniq`
    def uniq : ArrayLiteral
    end

    # Similar to `Array#[]`, but returns `NilLiteral` on out of bounds.
    def [](index : NumberLiteral) : ASTNode
    end

    # Similar to `Array#[]`.
    def [](index : RangeLiteral) : ArrayLiteral(ASTNode)
    end

    # Similar to `Array#[]=`.
    def []=(index : NumberLiteral, value : ASTNode) : ASTNode
    end

    # Similar to `Array#unshift`.
    def unshift(value : ASTNode) : ArrayLiteral
    end

    # Similar to `Array#push`.
    def push(value : ASTNode) : ArrayLiteral
    end

    # Similar to `Array#<<`.
    def <<(value : ASTNode) : ArrayLiteral
    end

    # Similar to `Array#+`.
    def +(other : ArrayLiteral) : ArrayLiteral
    end

    # Similar to `Array#-`.
    def -(other : ArrayLiteral) : ArrayLiteral
    end

    # Returns the type specified at the end of the array literal, if any.
    #
    # This refers to the part after brackets in `[] of String`.
    def of : ASTNode | Nop
    end

    # Returns the type that receives the items of the array.
    #
    # This refers to the part before brackets in `MyArray{1, 2, 3}`
    def type : Path | Nop
    end
  end

  # A hash literal.
  class HashLiteral < ASTNode
    # Similar to `Hash#clear`
    def clear : HashLiteral
    end

    # Similar to `Hash#delete`
    def delete(key : ASTNode) : HashLiteral
    end

    # Similar to `Hash#each`
    def each(&) : Nil
    end

    # Similar to `Hash#empty?`
    def empty? : BoolLiteral
    end

    # Similar to `Hash#keys`
    def keys : ArrayLiteral
    end

    # Similar to `Hash#size`
    def size : NumberLiteral
    end

    # Similar to `Hash#to_a`
    def to_a : ArrayLiteral(TupleLiteral)
    end

    # Similar to `Hash#values`
    def values : ArrayLiteral
    end

    # Similar to `Hash#map`
    def map : ArrayLiteral
    end

    # Similar to `Hash#[]?`
    def [](key : ASTNode) : ASTNode
    end

    # Similar to `Hash#[]=`
    def []=(key : ASTNode, value : ASTNode) : ASTNode
    end

    # Similar to `Hash#has_hey?`
    def has_key?(key : ASTNode) : BoolLiteral
    end

    # Returns the type specified at the end of the Hash literal, if any.
    #
    # This refers to the key type after brackets in `{} of String => Int32`.
    def of_key : ASTNode | Nop
    end

    # Returns the type specified at the end of the Hash literal, if any.
    #
    # This refers to the value type after brackets in `{} of String => Int32`.
    def of_value : ASTNode | Nop
    end

    # Returns the type that receives the items of the array.
    #
    # This refers to the part before brackets in `MyHash{'a' => 1, 'b' => 2}`
    def type : Path | Nop
    end

    # Returns a `MacroId` with all of this hash elements joined
    # by commas.
    #
    # If *trailing_string* is given, it will be appended to
    # the result unless this hash is empty. This lets you
    # splat a hash and optionally write a trailing comma
    # if needed.
    def double_splat(trailing_string : StringLiteral = nil) : MacroId
    end
  end

  # A named tuple literal.
  class NamedTupleLiteral < ASTNode
    # Similar to `Hash#delete`.
    def delete(key : StringLiteral | SymbolLiteral) : NamedTupleLiteral
    end

    # Similar to `NamedTuple#each`
    def each(&) : Nil
    end

    # Similar to `NamedTuple#each_with_index`
    def each_with_index(&) : Nil
    end

    # Similar to `NamedTuple#empty?`
    def empty? : BoolLiteral
    end

    # Similar to `NamedTuple#keys`
    def keys : ArrayLiteral
    end

    # Similar to `NamedTuple#size`
    def size : NumberLiteral
    end

    # Similar to `NamedTuple#to_a`
    def to_a : ArrayLiteral(TupleLiteral)
    end

    # Similar to `NamedTuple#values`
    def values : ArrayLiteral
    end

    # Similar to `NamedTuple#map`
    def map : ArrayLiteral
    end

    # Similar to `HashLiteral#double_splat`
    def double_splat(trailing_string : StringLiteral = nil) : MacroId
    end

    # Similar to `NamedTuple#[]` but returns `NilLiteral` if *key* is undefined.
    def [](key : SymbolLiteral | StringLiteral | MacroId) : ASTNode
    end

    # Adds or replaces a key.
    def []=(key : SymbolLiteral | StringLiteral | MacroId, value : ASTNode) : ASTNode
    end

    # Similar to `NamedTuple#has_key?`
    def has_key?(key : SymbolLiteral | StringLiteral | MacroId) : ASTNode
    end
  end

  # A range literal.
  class RangeLiteral < ASTNode
    # Similar to `Range#begin`
    def begin : ASTNode
    end

    # Similar to `Range#each`
    def each(&) : Nil
    end

    # Similar to `Range#end`
    def end : ASTNode
    end

    # Similar to `Range#excludes_end?`
    def excludes_end? : ASTNode
    end

    # Similar to `Enumerable#map` for a `Range`.
    # Only works on ranges of `NumberLiteral`s considered as integers.
    def map(&) : ArrayLiteral
    end

    # Similar to `Enumerable#to_a` for a `Range`.
    # Only works on ranges of `NumberLiteral`s considered as integers.
    def to_a : ArrayLiteral
    end
  end

  # A regular expression literal.
  class RegexLiteral < ASTNode
    # Similar to `Regex#source`.
    def source : StringLiteral | StringInterpolation
    end

    # Similar to `Regex#options`,
    # but returns an array of symbols such as `[:i, :m, :x]`
    def options : ArrayLiteral(SymbolLiteral)
    end
  end

  # A tuple literal.
  #
  # Its macro methods are nearly the same as `ArrayLiteral`.
  class TupleLiteral < ASTNode
    # Similar to `Enumerable#any?`
    def any?(&) : BoolLiteral
    end

    # Similar to `Enumerable#all?`
    def all?(&) : BoolLiteral
    end

    # Returns a `MacroId` with all of this tuple's elements joined
    # by commas.
    #
    # If *trailing_string* is given, it will be appended to
    # the result unless this tuple is empty. This lets you
    # splat a tuple and optionally write a trailing comma
    # if needed.
    def splat(trailing_string : StringLiteral = nil) : MacroId
    end

    # Similar to `Tuple#empty?`
    def empty? : BoolLiteral
    end

    # Similar to `Enumerable#find`
    def find(&) : ASTNode | NilLiteral
    end

    # Similar to `Tuple#first`, but returns a `NilLiteral` if the tuple is empty.
    def first : ASTNode | NilLiteral
    end

    # Similar to `Enumerable#includes?(obj)`.
    def includes?(node : ASTNode) : BoolLiteral
    end

    # Similar to `Enumerable#join`
    def join(separator) : StringLiteral
    end

    # Similar to `Tuple#last`, but returns a `NilLiteral` if the tuple is empty.
    def last : ASTNode | NilLiteral
    end

    # Similar to `Tuple#size`
    def size : NumberLiteral
    end

    # Similar to `Enumerable#map`
    def map(&) : TupleLiteral
    end

    # Similar to `Enumerable#map_with_index`
    def map_with_index(&) : TupleLiteral
    end

    # Similar to `Tuple#each`
    def each(&) : Nil
    end

    # Similar to `Enumerable#each_with_index`
    def each_with_index(&) : Nil
    end

    # Similar to `Enumerable#select`
    def select(&) : TupleLiteral
    end

    # Similar to `Enumerable#reject`
    def reject(&) : TupleLiteral
    end

    # Similar to `Enumerable#reduce`
    def reduce(&) : ASTNode
    end

    # Similar to `Enumerable#reduce`
    def reduce(memo : ASTNode, &) : ASTNode
    end

    # Similar to `Array#shuffle`
    def shuffle : TupleLiteral
    end

    # Similar to `Array#sort`
    def sort : TupleLiteral
    end

    # Similar to `Array#sort_by`
    def sort_by(&) : TupleLiteral
    end

    # Similar to `Array#uniq`
    def uniq : TupleLiteral
    end

    # Similar to `Tuple#[]`, but returns `NilLiteral` on out of bounds.
    def [](index : NumberLiteral) : ASTNode
    end

    # Similar to `Tuple#[]`.
    def [](index : RangeLiteral) : TupleLiteral(ASTNode)
    end

    # Similar to `Array#[]=`.
    def []=(index : NumberLiteral, value : ASTNode) : ASTNode
    end

    # Similar to `Array#unshift`.
    def unshift(value : ASTNode) : TupleLiteral
    end

    # Similar to `Array#push`.
    def push(value : ASTNode) : TupleLiteral
    end

    # Similar to `Array#<<`.
    def <<(value : ASTNode) : TupleLiteral
    end

    # Similar to `Tuple#+`.
    def +(other : TupleLiteral) : TupleLiteral
    end

    # Similar to `Array#-`.
    def -(other : TupleLiteral) : TupleLiteral
    end
  end

  # A fictitious node representing a variable or instance
  # variable, together with type information.
  class MetaVar < ASTNode
    # Returns the name of this variable.
    def name : MacroId
    end

    # Returns the type of this variable, if known, or `nil`.
    def type : TypeNode | NilLiteral
    end

    # Returns the default value of this variable.
    # Note that if the variable doesn't have a default value,
    # or the default value is `nil`, a `NilLiteral` will be
    # returned. To distinguish between these cases, use
    # `has_default_value?`.
    def default_value : ASTNode
    end

    # Returns whether this variable has a default value
    # (which can in turn be `nil`).
    def has_default_value? : BoolLiteral
    end

    # Returns the last `Annotation` with the given `type`
    # attached to this variable or `NilLiteral` if there are none.
    def annotation(type : TypeNode) : Annotation | NilLiteral
    end

    # Returns an array of annotations with the given `type`
    # attached to this variable, or an empty `ArrayLiteral` if there are none.
    def annotations(type : TypeNode) : ArrayLiteral(Annotation)
    end

    # Returns an array of all annotations attached to this
    # variable, or an empty `ArrayLiteral` if there are none.
    def annotations : ArrayLiteral(Annotation)
    end
  end

  # An annotation on top of a type or variable.
  class Annotation < ASTNode
    # Returns the name of this annotation.
    def name : Path
    end

    # Returns the value of a positional argument,
    # or NilLiteral if out of bounds.
    def [](index : NumberLiteral) : ASTNode
    end

    # Returns the value of a named argument,
    # or NilLiteral if the named argument isn't
    # used on `self`.
    def [](name : SymbolLiteral | StringLiteral | MacroId) : ASTNode
    end

    # Returns a `TupleLiteral` representing the positional arguments on `self`.
    def args : TupleLiteral
    end

    # Returns a `NamedTupleLiteral` representing the named arguments on `self`.
    def named_args : NamedTupleLiteral
    end
  end

  # A local variable or block argument.
  class Var < ASTNode
    # Returns this var's name as a `MacroId`.
    def id : MacroId
    end
  end

  # A code block.
  class Block < ASTNode
    # Returns the block's body, if any.
    def body : ASTNode
    end

    # Returns the blocks arguments.
    def args : ArrayLiteral(MacroId)
    end

    # Returns the index of the argument with a *splat, if any.
    def splat_index : NumberLiteral | NilLiteral
    end
  end

  # A group of expressions.
  class Expressions < ASTNode
    # Returns the list of expressions in this node
    def expressions : ArrayLiteral(ASTNode)
    end
  end

  # A method call.
  class Call < ASTNode
    # Returns this call's name as a `MacroId`.
    def id : MacroId
    end

    # Returns the method name of this call.
    def name : MacroId
    end

    # Returns this call's receiver, if any.
    def receiver : ASTNode | Nop
    end

    # Returns `true` if this call refers to a global method (starts with `::`).
    def global? : BoolLiteral
    end

    # Returns this call's arguments.
    def args : ArrayLiteral
    end

    # Returns this call's named arguments.
    def named_args : ArrayLiteral(NamedArgument)
    end

    # Returns this call's block, if any.
    def block : Block | Nop
    end

    # Returns this call's block argument, if any
    def block_arg : ASTNode | Nop
    end
  end

  # A call's named argument.
  class NamedArgument < ASTNode
    # Returns this named argument name.
    def name : MacroId
    end

    # Returns this named argument value.
    def value : ASTNode
    end
  end

  # An if expression.
  class If < ASTNode
    # Returns this if's condition.
    def cond : ASTNode
    end

    # Returns this if's `then` clause's body.
    def then : ASTNode
    end

    # Returns this if's `else` clause's body.
    def else : ASTNode
    end
  end

  # class Unless < ASTNode
  # end

  # Assign expression.
  class Assign < ASTNode
    # Returns the target assigned to.
    def target : ASTNode
    end

    # Returns the value that is being assigned.
    def value : ASTNode
    end
  end

  # Multiple assign expression.
  class MultiAssign < ASTNode
    # Returns the targets assigned to.
    def targets : ArrayLiteral(ASTNode)
    end

    # Returns the values that are being assigned.
    def values : ArrayLiteral(ASTNode)
    end
  end

  # An instance variable.
  class InstanceVar < ASTNode
    # Returns the name of this variable.
    def name : MacroId
    end
  end

  # Access to an instance variable, e.g. `obj.@var`.
  class ReadInstanceVar < ASTNode
    # Returns the object whose variable is being accessed.
    def obj : ASTNode
    end

    # Returns the name of the instance variable being accessed.
    def name : MacroId
    end
  end

  # A class variable.
  class ClassVar < ASTNode
    # Returns the name of this variable.
    def name : MacroId
    end
  end

  # A global variable.
  class Global < ASTNode
    # Returns the name of this variable.
    def name : MacroId
    end
  end

  # A binary expression like `And` and `Or`.
  abstract class BinaryOp < ASTNode
    # Returns the left hand side of this node.
    def left : ASTNode
    end

    # Returns the left hand side of this node.
    def right : ASTNode
    end
  end

  # An `&&` (and) expression
  class And < BinaryOp
  end

  # An `||` (or) expression
  class Or < BinaryOp
  end

  # A def argument.
  class Arg < ASTNode
    # Returns the last `Annotation` with the given `type`
    # attached to this arg or `NilLiteral` if there are none.
    def annotation(type : TypeNode) : Annotation | NilLiteral
    end

    # Returns an array of annotations with the given `type`
    # attached to this arg, or an empty `ArrayLiteral` if there are none.
    def annotations(type : TypeNode) : ArrayLiteral(Annotation)
    end

    # Returns an array of all annotations attached to this
    # arg, or an empty `ArrayLiteral` if there are none.
    def annotations : ArrayLiteral(Annotation)
    end

    # Returns the external name of this argument.
    #
    # For example, for `def write(to file)` returns `to`.
    def name : MacroId
    end

    # Returns the internal name of this argument.
    #
    # For example, for `def write(to file)` returns `file`.
    def internal_name : MacroId
    end

    # Returns the default value of this argument, if any.
    def default_value : ASTNode | Nop
    end

    # Returns the type restriction of this argument, if any.
    def restriction : ASTNode | Nop
    end
  end

  # The type of a proc or block argument, like `String -> Int32`.
  class ProcNotation < ASTNode
    # Returns the argument types, or an empty list if no arguments.
    def inputs : ArrayLiteral(ASTNode)
    end

    # Returns the output type, or nil if there is no return type.
    def output : ASTNode | NilLiteral
    end

    # Resolves this proc notation to a `TypeNode` if it denotes a type,
    # or otherwise gives a compile-time error.
    def resolve : ASTNode
    end

    # Resolves this proc notation to a `TypeNode` if it denotes a type,
    # or otherwise returns a `NilLiteral`.
    def resolve? : ASTNode | NilLiteral
    end
  end

  # A method definition.
  class Def < ASTNode
    # Returns the name of this method.
    def name : MacroId
    end

    # Returns the arguments of this method.
    def args : ArrayLiteral(Arg)
    end

    # Returns the index of the argument with a *splat, if any.
    def splat_index : NumberLiteral | NilLiteral
    end

    # Returns the double splat argument, if any.
    def double_splat : Arg | Nop
    end

    # Returns the block argument, if any.
    def block_arg : Arg | Nop
    end

    # Returns `true` if this method can be called with a block, `false` otherwise.
    def accepts_block? : BoolLiteral
    end

    # Returns the return type of the method, if specified.
    def return_type : ASTNode | Nop
    end

    # Returns the free variables of this method, or an empty `ArrayLiteral` if
    # there are none.
    def free_vars : ArrayLiteral(MacroId)
    end

    # Returns the body of this method.
    def body : ASTNode
    end

    # Returns the receiver (for example `self`) of this method definition,
    # or `Nop` if not specified.
    def receiver : ASTNode | Nop
    end

    # Returns `true` is this method is declared as abstract, `false` otherwise.
    def abstract? : BoolLiteral
    end

    # Returns the visibility of this def: `:public`, `:protected` or `:private`.
    def visibility : SymbolLiteral
    end

    # Returns the last `Annotation` with the given `type`
    # attached to this method or `NilLiteral` if there are none.
    def annotation(type : TypeNode) : Annotation | NilLiteral
    end

    # Returns an array of annotations with the given `type`
    # attached to this method, or an empty `ArrayLiteral` if there are none.
    def annotations(type : TypeNode) : ArrayLiteral(Annotation)
    end

    # Returns an array of all annotations attached to this
    # method, or an empty `ArrayLiteral` if there are none.
    def annotations : ArrayLiteral(Annotation)
    end
  end

  # A fictitious node representing the body of a `Def` marked with
  # `@[Primitive]`.
  class Primitive < ASTNode
    # Returns the name of the primitive.
    #
    # This is identical to the argument to the associated `@[Primitive]`
    # annotation.
    #
    # ```
    # module Foo
    #   @[Primitive(:abc)]
    #   def foo
    #   end
    # end
    #
    # {{ Foo.methods.first.body.name }} # => :abc
    # ```
    def name : SymbolLiteral
    end
  end

  # A macro definition.
  class Macro < ASTNode
    # Returns the name of this macro.
    def name : MacroId
    end

    # Returns the arguments of this macro.
    def args : ArrayLiteral(Arg)
    end

    # Returns the index of the argument with a *splat, if any.
    def splat_index : NumberLiteral | NilLiteral
    end

    # Returns the double splat argument, if any.
    def double_splat : Arg | Nop
    end

    # Returns the block argument, if any.
    def block_arg : Arg | Nop
    end

    # Returns the body of this macro.
    def body : ASTNode
    end

    # Returns the visibility of this macro: `:public`, `:protected` or `:private`.
    def visibility : SymbolLiteral
    end
  end

  # An unary expression
  abstract class UnaryExpression < ASTNode
    # Returns the expression that this unary operation is applied to.
    def exp : ASTNode
    end
  end

  # An unary `not` (`!`).
  class Not < UnaryExpression
  end

  # A `pointerof` expression.
  class PointerOf < UnaryExpression
  end

  # A `sizeof` expression.
  #
  # Every expression `node` is equivalent to:
  #
  # ```
  # sizeof({{ node.exp }})
  # ```
  class SizeOf < UnaryExpression
  end

  # An `instance_sizeof` expression.
  #
  # Every expression `node` is equivalent to:
  #
  # ```
  # instance_sizeof({{ node.exp }})
  # ```
  class InstanceSizeOf < UnaryExpression
  end

  # A `alignof` expression.
  #
  # Every expression `node` is equivalent to:
  #
  # ```
  # alignof({{ node.exp }})
  # ```
  class AlignOf < UnaryExpression
  end

  # An `instance_alignof` expression.
  #
  # Every expression `node` is equivalent to:
  #
  # ```
  # instance_alignof({{ node.exp }})
  # ```
  class InstanceAlignOf < UnaryExpression
  end

  # An `out` expression.
  class Out < UnaryExpression
  end

  # A splat expression: `*exp`.
  class Splat < UnaryExpression
  end

  # A double splat expression: `**exp`.
  class DoubleSplat < UnaryExpression
  end

  # An `offsetof` expression.
  class OffsetOf < ASTNode
    # Returns the type that has been used in this `offsetof` expression.
    def type : ASTNode
    end

    # Returns the offset argument used in this `offsetof` expression.
    def offset : ASTNode
    end
  end

  # A visibility modifier
  class VisibilityModifier < ASTNode
    # Returns the visibility of this modifier: `:public`, `:protected` or `:private`.
    def visibility : SymbolLiteral
    end

    # Returns the expression that the modifier is applied to.
    def exp : ASTNode
    end
  end

  # An `.is_a?` or `.nil?` call.
  class IsA < ASTNode
    # Returns this call's receiver.
    def receiver : ASTNode
    end

    # Returns this call's argument.
    def arg : ASTNode
    end
  end

  # A `.responds_to?` call.
  class RespondsTo < ASTNode
    # Returns this call's receiver.
    def receiver : ASTNode
    end

    # Returns the method name that is being checked for.
    def name : StringLiteral
    end
  end

  # A `require` statement.
  class Require < ASTNode
    # Returns the argument of the `require`.
    def path : StringLiteral
    end
  end

  # A `when` or `in` inside a `case` or `select`.
  class When < ASTNode
    # Returns the conditions of this `when`.
    def conds : ArrayLiteral
    end

    # Returns the body of this `when`.
    def body : ASTNode
    end

    # Returns `true` if this is an `in`, or `false` if this is a `when`.
    def exhaustive? : BoolLiteral
    end
  end

  # A `case` expression.
  class Case < ASTNode
    # Returns the condition (target) of this `case`.
    def cond : ASTNode
    end

    # Returns the `when`s of this `case`.
    def whens : ArrayLiteral(When)
    end

    # Returns the `else` of this `case`.
    def else : ASTNode
    end

    # Returns whether this `case` is exhaustive (`case ... in`).
    def exhaustive? : BoolLiteral
    end
  end

  # A `select` expression.
  #
  # Every expression `node` is equivalent to:
  #
  # ```
  # select
  # {% for when_clause in node.whens %}
  #   {{ when_clause }}
  # {% end %}
  # {% else_clause = node.else %}
  # {% unless else_clause.is_a?(Nop) %}
  #   else
  #     {{ else_clause }}
  # {% end %}
  # end
  # ```
  class Select < ASTNode
    # Returns the `when`s of this `select`.
    def whens : ArrayLiteral(When)
    end

    # Returns the `else` of this `select`.
    def else : ASTNode
    end
  end

  # Node that represents an implicit object in:
  #
  #     case foo
  #     when .bar? # this is a call with an implicit object
  #     end
  class ImplicitObj < ASTNode
  end

  # A Path to a constant or type, like `Foo` or `Foo::Bar::Baz`.
  class Path < ASTNode
    # Returns an array with each separate part of this path.
    def names : ArrayLiteral(MacroId)
    end

    # Returns `true` if this is a global path (starts with `::`)
    def global? : BoolLiteral
    end

    # Returns `true` if this is a global path (starts with `::`)
    @[Deprecated("Use `#global?` instead")]
    def global : BoolLiteral
    end

    # Resolves this path to a `TypeNode` if it denotes a type, to
    # the value of a constant if it denotes a constant, or otherwise
    # gives a compile-time error.
    def resolve : ASTNode
    end

    # Resolves this path to a `TypeNode` if it denotes a type, to
    # the value of a constant if it denotes a constant, or otherwise
    # returns a `NilLiteral`.
    def resolve? : ASTNode | NilLiteral
    end

    # Returns this path inside an array literal.
    # This method exists so you can call `types` on the type of a type
    # declaration and get all types, whether it's a Generic, Path or Union.
    def types : ArrayLiteral(ASTNode)
    end
  end

  # A class definition.
  #
  # Every class definition `node` is equivalent to:
  #
  # ```
  # {% begin %}
  #   {% "abstract".id if node.abstract? %} {{ node.kind }} {{ node.name }} {% if superclass = node.superclass %}< {{ superclass }}{% end %}
  #     {{ node.body }}
  #   end
  # {% end %}
  # ```
  class ClassDef < ASTNode
    # Returns whether this node defines an abstract class or struct.
    def abstract? : BoolLiteral
    end

    # Returns the keyword used to define this type.
    #
    # For `ClassDef` this is either `class` or `struct`.
    def kind : MacroId
    end

    # Returns the name of this type definition.
    #
    # If this node defines a generic type, and *generic_args* is true, returns a
    # `Generic` whose type arguments are `MacroId`s, possibly with a `Splat` at
    # the splat index. Otherwise, this method returns a `Path`.
    def name(*, generic_args : BoolLiteral = true) : Path | Generic
    end

    # Returns the superclass of this type definition, or a `Nop` if one isn't
    # specified.
    def superclass : ASTNode
    end

    # Returns the body of this type definition.
    def body : ASTNode
    end

    # Returns an array of `MacroId`s of this type definition's generic type
    # parameters.
    #
    # On a non-generic type definition, returns an empty array.
    def type_vars : ArrayLiteral
    end

    # Returns the splat index of this type definition's generic type parameters.
    #
    # Returns `nil` if this type definition isn't generic or if there isn't a
    # splat parameter.
    def splat_index : NumberLiteral | NilLiteral
    end

    # Returns `true` if this node defines a struct, `false` if this node defines
    # a class.
    def struct? : BoolLiteral
    end
  end

  # A module definition.
  #
  # Every module definition `node` is equivalent to:
  #
  # ```
  # {% begin %}
  #   {{ node.kind }} {{ node.name }}
  #     {{ node.body }}
  #   end
  # {% end %}
  # ```
  class ModuleDef < ASTNode
    # Returns the keyword used to define this type.
    #
    # For `ModuleDef` this is always `module`.
    def kind : MacroId
    end

    # Returns the name of this type definition.
    #
    # If this node defines a generic type, and *generic_args* is true, returns a
    # `Generic` whose type arguments are `MacroId`s, possibly with a `Splat` at
    # the splat index. Otherwise, this method returns a `Path`.
    def name(*, generic_args : BoolLiteral = true) : Path | Generic
    end

    # Returns the body of this type definition.
    def body : ASTNode
    end

    # Returns an array of `MacroId`s of this type definition's generic type
    # parameters.
    #
    # On a non-generic type definition, returns an empty array.
    def type_vars : ArrayLiteral
    end

    # Returns the splat index of this type definition's generic type parameters.
    #
    # Returns `nil` if this type definition isn't generic or if there isn't a
    # splat parameter.
    def splat_index : NumberLiteral | NilLiteral
    end
  end

  # An enum definition.
  #
  # ```
  # {% begin %}
  #   {{ node.kind }} {{ node.name }} {% if base_type = node.base_type %}: {{ base_type }}{% end %}
  #     {{ node.body }}
  #   end
  # {% end %}
  # ```
  class EnumDef < ASTNode
    # Returns the keyword used to define this type.
    #
    # For `EnumDef` this is always `enum`.
    def kind : MacroId
    end

    # Returns the name of this type definition.
    #
    # *generic_args* has no effect. It exists solely to match the interface of
    # other related AST nodes.
    def name(*, generic_args : BoolLiteral = true) : Path
    end

    # Returns the base type of this enum definition, or a `Nop` if one isn't
    # specified.
    def base_type : ASTNode
    end

    # Returns the body of this type definition.
    def body : ASTNode
    end
  end

  # An annotation definition.
  #
  # Every annotation definition `node` is equivalent to:
  #
  # ```
  # {% begin %}
  #   {{ node.kind }} {{ node.name }}
  #     {{ node.body }}
  #   end
  # {% end %}
  # ```
  class AnnotationDef < ASTNode
    # Returns the keyword used to define this type.
    #
    # For `AnnotationDef` this is always `annotation`.
    def kind : MacroId
    end

    # Returns the name of this type definition.
    #
    # *generic_args* has no effect. It exists solely to match the interface of
    # other related AST nodes.
    def name(*, generic_args : BoolLiteral = true) : Path
    end

    # Returns the body of this type definition.
    #
    # Currently this is always a `Nop`, because annotation definitions cannot
    # contain anything at all.
    def body : Nop
    end
  end

  # A lib definition.
  #
  # Every lib definition `node` is equivalent to:
  #
  # ```
  # {% begin %}
  #   {{ node.kind }} {{ node.name }}
  #     {{ node.body }}
  #   end
  # {% end %}
  # ```
  class LibDef < ASTNode
    # Returns the keyword used to define this type.
    #
    # For `LibDef` this is always `lib`.
    def kind : MacroId
    end

    # Returns the name of this type definition.
    #
    # *generic_args* has no effect. It exists solely to match the interface of
    # other related AST nodes.
    def name(*, generic_args : BoolLiteral = true) : Path
    end

    # Returns the body of this type definition.
    def body : ASTNode
    end
  end

  # A struct or union definition inside a lib.
  #
  # Every type definition `node` is equivalent to:
  #
  # ```
  # {% begin %}
  #   {{ node.kind }} {{ node.name }}
  #     {{ node.body }}
  #   end
  # {% end %}
  # ```
  class CStructOrUnionDef < ASTNode
    # Returns whether this node defines a C union.
    def union? : BoolLiteral
    end

    # Returns the keyword used to define this type.
    #
    # For `CStructOrUnionDef` this is either `struct` or `union`.
    def kind : MacroId
    end

    # Returns the name of this type definition.
    #
    # *generic_args* has no effect. It exists solely to match the interface of
    # other related AST nodes.
    def name(*, generic_args : BoolLiteral = true) : Path
    end

    # Returns the body of this type definition.
    def body : ASTNode
    end
  end

  # A function declaration inside a lib, or a top-level C function definition.
  #
  # Every function `node` is equivalent to:
  #
  # ```
  # fun {{ node.name }} {% if real_name = node.real_name %}= {{ real_name }}{% end %}(
  #   {% for arg in node.args %} {{ arg }}, {% end %}
  #   {% if node.variadic? %} ... {% end %}
  # ) {% if return_type = node.return_type %}: {{ return_type }}{% end %}
  # {% if node.has_body? %}
  #   {{ body }}
  # end
  # {% end %}
  # ```
  class FunDef < ASTNode
    # Returns the name of the function in Crystal.
    def name : MacroId
    end

    # Returns the real C name of the function, if any.
    def real_name : StringLiteral | Nop
    end

    # Returns the parameters of the function.
    #
    # This does not include the variadic parameter.
    def args : ArrayLiteral(Arg)
    end

    # Returns whether the function is variadic.
    def variadic? : BoolLiteral
    end

    # Returns the return type of the function, if specified.
    def return_type : ASTNode | Nop
    end

    # Returns the body of the function, if any.
    #
    # Both top-level funs and lib funs may return a `Nop`. Instead, `#has_body?`
    # can be used to distinguish between the two.
    #
    # ```
    # macro body_class(x)
    #   {{ (x.is_a?(LibDef) ? x.body : x).body.class_name }}
    # end
    #
    # body_class(lib MyLib
    #   fun foo
    # end) # => "Nop"
    #
    # body_class(fun foo
    # end) # => "Nop"
    # ```
    def body : ASTNode | Nop
    end

    # Returns whether this function has a body.
    #
    # Top-level funs have a body, whereas lib funs do not.
    #
    # ```
    # macro has_body(x)
    #   {{ (x.is_a?(LibDef) ? x.body : x).has_body? }}
    # end
    #
    # has_body(lib MyLib
    #   fun foo
    # end) # => false
    #
    # has_body(fun foo
    # end) # => true
    # ```
    def has_body? : BoolLiteral
    end
  end

  # A typedef inside a lib.
  #
  # Every typedef `node` is equivalent to:
  #
  # ```
  # type {{ node.name }} = {{ node.type }}
  # ```
  class TypeDef < ASTNode
    # Returns the name of the typedef.
    def name : Path
    end

    # Returns the name of the type this typedef is equivalent to.
    def type : ASTNode
    end
  end

  # An external variable declaration inside a lib.
  #
  # Every variable `node` is equivalent to:
  #
  # ```
  # ${{ node.name }} {% if real_name = node.real_name %}= {{ real_name }}{% end %} : {{ node.type }}
  # ```
  class ExternalVar < ASTNode
    # Returns the name of the variable in Crystal, without the preceding `$`.
    def name : MacroId
    end

    # Returns the real C name of the variable, if any.
    def real_name : StringLiteral | Nop
    end

    # Returns the name of the variable's type.
    def type : ASTNode
    end
  end

  # A `while` expression
  class While < ASTNode
    # Returns this while's condition.
    def cond : ASTNode
    end

    # Returns this while's body.
    def body : ASTNode
    end
  end

  # class Until < ASTNode
  # end

  # A generic instantiation, like `Foo(T)` or `Foo::Bar::Baz(T)`
  class Generic < ASTNode
    # Returns the path to the generic.
    def name : Path
    end

    # Returns the arguments (the type variables) of this instantiation.
    def type_vars : ArrayLiteral(ASTNode)
    end

    # Returns the named arguments of this instantiation, if any.
    def named_args : NamedTupleLiteral | NilLiteral
    end

    # Resolves this generic to a `TypeNode` if it denotes a type,
    # or otherwise gives a compile-time error.
    def resolve : ASTNode
    end

    # Resolves this path to a `TypeNode` if it denotes a type,
    # or otherwise returns a `NilLiteral`.
    def resolve? : ASTNode | NilLiteral
    end

    # Returns this generic inside an array literal.
    # This method exists so you can call `types` on the type of a type
    # declaration and get all types, whether it's a Generic, Path or Union.
    def types : ArrayLiteral(ASTNode)
    end
  end

  # A type declaration like `x : Int32`
  class TypeDeclaration < ASTNode
    # Returns the variable part of the declaration.
    def var : MacroId
    end

    # Returns the type part of the declaration.
    def type : ASTNode
    end

    # The value assigned to the variable, if any.
    def value : ASTNode | Nop
    end
  end

  # An uninitialized variable declaration: `a = uninitialized Int32`
  class UninitializedVar < ASTNode
    # Returns the variable part of the declaration.
    def var : MacroId
    end

    # Returns the type part of the declaration.
    def type : ASTNode
    end
  end

  # A `rescue` clause inside an exception handler.
  class Rescue < ASTNode
    # Returns this `rescue` clause's body.
    def body : ASTNode
    end

    # Returns this `rescue` clause's exception types, if any.
    def types : ArrayLiteral | NilLiteral
    end

    # Returns the variable name of the rescued exception, if any.
    def name : MacroId | Nop
    end
  end

  # A `begin ... end` expression with `rescue`, `else` and `ensure` clauses.
  class ExceptionHandler < ASTNode
    # Returns this exception handler's main body.
    def body : ASTNode
    end

    # Returns this exception handler's `rescue` clauses, if any.
    def rescues : ArrayLiteral(Rescue) | NilLiteral
    end

    # Returns this exception handler's `else` clause body, if any.
    def else : ASTNode | Nop
    end

    # Returns this exception handler's `ensure` clause body, if any.
    def ensure : ASTNode | Nop
    end
  end

  # A proc method, written like:
  # ```
  # ->(arg : String) {
  #   puts arg
  # }
  # ```
  class ProcLiteral < ASTNode
    # Returns the arguments of this proc.
    def args : ArrayLiteral(Arg)
    end

    # Returns the body of this proc.
    def body : ASTNode
    end

    # Returns the return type of this proc, if specified.
    def return_type : ASTNode | Nop
    end
  end

  # A proc pointer, like `->my_var.some_method(String)`
  class ProcPointer < ASTNode
    # Returns the types of the arguments of the proc.
    def args : ArrayLiteral(ASTNode)
    end

    # Returns the receiver of the proc, or nil if the proc is not attached to an object.
    def obj : ASTNode | NilLiteral
    end

    # Returns the name of the method this proc points to.
    def name : MacroId
    end

    # Returns true if this proc pointer refers to a global method (starts with
    # `::` and does not have a receiver).
    def global? : BoolLiteral
    end
  end

  # A type union, like `(Int32 | String)`.
  class Union < ASTNode
    # Resolves this union to a `TypeNode`. Gives a compile-time error
    # if any type inside the union can't be resolved.
    def resolve : ASTNode
    end

    # Resolves this union to a `TypeNode`. Returns a `NilLiteral`
    # if any type inside the union can't be resolved.
    def resolve? : ASTNode | NilLiteral
    end

    # Returns the types of this union.
    def types : ArrayLiteral(ASTNode)
    end
  end

  # The `self` expression. May appear in code, such as in an instance method,
  # and in type names.
  class Self < ASTNode
  end

  # The base class of control expressions.
  abstract class ControlExpression < ASTNode
    # Returns the argument to this control expression, if any.
    #
    # If multiple arguments are present, they are wrapped inside a single
    # `TupleLiteral`.
    def exp : ASTNode | Nop
    end
  end

  # A `return` expression.
  class Return < ControlExpression
  end

  # A `break` expression.
  class Break < ControlExpression
  end

  # A `next` expression.
  class Next < ControlExpression
  end

  # A `yield` expression.
  class Yield < ASTNode
    # Returns the arguments to this `yield`.
    def expressions : ArrayLiteral
    end

    # Returns the scope of this `yield`, if any.
    #
    # This refers to the part after `with` in a `with ... yield` expression.
    def scope : ASTNode | Nop
    end
  end

  # An `include` statement.
  #
  # Every statement `node` is equivalent to:
  #
  # ```
  # include {{ node.name }}
  # ```
  class Include < ASTNode
    # Returns the name of the type being included.
    def name : ASTNode
    end
  end

  # An `extend` statement.
  #
  # Every statement `node` is equivalent to:
  #
  # ```
  # extend {{ node.name }}
  # ```
  class Extend < ASTNode
    # Returns the name of the type being extended.
    def name : ASTNode
    end
  end

  # An `alias` statement.
  #
  # Every statement `node` is equivalent to:
  #
  # ```
  # alias {{ node.name }} = {{ node.type }}
  # ```
  class Alias < ASTNode
    # Returns the name of the alias.
    def name : Path
    end

    # Returns the name of the type this alias is equivalent to.
    def type : ASTNode
    end
  end

  # A metaclass in a type expression: `T.class`
  class Metaclass < ASTNode
    # Returns the node representing the instance type of this metaclass.
    def instance : ASTNode
    end

    # Resolves this metaclass to a `TypeNode` if it denotes a type,
    # or otherwise gives a compile-time error.
    def resolve : ASTNode
    end

    # Resolves this metaclass to a `TypeNode` if it denotes a type,
    # or otherwise returns a `NilLiteral`.
    def resolve? : ASTNode | NilLiteral
    end
  end

  # A cast call: `obj.as(to)`
  class Cast < ASTNode
    # Returns the object part of the cast.
    def obj : ASTNode
    end

    # Returns the target type of the cast.
    def to : ASTNode
    end
  end

  # A cast call: `obj.as?(to)`
  class NilableCast < ASTNode
    # Returns the object part of the cast.
    def obj : ASTNode
    end

    # Returns the target type of the cast.
    def to : ASTNode
    end
  end

  # A `typeof` expression.
  #
  # Every expression *node* is equivalent to:
  #
  # ```
  # typeof({{ node.args.splat }})
  # ```
  class TypeOf < ASTNode
    # Returns the arguments to this `typeof`.
    def args : ArrayLiteral(ASTNode)
    end
  end

  # A macro expression.
  #
  # Every expression *node* is equivalent to:
  #
  # ```
  # {% if node.output? %}
  #   \{{ {{ node.exp }} }}
  # {% else %}
  #   \{% {{ node.exp }} %}
  # {% end %}
  # ```
  class MacroExpression < ASTNode
    # Returns the expression inside this node.
    def exp : ASTNode
    end

    # Returns whether this node interpolates the expression's result.
    def output? : BoolLiteral
    end
  end

  # Free text that is part of a macro.
  class MacroLiteral < ASTNode
    # Returns the text of the literal.
    def value : MacroId
    end
  end

  # An `if`/`unless` inside a macro, e.g.
  #
  # ```
  # {% if cond %}
  #   puts "Then"
  # {% else %}
  #   puts "Else"
  # {% end %}
  #
  # {% unless cond %}
  #   puts "Then"
  # {% else %}
  #   puts "Else"
  # {% end %}
  # ```
  class MacroIf < ASTNode
    # The condition of the `if` clause.
    def cond : ASTNode
    end

    # The `then` branch of the `if`.
    def then : ASTNode
    end

    # The `else` branch of the `if`.
    def else : ASTNode
    end

    # Returns `true` if this node represents an `unless` conditional, otherwise returns `false`.
    def is_unless? : BoolLiteral
    end
  end

  # A `for` loop inside a macro, e.g.
  #
  # ```
  # {% for x in exp %}
  #   puts {{x}}
  # {% end %}
  # ```
  class MacroFor < ASTNode
    # The variables declared after `for`.
    def vars : ArrayLiteral(Var)
    end

    # The expression after `in`.
    def exp : ASTNode
    end

    # The body of the `for` loop.
    def body : ASTNode
    end
  end

  # A macro fresh variable.
  #
  # Every variable `node` is equivalent to:
  #
  # ```
  # {{ "%#{name}".id }}{% if expressions = node.expressions %}{{ "{#{expressions.splat}}".id }}{% end %}
  # ```
  class MacroVar < ASTNode
    # Returns the name of the fresh variable.
    def name : MacroId
    end

    # Returns the associated indices of the fresh variable.
    def expressions : ArrayLiteral
    end
  end

  # A verbatim expression.
  #
  # Every expression `node` is equivalent to:
  #
  # ```
  # \{% verbatim do %}
  #   {{ node.exp }}
  # \{% end %}
  # ```
  class MacroVerbatim < UnaryExpression
  end

  # The `_` expression. May appear in code, such as an assignment target, and in
  # type names.
  class Underscore < ASTNode
  end

  # A pseudo constant used to provide information about source code location.
  #
  # Usually this node is resolved by the compiler. It appears unresolved when
  # used as a default parameter value:
  #
  # ```
  # # the `__FILE__` here is a `MagicConstant`
  # def foo(file = __FILE__)
  #   # the `__LINE__` here becomes a `NumberLiteral`
  #   __LINE__
  # end
  # ```
  class MagicConstant < ASTNode
  end

  # An inline assembly expression.
  #
  # Every assembly `node` is equivalent to:
  #
  # ```
  # asm(
  #   {{ node.text }} :
  #   {{ node.outputs.splat }} :
  #   {{ node.inputs.splat }} :
  #   {{ node.clobbers.splat }} :
  #   {% if node.volatile? %} "volatile", {% end %}
  #   {% if node.alignstack? %} "alignstack", {% end %}
  #   {% if node.intel? %} "intel", {% end %}
  #   {% if node.can_throw? %} "unwind", {% end %}
  # )
  # ```
  class Asm < ASTNode
    # Returns the template string for this assembly expression.
    def text : StringLiteral
    end

    # Returns an array of output operands for this assembly expression.
    def outputs : ArrayLiteral(AsmOperand)
    end

    # Returns an array of input operands for this assembly expression.
    def inputs : ArrayLiteral(AsmOperand)
    end

    # Returns an array of clobbered register names for this assembly expression.
    def clobbers : ArrayLiteral(StringLiteral)
    end

    # Returns whether the assembly expression contains side effects that are
    # not listed in `#outputs`, `#inputs`, and `#clobbers`.
    def volatile? : BoolLiteral
    end

    # Returns whether the assembly expression requires stack alignment code.
    def alignstack? : BoolLiteral
    end

    # Returns `true` if the template string uses the Intel syntax, `false` if it
    # uses the AT&T syntax.
    def intel? : BoolLiteral
    end

    # Returns whether the assembly expression might unwind the stack.
    def can_throw? : BoolLiteral
    end
  end

  # An output or input operand for an `Asm` node.
  #
  # Every operand `node` is equivalent to:
  #
  # ```
  # {{ node.constraint }}({{ node.exp }})
  # ```
  class AsmOperand < ASTNode
    # Returns the constraint string of this operand.
    def constraint : StringLiteral
    end

    # Returns the associated output or input argument of this operand.
    def exp : ASTNode
    end
  end

  # A fictitious node representing an identifier like, `foo`, `Bar` or `something_else`.
  #
  # The parser doesn't create these nodes. Instead, you create them by invoking `id`
  # on some nodes. For example, invoking `id` on a `StringLiteral` returns a `MacroId`
  # for the string's content. Similarly, invoking ID on a `SymbolLiteral`, `Call`, `Var` and `Path`
  # returns a MacroId for the node's content.
  #
  # This allows you to treat strings, symbols, variables and calls uniformly. For example:
  #
  # ```text
  # macro getter(name)
  #   def {{name.id}}
  #     @{{name.id}}
  #   end
  # end
  #
  # getter unicorns
  # getter :unicorns
  # getter "unicorns"
  # ```
  #
  # All of the above macro calls work because we invoked `id`, and the generated code
  # looks like this:
  #
  # ```
  # def unicorns
  #   @unicorns
  # end
  # ```
  #
  # If we hadn't used `id`, the generated code would have been this:
  #
  # ```text
  # def unicorns
  #   @unicorns
  # end
  #
  # def :unicorns
  #   @:unicorns
  # end
  #
  # def "unicorns"
  #   @"unicorns"
  # end
  # ```
  #
  # The last two definitions are invalid and so will give a compile-time error.
  class MacroId < ASTNode
    def_string_methods MacroId

    # Similar to `String#>`
    def >(other : StringLiteral | MacroId) : BoolLiteral
    end

    # Similar to `String#<`
    def <(other : StringLiteral | MacroId) : BoolLiteral
    end
  end

  # Represents a type in the program, like `Int32` or `String`.
  class TypeNode < ASTNode
    # Returns `true` if `self` is abstract, otherwise `false`.
    #
    # ```
    # module One; end
    #
    # abstract struct Two; end
    #
    # class Three; end
    #
    # abstract class Four; end
    #
    # {{One.abstract?}}   # => false
    # {{Two.abstract?}}   # => true
    # {{Three.abstract?}} # => false
    # {{Four.abstract?}}  # => true
    # ```
    def abstract? : BoolLiteral
    end

    # Returns `true` if `self` is a union type, otherwise `false`.
    #
    # See also: `#union_types`.
    #
    # ```
    # {{String.union?}}              # => false
    # {{String?.union?}}             # => true
    # {{Union(String, Bool).union?}} # => true
    # ```
    def union? : BoolLiteral
    end

    # Returns `true` if `nil` is an instance of `self`, otherwise `false`.
    #
    # ```
    # {{String.nilable?}}                   # => false
    # {{String?.nilable?}}                  # => true
    # {{Union(String, Bool, Nil).nilable?}} # => true
    # {{NoReturn.nilable?}}                 # => false
    # {{Value.nilable?}}                    # => true
    # ```
    def nilable? : BoolLiteral
    end

    # Returns `true` if `self` is a `module`, otherwise `false`.
    #
    # ```
    # module One; end
    #
    # class Two; end
    #
    # struct Three; end
    #
    # {{One.module?}}   # => true
    # {{Two.module?}}   # => false
    # {{Three.module?}} # => false
    # ```
    def module? : BoolLiteral
    end

    # Returns `true` if `self` is a `class`, otherwise `false`.
    #
    # ```
    # module One; end
    #
    # class Two; end
    #
    # struct Three; end
    #
    # {{One.class?}}   # => false
    # {{Two.class?}}   # => true
    # {{Three.class?}} # => false
    # ```
    def class? : BoolLiteral
    end

    # Returns `true` if `self` is a `struct`, otherwise `false`.
    #
    # ```
    # module One; end
    #
    # class Two; end
    #
    # struct Three; end
    #
    # {{One.struct?}}   # => false
    # {{Two.struct?}}   # => false
    # {{Three.struct?}} # => true
    # ```
    def struct? : BoolLiteral
    end

    # Returns the types forming a union type, if this is a union type.
    # Otherwise returns this single type inside an array literal (so you can safely call `union_types` on any type and treat all types uniformly).
    #
    # See also: `#union?`.
    def union_types : ArrayLiteral(TypeNode)
    end

    # Returns the fully qualified name of this type.  Optionally without *generic_args* if `self` is a generic type; see `#type_vars`.
    #
    # ```
    # class Foo(T); end
    #
    # module Bar::Baz; end
    #
    # {{Bar::Baz.name}}                 # => Bar::Baz
    # {{Foo.name}}                      # => Foo(T)
    # {{Foo.name(generic_args: false)}} # => Foo
    # ```
    def name(*, generic_args : BoolLiteral = true) : MacroId
    end

    # Returns the type variables of the generic type. If the type is not
    # generic, an empty array is returned.
    def type_vars : ArrayLiteral(TypeNode)
    end

    # Returns the instance variables of this type.
    # Can only be called from within methods (not top-level code), otherwise will return an empty list.
    def instance_vars : ArrayLiteral(MetaVar)
    end

    # Returns the class variables of this type.
    def class_vars : ArrayLiteral(MetaVar)
    end

    # Returns all ancestors of this type.
    def ancestors : ArrayLiteral(TypeNode)
    end

    # Returns the direct superclass of this type.
    def superclass : TypeNode | NilLiteral
    end

    # Returns the direct subclasses of this type.
    def subclasses : ArrayLiteral(TypeNode)
    end

    # Returns all the types `self` is directly included in.
    def includers : ArrayLiteral(TypeNode)
    end

    # Returns all subclasses of this type.
    def all_subclasses : ArrayLiteral(TypeNode)
    end

    # Returns the constants and types defined by this type.
    def constants : ArrayLiteral(MacroId)
    end

    # Returns a constant defined in this type.
    #
    # If the constant is a constant (like `A = 1`), then its value
    # as an `ASTNode` is returned. If the constant is a type, the
    # type is returned as a `TypeNode`. Otherwise, `NilLiteral` is returned.
    def constant(name : StringLiteral | SymbolLiteral | MacroId) : ASTNode
    end

    # Returns `true` if this type has a constant. For example `DEFAULT_OPTIONS`
    # (the name you pass to this method is `"DEFAULT_OPTIONS"` or `:DEFAULT_OPTIONS`
    # in this cases).
    def has_constant?(name : StringLiteral | SymbolLiteral) : BoolLiteral
    end

    # Returns the instance methods defined by this type, without including
    # inherited methods.
    def methods : ArrayLiteral(Def)
    end

    # Returns `true` if this type has a method. For example `default_options`
    # (the name you pass to this method is `"default_options"` or `:default_options`
    # in this cases).
    def has_method?(name : StringLiteral | SymbolLiteral) : BoolLiteral
    end

    # Returns the last `Annotation` with the given `type`
    # attached to this type or `NilLiteral` if there are none.
    def annotation(type : TypeNode) : Annotation | NilLiteral
    end

    # Returns an array of annotations with the given `type`
    # attached to this type, or an empty `ArrayLiteral` if there are none.
    def annotations(type : TypeNode) : ArrayLiteral(Annotation)
    end

    # Returns an array of all annotations attached to this
    # type, or an empty `ArrayLiteral` if there are none.
    def annotations : ArrayLiteral(Annotation)
    end

    # Returns the number of elements in this tuple type or tuple metaclass type.
    # Gives a compile error if this is not one of those types.
    def size : NumberLiteral
    end

    # Returns the keys in this named tuple type.
    # Gives a compile error if this is not a named tuple type.
    def keys : ArrayLiteral(MacroId)
    end

    # Returns the type for the given key in this named tuple type.
    # Gives a compile error if this is not a named tuple type.
    def [](key : SymbolLiteral | MacroId) : TypeNode | NilLiteral
    end

    # Returns the class of this type. With this you can, for example, obtain class
    # methods by invoking `type.class.methods`.
    def class : TypeNode
    end

    # Returns the instance type of this type, if it's a class type,
    # or `self` otherwise. This is the opposite of `#class`.
    def instance : TypeNode
    end

    # Determines if `self` overrides any method named *method* from type *type*.
    #
    # ```
    # class Foo
    #   def one
    #     1
    #   end
    #
    #   def two
    #     2
    #   end
    # end
    #
    # class Bar < Foo
    #   def one
    #     11
    #   end
    # end
    #
    # {{ Bar.overrides?(Foo, "one") }} # => true
    # {{ Bar.overrides?(Foo, "two") }} # => false
    # ```
    def overrides?(type : TypeNode, method : StringLiteral | SymbolLiteral | MacroId) : Bool
    end

    # Returns `self`. This method exists so you can safely call `resolve` on a node and resolve it to a type, even if it's a type already.
    def resolve : TypeNode
    end

    # Returns `self`. This method exists so you can safely call `resolve` on a node and resolve it to a type, even if it's a type already.
    def resolve? : TypeNode
    end

    # Return `true` if `self` is private and `false` otherwise.
    def private? : BoolLiteral
    end

    # Return `true` if `self` is public and `false` otherwise.
    def public? : BoolLiteral
    end

    # Returns visibility of `self` as `:public` or `:private?`
    def visibility : SymbolLiteral
    end

    # Returns `true` if *other* is an ancestor of `self`.
    def <(other : TypeNode) : BoolLiteral
    end

    # Returns `true` if `self` is the same as *other* or if
    # *other* is an ancestor of `self`.
    def <=(other : TypeNode) : BoolLiteral
    end

    # Returns `true` if `self` is an ancestor of *other*.
    def >(other : TypeNode) : BoolLiteral
    end

    # Returns `true` if *other* is the same as `self` or if
    # `self` is an ancestor of *other*.
    def >=(other : TypeNode) : BoolLiteral
    end

    # Returns whether `self` contains any inner pointers.
    #
    # Primitive types, except `Void`, are expected to not contain inner pointers.
    # `Proc` and `Pointer` contain inner pointers.
    # Unions, structs and collection types (tuples, static arrays)
    # have inner pointers if any of their contained types has inner pointers.
    # All other types, including classes, are expected to contain inner pointers.
    #
    # Types that do not have inner pointers may opt to use atomic allocations,
    # i.e. `GC.malloc_atomic` rather than `GC.malloc`. The compiler ensures
    # that, for any type `T`:
    #
    # * `Pointer(T).malloc` is atomic if and only if `T` has no inner pointers;
    # * `T.allocate` is atomic if and only if `T` is a reference type and
    #   `ReferenceStorage(T)` has no inner pointers.
    # NOTE: Like `#instance_vars` this method must be called from within a method. The result may be incorrect when used in top-level code.
    def has_inner_pointers? : BoolLiteral
    end
  end
end
