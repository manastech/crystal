require "llvm"
require "json"
require "./types"

module Crystal
  # A program contains all types and top-level methods related to one
  # compilation of a program.
  #
  # It also carries around all information needed to compile a bunch
  # of files: the unions, the symbols used, all global variables,
  # all required files, etc. Because of this, a Program is usually passed
  # around in every step of a compilation to record and query this information.
  #
  # In a way, a Program is an alternative implementation to having global variables
  # for all of this data, but modeled this way one can easily test and exercise
  # programs because each one has its own definition of the types created,
  # methods instantiated, etc.
  #
  # Additionally, a Program acts as a regular type (a module) that can have
  # types (the top-level types) and methods (the top-level methods), and which
  # can also include other modules (this happens when you do `include Module`
  # at the top-level).
  class Program < NonGenericModuleType
    include DefInstanceContainer

    # All symbols (:foo, :bar) found in the program
    getter symbols = Set(String).new

    # Hash that prevents recursive splat expansions. For example:
    #
    # ```
    # def foo(*x)
    #   foo(x)
    # end
    #
    # foo(1)
    # ```
    #
    # Here x will be {Int32}, then {{Int32}}, etc.
    #
    # The way we detect this is by remembering the types of the splat,
    # associated to a def's object id (the UInt64), and on an instantiation
    # we compare the new type with the previous ones and check if they all
    # contain each other once the method is invoked a number of times recursively
    # (currently 5 times or more).
    getter splat_expansions : Hash(Def, Array(Type)) = ({} of Def => Array(Type)).compare_by_identity

    # All FileModules indexed by their filename.
    # These store file-private defs, and top-level variables in files other
    # than the main file.
    getter file_modules = {} of String => FileModule

    # Types that have instance vars initializers which need to be visited
    # (transformed) by `CleanupTransformer` once the semantic analysis finishes.
    #
    # TODO: this probably isn't needed and we can just traverse all types at the
    # end, and analyze all instance variables initializers that we found. This
    # should simplify a bit of code.
    getter after_inference_types = Set(Type).new

    # Top-level variables found in a program (only in the main file).
    getter vars = MetaVars.new

    # If `true`, doc comments are attached to types and methods.
    property? wants_doc = false

    # If `true`, error messages can be colorized
    property? color = true

    # All required files. The set stores absolute files. This way
    # files loaded by `require` nodes are only processed once.
    getter requires = Set(String).new

    # All created unions in a program, indexed by an array of opaque
    # ids of each type in the union. The array (the key) is sorted
    # by this opaque id.
    #
    # A program caches them this way so a union of `String | Int32`
    # or `Int32 | String` is represented by a single, unique type
    # in the program.
    getter unions = {} of Array(UInt64) => UnionType

    # A String pool to avoid creating the same strings over and over.
    # This pool is passed to the parser, macro expander, etc.
    getter string_pool = StringPool.new

    record ConstSliceInfo,
      name : String,
      element_type : NumberKind,
      args : Array(ASTNode)

    # All constant slices constructed via the `Slice.literal` primitive.
    getter const_slices = [] of ConstSliceInfo

    # Here we store constants, in the
    # order that they are used. They will be initialized as soon
    # as the program starts, before the main code.
    getter const_initializers = [] of Const

    # The class var initializers stored to be used by the cleanup transformer
    getter class_var_initializers = [] of ClassVarInitializer

    # The constant for ARGC_UNSAFE
    getter! argc : Const

    # The constant for ARGV_UNSAFE
    getter! argv : Const

    # Default standard output to use in a program, while compiling.
    property stdout : IO = STDOUT

    # Whether to show error trace
    property? show_error_trace = false

    # The main filename of this program
    property filename : String?

    # A `ProgressTracker` object which tracks compilation progress.
    property progress_tracker = ProgressTracker.new

    getter codegen_target = Config.host_target

    getter predefined_constants = Array(Const).new

    property compiler : Compiler?

    def initialize
      super(self, self, "main")

      # Every crystal program comes with some predefined types that we initialize here,
      # like Object, Value, Reference, etc.
      types = self.types

      types["Object"] = object = @object = NonGenericClassType.new self, self, "Object", nil
      object.can_be_stored = false
      object.abstract = true

      types["Reference"] = reference = @reference = NonGenericClassType.new self, self, "Reference", object
      reference.can_be_stored = false

      types["Value"] = value = @value = NonGenericClassType.new self, self, "Value", object
      abstract_value_type(value)

      types["Number"] = number = @number = NonGenericClassType.new self, self, "Number", value
      abstract_value_type(number)

      types["NoReturn"] = @no_return = NoReturnType.new self, self, "NoReturn"
      types["Void"] = @void = VoidType.new self, self, "Void"
      types["Nil"] = @nil = NilType.new self, self, "Nil", value, 1
      types["Bool"] = @bool = BoolType.new self, self, "Bool", value, 1
      types["Char"] = @char = CharType.new self, self, "Char", value, 4

      types["Int"] = int = @int = NonGenericClassType.new self, self, "Int", number
      abstract_value_type(int)

      types["Int8"] = @int8 = IntegerType.new self, self, "Int8", int, 1, 1, :i8
      types["UInt8"] = @uint8 = IntegerType.new self, self, "UInt8", int, 1, 2, :u8
      types["Int16"] = @int16 = IntegerType.new self, self, "Int16", int, 2, 3, :i16
      types["UInt16"] = @uint16 = IntegerType.new self, self, "UInt16", int, 2, 4, :u16
      types["Int32"] = @int32 = IntegerType.new self, self, "Int32", int, 4, 5, :i32
      types["UInt32"] = @uint32 = IntegerType.new self, self, "UInt32", int, 4, 6, :u32
      types["Int64"] = @int64 = IntegerType.new self, self, "Int64", int, 8, 7, :i64
      types["UInt64"] = @uint64 = IntegerType.new self, self, "UInt64", int, 8, 8, :u64
      types["Int128"] = @int128 = IntegerType.new self, self, "Int128", int, 16, 9, :i128
      types["UInt128"] = @uint128 = IntegerType.new self, self, "UInt128", int, 16, 10, :u128

      types["Float"] = float = @float = NonGenericClassType.new self, self, "Float", number
      abstract_value_type(float)

      types["Float32"] = @float32 = FloatType.new self, self, "Float32", float, 4, 9
      types["Float64"] = @float64 = FloatType.new self, self, "Float64", float, 8, 10

      types["Symbol"] = @symbol = SymbolType.new self, self, "Symbol", value, 4
      types["Pointer"] = pointer = @pointer = PointerType.new self, self, "Pointer", value, ["T"]
      pointer.struct = true
      pointer.can_be_stored = false

      types["Tuple"] = tuple = @tuple = TupleType.new self, self, "Tuple", value, ["T"]
      tuple.can_be_stored = false

      types["NamedTuple"] = named_tuple = @named_tuple = NamedTupleType.new self, self, "NamedTuple", value, ["T"]
      named_tuple.can_be_stored = false

      types["StaticArray"] = static_array = @static_array = StaticArrayType.new self, self, "StaticArray", value, ["T", "N"]
      static_array.struct = true
      static_array.declare_instance_var("@buffer", static_array.type_parameter("T"))
      static_array.can_be_stored = false

      types["String"] = string = @string = NonGenericClassType.new self, self, "String", reference
      string.declare_instance_var("@bytesize", int32)
      string.declare_instance_var("@length", int32)
      string.declare_instance_var("@c", uint8)

      types["Class"] = klass = @class = MetaclassType.new(self, object, value, "Class")
      klass.can_be_stored = false

      types["Struct"] = struct_t = @struct_t = NonGenericClassType.new self, self, "Struct", value
      abstract_value_type(struct_t)

      types["Enumerable"] = @enumerable = GenericModuleType.new self, self, "Enumerable", ["T"]
      types["Indexable"] = @indexable = GenericModuleType.new self, self, "Indexable", ["T"]

      types["Array"] = @array = GenericClassType.new self, self, "Array", reference, ["T"]
      types["Hash"] = @hash_type = GenericClassType.new self, self, "Hash", reference, ["K", "V"]
      types["Regex"] = @regex = NonGenericClassType.new self, self, "Regex", reference
      types["Range"] = range = @range = GenericClassType.new self, self, "Range", struct_t, ["B", "E"]
      range.struct = true
      types["Slice"] = slice = @slice = GenericClassType.new self, self, "Slice", struct_t, ["T"]
      slice.struct = true

      types["Exception"] = @exception = NonGenericClassType.new self, self, "Exception", reference

      types["Enum"] = enum_t = @enum = NonGenericClassType.new self, self, "Enum", value
      abstract_value_type(enum_t)

      types["Proc"] = @proc = ProcType.new self, self, "Proc", value, ["T", "R"]
      types["Union"] = @union = GenericUnionType.new self, self, "Union", value, ["T"]
      types["Crystal"] = @crystal = NonGenericModuleType.new self, self, "Crystal"

      types["ARGC_UNSAFE"] = @argc = argc_unsafe = Const.new self, self, "ARGC_UNSAFE", Primitive.new("argc", int32)
      types["ARGV_UNSAFE"] = @argv = argv_unsafe = Const.new self, self, "ARGV_UNSAFE", Primitive.new("argv", pointer_of(pointer_of(uint8)))

      argc_unsafe.no_init_flag = true
      argv_unsafe.no_init_flag = true

      predefined_constants << argc_unsafe
      predefined_constants << argv_unsafe

      # Make sure to initialize `ARGC_UNSAFE` and `ARGV_UNSAFE` as soon as the program starts
      const_initializers << argc_unsafe
      const_initializers << argv_unsafe

      types["GC"] = gc = NonGenericModuleType.new self, self, "GC"
      gc.metaclass.as(ModuleType).add_def Def.new("add_finalizer", [Arg.new("object")], Nop.new)

      # Built-in annotations
      types["AlwaysInline"] = @always_inline_annotation = AnnotationType.new self, self, "AlwaysInline"
      types["CallConvention"] = @call_convention_annotation = AnnotationType.new self, self, "CallConvention"
      types["Extern"] = @extern_annotation = AnnotationType.new self, self, "Extern"
      types["Flags"] = @flags_annotation = AnnotationType.new self, self, "Flags"
      types["Link"] = @link_annotation = AnnotationType.new self, self, "Link"
      types["Naked"] = @naked_annotation = AnnotationType.new self, self, "Naked"
      types["NoInline"] = @no_inline_annotation = AnnotationType.new self, self, "NoInline"
      types["Packed"] = @packed_annotation = AnnotationType.new self, self, "Packed"
      types["Primitive"] = @primitive_annotation = AnnotationType.new self, self, "Primitive"
      types["Raises"] = @raises_annotation = AnnotationType.new self, self, "Raises"
      types["ReturnsTwice"] = @returns_twice_annotation = AnnotationType.new self, self, "ReturnsTwice"
      types["ThreadLocal"] = @thread_local_annotation = AnnotationType.new self, self, "ThreadLocal"
      types["Deprecated"] = @deprecated_annotation = AnnotationType.new self, self, "Deprecated"
      types["Experimental"] = @experimental_annotation = AnnotationType.new self, self, "Experimental"

      define_crystal_constants

      # definition in `macros/types.cr`
      define_macro_types
    end

    # Returns a new `Parser` for the given *source*, sharing the string pool and
    # warnings with this program.
    def new_parser(source : String, var_scopes = [Set(String).new])
      Parser.new(source, string_pool, var_scopes, warnings)
    end

    # Returns a `LiteralExpander` useful to expand literal like arrays and hashes
    # into simpler forms.
    getter(literal_expander) { LiteralExpander.new self }

    # Returns a `CrystalPath` for this program.
    getter(crystal_path) { CrystalPath.new(codegen_target: codegen_target) }

    # Returns a `Var` that has `Nil` as a type.
    # This variable is bound to other nodes in the semantic phase for things
    # that need to be nilable, for example to a variable that's only declared
    # in one branch of an `if` expression.
    getter(nil_var) { Var.new("<nil_var>", nil_type) }

    # Defines a predefined constant in the Crystal module, such as BUILD_DATE and VERSION.
    private def define_crystal_constants
      if build_commit = Crystal::Config.build_commit
        build_commit_const = define_crystal_string_constant "BUILD_COMMIT", build_commit
      else
        build_commit_const = define_crystal_nil_constant "BUILD_COMMIT"
      end
      build_commit_const.doc = <<-MD
        The build commit identifier of the Crystal compiler.
        MD

      define_crystal_string_constant "BUILD_DATE", Crystal::Config.date, <<-MD
        The build date of the Crystal compiler.
        MD
      define_crystal_string_constant "CACHE_DIR", CacheDir.instance.dir, <<-MD
        The cache directory configured for the Crystal compiler.

        The value is defined by the environment variable `CRYSTAL_CACHE_DIR` and
        defaults to the user's configured cache directory.
        MD
      define_crystal_string_constant "DEFAULT_PATH", Crystal::Config.path, <<-MD
        The default Crystal path configured in the compiler. This value is baked
        into the compiler and usually points to the accompanying version of the
        standard library.
        MD
      define_crystal_string_constant "DESCRIPTION", Crystal::Config.description, <<-MD
        Full version information of the Crystal compiler. Equivalent to `crystal --version`.
        MD
      define_crystal_string_constant "PATH", Crystal::CrystalPath.default_path, <<-MD
        Colon-separated paths where the compiler searches for required source files.

        The value is defined by the environment variable `CRYSTAL_PATH`
        and defaults to `DEFAULT_PATH`.
        MD
      define_crystal_string_constant "LIBRARY_PATH", Crystal::CrystalLibraryPath.default_path, <<-MD
        Colon-separated paths where the compiler searches for (binary) libraries.

        The value is defined by the environment variables `CRYSTAL_LIBRARY_PATH`.
        MD
      define_crystal_string_constant "VERSION", Crystal::Config.version, <<-MD
        The version of the Crystal compiler.
        MD
      define_crystal_string_constant "LLVM_VERSION", LLVM.version, <<-MD
        The version of LLVM used by the Crystal compiler.
        MD
      define_crystal_string_constant "HOST_TRIPLE", Crystal::Config.host_target.to_s, <<-MD
        The LLVM target triple of the host system (the machine that the compiler runs on).
        MD
      define_crystal_string_constant "TARGET_TRIPLE", Crystal::Config.host_target.to_s, <<-MD
        The LLVM target triple of the target system (the machine that the compiler builds for).
        MD
    end

    private def define_crystal_string_constant(name, value, doc = nil)
      define_crystal_constant name, StringLiteral.new(value).tap(&.set_type(string)), doc
    end

    private def define_crystal_nil_constant(name, doc = nil)
      define_crystal_constant name, NilLiteral.new.tap(&.set_type(self.nil)), doc
    end

    private def define_crystal_constant(name, value, doc = nil) : Const
      crystal.types[name] = const = Const.new self, crystal, name, value
      const.no_init_flag = true
      const.doc = doc

      predefined_constants << const
      const
    end

    property(target_machine : LLVM::TargetMachine) { codegen_target.to_target_machine }

    def codegen_target=(@codegen_target : Codegen::Target) : Codegen::Target
      crystal.types["TARGET_TRIPLE"].as(Const).value.as(StringLiteral).value = codegen_target.to_s
      @codegen_target
    end

    # Returns the `Type` for `Array(type)`
    def array_of(type)
      array.instantiate [type] of TypeVar
    end

    # Returns the `Type` for `Hash(key_type, value_type)`
    def hash_of(key_type, value_type)
      hash_type.instantiate [key_type, value_type] of TypeVar
    end

    # Returns the `Type` for `Range(begin_type, end_type)`
    def range_of(begin_type, end_type)
      range.instantiate [begin_type, end_type] of TypeVar
    end

    # Returns the `Type` for `Tuple(*types)`
    def tuple_of(types)
      type_vars = types.map &.as(TypeVar)
      tuple.instantiate(type_vars)
    end

    # Returns the `Type` for `NamedTuple(**entries)`
    def named_tuple_of(entries : Hash(String, Type) | NamedTuple)
      entries = entries.map { |k, v| NamedArgumentType.new(k.to_s, v.as(Type)) }
      named_tuple_of(entries)
    end

    # :ditto:
    def named_tuple_of(entries : Array(NamedArgumentType))
      named_tuple.instantiate_named_args(entries)
    end

    # Returns the `Type` for `type | Nil`
    def nilable(type)
      case type
      when self.nil, self.no_return
        # Nil | Nil      # => Nil
        # NoReturn | Nil # => Nil
        self.nil
      when UnionType
        types = Array(Type).new(type.union_types.size + 1)
        types.concat type.union_types
        types << self.nil unless types.includes? self.nil
        union_of types
      else
        union_of self.nil, type
      end
    end

    # Returns the `Type` for `type1 | type2`
    def union_of(type1, type2)
      # T | T # => T
      return type1 if type1 == type2

      union_of([type1, type2] of Type).not_nil!
    end

    # Returns the `Type` for `Union(*types)`
    def union_of(types : Array)
      case types.size
      when 0
        nil
      when 1
        types.first
      else
        types.sort_by! &.opaque_id
        opaque_ids = types.map(&.opaque_id)
        unions[opaque_ids] ||= make_union_type(types, opaque_ids)
      end
    end

    private def make_union_type(types, opaque_ids)
      # NilType has opaque_id == 0
      has_nil = opaque_ids.first == 0

      if has_nil
        # Check if it's a Nilable type
        if types.size == 2
          other_type = types[1]
          if other_type.reference_like? && !other_type.virtual?
            return NilableReferenceType.new(self, other_type)
          else
            untyped_type = other_type.remove_typedef
            if untyped_type.proc?
              return NilableProcType.new(self, other_type)
            end
          end
        end

        # Remove the Nil type now and later insert it at the end
        nil_type = types.shift
      end

      # Sort by name so a same union type, say `Int32 | String`, always is named that
      # way, regardless of the actual order of the types. However, we always put
      # Nil at the end, inside the `nil_type` check.
      types.sort_by! &.to_s

      if nil_type
        types.push nil_type

        if types.all?(&.reference_like?)
          return NilableReferenceUnionType.new(self, types)
        else
          return MixedUnionType.new(self, types)
        end
      end

      if types.all? &.reference_like?
        return ReferenceUnionType.new(self, types)
      end

      MixedUnionType.new(self, types)
    end

    # Returns the `Type` for `Proc(*types)`
    def proc_of(types : Array)
      type_vars = types.map &.as(TypeVar)
      unless type_vars.empty?
        type_vars[-1] = self.nil if type_vars[-1].is_a?(VoidType)
      end
      proc.instantiate(type_vars)
    end

    # Returns the `Type` for `Proc(*nodes.map(&.type), return_type)`
    def proc_of(nodes : Array(ASTNode), return_type : Type)
      type_vars = Array(TypeVar).new(nodes.size + 1)
      nodes.each do |node|
        type_vars << node.type
      end
      return_type = self.nil if return_type.void?
      type_vars << return_type
      proc.instantiate(type_vars)
    end

    # Returns the `Type` for `Pointer(type)`
    def pointer_of(type)
      pointer.instantiate([type] of TypeVar)
    end

    # Returns the `Type` for `StaticArray(type, size)`
    def static_array_of(type, size)
      static_array.instantiate([type, NumberLiteral.new(size)] of TypeVar)
    end

    record RecordedRequire, filename : String, relative_to : String? do
      include JSON::Serializable
    end
    property recorded_requires = [] of RecordedRequire

    # Remembers that the program depends on this require.
    def record_require(filename, relative_to) : Nil
      recorded_requires << RecordedRequire.new(filename, relative_to)
    end

    def run_requires(node : Require, filenames, &) : Nil
      dependency_printer = compiler.try(&.dependency_printer)

      filenames.each do |filename|
        unseen_file = requires.add?(filename)

        dependency_printer.try(&.enter_file(filename, unseen_file))

        if unseen_file
          yield filename
        end

        dependency_printer.try(&.leave_file)
      end
    end

    # Finds *filename* in the configured CRYSTAL_PATH for this program,
    # relative to *relative_to*.
    def find_in_path(filename, relative_to = nil) : Array(String)?
      crystal_path.find filename, relative_to
    end

    {% for name in %w(object no_return value number reference void nil bool char int int8 int16 int32 int64 int128
                     uint8 uint16 uint32 uint64 uint128 float float32 float64 string symbol pointer enumerable indexable
                     array static_array exception tuple named_tuple proc union enum range slice regex crystal
                     packed_annotation thread_local_annotation no_inline_annotation
                     always_inline_annotation naked_annotation returns_twice_annotation
                     raises_annotation primitive_annotation call_convention_annotation
                     flags_annotation link_annotation extern_annotation deprecated_annotation experimental_annotation) %}
      def {{name.id}}
        @{{name.id}}.not_nil!
      end
    {% end %}

    # Returns the `Nil` type
    def nil_type
      @nil.not_nil!
    end

    # Returns the `Hash` type
    def hash_type
      @hash_type.not_nil!
    end

    def type_from_literal_kind(kind : NumberKind)
      case kind
      in .i8?   then int8
      in .i16?  then int16
      in .i32?  then int32
      in .i64?  then int64
      in .i128? then int128
      in .u8?   then uint8
      in .u16?  then uint16
      in .u32?  then uint32
      in .u64?  then uint64
      in .u128? then uint128
      in .f32?  then float32
      in .f64?  then float64
      end
    end

    def int_type(signed, size)
      if signed
        case size
        when  1 then int8
        when  2 then int16
        when  4 then int32
        when  8 then int64
        when 16 then int128
        else
          raise "BUG: Invalid int size: #{size}"
        end
      else
        case size
        when  1 then uint8
        when  2 then uint16
        when  4 then uint32
        when  8 then uint64
        when 16 then uint128
        else
          raise "BUG: Invalid int size: #{size}"
        end
      end
    end

    # Returns the `IntegerType` that matches the given Int value
    def int?(int)
      case int
      when Int8    then int8
      when Int16   then int16
      when Int32   then int32
      when Int64   then int64
      when Int128  then int128
      when UInt8   then uint8
      when UInt16  then uint16
      when UInt32  then uint32
      when UInt64  then uint64
      when UInt128 then uint128
      else
        nil
      end
    end

    # Returns the `Struct` type
    def struct
      @struct_t.not_nil!
    end

    # Returns the `Class` type
    def class_type
      @class.not_nil!
    end

    def new_temp_var : Var
      Var.new(new_temp_var_name)
    end

    @temp_var_counter = 0

    def new_temp_var_name
      @temp_var_counter += 1
      "__temp_#{@temp_var_counter}"
    end

    # Colorizes the given object, depending on whether this program
    # is configured to use colors.
    def colorize(obj)
      obj.colorize.toggle(@color)
    end

    private def abstract_value_type(type)
      type.abstract = true
      type.struct = true
      type.can_be_stored = false
    end

    # Next come overrides for the type system

    def metaclass
      self
    end

    def type_desc
      "main"
    end

    def add_def(node : Def)
      if file_module = check_private(node)
        file_module.add_def node
      else
        super
      end
    end

    def add_macro(node : Macro)
      if file_module = check_private(node)
        file_module.add_macro node
      else
        super
      end
    end

    def lookup_private_matches(filename, signature, analyze_all = false)
      file_module?(filename).try &.lookup_matches(signature, analyze_all: analyze_all)
    end

    def file_module?(filename)
      file_modules[filename]?
    end

    def file_module(filename)
      file_modules[filename] ||= FileModule.new(self, self, filename)
    end

    def check_private(node)
      return nil unless node.visibility.private?

      filename = node.location.try &.original_filename
      return nil unless filename

      file_module(filename)
    end

    def to_s(io : IO) : Nil
      io << "<Program>"
    end
  end
end
