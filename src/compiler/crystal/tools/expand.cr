require "./typed_def_processor"
require "./implementations"

module Crystal
  struct ExpandResult
    include JSON::Serializable

    property status : String
    property message : String
    property expansions : Array(Expansion)?

    def initialize(@status, @message)
    end

    def to_text(io)
      io.puts message
      expansions.try &.each_with_index do |expansion, i|
        io.puts "expansion #{i + 1}:"
        io << "   "
        io.puts expansion.original_source.lines(chomp: false).join "   "
        io.puts
        expansion.expanded_sources.zip(expansion.expanded_macros)
          .each_with_index do |(expanded_source, expanded_macro), j|
            expanded_macro.each do |a_macro|
              name = a_macro[:name]
              impl = a_macro[:implementation]
              io.puts "# expand macro '#{name}' (#{impl.filename}:#{impl.line}:#{impl.column})"
              # TODO: When `impl.expands` is not `nil`, how shows this?
            end
            io << "~> "
            io.puts expanded_source.lines(chomp: false).join "   "
            io.puts
          end
      end
    end

    struct Expansion
      include JSON::Serializable
      alias MacroImplementation = {name: String, implementation: ImplementationTrace}

      property original_source : String
      property expanded_sources : Array(String)
      property expanded_macros : Array(Array(MacroImplementation))

      def initialize(@original_source, @expanded_sources, @expanded_macros)
      end

      def self.build(original_node)
        original_source = ast_to_s original_node

        transformer = ExpandTransformer.new
        expanded_node = transformer.transform original_node

        expanded_sources = [] of String
        expanded_macros = [] of Array(MacroImplementation)

        while transformer.expanded?
          expanded_sources << ast_to_s expanded_node
          expanded_macros << transformer.macro_calls
            .compact_map do |call|
              if (a_macro = call.expanded_macro) && (location = a_macro.location)
                name = a_macro.name
                # Fix name like `mapping` to `JSON.mapping`
                name = "#{call.obj}.#{name}" if call.obj.is_a?(Path)

                implementation = ImplementationTrace.build location
                MacroImplementation.new(
                  name: name,
                  implementation: implementation)
              end
            end

          transformer.expanded = false
          transformer.macro_calls.clear
          expanded_node = transformer.transform expanded_node
        end

        Expansion.new original_source, expanded_sources, expanded_macros
      end

      private def self.ast_to_s(node)
        source = String.build { |io| node.to_s(io, emit_doc: true) }

        # Re-indentation is needed for `MacroIf` and `MacroFor`, because they have
        # `MacroBody`, which is sub string of source code, in other words they may
        # contain source code's indent.
        return source unless node.is_a?(MacroIf) || node.is_a?(MacroFor)

        indent = node.location.not_nil!.column_number - 1
        source.lines(chomp: false).map do |line|
          i = 0
          line.each_char do |c|
            break unless c.ascii_whitespace? && i < indent
            i += 1
          end
          line[{i, indent}.min..-1]
        end.join
      end
    end
  end

  class ExpandVisitor < Visitor
    include TypedDefProcessor

    def initialize(@target_location : Location)
      @found_nodes = [] of ASTNode
      @in_defs = false
      @message = "no expansion found"
    end

    def process(result : Compiler::Result)
      @in_defs = true
      process_result result
      @in_defs = false

      result.node.accept(self)

      if @found_nodes.empty?
        ExpandResult.new("failed", @message)
      else
        res = ExpandResult.new("ok", "#{@found_nodes.size} expansion#{@found_nodes.size > 1 ? "s" : ""} found")
        res.expansions = @found_nodes.map { |node| ExpandResult::Expansion.build(node) }
        res
      end
    end

    def visit(node : Def | FunDef)
      @in_defs && contains_target(node)
    end

    def visit(node : Require)
      return false if node.string == "prelude"

      if loc_start = node.location
        loc_end = node.end_location || loc_start
        if @target_location.between?(loc_start, loc_end)
          @found_nodes << node
          return false
        end
      end

      # Find target location into required file.
      # It is needed when target location is out of main file. (#6098)
      node.expanded.try &.accept self
      false
    end

    def visit(node : Call)
      if loc_start = node.location
        # If node.obj (a.k.a. an receiver) is a Path, it may be macro call and node.obj has no expansion surely.
        # Otherwise, we cannot decide node.obj has no expansion.
        loc_start = node.name_location unless node.obj.is_a?(Path)
        loc_end = node.name_end_location
        if @target_location.between?(loc_start, loc_end)
          if node.expanded
            @found_nodes << node
          else
            @message = "no expansion found: #{node} may not be a macro"
          end
          return false
        end
      else
        false
      end

      return true if contains_target(node)

      # Find target location into macro expansion.
      # Because macro expansion may contain `require`.
      node.expanded.try &.accept self
      false
    end

    def visit(node : MacroFor | MacroIf | MacroExpression)
      if loc_start = node.location
        loc_end = node.end_location || loc_start
        if @target_location.between?(loc_start, loc_end) && node.expanded
          @found_nodes << node
          return false
        end
      else
        false
      end

      node.expanded.try &.accept self
      false
    end

    def visit(node : Expressions | ModuleDef | ClassDef)
      # These top-level nodes can contain `require`, so always returns `true`.
      true
    end

    def visit(node)
      contains_target(node)
    end
  end

  class ExpandTransformer < Transformer
    property? expanded = false
    getter macro_calls = [] of Call

    def transform(node : Call)
      if expanded = node.expanded
        self.expanded = true
        macro_calls << node
        expanded
      else
        super
      end
    end

    def transform(node : Require | MacroFor | MacroIf | MacroExpression)
      if expanded = node.expanded
        self.expanded = true
        expanded
      else
        super
      end
    end
  end
end
