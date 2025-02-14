require "./ast"
require "./visitor"

module Crystal
  class ASTNode
    def inspect(io : IO) : Nil
      to_s(io)
    end

    def to_s(io : IO, macro_expansion_pragmas = nil, emit_doc = false) : Nil
      visitor = ToSVisitor.new(io, macro_expansion_pragmas: macro_expansion_pragmas, emit_doc: emit_doc)
      self.accept visitor
    end
  end

  class ToSVisitor < Visitor
    @str : IO
    @macro_expansion_pragmas : Hash(Int32, Array(Lexer::LocPragma))?
    @current_arg_type : DefArgType = :none
    @write_trailing_newline : Bool = true

    # Inside a comma-separated list of parameters or args, this becomes true and
    # the outermost pair of parentheses are removed from type restrictions that
    # are `ProcNotation` nodes, so `foo(x : (T, U -> V), W)` becomes
    # `foo(x : T, U -> V, W)`. This is used by defs, lib funs, and calls to deal
    # with the parsing rules for `->`. See #11966 and #14216 for more details.
    getter? drop_parens_for_proc_notation = false

    private enum DefArgType
      NONE
      SPLAT
      DOUBLE_SPLAT
      BLOCK_ARG
    end

    def initialize(@str = IO::Memory.new, @macro_expansion_pragmas = nil, @emit_doc = false)
      @indent = 0
      @inside_macro = 0
    end

    def visit_any(node)
      if @emit_doc && (doc = node.doc) && !doc.empty?
        doc.each_line(chomp: true) do |line|
          @str << "# "
          @str << line
          newline
          append_indent
        end
      end

      if (macro_expansion_pragmas = @macro_expansion_pragmas) && (loc = node.location) && (filename = loc.filename).is_a?(String)
        pragmas = macro_expansion_pragmas[@str.pos.to_i32] ||= [] of Lexer::LocPragma
        pragmas << Lexer::LocSetPragma.new(filename, loc.line_number, loc.column_number)
      end

      true
    end

    private def write_extra_newlines(first_node_location : Location?, second_node_location : Location?, &) : Nil
      # If any location information is missing, don't add any extra newlines.
      if !first_node_location || !second_node_location
        yield
        return
      end

      # Only write the "extra" newlines. I.e. If there are more than one. The first newline is handled directly via the Expressions visitor.
      ((second_node_location.line_number - 1) - first_node_location.line_number).times do
        newline
      end

      yield
    end

    def visit(node : Nop)
      false
    end

    def visit(node : BoolLiteral)
      @str << (node.value ? "true" : "false")
      false
    end

    def visit(node : NumberLiteral)
      @str << node.value

      if needs_suffix?(node)
        @str << '_'
        @str << node.kind.to_s
      end

      false
    end

    def needs_suffix?(node : NumberLiteral)
      case node.kind
      when .i32?
        false
      when .f64?
        # If there's no '.' nor 'e', for example in `1_f64`,
        # we need to include it (#3315)
        node.value.each_char do |char|
          return false if char.in?('.', 'e')
        end

        true
      else
        true
      end
    end

    def visit(node : CharLiteral)
      node.value.inspect(@str)
      false
    end

    def visit(node : SymbolLiteral)
      visit_symbol_literal_value node.value
      false
    end

    def visit_symbol_literal_value(value : String)
      @str << ':'
      if Symbol.needs_quotes?(value)
        value.inspect(@str)
      else
        value.to_s(@str)
      end
    end

    def visit(node : StringLiteral)
      node.value.inspect(@str)
      false
    end

    def visit(node : StringInterpolation)
      @str << '"'
      visit_interpolation node, &.inspect_unquoted
      @str << '"'
      false
    end

    def visit_interpolation(node, &)
      node.expressions.each do |exp|
        if exp.is_a?(StringLiteral)
          @str << yield exp.value
        else
          @str << "\#{"
          exp.accept(self)
          @str << '}'
        end
      end
    end

    def visit(node : ArrayLiteral)
      name = node.name
      if name
        name.accept self
        @str << " {"
      else
        @str << '['
      end

      node.elements.join(@str, ", ", &.accept self)

      if name
        @str << '}'
      else
        @str << ']'
      end

      if of = node.of
        @str << " of "
        of.accept self
      end
      false
    end

    def visit(node : HashLiteral)
      if name = node.name
        name.accept self
        @str << ' '
      end

      space = false
      @str << '{'

      node.entries.each_with_index do |entry, i|
        @str << ", " if i > 0

        space = i == 0 && entry.key.is_a?(TupleLiteral) || entry.key.is_a?(NamedTupleLiteral) || entry.key.is_a?(HashLiteral)
        @str << ' ' if space

        entry.key.accept self
        @str << " => "
        entry.value.accept self
      end

      @str << ' ' if space
      @str << '}'
      if of = node.of
        @str << " of "
        of.key.accept self
        @str << " => "
        of.value.accept self
      end
      false
    end

    def visit(node : NamedTupleLiteral)
      @str << '{'
      node.entries.join(@str, ", ") do |entry|
        visit_named_arg_name(entry.key)
        @str << ": "
        entry.value.accept self
      end
      @str << '}'
      false
    end

    def visit(node : NilLiteral)
      @str << "nil"
      false
    end

    def visit(node : Expressions)
      case node.keyword
      in .paren?
        @str << '('
      in .begin?
        @str << "begin"
        @indent += 1
        newline
      in .none?
        # Not a special condition
      end

      if @inside_macro > 0
        node.expressions.each &.accept self
      else
        last_node = nil

        node.expressions.each_with_index do |exp, i|
          unless exp.nop?
            self.write_extra_newlines((last_node || exp).end_location, exp.location) do
              append_indent unless node.keyword.paren? && i == 0
              exp.accept self

              if !@write_trailing_newline && i == node.expressions.size - 1
                # no-op
              else
                newline unless node.keyword.paren? && i == node.expressions.size - 1
              end
            end

            last_node = exp
          end
        end
      end

      case node.keyword
      in .paren?
        @str << ')'
      in .begin?
        @indent -= 1
        append_indent
        @str << "end"
      in .none?
        # Not a special condition
      end

      false
    end

    def visit(node : If)
      if node.ternary?
        node.cond.accept self
        @str << " ? "
        node.then.accept self
        @str << " : "
        node.else.accept self
        return false
      end

      visit_if_or_unless "if", node
    end

    def visit(node : Unless)
      visit_if_or_unless "unless", node
    end

    def visit_if_or_unless(prefix, node)
      @str << prefix
      @str << ' '
      node.cond.accept self
      newline
      accept_with_indent(node.then)
      unless node.else.nop?
        append_indent
        @str << "else"
        newline
        accept_with_indent(node.else)
      end
      append_indent
      @str << "end"
      false
    end

    def visit(node : ClassDef)
      if node.abstract?
        @str << "abstract "
      end
      @str << (node.struct? ? "struct" : "class")
      @str << ' '
      node.name.accept self
      if type_vars = node.type_vars
        @str << '('
        type_vars.each_with_index do |type_var, i|
          @str << ", " if i > 0
          @str << '*' if node.splat_index == i
          @str << type_var.to_s
        end
        @str << ')'
      end
      if superclass = node.superclass
        @str << " < "
        superclass.accept self
      end
      newline
      accept_with_indent(node.body)

      append_indent
      @str << "end"
      false
    end

    def visit(node : ModuleDef)
      @str << "module "
      node.name.accept self
      if type_vars = node.type_vars
        @str << '('
        type_vars.each_with_index do |type_var, i|
          @str << ", " if i > 0
          @str << '*' if node.splat_index == i
          @str << type_var
        end
        @str << ')'
      end
      newline
      accept_with_indent(node.body)

      append_indent
      @str << "end"
      false
    end

    def visit(node : AnnotationDef)
      @str << "annotation "
      node.name.accept self
      newline
      append_indent
      @str << "end"
      false
    end

    def visit(node : Call)
      visit_call node
    end

    # Related: `Token::Kind#unary_operator?`
    UNARY_OPERATORS = {"+", "-", "~", "&+", "&-"}

    def visit_call(node, ignore_obj = false)
      if node.name == "`"
        visit_backtick(node.args[0])
        return false
      end

      node_obj = ignore_obj ? nil : node.obj
      block = node.block

      short_block_call = nil
      if block
        # Check if this is foo &.bar
        first_block_arg = block.args.first?
        if first_block_arg && block.args.size == 1 && block.args.first.name.starts_with?("__arg")
          block_body = block.body
          if block_body.is_a?(Call)
            block_obj = block_body.obj
            if block_obj.is_a?(Var) && block_obj.name == first_block_arg.name
              short_block_call = block_body
              block = nil
            end
          end
        end
      end

      need_parens = need_parens(node_obj)

      @str << "::" if node.global?
      if node_obj.is_a?(ImplicitObj)
        @str << '.'
        node_obj = nil
      end

      if node_obj && node.name.in?("[]", "[]?") && !block
        in_parenthesis(need_parens, node_obj)

        @str << "["
        visit_args(node)

        if short_block_call
          @str << ", " if node.args.present? || node.named_args
          @str << "&."
          visit_call short_block_call, ignore_obj: true
        end

        if node.name == "[]"
          @str << "]"
        else
          @str << "]?"
        end
      elsif node_obj && node.name == "[]=" && !node.args.empty? && !block
        in_parenthesis(need_parens, node_obj)

        @str << "["
        visit_args(node, exclude_last: true)

        if short_block_call
          @str << ", " if node.args.size > 1 || node.named_args
          @str << "&."
          visit_call short_block_call, ignore_obj: true
        end

        @str << "] = "
        node.args.last.accept self
      elsif node_obj && node.name.in?(UNARY_OPERATORS) && node.args.empty? && !node.named_args && !node.block_arg && !block && !short_block_call
        @str << node.name
        in_parenthesis(need_parens, node_obj)
      elsif node_obj && !Lexer.ident?(node.name) && node.name != "~" && node.args.size == 1 && !node.named_args && !node.block_arg && !block && !short_block_call
        in_parenthesis(need_parens, node_obj)

        arg = node.args[0]
        @str << ' '
        @str << node.name
        @str << ' '
        in_parenthesis(need_parens(arg), arg)
      else
        if node_obj
          in_parenthesis(need_parens, node_obj)
          @str << '.'
        end
        if Lexer.setter?(node.name)
          @str << node.name.rchop
          @str << " = "
          node.args.join(@str, ", ", &.accept self)
        else
          @str << node.name
          in_parenthesis(node.has_parentheses? || !node.args.empty? || node.block_arg || node.named_args || short_block_call) do
            visit_args(node)

            if short_block_call
              @str << ", " if node.args.present? || node.named_args
              @str << "&."
              visit_call short_block_call, ignore_obj: true
            end
          end
        end
      end

      if block
        @str << ' '
        block.accept self
      end

      false
    end

    private def visit_args(node, exclude_last = false)
      printed_arg = false
      node.args.each_with_index do |arg, i|
        break if exclude_last && i == node.args.size - 1

        @str << ", " if printed_arg
        drop_parens_for_proc_notation(arg, &.accept(self))
        printed_arg = true
      end
      if named_args = node.named_args
        named_args.each do |named_arg|
          @str << ", " if printed_arg
          drop_parens_for_proc_notation(named_arg, &.accept(self))
          printed_arg = true
        end
      end
      if block_arg = node.block_arg
        @str << ", " if printed_arg
        @str << '&'
        drop_parens_for_proc_notation(block_arg, &.accept(self))
      end
    end

    private def need_parens(obj)
      case obj
      when Call
        case obj.args.size
        when 0
          !Lexer.ident?(obj.name)
        else
          case obj.name
          when "[]", "[]?", "<", "<=", ">", ">="
            false
          else
            true
          end
        end
      when Var, NilLiteral, BoolLiteral, CharLiteral, NumberLiteral, StringLiteral,
           StringInterpolation, Path, Generic, InstanceVar, ClassVar, Global,
           ImplicitObj, TupleLiteral, NamedTupleLiteral, IsA, Not
        false
      when ArrayLiteral
        !!obj.of
      when HashLiteral
        !!obj.of
      else
        true
      end
    end

    def in_parenthesis(need_parens, &)
      if need_parens
        @str << '('
        yield
        @str << ')'
      else
        yield
      end
    end

    def in_parenthesis(need_parens, node)
      in_parenthesis(need_parens) do
        if node.is_a?(Expressions) && node.expressions.size == 1
          node.expressions.first.accept self
        else
          node.accept self
        end
      end
    end

    def visit(node : NamedArgument)
      visit_named_arg_name(node.name)
      @str << ": "
      node.value.accept self
      false
    end

    def visit_backtick(exp)
      @str << '`'
      case exp
      when StringLiteral
        @str << exp.value.inspect_unquoted.gsub('`', "\\`")
      when StringInterpolation
        visit_interpolation exp, &.inspect_unquoted.gsub('`', "\\`")
      else
        # This branch can be reached after the literal expander has expanded
        # `StringLiteral` nodes to a call to `::String.interpolation` which means
        # `exp` is a `Call`.

        @str << "\#{"
        exp.accept(self)
        @str << "}"
      end
      @str << '`'
      false
    end

    def visit(node : Assign)
      node.target.accept self
      @str << " = "

      need_parens = node.value.is_a?(Expressions)
      in_parenthesis(need_parens, node.value)

      false
    end

    def visit(node : OpAssign)
      node.target.accept self
      @str << ' ' << node.op << '=' << ' '
      node.value.accept self
      false
    end

    def visit(node : MultiAssign)
      node.targets.join(@str, ", ", &.accept self)
      @str << " = "
      node.values.join(@str, ", ", &.accept self)
      false
    end

    def visit(node : While)
      visit_while_or_until node, "while"
    end

    def visit(node : Until)
      visit_while_or_until node, "until"
    end

    def visit_while_or_until(node, name)
      @str << name
      @str << ' '
      node.cond.accept self
      newline
      accept_with_indent(node.body)
      append_indent
      @str << "end"
      false
    end

    def visit(node : Out)
      @str << "out "
      node.exp.accept self
      false
    end

    def visit(node : Var)
      @str << node.name
      false
    end

    def visit(node : ProcLiteral)
      @str << "->"
      if node.def.args.size > 0
        @str << '('
        node.def.args.join(@str, ", ", &.accept self)
        @str << ')'
      end
      if return_type = node.def.return_type
        @str << " : "
        return_type.accept self
      end
      @str << " do"
      newline
      accept_with_indent(node.def.body)
      append_indent
      @str << "end"
      false
    end

    def visit(node : ProcPointer)
      @str << "->"
      @str << "::" if node.global?
      if obj = node.obj
        obj.accept self
        @str << '.'
      end
      @str << node.name

      if node.args.size > 0
        @str << '('
        node.args.join(@str, ", ", &.accept self)
        @str << ')'
      end
      false
    end

    def visit(node : Def)
      @str << "abstract " if node.abstract?
      @str << "def "
      if node_receiver = node.receiver
        node_receiver.accept self
        @str << '.'
      end
      @str << node.name
      if node.args.size > 0 || node.block_arity || node.double_splat
        @str << '('
        printed_arg = false
        node.args.each_with_index do |arg, i|
          @str << ", " if printed_arg
          @current_arg_type = :splat if node.splat_index == i
          drop_parens_for_proc_notation(arg, &.accept(self))
          printed_arg = true
        end
        if double_splat = node.double_splat
          @current_arg_type = :double_splat
          @str << ", " if printed_arg
          drop_parens_for_proc_notation(double_splat, &.accept(self))
          printed_arg = true
        end
        if block_arg = node.block_arg
          @current_arg_type = :block_arg
          @str << ", " if printed_arg
          drop_parens_for_proc_notation(block_arg, &.accept(self))
        elsif node.block_arity
          @str << ", " if printed_arg
          @str << '&'
        end
        @str << ')'
      end
      if return_type = node.return_type
        @str << " : "
        return_type.accept self
      end

      if free_vars = node.free_vars
        @str << " forall "
        free_vars.join(@str, ", ")
      end

      newline

      unless node.abstract?
        accept_with_indent(node.body)
        append_indent
        @str << "end"
      end
      false
    end

    def visit(node : Macro)
      @str << "macro "
      @str << node.name.to_s
      if node.args.size > 0 || node.block_arg || node.double_splat
        @str << '('
        printed_arg = false
        # NOTE: `drop_parens_for_proc_notation` needed here if macros support
        # restrictions
        node.args.each_with_index do |arg, i|
          @str << ", " if printed_arg
          @current_arg_type = :splat if i == node.splat_index
          arg.accept self
          printed_arg = true
        end
        if double_splat = node.double_splat
          @str << ", " if printed_arg
          @current_arg_type = :double_splat
          double_splat.accept self
          printed_arg = true
        end
        if block_arg = node.block_arg
          @str << ", " if printed_arg
          @current_arg_type = :block_arg
          block_arg.accept self
        end
        @str << ')'
      end
      newline

      with_indent do
        inside_macro do
          accept node.body
        end
      end

      # newline
      append_indent
      @str << "end"
      false
    end

    def visit(node : MacroExpression)
      # A node starts multiline when its starting location (`{{` or `{%`) is on a different line than the start of its expression
      start_multiline = (start_loc = node.location) && (end_loc = node.exp.location) && end_loc.line_number > start_loc.line_number

      # and similarly ends multiline if its expression end location is on a different line than its end location (`}}` or `%}`)
      end_multiline = (body_end_loc = node.exp.end_location) && (end_loc = node.end_location) && end_loc.line_number > body_end_loc.line_number

      @str << (node.output? ? "{{ " : start_multiline ? "{%" : "{% ")

      if start_multiline
        newline
        @indent += 1
      end

      outside_macro do
        self.write_extra_newlines(node.location, node.exp.location) do
          # If the MacroExpression consists of a single node we need to manually handle appending indent and trailing newline if *start_multiline*
          # Otherwise, the Expressions logic handles that for us
          if start_multiline && !node.exp.is_a?(Expressions)
            append_indent
          end

          # Only skip writing trailing newlines when the macro expressions' expression is not an Expressions.
          # This allow Expressions that may be nested deeper in the AST to include trailing newlines.
          @write_trailing_newline = !node.exp.is_a?(Expressions)
          node.exp.accept self
          @write_trailing_newline = true
        end
      end

      self.write_extra_newlines(node.exp.end_location, node.end_location) { }

      # After writing the expression body, de-indent if things were originally multiline.
      # This ensures the ending control has the proper indent relative to the start.
      @indent -= 1 if start_multiline

      if end_multiline
        newline
        append_indent
      end

      @str << (node.output? ? " }}" : end_multiline ? "%}" : " %}")
      false
    end

    def visit(node : MacroIf)
      @str << "{% if "
      node.cond.accept self
      @str << " %}"
      inside_macro do
        node.then.accept self
      end
      unless node.else.nop?
        @str << "{% else %}"
        inside_macro do
          node.else.accept self
        end
      end
      @str << "{% end %}"
      false
    end

    def visit(node : MacroFor)
      @str << "{% for "
      node.vars.join(@str, ", ", &.accept self)
      @str << " in "
      node.exp.accept self
      @str << " %}"
      inside_macro do
        node.body.accept self
      end
      @str << "{% end %}"
      false
    end

    def visit(node : MacroVar)
      @str << '%'
      @str << node.name
      if exps = node.exps
        @str << '{'
        exps.join(@str, ", ", &.accept self)
        @str << '}'
      end
      false
    end

    def visit(node : MacroLiteral)
      # These two can only come from an escaped sequence like \{ or \{%
      if node.value == "{" || node.value.starts_with?("{%")
        @str << "\\"
      end
      @str << node.value
      false
    end

    def visit(node : MacroVerbatim)
      @str << "{% verbatim do %}"

      with_indent do
        inside_macro do
          node.exp.accept self
        end
      end

      @str << "{% end %}"
      false
    end

    def visit(node : ExternalVar)
      @str << '$'
      @str << node.name
      if real_name = node.real_name
        @str << " = "
        @str << real_name
      end
      @str << " : "
      node.type_spec.accept self
      false
    end

    def visit(node : Arg)
      if parsed_annotations = node.parsed_annotations
        parsed_annotations.each do |ann|
          ann.accept self
          @str << ' '
        end
      end

      case @current_arg_type
      when .splat?        then @str << '*'
      when .double_splat? then @str << "**"
      when .block_arg?    then @str << '&'
      end

      if node.external_name != node.name
        visit_named_arg_name(node.external_name)
        @str << ' '
      end
      if node.name
        @str << node.name
      else
        @str << '?'
      end
      if restriction = node.restriction
        @str << " : "
        restriction.accept self
      end
      if default_value = node.default_value
        @str << " = "
        default_value.accept self
      end
      false
    ensure
      @current_arg_type = :none
    end

    def visit(node : ProcNotation)
      @str << '(' unless drop_parens_for_proc_notation?

      # only drop the outermost pair of parentheses; this produces
      # `foo(x : (T -> U) -> V, W)`, not
      # `foo(x : ((T -> U) -> V), W)` nor `foo(x : T -> U -> V, W)`
      drop_parens_for_proc_notation(false) do
        if inputs = node.inputs
          inputs.join(@str, ", ", &.accept self)
          @str << ' '
        end
        @str << "->"
        if output = node.output
          @str << ' '
          output.accept self
        end
      end

      @str << ')' unless drop_parens_for_proc_notation?
      false
    end

    def visit(node : Self)
      @str << "self"
      false
    end

    def visit(node : Path)
      @str << "::" if node.global?
      node.names.join(@str, "::")
      false
    end

    def visit(node : Generic)
      name = node.name

      node.name.accept self

      printed_arg = false

      @str << '('
      node.type_vars.join(@str, ", ") do |var|
        var.accept self
        printed_arg = true
      end

      if named_args = node.named_args
        named_args.each do |named_arg|
          @str << ", " if printed_arg
          visit_named_arg_name(named_arg.name)
          @str << ": "
          named_arg.value.accept self
          printed_arg = true
        end
      end

      @str << ')'
      false
    end

    def visit_named_arg_name(name)
      Symbol.quote_for_named_argument(@str, name)
    end

    def visit(node : Underscore)
      @str << '_'
      false
    end

    def visit(node : Splat)
      @str << '*'
      node.exp.accept self
      false
    end

    def visit(node : DoubleSplat)
      @str << "**"
      node.exp.accept self
      false
    end

    def visit(node : Union)
      node.types.join(@str, " | ", &.accept self)
      false
    end

    def visit(node : Metaclass)
      needs_parens = node.name.is_a?(Union)
      @str << '(' if needs_parens
      node.name.accept self
      @str << ')' if needs_parens
      @str << ".class"
      false
    end

    def visit(node : InstanceVar)
      @str << node.name
      false
    end

    def visit(node : ReadInstanceVar)
      node.obj.accept self
      @str << '.'
      @str << node.name
      false
    end

    def visit(node : ClassVar)
      @str << node.name
      false
    end

    def visit(node : Yield)
      if scope = node.scope
        @str << "with "
        scope.accept self
        @str << ' '
      end
      @str << "yield"
      in_parenthesis(node.has_parentheses?) do
        if node.exps.size > 0
          @str << ' ' unless node.has_parentheses?
          node.exps.join(@str, ", ", &.accept self)
        end
      end
      false
    end

    def visit(node : Return)
      visit_control node, "return"
    end

    def visit(node : Break)
      visit_control node, "break"
    end

    def visit(node : Next)
      visit_control node, "next"
    end

    def visit_control(node, keyword)
      @str << keyword
      if exp = node.exp
        @str << ' '
        exp.accept self
      end
      false
    end

    def visit(node : RegexLiteral)
      if (exp = node.value).is_a?(StringLiteral) && exp.value.empty?
        # // is not always an empty regex, sometimes is an operator
        # so it's safer to emit empty regex as %r()
        @str << "%r()"
      else
        @str << '/'
        case exp = node.value
        when StringLiteral
          @str << '\\' if exp.value[0]?.try &.ascii_whitespace?
          Regex.append_source exp.value, @str
        when StringInterpolation
          @str << '\\' if exp.expressions.first?.as?(StringLiteral).try &.value[0]?.try &.ascii_whitespace?
          visit_interpolation(exp) { |s| Regex.append_source s, @str }
        else
          raise "Bug: shouldn't happen"
        end
        @str << '/'
      end
      @str << 'i' if node.options.ignore_case?
      @str << 'm' if node.options.multiline?
      @str << 'x' if node.options.extended?
      false
    end

    def visit(node : TupleLiteral)
      @str << '{'

      first = node.elements.first?
      space = first.is_a?(TupleLiteral) || first.is_a?(NamedTupleLiteral) || first.is_a?(HashLiteral)
      @str << ' ' if space
      node.elements.join(@str, ", ", &.accept self)
      @str << ' ' if space
      @str << '}'
      false
    end

    def visit(node : TypeDeclaration)
      node.var.accept self
      @str << " : "
      node.declared_type.accept self
      if value = node.value
        @str << " = "
        value.accept self
      end
      false
    end

    def visit(node : UninitializedVar)
      node.var.accept self
      @str << " = uninitialized "
      node.declared_type.accept self
      false
    end

    def visit(node : Block)
      @str << "do"

      unless node.args.empty?
        @str << " |"
        node.args.each_with_index do |arg, i|
          @str << ", " if i > 0
          @str << '*' if i == node.splat_index

          if arg.name == ""
            # This is an unpack
            unpack = node.unpacks.not_nil![i]

            visit_unpack(unpack)
          else
            arg.accept self
          end
        end
        @str << '|'
      end

      newline
      accept_with_indent(node.body)

      append_indent
      @str << "end"

      false
    end

    def visit_unpack(node)
      case node
      when Expressions
        @str << "("
        node.expressions.join(@str, ", ") do |exp|
          visit_unpack exp
        end
        @str << ")"
      else
        node.accept self
      end
    end

    def visit(node : Include)
      @str << "include "
      node.name.accept self
      false
    end

    def visit(node : Extend)
      @str << "extend "
      node.name.accept self
      false
    end

    def visit(node : And)
      to_s_binary node, "&&"
    end

    def visit(node : Or)
      to_s_binary node, "||"
    end

    def visit(node : Not)
      @str << '.' if node.exp.is_a?(ImplicitObj)
      @str << '!'
      need_parens = need_parens(node.exp)
      in_parenthesis(need_parens, node.exp)
      false
    end

    def visit(node : VisibilityModifier)
      @str << node.modifier.to_s.downcase
      @str << ' '
      node.exp.accept self
      false
    end

    def to_s_binary(node, op)
      left_needs_parens = need_parens(node.left)
      in_parenthesis(left_needs_parens, node.left)

      @str << ' '
      @str << op
      @str << ' '

      right_needs_parens = need_parens(node.right)
      in_parenthesis(right_needs_parens, node.right)
      false
    end

    def visit(node : Global)
      @str << node.name
      false
    end

    def visit(node : LibDef)
      @str << "lib "
      node.name.accept self
      newline
      accept_with_indent(node.body)
      append_indent
      @str << "end"
      false
    end

    def visit(node : FunDef)
      @str << "fun "
      if node.name == node.real_name
        @str << node.name
      else
        @str << node.name
        @str << " = "
        Symbol.quote_for_named_argument(@str, node.real_name)
      end
      if node.args.size > 0
        @str << '('
        node.args.join(@str, ", ") do |arg|
          if arg_name = arg.name.presence
            @str << arg_name << " : "
          end
          drop_parens_for_proc_notation(arg) do
            arg.restriction.not_nil!.accept self
          end
        end
        if node.varargs?
          @str << ", ..."
        end
        @str << ')'
      elsif node.varargs?
        @str << "(...)"
      end
      if node_return_type = node.return_type
        @str << " : "
        node_return_type.accept self
      end
      if body = node.body
        newline
        accept_with_indent body
        append_indent
        @str << "end"
      end
      false
    end

    def visit(node : TypeDef)
      @str << "type "
      @str << node.name.to_s
      @str << " = "
      node.type_spec.accept self
      false
    end

    def visit(node : CStructOrUnionDef)
      @str << (node.union? ? "union" : "struct")
      @str << ' '
      @str << node.name.to_s
      newline
      accept_with_indent node.body
      append_indent
      @str << "end"
      false
    end

    def visit(node : EnumDef)
      @str << "enum "
      @str << node.name.to_s
      if base_type = node.base_type
        @str << " : "
        base_type.accept self
      end
      newline
      with_indent do
        node.members.each do |member|
          append_indent
          member.accept self
          newline
        end
      end
      append_indent
      @str << "end"
      false
    end

    def visit(node : RangeLiteral)
      unless node.from.nop?
        need_parens = need_parens(node.from)
        in_parenthesis(need_parens, node.from)
      end

      if node.exclusive?
        @str << "..."
      else
        @str << ".."
      end

      unless node.to.nop?
        need_parens = need_parens(node.to)
        in_parenthesis(need_parens, node.to)
      end

      false
    end

    def visit(node : PointerOf)
      @str << "pointerof("
      node.exp.accept(self)
      @str << ')'
      false
    end

    def visit(node : SizeOf)
      @str << "sizeof("
      node.exp.accept(self)
      @str << ')'
      false
    end

    def visit(node : InstanceSizeOf)
      @str << "instance_sizeof("
      node.exp.accept(self)
      @str << ')'
      false
    end

    def visit(node : AlignOf)
      @str << "alignof("
      node.exp.accept(self)
      @str << ')'
      false
    end

    def visit(node : InstanceAlignOf)
      @str << "instance_alignof("
      node.exp.accept(self)
      @str << ')'
      false
    end

    def visit(node : OffsetOf)
      @str << "offsetof("
      node.offsetof_type.accept(self)
      @str << ", "
      node.offset.accept(self)
      @str << ')'
      false
    end

    def visit(node : IsA)
      node.obj.accept self
      if node.nil_check?
        @str << ".nil?"
      else
        @str << ".is_a?("
        node.const.accept self
        @str << ')'
      end
      false
    end

    def visit(node : Cast)
      visit_cast node, "as"
    end

    def visit(node : NilableCast)
      visit_cast node, "as?"
    end

    def visit_cast(node, keyword)
      need_parens = need_parens(node.obj)
      in_parenthesis(need_parens, node.obj)
      @str << '.'
      @str << keyword
      @str << '('
      node.to.accept self
      @str << ')'
      false
    end

    def visit(node : RespondsTo)
      node.obj.accept self
      @str << ".responds_to?("
      visit_symbol_literal_value node.name
      @str << ')'
      false
    end

    def visit(node : Require)
      @str << "require \""
      @str << node.string
      @str << '"'
      false
    end

    def visit(node : Case)
      @str << "case"
      if cond = node.cond
        @str << ' '
        cond.accept self
      end
      newline

      node.whens.each do |wh|
        wh.accept self
      end

      if node_else = node.else
        append_indent
        @str << "else"
        newline
        accept_with_indent node_else
      end
      append_indent
      @str << "end"
      false
    end

    def visit(node : When)
      append_indent
      @str << (node.exhaustive? ? "in" : "when")
      @str << ' '
      node.conds.join(@str, ", ", &.accept self)
      newline
      accept_with_indent node.body
      false
    end

    def visit(node : Select)
      @str << "select"
      newline
      node.whens.each do |a_when|
        append_indent
        @str << "when "
        a_when.conds.first.accept self
        newline
        accept_with_indent a_when.body
      end
      if a_else = node.else
        append_indent
        @str << "else"
        newline
        accept_with_indent a_else
      end
      append_indent
      @str << "end"
      false
    end

    def visit(node : ImplicitObj)
      false
    end

    def visit(node : ExceptionHandler)
      @str << "begin"
      newline

      accept_with_indent node.body

      node.rescues.try &.each do |a_rescue|
        append_indent
        a_rescue.accept self
      end

      if node_else = node.else
        append_indent
        @str << "else"
        newline
        accept_with_indent node_else
      end

      if node_ensure = node.ensure
        append_indent
        @str << "ensure"
        newline
        accept_with_indent node_ensure
      end

      append_indent
      @str << "end"
      false
    end

    def visit(node : Rescue)
      @str << "rescue"
      if name = node.name
        @str << ' '
        @str << name
      end
      if (types = node.types) && types.size > 0
        if node.name
          @str << " :"
        end
        @str << ' '
        types.join(@str, " | ", &.accept self)
      end
      newline
      accept_with_indent node.body
      false
    end

    def visit(node : Alias)
      @str << "alias "
      node.name.accept self
      @str << " = "
      node.value.accept self
      false
    end

    def visit(node : TypeOf)
      @str << "typeof("
      node.expressions.join(@str, ", ", &.accept self)
      @str << ')'
      false
    end

    def visit(node : Annotation)
      @str << "@["
      @str << node.path
      if !node.args.empty? || node.named_args
        @str << '('
        printed_arg = false
        node.args.join(@str, ", ") do |arg|
          arg.accept self
          printed_arg = true
        end
        if named_args = node.named_args
          named_args.each do |named_arg|
            @str << ", " if printed_arg
            visit_named_arg_name(named_arg.name)
            @str << ": "
            named_arg.value.accept self
            printed_arg = true
          end
        end
        @str << ')'
      end
      @str << ']'
      false
    end

    def visit(node : MagicConstant)
      @str << node.name
      false
    end

    def visit(node : Asm)
      @str << "asm("
      node.text.inspect(@str)
      @str << " :"
      if outputs = node.outputs
        @str << ' '
        outputs.join(@str, ", ", &.accept self)
        @str << ' '
      end
      @str << ':'
      if inputs = node.inputs
        @str << ' '
        inputs.join(@str, ", ", &.accept self)
        @str << ' '
      end
      @str << ":"
      if clobbers = node.clobbers
        @str << ' '
        clobbers.join(@str, ", ", &.inspect @str)
        @str << ' '
      end
      @str << ":"
      if node.volatile? || node.alignstack? || node.intel? || node.can_throw?
        @str << ' '
        comma = false
        if node.volatile?
          @str << %("volatile")
          comma = true
        end
        if node.alignstack?
          @str << ", " if comma
          @str << %("alignstack")
          comma = true
        end
        if node.intel?
          @str << ", " if comma
          @str << %("intel")
          comma = true
        end
        if node.can_throw?
          @str << ", " if comma
          @str << %("unwind")
        end
      end
      @str << ')'
      false
    end

    def visit(node : AsmOperand)
      node.constraint.inspect(@str)
      @str << '('
      node.exp.accept self
      @str << ')'
      false
    end

    def newline
      @str << '\n'
    end

    def indent_string
      "  "
    end

    def append_indent
      @indent.times do
        @str << indent_string
      end
    end

    def with_indent(&)
      @indent += 1
      yield
      @indent -= 1
    end

    def accept_with_indent(node : Expressions)
      with_indent do
        append_indent unless node.keyword.none?
        node.accept self
      end
      newline unless node.keyword.none?
    end

    def accept_with_indent(node : Nop)
    end

    def accept_with_indent(node : ASTNode)
      with_indent do
        append_indent
        node.accept self
      end
      newline
    end

    def inside_macro(&)
      @inside_macro += 1
      yield
      @inside_macro -= 1
    end

    def outside_macro(&)
      old_inside_macro = @inside_macro
      @inside_macro = 0
      yield
      @inside_macro = old_inside_macro
    end

    def drop_parens_for_proc_notation(drop : Bool = true, &)
      old_drop_parens_for_proc_notation = @drop_parens_for_proc_notation
      @drop_parens_for_proc_notation = drop
      begin
        yield
      ensure
        @drop_parens_for_proc_notation = old_drop_parens_for_proc_notation
      end
    end

    def drop_parens_for_proc_notation(node : ASTNode, &)
      outermost_type_is_proc_notation =
        case node
        when Arg
          # def / fun parameters
          node.restriction.is_a?(ProcNotation)
        when TypeDeclaration
          # call arguments
          node.declared_type.is_a?(ProcNotation)
        else
          false
        end

      drop_parens_for_proc_notation(outermost_type_is_proc_notation) { yield node }
    end

    def to_s : String
      @str.to_s
    end

    def to_s(io : IO) : Nil
      @str.to_s(io)
    end
  end
end
