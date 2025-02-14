module Crystal
  class SourceTyper
    # Represents a fully typed definition signature
    record Signature,
      name : String,
      return_type : Crystal::ASTNode,
      location : Crystal::Location,
      args = {} of String => Crystal::ASTNode

    getter program, files

    def initialize(@entrypoint : String,
                   @def_locators : Array(String),
                   @excludes : Array(String),
                   @type_blocks : Bool,
                   @type_splats : Bool,
                   @type_double_splats : Bool,
                   @prelude : String = "prelude",
                   stats : Bool = false,
                   progress : Bool = false,
                   error_trace : Bool = false)
      @entrypoint = File.expand_path(@entrypoint) unless @entrypoint.starts_with?("/")
      @program = Crystal::Program.new
      @files = Set(String).new
      @warnings = [] of String

      @program.progress_tracker.stats = stats
      @program.progress_tracker.progress = progress
      @program.show_error_trace = error_trace
    end

    # Run the entire typing flow, from semantic to file reformatting
    def run : Hash(String, String)
      semantic(@entrypoint, File.read(@entrypoint))

      rets = {} of String => String

      @warnings.each do |warning|
        puts "WARNING: #{warning}"
      end

      @files.each do |file|
        next unless File.file?(file)
        source = File.read(file)
        if typed_source = type_source(file, source)
          rets[file] = typed_source
        end
      end

      rets
    end

    # Take the entrypoint file (and its textual content) and run semantic on it.
    # Semantic results are used to generate signatures for all defs that match
    # at least one def_locator.
    def semantic(entrypoint, entrypoint_content) : Nil
      parser = program.new_parser(entrypoint_content)
      parser.filename = entrypoint
      parser.wants_doc = false
      original_node = parser.parse

      nodes = Crystal::Expressions.from([original_node])

      if !@prelude.empty?
        # Prepend the prelude to the parsed program
        location = Crystal::Location.new(entrypoint, 1, 1)
        nodes = Crystal::Expressions.new([Crystal::Require.new(@prelude).at(location), nodes] of Crystal::ASTNode)
      end

      program.normalize(nodes)

      # And now infer types of everything
      semantic_node = program.semantic nodes, cleanup: true

      # We might run semantic later in an attempt to resolve defaults, don't display those stats or progress
      @program.progress_tracker.stats = false
      @program.progress_tracker.progress = false

      # Use the DefVisitor to locate and match any 'def's that match a def_locator
      def_visitor = DefVisitor.new(@def_locators, @excludes, entrypoint)
      semantic_node.accept(def_visitor)

      # Hash up the location => (parsed) definition.
      # At this point the types have been infeered (from semantic above) and stored in various
      # def_instances in the `program` arg and its types.
      accepted_defs = def_visitor.all_defs.map do |the_def|
        {
          the_def.location.to_s,
          the_def,
        }
      end.to_h
      init_signatures(accepted_defs)

      @files = def_visitor.files
    end

    # Given a (presumably) crystal file and its content, re-format it with the crystal-formatter-that-types-things (SourceTyperFormatter).
    # Returns nil if no type restrictions were added anywhere.
    def type_source(filename, source) : String?
      formatter = SourceTyperFormatter.new(source, signatures)

      parser = program.new_parser(source)
      parser.filename = filename
      parser.wants_doc = false
      original_node = parser.parse

      formatter.skip_space_or_newline
      original_node.accept formatter

      formatter.added_types? ? formatter.finish : nil
    end

    @_signatures : Hash(String, Signature)?

    # Signatures represents a mapping of location => Signature for def at that location
    def signatures : Hash(String, Signature)
      @_signatures || raise "Signatures not properly initialized!"
    end

    # Given `accepted_defs` (location => (parsed) defs that match a def_locator), generated a new hash of
    # location => (typed, multiple) def_instances that match a location.
    #
    # A given parsed def can have multiple def_instances, depending on how the method is called throughout
    # the program, and the types of those calls.
    private def accepted_def_instances(accepted_defs : Hash(String, Crystal::Def)) : Hash(String, Array(Crystal::Def))
      ret = Hash(String, Array(Crystal::Def)).new do |h, k|
        h[k] = [] of Crystal::Def
      end

      # First, check global definitions
      program.def_instances.each do |_, def_instance|
        next unless accepted_defs.keys.includes?(def_instance.location.to_s)

        ret[def_instance.location.to_s] << def_instance
      end

      # Breadth first search time! This list will be a continuously populated queue of all of the types we need
      # to scan, with newly discovered types added to the end of the queue from "parent" (namespace) types.
      types = [] of Crystal::Type

      program.types.each { |_, t| types << t }

      overridden_method_locations = {} of String => String
      while type = types.shift?
        type.types?.try &.each { |_, t| types << t }
        def_overrides_parent_def(type).each do |child_def_loc, ancestor_def_loc|
          overridden_method_locations[child_def_loc] = ancestor_def_loc
        end

        # Check for class instance 'def's
        if type.responds_to?(:def_instances)
          type.def_instances.each do |_, def_instance|
            next unless accepted_defs.keys.includes?(def_instance.location.to_s)

            ret[def_instance.location.to_s] << def_instance
          end
        end

        # Check for class 'self.def's
        metaclass = type.metaclass
        if metaclass.responds_to?(:def_instances)
          metaclass.def_instances.each do |_, def_instance|
            next unless accepted_defs.keys.includes?(def_instance.location.to_s)

            ret[def_instance.location.to_s] << def_instance
          end
        end
      end

      # Now remove all overridden methods
      overridden_method_locations.each do |child_loc, ancestor_loc|
        if ret.delete(child_loc)
          @warnings << "Not adding type restrictions to definition at #{child_loc} as it overrides definition #{ancestor_loc}"
        end
      end

      ret
    end

    private def def_overrides_parent_def(type) : Hash(String, String)
      overriden_locations = {} of String => String
      type.defs.try &.each_value do |defs_with_metadata|
        defs_with_metadata.each do |def_with_metadata|
          next if def_with_metadata.def.location.to_s.starts_with?("expanded macro:") || def_with_metadata.def.name == "initialize"
          type.ancestors.each do |ancestor|
            ancestor_defs_with_metadata = ancestor.defs.try &.[def_with_metadata.def.name]?
            ancestor_defs_with_metadata.try &.each do |ancestor_def_with_metadata|
              next if ancestor_def_with_metadata.def.location.to_s.starts_with?("expanded macro:")
              found_def_with_same_name = true

              if def_with_metadata.compare_strictness(ancestor_def_with_metadata, self_owner: type, other_owner: ancestor) == 0
                overriden_locations[def_with_metadata.def.location.to_s] = ancestor_def_with_metadata.def.location.to_s
                overriden_locations[ancestor_def_with_metadata.def.location.to_s] = def_with_metadata.def.location.to_s
              end
            end
          end
        end
      end
      overriden_locations
    end

    # Given an 'arg', return its type that's good for printing (VirtualTypes suffix themselves with a '+')
    private def resolve_type(arg)
      t = arg.type
      t.is_a?(Crystal::VirtualType) ? t.base_type : t
    end

    # Strip out any NoReturns, or Procs that point to them (maybe all generics? Start with procs)
    private def filter_no_return(types)
      compacted_types = types.to_a.reject! do |type|
        type.no_return? || (type.is_a?(Crystal::ProcInstanceType) && type.as(Crystal::ProcInstanceType).return_type.no_return?)
      end

      compacted_types << program.nil if compacted_types.empty?
      compacted_types
    end

    # Generates a map of (parsed) Def#location => Signature for that Def
    private def init_signatures(accepted_defs : Hash(String, Crystal::Def)) : Hash(String, Signature)
      @_signatures ||= accepted_def_instances(accepted_defs).compact_map do |location, def_instances|
        parsed = accepted_defs[location]

        all_typed_args = Hash(String, Set(Crystal::Type)).new { |h, k| h[k] = Set(Crystal::Type).new }

        # splats only exist in the parsed defs, while the def_instances have all had their splats "exploded".
        # For typing splats, use the parsed defs for splat names and scan def_intances for various arg names that look... splatty.
        safe_splat_index = parsed.splat_index || Int32::MAX
        splat_arg_name = parsed.args[safe_splat_index]?.try &.name.try { |name| name.empty? ? nil : name }
        named_arg_name = parsed.double_splat.try &.name

        encountered_non_splat_arg_def_instance = false
        encountered_non_double_splat_arg_def_instance = false

        def_instances.each do |def_instance|
          encountered_splat_arg = false
          encountered_double_splat_arg = false
          def_instance.args.each do |arg|
            if arg.name == arg.external_name && !arg.name.starts_with?("__temp_")
              # Regular arg
              all_typed_args[arg.external_name] << resolve_type(arg)
            elsif arg.name != arg.external_name && (arg.name.starts_with?("__arg") || !arg.name.starts_with?("__"))
              # Either
              # A class / instance var that used a keword and then got used in a method argument, like:
              # def begin=(@begin)
              # end
              # - OR -
              # A method used an external_name in the argument list, like:
              # def test(external_name real_name)
              # end
              all_typed_args[arg.external_name] << resolve_type(arg)
            elsif @type_splats && (splat_arg = splat_arg_name) && arg.name == arg.external_name && arg.name.starts_with?("__temp_")
              # Splat arg, where the compiler generated a uniq name for it
              encountered_splat_arg = true
              all_typed_args[splat_arg] << resolve_type(arg)
            elsif @type_double_splats && (named_arg = named_arg_name) && arg.name != arg.external_name && arg.name.starts_with?("__temp_")
              # Named splat arg, where an "external" name was retained, but compiler generated uniq name for it
              encountered_double_splat_arg = true
              all_typed_args[named_arg] << resolve_type(arg)
            elsif (!@type_splats || !@type_double_splats) && arg.name.starts_with?("__temp_")
              # Ignore, it didn't fall into one of the above conditions (i.e. typing a particular splat wasn't specified)
            else
              raise "Unknown handling of arg #{arg} at #{def_instance.location} in #{def_instance}\n#{parsed}"
            end
          end

          encountered_non_splat_arg_def_instance |= !encountered_splat_arg
          encountered_non_double_splat_arg_def_instance |= !encountered_double_splat_arg

          if @type_blocks && (arg = def_instance.block_arg)
            all_typed_args[arg.external_name] << resolve_type(arg)
          end
        end

        parsed.args.each do |arg|
          if def_val = arg.default_value
            if def_val.to_s.matches?(/^[A-Z_]+$/)
              # This looks like a constant, let's try qualifying it with the parent type
              def_val = Crystal::Path.new([parsed.owner.to_s, def_val.to_s])
            end
            all_typed_args[arg.external_name] << program.semantic(def_val).type rescue nil
          end
        end

        # If a given collection of def_instances has a splat defined AND at least one def_instance didn't have a type for it,
        # then we can't add types to the signature.
        # https://crystal-lang.org/reference/1.14/syntax_and_semantics/type_restrictions.html#splat-type-restrictions
        if @type_splats && (splat_arg = splat_arg_name) && encountered_non_splat_arg_def_instance
          @warnings << "Not adding type restriction for splat #{splat_arg}, found empty splat call: #{parsed.location}"
          all_typed_args.delete(splat_arg)
        end
        if @type_double_splats && (named_arg = named_arg_name) && encountered_non_double_splat_arg_def_instance
          @warnings << "Not adding type restriction for double splat #{named_arg}, found empty deouble splat call: #{parsed.location}"
          all_typed_args.delete(named_arg)
        end

        # Convert each set of types into a single ASTNode (for easier printing) representing those types
        all_args = all_typed_args.compact_map do |name, type_set|
          compacted_types = filter_no_return(type_set)

          {name, to_ast(compacted_types)}
        end.to_h

        # Similar idea for return_type to get into an easier to print state
        returns = filter_no_return(def_instances.compact_map do |inst|
          resolve_type(inst)
        end.uniq!)

        return_type = to_ast(returns)

        {parsed.location.to_s, Signature.new(
          name: parsed.name,
          return_type: return_type,
          location: parsed.location.not_nil!,
          args: all_args
        )}
      end.to_h
    end

    # Given a list of types, wrap them in a ASTNode appropriate for printing that type out
    private def to_ast(types : Array(Crystal::Type))
      flattened = flatten_types(types)
      case flattened.size
      when 1
        # Use var to communicate a single type name
        Crystal::Var.new(type_name(flattened[0]))
      when 2
        if flattened.includes?(program.nil)
          # One type is Nil, so write this using the slightly more human readable format with a '?' suffix
          not_nil_type = flattened.reject(&.==(program.nil))[0]
          Crystal::Var.new("#{not_nil_type}?")
        else
          Crystal::Union.new(flattened.map { |t| Crystal::Var.new(type_name(t)).as(Crystal::ASTNode) })
        end
      else
        Crystal::Union.new(flattened.map { |t| Crystal::Var.new(type_name(t)).as(Crystal::ASTNode) })
      end
    end

    def flatten_types(types : Array(Crystal::Type)) : Array(Crystal::Type)
      types.map do |type|
        type.is_a?(Crystal::UnionType) ? flatten_types(type.concrete_types) : type
      end.flatten.uniq
    end

    def type_name(type : Crystal::Type) : String
      type.to_s.gsub(/:Module$/, ".class").gsub("+", "")
    end

    # Child class of the crystal formatter, but will write in type restrictions for the def return_type, or individual args,
    # if there's a signature for a given def and those type restrictions are missing.
    #
    # All methods present are copy / paste from the original Crystal::Formatter for the given `visit` methods
    class SourceTyperFormatter < Crystal::Formatter
      @current_def : Crystal::Def? = nil
      getter? added_types = false

      def initialize(source : String, @signatures : Hash(String, Signature))
        # source = File.read(filename)
        super(source)
      end

      def visit(node : Crystal::Def)
        @implicit_exception_handler_indent = @indent
        @inside_def += 1
        @vars.push Set(String).new

        write_keyword :abstract, " " if node.abstract?

        write_keyword :def, " ", skip_space_or_newline: false

        if receiver = node.receiver
          skip_space_or_newline
          accept receiver
          skip_space_or_newline
          write_token :OP_PERIOD
        end

        @lexer.wants_def_or_macro_name do
          skip_space_or_newline
        end

        write node.name

        indent do
          next_token

          # this formats `def foo # ...` to `def foo(&) # ...` for yielding
          # methods before consuming the comment line
          if node.block_arity && node.args.empty? && !node.block_arg && !node.double_splat
            write "(&)"
          end

          skip_space consume_newline: false
          next_token_skip_space if @token.type.op_eq?
        end

        # ===== BEGIN NEW CODE =====
        # Wrap the format_def_args call with a quick-to-reach reference to the current def (for signature lookup)
        @current_def = node
        to_skip = format_def_args node
        @current_def = nil
        # ===== END NEW CODE =====

        if return_type = node.return_type
          skip_space
          write_token " ", :OP_COLON, " "
          skip_space_or_newline
          accept return_type
          # ===== BEGIN NEW CODE =====
          # If the def doesn't already have a type restriction and we have a signature for this method, write in the return_type
        elsif (sig = @signatures[node.location.to_s]?) && sig.name != "initialize"
          skip_space
          write " : #{sig.return_type}"
          @added_types = true
          # ===== END NEW CODE =====
        end

        if free_vars = node.free_vars
          skip_space_or_newline
          write " forall "
          next_token
          last_index = free_vars.size - 1
          free_vars.each_with_index do |free_var, i|
            skip_space_or_newline
            check :CONST
            write free_var
            next_token
            skip_space_or_newline if last_index != i
            if @token.type.op_comma?
              write ", "
              next_token_skip_space_or_newline
            end
          end
        end

        body = remove_to_skip node, to_skip

        unless node.abstract?
          format_nested_with_end body
        end

        @vars.pop
        @inside_def -= 1

        false
      end

      def visit(node : Crystal::Arg)
        @last_arg_is_skip = false

        restriction = node.restriction
        default_value = node.default_value

        if @inside_lib > 0
          # This is the case of `fun foo(Char)`
          if !@token.type.ident? && restriction
            accept restriction
            return false
          end
        end

        if node.name.empty?
          skip_space_or_newline
        else
          @vars.last.add(node.name)

          at_skip = at_skip?

          if !at_skip && node.external_name != node.name
            if node.external_name.empty?
              write "_"
            elsif @token.type.delimiter_start?
              accept Crystal::StringLiteral.new(node.external_name)
            else
              write @token.value
            end
            write " "
            next_token_skip_space_or_newline
          end

          @last_arg_is_skip = at_skip?

          write @token.value
          next_token
        end

        if restriction
          skip_space_or_newline
          write_token " ", :OP_COLON, " "
          skip_space_or_newline
          accept restriction
          # ===== BEGIN NEW CODE =====
          # If the current arg doesn't have a restriction already and we have a signature, write in the type restriction
        elsif (sig = @signatures[@current_def.try &.location.to_s || 0_u64]?) && sig.args[node.external_name]?
          skip_space_or_newline
          write " : #{sig.args[node.external_name]}"
          @added_types = true
          # ===== END NEW CODE =====
        end

        if default_value
          # The default value might be a Proc with args, so
          # we need to remember this and restore it later
          old_last_arg_is_skip = @last_arg_is_skip

          skip_space_or_newline

          check_align = check_assign_length node
          write_token " ", :OP_EQ, " "
          before_column = @column
          skip_space_or_newline
          accept default_value
          check_assign_align before_column, default_value if check_align

          @last_arg_is_skip = old_last_arg_is_skip
        end

        # This is the case of an enum member
        if @token.type.op_semicolon?
          next_token
          @lexer.skip_space
          if @token.type.comment?
            write_comment
            @exp_needs_indent = true
          else
            write ";" if @token.type.const?
            write " "
            @exp_needs_indent = @token.type.newline?
          end
        end

        false
      end
    end

    # A visitor for defs, oddly enough.
    #
    # Walk through the AST and capture all references to Defs that match a def_locator
    class DefVisitor < Crystal::Visitor
      getter all_defs = Array(Crystal::Def).new
      getter files = Set(String).new

      CRYSTAL_LOCATOR_PARSER = /^.*\.cr(:(?<line_number>\d+))?(:(?<col_number>\d+))?$/

      @dir_locators : Array(String)
      @file_locators : Array(String) = [] of String
      @line_locators : Array(String) = [] of String
      @line_and_column_locators : Array(String) = [] of String
      @excludes : Array(String)

      def initialize(def_locators : Array(String), excludes : Array(String), entrypoint : String)
        if def_locators.empty?
          # No def_locators provided, default to the directory of entrypoint.
          def_locators << File.dirname(entrypoint)
        end

        def_locs = def_locators.map { |p| File.expand_path(Crystal.normalize_path(p)) }
        @excludes = excludes.map { |p| File.expand_path(Crystal.normalize_path(p)) }
        @dir_locators = def_locs.reject(&.match(CRYSTAL_LOCATOR_PARSER))
        def_locs.compact_map(&.match(CRYSTAL_LOCATOR_PARSER)).each do |loc|
          @file_locators << loc[0] unless loc["line_number"]?
          @line_locators << loc[0] unless loc["col_number"]?
          @line_and_column_locators << loc[0] if loc["line_number"]? && loc["col_number"]?
        end

        @excludes = @excludes - @dir_locators
      end

      def visit(node : Crystal::Def)
        return false unless loc = node.location
        return false unless loc.filename && loc.line_number && loc.column_number
        return false if fully_typed?(node)
        if node_in_def_locators(loc)
          all_defs << node
          files << loc.filename.to_s
        end

        false
      end

      def visit(node : Crystal::ASTNode)
        true
      end

      private def node_in_def_locators(location : Crystal::Location) : Bool
        # location isn't an actual filename (i.e. "expanded macro at ...")
        return false unless location.to_s.starts_with?("/") || location.to_s.starts_with?(/\w:/)

        # Location matched exactly
        return true if @line_and_column_locators.includes?("#{location.filename}:#{location.line_number}:#{location.column_number}")
        return true if @line_locators.includes?("#{location.filename}:#{location.line_number}")
        return true if @file_locators.includes?(location.filename)

        # Check excluded directories before included directories (this assumes excluded directories are children of included directories)
        return false if @excludes.any? { |d| location.filename.to_s.starts_with?(d) }

        return true if @dir_locators.any? { |d| location.filename.to_s.starts_with?(d) }

        # Whelp, nothing matched, skip this location
        false
      end

      # If a def is already fully typed, we don't need to check / write it
      private def fully_typed?(d : Def) : Bool
        ret = true
        ret &= d.args.all?(&.restriction)
        ret &= (d.name == "initialize" || !!d.return_type)
        ret
      end
    end
  end
end
