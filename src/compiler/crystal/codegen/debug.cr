require "./codegen"

module Crystal
  class CodeGenVisitor
    # workaround for `LLVM::Builder` not being GC'ed (#13250)
    private class DIBuilder
      def initialize(mod : LLVM::Module)
        @builder = LLVM::DIBuilder.new(mod)
      end

      def finalize
        @builder.dispose
      end

      forward_missing_to @builder
    end

    record FunMetadata, filename : String, metadata : LibLLVM::MetadataRef

    alias DebugFilename = Crystal::VirtualFile | String?

    @current_debug_location : Location?

    # We cache these either for performance, memory use, or protection from the GC
    @debug_files_per_module = {} of LLVM::Module => Hash(DebugFilename, LibLLVM::MetadataRef)
    @debug_types_per_module = {} of LLVM::Module => Hash(Type, LibLLVM::MetadataRef?)

    def di_builder(llvm_module = @llvm_mod || @main_mod)
      di_builders = @di_builders ||= {} of LLVM::Module => DIBuilder
      di_builders[llvm_module] ||= DIBuilder.new(llvm_module).tap do |di_builder|
        file, dir = file_and_dir(llvm_module.name == "" ? "main" : llvm_module.name)
        # @debug.variables? is set to true if parameter --debug is set in command line.
        # This flag affects only debug variables generation. It sets Optimized parameter to false.
        is_optimised = !@debug.variables?
        # TODO: switch to Crystal's language code for LLVM 16+ (#13174)
        di_builder.create_compile_unit(LLVM::DwarfSourceLanguage::C_plus_plus, file, dir, "Crystal", is_optimised, "", 0_u32)
      end
    end

    def push_debug_info_metadata(mod)
      di_builder(mod).end

      if @program.has_flag?("msvc")
        # Windows uses CodeView instead of DWARF
        mod.add_flag(LibLLVM::ModuleFlagBehavior::Warning, "CodeView", 1)
      end

      mod.add_flag(
        LibLLVM::ModuleFlagBehavior::Warning,
        "Debug Info Version",
        LLVM::DEBUG_METADATA_VERSION
      )
    end

    def fun_metadatas
      @fun_metadatas ||= {} of LLVM::Function => Array(FunMetadata)
    end

    def fun_metadata_type(debug_types = [] of LibLLVM::MetadataRef)
      if debug_types.empty?
        int = di_builder.create_basic_type("int", 32, 32, LLVM::DwarfTypeEncoding::Signed)
        debug_types << int
      end
      di_builder.create_subroutine_type(nil, debug_types)
    end

    def debug_type_cache
      # We must cache debug types per module so metadata of a type
      # from one module isn't incorrectly used in another module.
      @debug_types_per_module[@llvm_mod] ||= {} of Type => LibLLVM::MetadataRef?
    end

    def debug_files_cache
      # We must cache debug files per module so metadata of a type
      # from one module isn't incorrectly used in another module.
      @debug_files_per_module[@llvm_mod] ||= {} of DebugFilename => LibLLVM::MetadataRef
    end

    private def current_debug_file
      # These debug files are only used for `DIBuilder#create_union_type`, even
      # though they are unneeded here, just as struct types don't need a file;
      # LLVM 12 or below produces an assertion failure that is now removed
      # (https://github.com/llvm/llvm-project/commit/ad60802a7187aa39b0374536be3fa176fe3d6256)
      {% if LibLLVM::IS_LT_130 %}
        filename = @current_debug_location.try(&.filename) || "??"
        debug_files_cache[filename] ||= begin
          file, dir = file_and_dir(filename)
          di_builder.create_file(file, dir)
        end
      {% else %}
        Pointer(Void).null.as(LibLLVM::MetadataRef)
      {% end %}
    end

    def get_debug_type(type, original_type : Type)
      type = type.remove_indirection
      debug_type_cache[original_type] ||= create_debug_type(type, original_type)
    end

    def create_debug_type(type : NilType, original_type : Type)
      di_builder.create_unspecified_type("decltype(nullptr)")
    end

    def create_debug_type(type : VoidType, original_type : Type)
      di_builder.create_basic_type("Void", 8u64 * llvm_typer.pointer_size, 8u64 * llvm_typer.pointer_size, LLVM::DwarfTypeEncoding::Address)
    end

    def create_debug_type(type : CharType, original_type : Type)
      di_builder.create_basic_type("char32_t", 32, 32, LLVM::DwarfTypeEncoding::Utf)
    end

    def create_debug_type(type : IntegerType, original_type : Type)
      di_builder.create_basic_type(type.to_s, type.bits, type.bits,
        type.signed? ? LLVM::DwarfTypeEncoding::Signed : LLVM::DwarfTypeEncoding::Unsigned)
    end

    def create_debug_type(type : SymbolType, original_type : Type)
      di_builder.create_basic_type(type.to_s, 32, 32, LLVM::DwarfTypeEncoding::Unsigned)
    end

    def create_debug_type(type : FloatType, original_type : Type)
      di_builder.create_basic_type(type.to_s, 8u64 * type.bytes, 8u64 * type.bytes, LLVM::DwarfTypeEncoding::Float)
    end

    def create_debug_type(type : BoolType, original_type : Type)
      di_builder.create_basic_type(type.to_s, 8, 8, LLVM::DwarfTypeEncoding::Boolean)
    end

    def create_debug_type(type : EnumType, original_type : Type)
      elements = type.types.map do |name, item|
        str_value = item.as?(Const).try &.value.as?(NumberLiteral).try &.value

        value =
          if type.base_type.kind.unsigned_int?
            str_value.try(&.to_u64?) || 0_u64
          else
            str_value.try(&.to_i64?) || 0_i64
          end

        di_builder.create_enumerator(name, value)
      end

      size_in_bits = type.base_type.kind.bytesize
      align_in_bits = align_of(type.base_type)
      di_builder.create_enumeration_type(nil, original_type.to_s, nil, 1, size_in_bits, align_in_bits, elements, get_debug_type(type.base_type))
    end

    def create_debug_type(type : InstanceVarContainer, original_type : Type)
      ivars = type.all_instance_vars
      element_types = [] of LibLLVM::MetadataRef
      struct_type = llvm_struct_type(type)

      tmp_debug_type = di_builder.create_replaceable_composite_type(nil, original_type.to_s, nil, 1)
      debug_type_cache[original_type] = tmp_debug_type

      ivars.each_with_index do |(name, ivar), idx|
        next if ivar.type.is_a?(NilType)
        if (ivar_type = ivar.type?) && (ivar_debug_type = get_debug_type(ivar_type))
          offset = type.extern_union? ? 0_u64 : @program.target_machine.data_layout.offset_of_element(struct_type, idx &+ (type.struct? ? 0 : 1))
          size = @program.target_machine.data_layout.size_in_bits(llvm_embedded_type(ivar_type))

          member = di_builder.create_member_type(nil, name[1..-1], nil, 1, size, size, 8u64 * offset, LLVM::DIFlags::Zero, ivar_debug_type)
          element_types << member
        end
      end

      size = @program.target_machine.data_layout.size_in_bits(struct_type)
      if type.extern_union?
        debug_type = di_builder.create_union_type(nil, original_type.to_s, current_debug_file, 1, size, size, LLVM::DIFlags::Zero, element_types)
      else
        debug_type = di_builder.create_struct_type(nil, original_type.to_s, nil, 1, size, size, LLVM::DIFlags::Zero, nil, element_types)
        unless type.struct?
          debug_type = di_builder.create_pointer_type(debug_type, 8u64 * llvm_typer.pointer_size, 8u64 * llvm_typer.pointer_size, original_type.to_s)
        end
      end
      di_builder.replace_temporary(tmp_debug_type, debug_type)
      debug_type
    end

    def create_debug_type(type : PointerInstanceType, original_type : Type)
      element_type = get_debug_type(type.element_type)
      return unless element_type
      di_builder.create_pointer_type(element_type, 8u64 * llvm_typer.pointer_size, 8u64 * llvm_typer.pointer_size, original_type.to_s)
    end

    def create_debug_type(type : MixedUnionType, original_type : Type)
      element_types = [] of LibLLVM::MetadataRef
      struct_type = llvm_type(type)
      struct_type_size = @program.target_machine.data_layout.size_in_bits(struct_type)
      is_struct = struct_type.struct_element_types.size == 1

      tmp_debug_type = di_builder.create_replaceable_composite_type(nil, original_type.to_s, nil, 1)
      debug_type_cache[original_type] = tmp_debug_type

      type.expand_union_types.each do |ivar_type|
        next if ivar_type.is_a?(NilType)
        if ivar_debug_type = get_debug_type(ivar_type)
          embedded_type = llvm_type(ivar_type)
          size = @program.target_machine.data_layout.size_in_bits(embedded_type)
          align = align_of(ivar_type)
          member = di_builder.create_member_type(nil, ivar_type.to_s, nil, 1, size, align, 0, LLVM::DIFlags::Zero, ivar_debug_type)
          element_types << member
        end
      end

      size = @program.target_machine.data_layout.size_in_bits(struct_type.struct_element_types[is_struct ? 0 : 1])
      offset = @program.target_machine.data_layout.offset_of_element(struct_type, 1) * 8u64
      debug_type = di_builder.create_union_type(nil, "", current_debug_file, 1, size, size, LLVM::DIFlags::Zero, element_types)
      unless is_struct
        element_types.clear
        element_types << di_builder.create_member_type(nil, "type_id", nil, 1, 32, 32, 0, LLVM::DIFlags::Zero, get_debug_type(@program.uint32))
        element_types << di_builder.create_member_type(nil, "union", nil, 1, size, size, offset, LLVM::DIFlags::Zero, debug_type)
        debug_type = di_builder.create_struct_type(nil, original_type.to_s, nil, 1, struct_type_size, struct_type_size, LLVM::DIFlags::Zero, nil, element_types)
      end
      di_builder.replace_temporary(tmp_debug_type, debug_type)
      debug_type
    end

    def create_debug_type(type : NilableReferenceUnionType | ReferenceUnionType, original_type : Type)
      element_types = [] of LibLLVM::MetadataRef
      struct_type = llvm_type(type)
      tmp_debug_type = di_builder.create_replaceable_composite_type(nil, original_type.to_s, nil, 1)
      debug_type_cache[original_type] = tmp_debug_type

      type.expand_union_types.each do |ivar_type|
        next if ivar_type.is_a?(NilType)
        if ivar_debug_type = get_debug_type(ivar_type)
          embedded_type = llvm_type(ivar_type)
          size = @program.target_machine.data_layout.size_in_bits(embedded_type)
          member = di_builder.create_member_type(nil, ivar_type.to_s, nil, 1, size, size, 0, LLVM::DIFlags::Zero, ivar_debug_type)
          element_types << member
        end
      end

      size = @program.target_machine.data_layout.size_in_bits(struct_type)
      debug_type = di_builder.create_union_type(nil, original_type.to_s, current_debug_file, 1, size, size, LLVM::DIFlags::Zero, element_types)
      di_builder.replace_temporary(tmp_debug_type, debug_type)
      debug_type
    end

    def create_debug_type(type : NilableReferenceType, original_type : Type)
      get_debug_type(type.not_nil_type, original_type)
    end

    def create_debug_type(type : StaticArrayInstanceType, original_type : Type)
      debug_type = get_debug_type(type.element_type)
      return unless debug_type
      subrange = di_builder.get_or_create_array_subrange(0, type.size.as(NumberLiteral).value.to_i)
      di_builder.create_array_type(type.size.as(NumberLiteral).value.to_i, llvm_typer.pointer_size, debug_type, [subrange])
    end

    def create_debug_type(type : TypeDefType, original_type : Type)
      get_debug_type(type.typedef, original_type)
    end

    def create_debug_type(type : TupleInstanceType, original_type : Type)
      ivars = type.tuple_types
      element_types = [] of LibLLVM::MetadataRef
      struct_type = llvm_struct_type(type)

      tmp_debug_type = di_builder.create_replaceable_composite_type(nil, original_type.to_s, nil, 1)
      debug_type_cache[original_type] = tmp_debug_type

      ivars.each_with_index do |ivar_type, idx|
        next if ivar_type.is_a?(NilType)
        if ivar_debug_type = get_debug_type(ivar_type)
          offset = @program.target_machine.data_layout.offset_of_element(struct_type, idx &+ (type.struct? ? 0 : 1))
          size = @program.target_machine.data_layout.size_in_bits(llvm_embedded_type(ivar_type))

          member = di_builder.create_member_type(nil, "[#{idx}]", nil, 1, size, size, 8u64 * offset, LLVM::DIFlags::Zero, ivar_debug_type)
          element_types << member
        end
      end

      size = @program.target_machine.data_layout.size_in_bits(struct_type)
      debug_type = di_builder.create_struct_type(nil, original_type.to_s, nil, 1, size, size, LLVM::DIFlags::Zero, nil, element_types)
      unless type.struct?
        debug_type = di_builder.create_pointer_type(debug_type, 8u64 * llvm_typer.pointer_size, 8u64 * llvm_typer.pointer_size, original_type.to_s)
      end
      di_builder.replace_temporary(tmp_debug_type, debug_type)
      debug_type
    end

    def create_debug_type(type : NamedTupleInstanceType, original_type : Type)
      ivars = type.entries
      element_types = [] of LibLLVM::MetadataRef
      struct_type = llvm_struct_type(type)

      tmp_debug_type = di_builder.create_replaceable_composite_type(nil, original_type.to_s, nil, 1)
      debug_type_cache[original_type] = tmp_debug_type

      ivars.each_with_index do |ivar, idx|
        next if (ivar_type = ivar.type).is_a?(NilType)
        if ivar_debug_type = get_debug_type(ivar_type)
          offset = @program.target_machine.data_layout.offset_of_element(struct_type, idx &+ (type.struct? ? 0 : 1))
          size = @program.target_machine.data_layout.size_in_bits(llvm_embedded_type(ivar_type))

          member = di_builder.create_member_type(nil, ivar.name, nil, 1, size, size, 8u64 * offset, LLVM::DIFlags::Zero, ivar_debug_type)
          element_types << member
        end
      end

      size = @program.target_machine.data_layout.size_in_bits(struct_type)
      debug_type = di_builder.create_struct_type(nil, original_type.to_s, nil, 1, size, size, LLVM::DIFlags::Zero, nil, element_types)
      unless type.struct?
        debug_type = di_builder.create_pointer_type(debug_type, 8u64 * llvm_typer.pointer_size, 8u64 * llvm_typer.pointer_size, original_type.to_s)
      end
      di_builder.replace_temporary(tmp_debug_type, debug_type)
      debug_type
    end

    # This is a sinkhole for debug types that most likely does not need to be implemented
    def create_debug_type(type : NonGenericModuleType | GenericClassInstanceMetaclassType | MetaclassType | NilableProcType | VirtualMetaclassType, original_type : Type)
    end

    def create_debug_type(type, original_type : Type)
      # "Unsupported type for debugging: #{type} (#{type.class}), original_type=#{original_type.to_s}" }
    end

    def get_debug_type(type)
      get_debug_type(type, type)
    end

    def declare_parameter(arg_name, arg_type, arg_no, alloca, location)
      return alloca unless @debug.variables?

      declare_local(arg_type, alloca, location) do |scope, file, line_number, debug_type|
        di_builder.create_parameter_variable scope, arg_name, arg_no, file, line_number, debug_type
      end
    end

    def declare_variable(var_name, var_type, alloca, location, basic_block : LLVM::BasicBlock? = nil)
      return false unless @debug.variables?
      declare_local(var_type, alloca, location, basic_block) do |scope, file, line_number, debug_type|
        di_builder.create_auto_variable scope, var_name, file, line_number, debug_type, align_of(var_type)
      end
    end

    private def align_of(type)
      @program.target_machine.data_layout.abi_alignment(llvm_type(type)) * 8
    end

    private def declare_local(type, alloca, location, basic_block : LLVM::BasicBlock? = nil, &)
      location = location.try &.expanded_location
      return false unless location

      file, dir = file_and_dir(location.filename)
      file = debug_files_cache[location.filename] ||= di_builder.create_file(file, dir)

      debug_type = get_debug_type(type)
      return false unless debug_type

      scope = get_current_debug_scope(location)
      return false unless scope

      var = yield scope, file, location.line_number, debug_type
      expr = di_builder.create_expression(nil, 0)
      if basic_block
        block = basic_block
      else
        block = context.fun.basic_blocks.last? || new_block("alloca")
      end
      old_debug_location = @current_debug_location
      set_current_debug_location location
      if builder.current_debug_location != llvm_nil && (ptr = alloca)
        # FIXME: When debug records are used instead of debug intrinsics, it
        # seems inserting them into an empty BasicBlock will instead place them
        # in a totally different (next?) function where the variable doesn't
        # exist, leading to a "function-local metadata used in wrong function"
        # validation error. This might happen when e.g. all variables inside a
        # block are closured. Ideally every debug record should immediately
        # follow the variable it declares.
        {% unless LibLLVM::IS_LT_190 %}
          call(do_nothing_fun) if block.instructions.empty?
        {% end %}
        di_builder.insert_declare_at_end(ptr, var, expr, builder.current_debug_location_metadata, block)
        set_current_debug_location old_debug_location
        true
      else
        set_current_debug_location old_debug_location
        false
      end
    end

    private def do_nothing_fun
      fetch_typed_fun(@llvm_mod, "llvm.donothing") do
        LLVM::Type.function([] of LLVM::Type, @llvm_context.void)
      end
    end

    # Emit debug info for toplevel variables. Used for the main module and all
    # required files.
    def emit_vars_debug_info(vars)
      return if @debug.none?
      in_alloca_block do
        vars.each do |name, var|
          # If a variable is deduced to have type `NoReturn` it might not be
          # allocated at all
          next unless (llvm_var = context.vars[name]?)
          next if llvm_var.debug_variable_created
          set_current_debug_location var.location
          declare_variable name, var.type, llvm_var.pointer, var.location, alloca_block
        end
        clear_current_debug_location
      end
    end

    def file_and_dir(filename)
      # We should have expanded locations with VirtualFiles in them to
      # the location where they expanded. Debug locations will point
      # to the single line where the macro was expanded. This is not
      # convenient for debugging macro code, but the other solution
      # involves creating temporary files to hold the expanded macro
      # code, but that prevents reusing previous compilations. In
      # any case, macro code *should* be simple so that it doesn't
      # need to be debugged at runtime (because macros work at compile-time.)
      unless filename.is_a?(String)
        raise "BUG: expected debug filename to be a String, not #{filename.class}"
      end

      {
        File.basename(filename), # File
        File.dirname(filename),  # Directory
      }
    end

    def set_current_debug_location(node : ASTNode)
      location = node.location
      if location
        set_current_debug_location(location)
      else
        clear_current_debug_location
      end
    end

    def get_current_debug_scope(location)
      if context.fun.name == MAIN_NAME
        main_scopes = (@main_scopes ||= {} of {String, String} => LibLLVM::MetadataRef)
        file, dir = file_and_dir(location.filename)
        main_scope = main_scopes[{file, dir}] ||= begin
          di_builder = di_builder(@main_mod)
          file = di_builder.create_file(file, dir)
          di_builder.create_lexical_block(fun_metadatas[context.fun][0].metadata, file, 1, 1)
        end
        main_scope
      else
        scope = nil
        if array = fun_metadatas[context.fun]?
          array.each do |scope_pair|
            return scope_pair.metadata if scope_pair.filename == location.filename
          end
          file, dir = file_and_dir(location.filename)
          di_builder = di_builder()
          file_scope = di_builder.create_file(file, dir)
          scope = di_builder.create_lexical_block_file(fun_metadatas[context.fun][0].metadata, file_scope)
          array << FunMetadata.new(location.original_filename || "??", scope)
        end
        scope
      end
    end

    def set_current_debug_location(location)
      location = location.try &.expanded_location
      return unless location

      @current_debug_location = location

      scope = get_current_debug_scope(location)

      if scope
        debug_loc = di_builder.create_debug_location(location.line_number || 1, location.column_number, scope)
        # NOTE: `di_builder.context` is only necessary for LLVM 8
        builder.set_current_debug_location(debug_loc, di_builder.context)
      else
        clear_current_debug_location
      end
    end

    def clear_current_debug_location
      @current_debug_location = nil

      builder.clear_current_debug_location
    end

    def emit_fun_debug_metadata(func, fun_name, location, *, debug_types = [] of LibLLVM::MetadataRef, is_optimized = false)
      filename = location.try(&.original_filename) || "??"
      line_number = location.try(&.line_number) || 0

      file, dir = file_and_dir(filename)
      scope = di_builder.create_file(file, dir)
      fn_metadata = di_builder.create_function(scope, fun_name, fun_name, scope,
        line_number, fun_metadata_type(debug_types), true, true,
        line_number, LLVM::DIFlags::Zero, is_optimized, func)
      fun_metadatas[func] = [FunMetadata.new(filename, fn_metadata)]
    end

    def emit_def_debug_metadata(target_def)
      location = target_def.location.try &.expanded_location
      return unless location

      emit_fun_debug_metadata(context.fun, target_def.name, location,
        debug_types: context.fun_debug_params,
        is_optimized: !@debug.variables?)
    end

    def declare_debug_for_function_argument(arg_name, arg_type, arg_no, alloca, location)
      return alloca unless @debug.variables?
      old_debug_location = @current_debug_location
      set_current_debug_location location
      debug_alloca = alloca alloca.type, "dbg.#{arg_name}"
      store alloca, debug_alloca
      declare_parameter(arg_name, arg_type, arg_no, debug_alloca, location)
      alloca = load alloca.type, debug_alloca
      set_current_debug_location old_debug_location
      alloca
    end
  end
end
