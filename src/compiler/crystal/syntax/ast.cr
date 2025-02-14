module Crystal
  # Base class for nodes in the grammar.
  abstract class ASTNode
    # The location where this node starts, or `nil`
    # if the location is not known.
    property location : Location?

    # The location where this node ends, or `nil`
    # if the location is not known.
    property end_location : Location?

    # Updates this node's location and returns `self`
    def at(@location : Location?)
      self
    end

    # Sets this node's location and end location to those
    # of `node`, and returns `self`
    def at(node : ASTNode)
      @location = node.location
      @end_location = node.end_location
      self
    end

    # Updates this node's end location and returns `self`
    def at_end(@end_location : Location?)
      self
    end

    # Sets this node's end location to those of `node` and
    # returns self
    def at_end(node : ASTNode)
      @end_location = node.end_location
      self
    end

    # Returns the number of lines between start and end locations
    def length : Int32?
      Location.lines(location, end_location)
    end

    # Returns a deep copy of this node. Copied nodes retain
    # the location and end location of the original nodes.
    def clone
      clone = clone_without_location
      clone.location = location
      clone.end_location = end_location
      clone.doc = doc
      clone
    end

    # Returns the doc comment attached to this node. Not every node
    # supports having doc comments, so by default this returns `nil`.
    def doc
    end

    # Attaches a doc comment to this node. Not every node supports
    # having doc comments, so by default this does nothing and some
    # subclasses implement this.
    def doc=(doc)
    end

    def name_location
      nil
    end

    def name_size
      0
    end

    def visibility=(visibility : Visibility)
    end

    def visibility
      Visibility::Public
    end

    def nop?
      self.is_a?(Nop)
    end

    def true_literal?
      self.is_a?(BoolLiteral) && self.value
    end

    def false_literal?
      self.is_a?(BoolLiteral) && !self.value
    end

    def self.class_desc : String
      {{@type.name.split("::").last.id.stringify}}
    end

    def class_desc
      self.class.class_desc
    end

    def pretty_print(pp)
      pp.text to_s
    end

    # It yields itself for any node, but `Expressions` yields first node
    # if it holds only a node.
    def single_expression
      single_expression? || self
    end

    # It yields `nil` always.
    # (It is overridden by `Expressions` to implement `#single_expression`.)
    def single_expression?
      nil
    end
  end

  class Nop < ASTNode
    def clone_without_location
      Nop.new
    end

    def_equals_and_hash
  end

  # A container for one or many expressions.
  class Expressions < ASTNode
    enum Keyword
      None
      Paren
      Begin
    end

    property expressions : Array(ASTNode)
    property keyword : Keyword = Keyword::None

    def self.from(obj : Nil)
      Nop.new
    end

    def self.from(obj : Array)
      case obj.size
      when 0
        Nop.new
      when 1
        obj.first
      else
        new obj
      end
    end

    def self.from(obj : ASTNode)
      obj
    end

    def initialize(@expressions = [] of ASTNode)
    end

    def empty?
      @expressions.empty?
    end

    def [](i)
      @expressions[i]
    end

    def last
      @expressions.last
    end

    def location
      @location || @expressions.first?.try &.location
    end

    def end_location
      @end_location || @expressions.last?.try &.end_location
    end

    # It yields first node if this holds only one node, or yields `nil`.
    def single_expression?
      return @expressions.first.single_expression if @expressions.size == 1

      nil
    end

    def accept_children(visitor)
      @expressions.each &.accept visitor
    end

    def clone_without_location
      Expressions.new(@expressions.clone).tap &.keyword = keyword
    end

    def_equals_and_hash expressions
  end

  # The nil literal.
  #
  #     'nil'
  #
  class NilLiteral < ASTNode
    def clone_without_location
      NilLiteral.new
    end

    def_equals_and_hash
  end

  # A bool literal.
  #
  #     'true' | 'false'
  #
  class BoolLiteral < ASTNode
    property value : Bool

    def initialize(@value)
    end

    def clone_without_location
      BoolLiteral.new(@value)
    end

    def_equals_and_hash value
  end

  # The kind of primitive numbers.
  enum NumberKind
    I8
    I16
    I32
    I64
    I128
    U8
    U16
    U32
    U64
    U128
    F32
    F64

    def to_s : String
      super.downcase
    end

    def bytesize
      case self
      in .i8?   then 8
      in .i16?  then 16
      in .i32?  then 32
      in .i64?  then 64
      in .i128? then 128
      in .u8?   then 8
      in .u16?  then 16
      in .u32?  then 32
      in .u64?  then 64
      in .u128? then 128
      in .f32?  then 32
      in .f64?  then 64
      end
    end

    def signed_int?
      i8? || i16? || i32? || i64? || i128?
    end

    def unsigned_int?
      u8? || u16? || u32? || u64? || u128?
    end

    def float?
      f32? || f64?
    end

    def self.from_number(number : Number::Primitive) : self
      case number
      in Int8    then I8
      in Int16   then I16
      in Int32   then I32
      in Int64   then I64
      in Int128  then I128
      in UInt8   then U8
      in UInt16  then U16
      in UInt32  then U32
      in UInt64  then U64
      in UInt128 then U128
      in Float32 then F32
      in Float64 then F64
      end
    end

    def cast(number) : Number::Primitive
      case self
      in .i8?   then number.to_i8
      in .i16?  then number.to_i16
      in .i32?  then number.to_i32
      in .i64?  then number.to_i64
      in .i128? then number.to_i128
      in .u8?   then number.to_u8
      in .u16?  then number.to_u16
      in .u32?  then number.to_u32
      in .u64?  then number.to_u64
      in .u128? then number.to_u128
      in .f32?  then number.to_f32
      in .f64?  then number.to_f64
      end
    end
  end

  # Any number literal.
  class NumberLiteral < ASTNode
    property value : String
    property kind : NumberKind

    def initialize(@value : String, @kind : NumberKind = :i32)
    end

    def self.new(value : Number)
      new(value.to_s, NumberKind.from_number(value))
    end

    def has_sign?
      @value[0].in?('+', '-')
    end

    def integer_value
      unless kind.signed_int? || kind.unsigned_int?
        raise "BUG: called 'integer_value' for non-integer literal"
      end

      kind.cast(value)
    end

    # Returns true if this literal is representable in the *other_type*. Used to
    # define number literal autocasting.
    #
    # TODO: if *other_type* is a `FloatType` then precision loss and overflow
    # may occur (#11710)
    def representable_in?(other_type)
      case {self.type, other_type}
      when {IntegerType, IntegerType}
        min, max = other_type.range
        min <= integer_value <= max
      when {IntegerType, FloatType}
        true
      when {FloatType, FloatType}
        true
      else
        false
      end
    end

    def clone_without_location
      NumberLiteral.new(@value, @kind)
    end

    def_equals value.to_f64, kind
    def_hash value, kind
  end

  # A char literal.
  #
  #     "'" \w "'"
  #
  class CharLiteral < ASTNode
    property value : Char

    def initialize(@value : Char)
    end

    def clone_without_location
      CharLiteral.new(@value)
    end

    def_equals_and_hash value
  end

  class StringLiteral < ASTNode
    property value : String

    def initialize(@value : String)
    end

    def clone_without_location
      StringLiteral.new(@value)
    end

    def_equals_and_hash value
  end

  class StringInterpolation < ASTNode
    property expressions : Array(ASTNode)

    # Removed indentation size.
    # This property is only available when this is created from heredoc.
    property heredoc_indent : Int32

    def initialize(@expressions : Array(ASTNode), @heredoc_indent = 0)
    end

    def accept_children(visitor)
      @expressions.each &.accept visitor
    end

    def clone_without_location
      StringInterpolation.new(@expressions.clone)
    end

    def_equals_and_hash expressions
  end

  class SymbolLiteral < ASTNode
    property value : String

    def initialize(@value : String)
    end

    def clone_without_location
      SymbolLiteral.new(@value)
    end

    def_equals_and_hash value
  end

  # An array literal.
  #
  #  '[' [ expression [ ',' expression ]* ] ']'
  #
  class ArrayLiteral < ASTNode
    property elements : Array(ASTNode)
    property of : ASTNode?
    property name : ASTNode?

    def initialize(@elements = [] of ASTNode, @of = nil, @name = nil)
    end

    def self.map(values, of = nil, &)
      new(values.map { |value| (yield value).as(ASTNode) }, of: of)
    end

    def self.map_with_index(values, &)
      new(values.map_with_index { |value, idx| (yield value, idx).as(ASTNode) }, of: nil)
    end

    def accept_children(visitor)
      @name.try &.accept visitor
      elements.each &.accept visitor
      @of.try &.accept visitor
    end

    def clone_without_location
      ArrayLiteral.new(@elements.clone, @of.clone, @name.clone)
    end

    def_equals_and_hash @elements, @of, @name
  end

  class HashLiteral < ASTNode
    property entries : Array(Entry)
    property of : Entry?
    property name : ASTNode?

    def initialize(@entries = [] of Entry, @of = nil, @name = nil)
    end

    def accept_children(visitor)
      @name.try &.accept visitor
      @entries.each do |entry|
        entry.key.accept visitor
        entry.value.accept visitor
      end
      if of = @of
        of.key.accept visitor
        of.value.accept visitor
      end
    end

    def clone_without_location
      HashLiteral.new(@entries.clone, @of.clone, @name.clone)
    end

    def_equals_and_hash @entries, @of, @name

    record Entry, key : ASTNode, value : ASTNode
  end

  class NamedTupleLiteral < ASTNode
    property entries : Array(Entry)

    def initialize(@entries = [] of Entry)
    end

    def accept_children(visitor)
      @entries.each do |entry|
        entry.value.accept visitor
      end
    end

    def clone_without_location
      NamedTupleLiteral.new(@entries.clone)
    end

    def_equals_and_hash @entries

    record Entry, key : String, value : ASTNode
  end

  class RangeLiteral < ASTNode
    property from : ASTNode
    property to : ASTNode
    property? exclusive : Bool

    def initialize(@from, @to, @exclusive)
    end

    def accept_children(visitor)
      @from.accept visitor
      @to.accept visitor
    end

    def clone_without_location
      RangeLiteral.new(@from.clone, @to.clone, @exclusive.clone)
    end

    def_equals_and_hash @from, @to, @exclusive
  end

  class RegexLiteral < ASTNode
    property value : ASTNode
    property options : Regex::CompileOptions

    def initialize(@value, @options = Regex::CompileOptions::None)
    end

    def accept_children(visitor)
      @value.accept visitor
    end

    def clone_without_location
      RegexLiteral.new(@value.clone, @options)
    end

    def_equals_and_hash @value, @options
  end

  class TupleLiteral < ASTNode
    property elements : Array(ASTNode)

    def initialize(@elements)
    end

    def self.map(values, &)
      new(values.map { |value| (yield value).as(ASTNode) })
    end

    def self.map_with_index(values, &)
      new(values.map_with_index { |value, idx| (yield value, idx).as(ASTNode) })
    end

    def accept_children(visitor)
      elements.each &.accept visitor
    end

    def clone_without_location
      TupleLiteral.new(elements.clone)
    end

    def_equals_and_hash elements
  end

  module SpecialVar
    def special_var?
      @name.starts_with? '$'
    end
  end

  # A local variable or block argument.
  class Var < ASTNode
    include SpecialVar

    property name : String
    property doc : String?

    def initialize(@name : String)
    end

    def name_size
      name.size
    end

    def clone_without_location
      Var.new(@name)
    end

    def_equals name
    def_hash name
  end

  # A code block.
  #
  #     'do' [ '|' arg [ ',' arg ]* '|' ]
  #       body
  #     'end'
  #   |
  #     '{' [ '|' arg [ ',' arg ]* '|' ] body '}'
  #
  class Block < ASTNode
    property args : Array(Var)
    property body : ASTNode
    property call : Call?
    property splat_index : Int32?

    # When a block argument unpacks, the corresponding Var will
    # have an empty name, and `unpacks` will have the unpacked
    # Expressions in that index.
    property unpacks : Hash(Int32, Expressions)?

    def initialize(@args = [] of Var, body = nil, @splat_index = nil, @unpacks = nil)
      @body = Expressions.from body
    end

    def accept_children(visitor)
      @args.each &.accept visitor
      @body.accept visitor
      @unpacks.try &.each_value &.accept visitor
    end

    def clone_without_location
      Block.new(@args.clone, @body.clone, @splat_index, @unpacks.clone)
    end

    def_equals_and_hash args, body, splat_index, unpacks
  end

  # A method call.
  #
  #     [ obj '.' ] name '(' ')' [ block ]
  #   |
  #     [ obj '.' ] name '(' arg [ ',' arg ]* ')' [ block ]
  #   |
  #     [ obj '.' ] name arg [ ',' arg ]* [ block ]
  #   |
  #     arg name arg
  #
  # The last syntax is for infix operators, and name will be
  # the symbol of that operator instead of a string.
  #
  class Call < ASTNode
    property obj : ASTNode?
    property name : String
    property args : Array(ASTNode)
    property block : Block?
    property block_arg : ASTNode?
    property named_args : Array(NamedArgument)?
    property name_location : Location?
    @name_size = -1
    property doc : String?
    property visibility = Visibility::Public
    property? global : Bool
    property? expansion = false
    property? args_in_brackets = false
    property? has_parentheses = false

    def initialize(@obj : ASTNode?, @name : String, @args : Array(ASTNode) = [] of ASTNode, @block = nil, @block_arg = nil, @named_args = nil, @global : Bool = false)
      if block = @block
        block.call = self
      end
    end

    def self.new(obj : ASTNode?, name : String, *args : ASTNode, block : Block? = nil, block_arg : ASTNode? = nil, named_args : Array(NamedArgument)? = nil, global : Bool = false)
      {% if compare_versions(Crystal::VERSION, "1.5.0") > 0 %}
        new obj, name, [*args] of ASTNode, block: block, block_arg: block_arg, named_args: named_args, global: global
      {% else %}
        new obj, name, args.to_a(&.as(ASTNode)), block: block, block_arg: block_arg, named_args: named_args, global: global
      {% end %}
    end

    def self.new(name : String, args : Array(ASTNode) = [] of ASTNode, block : Block? = nil, block_arg : ASTNode? = nil, named_args : Array(NamedArgument)? = nil, global : Bool = false)
      new(nil, name, args, block: block, block_arg: block_arg, named_args: named_args, global: global)
    end

    def self.new(name : String, *args : ASTNode, block : Block? = nil, block_arg : ASTNode? = nil, named_args : Array(NamedArgument)? = nil, global : Bool = false)
      new(nil, name, *args, block: block, block_arg: block_arg, named_args: named_args, global: global)
    end

    def self.global(name, *args : ASTNode)
      new nil, name, *args, global: true
    end

    def name_size
      if @name_size == -1
        @name_size = name.to_s.ends_with?('=') || name.to_s.ends_with?('@') ? name.size - 1 : name.size
      end
      @name_size
    end

    setter name_size

    def accept_children(visitor)
      @obj.try &.accept visitor
      @args.each &.accept visitor
      @named_args.try &.each &.accept visitor
      @block_arg.try &.accept visitor
      @block.try &.accept visitor
    end

    def clone_without_location
      clone = Call.new(@obj.clone, @name, @args.clone, @block.clone, @block_arg.clone, @named_args.clone, @global)
      clone.name_location = name_location
      clone.has_parentheses = has_parentheses?
      clone.name_size = name_size
      clone.expansion = expansion?
      clone
    end

    def name_end_location
      loc = @name_location
      return unless loc

      Location.new(loc.filename, loc.line_number, loc.column_number + name_size - 1)
    end

    def_equals_and_hash obj, name, args, block, block_arg, named_args, global?
  end

  class NamedArgument < ASTNode
    property name : String
    property value : ASTNode

    def initialize(@name : String, @value : ASTNode)
    end

    def accept_children(visitor)
      @value.accept visitor
    end

    def clone_without_location
      NamedArgument.new(name, value.clone)
    end

    def end_location
      @end_location || value.end_location
    end

    def_equals_and_hash name, value
  end

  # An if expression.
  #
  #     'if' cond
  #       then
  #     [
  #     'else'
  #       else
  #     ]
  #     'end'
  #
  # An if elsif end is parsed as an If whose
  # else is another If.
  class If < ASTNode
    property cond : ASTNode
    property then : ASTNode
    property else : ASTNode
    property? ternary : Bool

    # The location of the `else` keyword if present.
    property else_location : Location?

    def initialize(@cond, a_then = nil, a_else = nil, @ternary = false)
      @then = Expressions.from a_then
      @else = Expressions.from a_else
    end

    def accept_children(visitor)
      @cond.accept visitor
      @then.accept visitor
      @else.accept visitor
    end

    def clone_without_location
      If.new(@cond.clone, @then.clone, @else.clone, @ternary)
    end

    def_equals_and_hash @cond, @then, @else
  end

  class Unless < ASTNode
    property cond : ASTNode
    property then : ASTNode
    property else : ASTNode

    # The location of the `else` keyword if present.
    property else_location : Location?

    def initialize(@cond, a_then = nil, a_else = nil)
      @then = Expressions.from a_then
      @else = Expressions.from a_else
    end

    def accept_children(visitor)
      @cond.accept visitor
      @then.accept visitor
      @else.accept visitor
    end

    def clone_without_location
      Unless.new(@cond.clone, @then.clone, @else.clone)
    end

    def_equals_and_hash @cond, @then, @else
  end

  # Assign expression.
  #
  #     target '=' value
  #
  class Assign < ASTNode
    property target : ASTNode
    property value : ASTNode
    property doc : String?

    def initialize(@target, @value)
    end

    def visibility=(visibility)
      target.visibility = visibility
    end

    def accept_children(visitor)
      @target.accept visitor
      @value.accept visitor
    end

    def end_location
      @end_location || value.end_location
    end

    def clone_without_location
      Assign.new(@target.clone, @value.clone)
    end

    def_equals_and_hash @target, @value
  end

  # Operator assign expression.
  #
  #     target op'=' value
  #
  # For example if `op` is `+` then the above is:
  #
  #     target '+=' value
  class OpAssign < ASTNode
    property target : ASTNode
    property op : String
    property value : ASTNode
    property name_location : Location?

    def initialize(@target, @op, @value)
    end

    def accept_children(visitor)
      @target.accept visitor
      @value.accept visitor
    end

    def end_location
      @end_location || value.end_location
    end

    def clone_without_location
      OpAssign.new(@target.clone, @op, @value.clone)
    end

    def_equals_and_hash @target, @op, @value
  end

  # Assign expression.
  #
  #     target [',' target]+ '=' value [',' value]*
  #
  class MultiAssign < ASTNode
    property targets : Array(ASTNode)
    property values : Array(ASTNode)

    def initialize(@targets, @values)
    end

    def accept_children(visitor)
      @targets.each &.accept visitor
      @values.each &.accept visitor
    end

    def end_location
      @end_location || @values.last.end_location
    end

    def clone_without_location
      MultiAssign.new(@targets.clone, @values.clone)
    end

    def_equals_and_hash @targets, @values
  end

  # An instance variable.
  class InstanceVar < ASTNode
    property name : String

    def initialize(@name)
    end

    def name_size
      name.size
    end

    def clone_without_location
      InstanceVar.new(@name)
    end

    def_equals_and_hash name
  end

  class ReadInstanceVar < ASTNode
    property obj : ASTNode
    property name : String

    def initialize(@obj, @name)
    end

    def accept_children(visitor)
      @obj.accept visitor
    end

    def clone_without_location
      ReadInstanceVar.new(@obj.clone, @name)
    end

    def_equals_and_hash @obj, @name
  end

  class ClassVar < ASTNode
    property name : String

    def initialize(@name)
    end

    def clone_without_location
      ClassVar.new(@name)
    end

    def_equals_and_hash name
  end

  # A global variable.
  class Global < ASTNode
    property name : String

    def initialize(@name)
    end

    def name_size
      name.size
    end

    def clone_without_location
      Global.new(@name)
    end

    def_equals_and_hash name
  end

  abstract class BinaryOp < ASTNode
    property left : ASTNode
    property right : ASTNode

    def initialize(@left, @right)
    end

    def accept_children(visitor)
      @left.accept visitor
      @right.accept visitor
    end

    def end_location
      @end_location || @right.end_location
    end

    def_equals_and_hash left, right
  end

  # Expressions and.
  #
  #     expression '&&' expression
  #
  class And < BinaryOp
    def clone_without_location
      And.new(@left.clone, @right.clone)
    end
  end

  # Expressions or.
  #
  #     expression '||' expression
  #
  class Or < BinaryOp
    def clone_without_location
      Or.new(@left.clone, @right.clone)
    end
  end

  # A def argument.
  class Arg < ASTNode
    include SpecialVar

    # The internal name
    property name : String
    property external_name : String
    property default_value : ASTNode?
    property restriction : ASTNode?
    property doc : String?
    property parsed_annotations : Array(Annotation)?

    def initialize(@name : String, @default_value : ASTNode? = nil, @restriction : ASTNode? = nil, external_name : String? = nil, @parsed_annotations : Array(Annotation)? = nil)
      @external_name = external_name || @name
    end

    def accept_children(visitor)
      @default_value.try &.accept visitor
      @restriction.try &.accept visitor
    end

    def name_size
      name.size
    end

    def clone_without_location
      Arg.new @name, @default_value.clone, @restriction.clone, @external_name.clone, @parsed_annotations.clone
    end

    def_equals_and_hash name, default_value, restriction, external_name, parsed_annotations
  end

  # The Proc notation in the type grammar:
  #
  #    input1, input2, ..., inputN -> output
  class ProcNotation < ASTNode
    property inputs : Array(ASTNode)?
    property output : ASTNode?

    def initialize(@inputs = nil, @output = nil)
    end

    def accept_children(visitor)
      @inputs.try &.each &.accept visitor
      @output.try &.accept visitor
    end

    def clone_without_location
      ProcNotation.new(@inputs.clone, @output.clone)
    end

    def_equals_and_hash inputs, output
  end

  # A method definition.
  #
  #     'def' [ receiver '.' ] name
  #       body
  #     'end'
  #   |
  #     'def' [ receiver '.' ] name '(' [ arg [ ',' arg ]* ] ')'
  #       body
  #     'end'
  #
  class Def < ASTNode
    property free_vars : Array(String)?
    property receiver : ASTNode?
    property name : String
    property args : Array(Arg)
    property double_splat : Arg?
    property body : ASTNode
    property block_arg : Arg?
    property return_type : ASTNode?
    # Number of block arguments accepted by this method.
    # `nil` if it does not receive a block.
    property block_arity : Int32?
    property name_location : Location?
    property splat_index : Int32?
    property doc : String?
    property visibility = Visibility::Public

    property? macro_def : Bool
    property? calls_super = false
    property? calls_initialize = false
    property? calls_previous_def = false
    property? uses_block_arg = false
    property? assigns_special_var = false
    property? abstract : Bool

    def initialize(@name, @args = [] of Arg, body = nil, @receiver = nil, @block_arg = nil, @return_type = nil, @macro_def = false, @block_arity = nil, @abstract = false, @splat_index = nil, @double_splat = nil, @free_vars = nil)
      @body = Expressions.from body
    end

    def accept_children(visitor)
      @receiver.try &.accept visitor
      @args.each &.accept visitor
      @double_splat.try &.accept visitor
      @block_arg.try &.accept visitor
      @return_type.try &.accept visitor
      @body.accept visitor
    end

    def name_size
      name.size
    end

    def clone_without_location
      a_def = Def.new(@name, @args.clone, @body.clone, @receiver.clone, @block_arg.clone, @return_type.clone, @macro_def, @block_arity, @abstract, @splat_index, @double_splat.clone, @free_vars)
      a_def.calls_super = calls_super?
      a_def.calls_initialize = calls_initialize?
      a_def.calls_previous_def = calls_previous_def?
      a_def.uses_block_arg = uses_block_arg?
      a_def.assigns_special_var = assigns_special_var?
      a_def.name_location = name_location
      a_def.visibility = visibility
      a_def
    end

    def_equals_and_hash @name, @args, @body, @receiver, @block_arg, @return_type, @macro_def, @block_arity, @abstract, @splat_index, @double_splat

    def autogenerated?
      location == body.location
    end
  end

  class Macro < ASTNode
    property name : String
    property args : Array(Arg)
    property body : ASTNode
    property double_splat : Arg?
    property block_arg : Arg?
    property name_location : Location?
    property splat_index : Int32?
    property doc : String?
    property visibility = Visibility::Public

    def initialize(@name, @args = [] of Arg, @body = Nop.new, @block_arg = nil, @splat_index = nil, @double_splat = nil)
    end

    def accept_children(visitor)
      @args.each &.accept visitor
      @body.accept visitor
      @double_splat.try &.accept visitor
      @block_arg.try &.accept visitor
    end

    def name_size
      name.size
    end

    def clone_without_location
      m = Macro.new(@name, @args.clone, @body.clone, @block_arg.clone, @splat_index, @double_splat.clone)
      m.name_location = name_location
      m
    end

    def_equals_and_hash @name, @args, @body, @block_arg, @splat_index, @double_splat
  end

  abstract class UnaryExpression < ASTNode
    property exp : ASTNode

    def initialize(@exp)
    end

    def accept_children(visitor)
      @exp.accept visitor
    end

    def end_location
      @end_location || @exp.end_location
    end

    def_equals_and_hash exp
  end

  # Used only for flags
  class Not < UnaryExpression
    def clone_without_location
      Not.new(@exp.clone)
    end
  end

  class PointerOf < UnaryExpression
    def clone_without_location
      PointerOf.new(@exp.clone)
    end
  end

  class SizeOf < UnaryExpression
    def clone_without_location
      SizeOf.new(@exp.clone)
    end
  end

  class InstanceSizeOf < UnaryExpression
    def clone_without_location
      InstanceSizeOf.new(@exp.clone)
    end
  end

  class AlignOf < UnaryExpression
    def clone_without_location
      AlignOf.new(@exp.clone)
    end
  end

  class InstanceAlignOf < UnaryExpression
    def clone_without_location
      InstanceAlignOf.new(@exp.clone)
    end
  end

  class Out < UnaryExpression
    def clone_without_location
      Out.new(@exp.clone)
    end
  end

  class OffsetOf < ASTNode
    property offsetof_type : ASTNode
    property offset : ASTNode

    def initialize(@offsetof_type, @offset)
    end

    def accept_children(visitor)
      @offsetof_type.accept visitor
      @offset.accept visitor
    end

    def clone_without_location
      OffsetOf.new(@offsetof_type.clone, @offset.clone)
    end

    def_equals_and_hash @offsetof_type, @offset
  end

  class VisibilityModifier < ASTNode
    property modifier : Visibility
    property exp : ASTNode
    property doc : String?

    def initialize(@modifier : Visibility, @exp)
    end

    def accept_children(visitor)
      @exp.accept visitor
    end

    def clone_without_location
      VisibilityModifier.new(@modifier, @exp.clone)
    end

    def end_location
      @end_location || @exp.end_location
    end

    def_equals_and_hash modifier, exp
  end

  class IsA < ASTNode
    property obj : ASTNode
    property const : ASTNode
    property? nil_check : Bool

    def initialize(@obj, @const, @nil_check = false)
    end

    def accept_children(visitor)
      @obj.accept visitor
      @const.accept visitor
    end

    def clone_without_location
      IsA.new(@obj.clone, @const.clone, @nil_check)
    end

    def_equals_and_hash @obj, @const, @nil_check
  end

  class RespondsTo < ASTNode
    property obj : ASTNode
    property name : String

    def initialize(@obj, @name)
    end

    def accept_children(visitor)
      obj.accept visitor
    end

    def clone_without_location
      RespondsTo.new(@obj.clone, @name)
    end

    def_equals_and_hash @obj, @name
  end

  class Require < ASTNode
    property string : String

    def initialize(@string)
    end

    def clone_without_location
      Require.new(@string)
    end

    def_equals_and_hash string
  end

  class When < ASTNode
    property conds : Array(ASTNode)
    property body : ASTNode
    property? exhaustive : Bool

    def initialize(@conds : Array(ASTNode), body : ASTNode? = nil, @exhaustive = false)
      @body = Expressions.from body
    end

    def self.new(cond : ASTNode, body : ASTNode? = nil, exhaustive = false)
      new([cond] of ASTNode, body, exhaustive)
    end

    def accept_children(visitor)
      @conds.each &.accept visitor
      @body.accept visitor
    end

    def clone_without_location
      When.new(@conds.clone, @body.clone, @exhaustive)
    end

    def_equals_and_hash @conds, @body, @exhaustive
  end

  class Case < ASTNode
    property cond : ASTNode?
    property whens : Array(When)
    property else : ASTNode?
    property? exhaustive : Bool

    def initialize(@cond : ASTNode?, @whens : Array(When), @else : ASTNode?, @exhaustive : Bool)
      @whens.each do |wh|
        wh.exhaustive = self.exhaustive?
      end
    end

    def accept_children(visitor)
      @cond.try &.accept visitor
      @whens.each &.accept visitor
      @else.try &.accept visitor
    end

    def clone_without_location
      Case.new(@cond.clone, @whens.clone, @else.clone, @exhaustive)
    end

    def_equals_and_hash @exhaustive, @cond, @whens, @else
  end

  class Select < ASTNode
    property whens : Array(When)
    property else : ASTNode?

    def initialize(@whens, @else = nil)
    end

    def accept_children(visitor)
      @whens.each &.accept visitor
      @else.try &.accept visitor
    end

    def clone_without_location
      Select.new(@whens.clone, @else.clone)
    end

    def_equals_and_hash @whens, @else
  end

  # Node that represents an implicit obj in:
  #
  #     case foo
  #     when .bar? # this is a call with an implicit obj
  #     end
  class ImplicitObj < ASTNode
    def ==(other : self)
      true
    end

    def clone_without_location
      self
    end

    def_hash
  end

  # A qualified identifier.
  #
  #     const [ '::' const ]*
  #
  class Path < ASTNode
    property names : Array(String)
    property? global : Bool
    property visibility = Visibility::Public

    def initialize(@names : Array, @global = false)
    end

    def self.new(name : String, global = false)
      new [name], global
    end

    def self.new(name1 : String, name2 : String, global = false)
      new [name1, name2], global
    end

    def self.global(names)
      new names, true
    end

    def name_size
      names.sum(&.size) + (names.size + (global? ? 0 : -1)) * 2
    end

    # Returns true if this path has a single component
    # with the given name
    def single?(name)
      names.size == 1 && names.first == name
    end

    # Returns this path's name if it has only one part and is not global
    def single_name?
      names.first if names.size == 1 && !global?
    end

    def clone_without_location
      ident = Path.new(@names.clone, @global)
      ident
    end

    def_equals_and_hash @names, @global
  end

  # Class definition:
  #
  #     'class' name [ '<' superclass ]
  #       body
  #     'end'
  #
  class ClassDef < ASTNode
    property name : Path
    property body : ASTNode
    property superclass : ASTNode?
    property type_vars : Array(String)?
    property name_location : Location?
    property doc : String?
    property splat_index : Int32?
    property? abstract : Bool
    property? struct : Bool
    property visibility = Visibility::Public

    def initialize(@name, body = nil, @superclass = nil, @type_vars = nil, @abstract = false, @struct = false, @splat_index = nil)
      @body = Expressions.from body
    end

    def accept_children(visitor)
      @superclass.try &.accept visitor
      @body.accept visitor
    end

    def clone_without_location
      clone = ClassDef.new(@name, @body.clone, @superclass.clone, @type_vars.clone, @abstract, @struct, @splat_index)
      clone.name_location = name_location
      clone
    end

    def_equals_and_hash @name, @body, @superclass, @type_vars, @abstract, @struct, @splat_index
  end

  # Module definition:
  #
  #     'module' name
  #       body
  #     'end'
  #
  class ModuleDef < ASTNode
    property name : Path
    property body : ASTNode
    property type_vars : Array(String)?
    property splat_index : Int32?
    property name_location : Location?
    property doc : String?
    property visibility = Visibility::Public

    def initialize(@name, body = nil, @type_vars = nil, @splat_index = nil)
      @body = Expressions.from body
    end

    def accept_children(visitor)
      @body.accept visitor
    end

    def clone_without_location
      clone = ModuleDef.new(@name, @body.clone, @type_vars.clone, @splat_index)
      clone.name_location = name_location
      clone
    end

    def_equals_and_hash @name, @body, @type_vars, @splat_index
  end

  # Annotation definition:
  #
  #     'annotation' name
  #     'end'
  #
  class AnnotationDef < ASTNode
    property name : Path
    property doc : String?
    property name_location : Location?

    def initialize(@name)
    end

    def accept_children(visitor)
    end

    def clone_without_location
      clone = AnnotationDef.new(@name)
      clone.name_location = name_location
      clone
    end

    def_equals_and_hash @name
  end

  # While expression.
  #
  #     'while' cond
  #       body
  #     'end'
  #
  class While < ASTNode
    property cond : ASTNode
    property body : ASTNode

    def initialize(@cond, body = nil)
      @body = Expressions.from body
    end

    def accept_children(visitor)
      @cond.accept visitor
      @body.accept visitor
    end

    def clone_without_location
      While.new(@cond.clone, @body.clone)
    end

    def_equals_and_hash @cond, @body
  end

  # Until expression.
  #
  #     'until' cond
  #       body
  #     'end'
  #
  class Until < ASTNode
    property cond : ASTNode
    property body : ASTNode

    def initialize(@cond, body = nil)
      @body = Expressions.from body
    end

    def accept_children(visitor)
      @cond.accept visitor
      @body.accept visitor
    end

    def clone_without_location
      Until.new(@cond.clone, @body.clone)
    end

    def_equals_and_hash @cond, @body
  end

  class Generic < ASTNode
    # Usually a Path, but can also be a TypeNode in the case of a
    # custom array/hash-like literal.
    property name : ASTNode
    property type_vars : Array(ASTNode)
    property named_args : Array(NamedArgument)?

    property suffix : Suffix

    enum Suffix
      None
      Question # T?
      Asterisk # T*
      Bracket  # T[N]
    end

    def initialize(@name, @type_vars : Array, @named_args = nil, @suffix = Suffix::None)
    end

    def self.new(name, type_var : ASTNode)
      new name, [type_var] of ASTNode
    end

    def accept_children(visitor)
      @name.accept visitor
      @type_vars.each &.accept visitor
      @named_args.try &.each &.accept visitor
    end

    def clone_without_location
      generic = Generic.new(@name.clone, @type_vars.clone, @named_args.clone, @suffix)
      generic
    end

    def_equals_and_hash @name, @type_vars, @named_args
  end

  class TypeDeclaration < ASTNode
    property doc : String?
    property var : ASTNode
    property declared_type : ASTNode
    property value : ASTNode?

    def initialize(@var, @declared_type, @value = nil)
    end

    def accept_children(visitor)
      var.accept visitor
      declared_type.accept visitor
      value.try &.accept visitor
    end

    def name_size
      var = @var
      case var
      when Var
        var.name.size
      when InstanceVar
        var.name.size
      when ClassVar
        var.name.size
      when Global
        var.name.size
      else
        raise "can't happen"
      end
    end

    def clone_without_location
      TypeDeclaration.new(@var.clone, @declared_type.clone, @value.clone)
    end

    def_equals_and_hash @var, @declared_type, @value
  end

  class UninitializedVar < ASTNode
    property var : ASTNode
    property declared_type : ASTNode

    def initialize(@var, @declared_type)
    end

    def accept_children(visitor)
      var.accept visitor
      declared_type.accept visitor
    end

    def name_size
      var = @var
      case var
      when Var
        var.name.size
      when InstanceVar
        var.name.size
      when ClassVar
        var.name.size
      else
        raise "can't happen"
      end
    end

    def clone_without_location
      UninitializedVar.new(@var.clone, @declared_type.clone)
    end

    def_equals_and_hash @var, @declared_type
  end

  class Rescue < ASTNode
    property body : ASTNode
    property types : Array(ASTNode)?
    property name : String?

    def initialize(body = nil, @types = nil, @name = nil)
      @body = Expressions.from body
    end

    def accept_children(visitor)
      @body.accept visitor
      @types.try &.each &.accept visitor
    end

    def clone_without_location
      Rescue.new(@body.clone, @types.clone, @name)
    end

    def_equals_and_hash @body, @types, @name
  end

  class ExceptionHandler < ASTNode
    property body : ASTNode
    property rescues : Array(Rescue)?
    property else : ASTNode?
    property ensure : ASTNode?
    property implicit = false
    property suffix = false

    # The location of the `else` keyword if present.
    property else_location : Location?

    # The location of the `ensure` keyword if present.
    property ensure_location : Location?

    def initialize(body = nil, @rescues = nil, @else = nil, @ensure = nil)
      @body = Expressions.from body
    end

    def accept_children(visitor)
      @body.accept visitor
      @rescues.try &.each &.accept visitor
      @else.try &.accept visitor
      @ensure.try &.accept visitor
    end

    def clone_without_location
      ex = ExceptionHandler.new(@body.clone, @rescues.clone, @else.clone, @ensure.clone)
      ex.implicit = implicit
      ex.suffix = suffix
      ex
    end

    def_equals_and_hash @body, @rescues, @else, @ensure
  end

  class ProcLiteral < ASTNode
    property def : Def

    def initialize(@def = Def.new("->"))
    end

    def accept_children(visitor)
      @def.accept visitor
    end

    def clone_without_location
      ProcLiteral.new(@def.clone)
    end

    def_equals_and_hash @def
  end

  class ProcPointer < ASTNode
    property obj : ASTNode?
    property name : String
    property args : Array(ASTNode)
    property? global : Bool

    def initialize(@obj, @name, @args = [] of ASTNode, @global = false)
    end

    def accept_children(visitor)
      @obj.try &.accept visitor
      @args.each &.accept visitor
    end

    def clone_without_location
      ProcPointer.new(@obj.clone, @name, @args.clone, @global)
    end

    def_equals_and_hash @obj, @name, @args, @global
  end

  class Union < ASTNode
    property types : Array(ASTNode)

    def initialize(@types)
    end

    def accept_children(visitor)
      @types.each &.accept visitor
    end

    def clone_without_location
      Union.new(@types.clone)
    end

    def_equals_and_hash types
  end

  class Self < ASTNode
    def ==(other : self)
      true
    end

    def clone_without_location
      Self.new
    end

    def_hash
  end

  abstract class ControlExpression < ASTNode
    property exp : ASTNode?

    def initialize(@exp : ASTNode? = nil)
    end

    def accept_children(visitor)
      @exp.try &.accept visitor
    end

    def end_location
      @end_location || @exp.try(&.end_location)
    end

    def_equals_and_hash exp
  end

  class Return < ControlExpression
    def clone_without_location
      Return.new(@exp.clone)
    end
  end

  class Break < ControlExpression
    def clone_without_location
      Break.new(@exp.clone)
    end
  end

  class Next < ControlExpression
    def clone_without_location
      Next.new(@exp.clone)
    end
  end

  class Yield < ASTNode
    property exps : Array(ASTNode)
    property scope : ASTNode?
    property? has_parentheses = false

    def initialize(@exps = [] of ASTNode, @scope = nil, @has_parentheses = false)
    end

    def accept_children(visitor)
      @scope.try &.accept visitor
      @exps.each &.accept visitor
    end

    def clone_without_location
      Yield.new(@exps.clone, @scope.clone, @has_parentheses)
    end

    def end_location
      @end_location || @exps.last?.try(&.end_location)
    end

    def_equals_and_hash @exps, @scope, @has_parentheses
  end

  class Include < ASTNode
    property name : ASTNode

    def initialize(@name)
    end

    def accept_children(visitor)
      @name.accept visitor
    end

    def clone_without_location
      Include.new(@name)
    end

    def end_location
      @end_location || @name.end_location
    end

    def_equals_and_hash name
  end

  class Extend < ASTNode
    property name : ASTNode

    def initialize(@name)
    end

    def accept_children(visitor)
      @name.accept visitor
    end

    def clone_without_location
      Extend.new(@name)
    end

    def end_location
      @end_location || @name.end_location
    end

    def_equals_and_hash name
  end

  class LibDef < ASTNode
    property name : Path
    property doc : String?
    property body : ASTNode
    property name_location : Location?
    property visibility = Visibility::Public

    def initialize(@name, body = nil)
      @body = Expressions.from body
    end

    def accept_children(visitor)
      @body.accept visitor
    end

    def clone_without_location
      clone = LibDef.new(@name, @body.clone)
      clone.name_location = name_location
      clone
    end

    def_equals_and_hash @name, @body
  end

  class FunDef < ASTNode
    property name : String
    property args : Array(Arg)
    property return_type : ASTNode?
    property body : ASTNode?
    property real_name : String
    property doc : String?
    property? varargs : Bool
    property name_location : Location?

    def initialize(@name, @args = [] of Arg, @return_type = nil, @varargs = false, @body = nil, @real_name = name)
    end

    def accept_children(visitor)
      @args.each &.accept visitor
      @return_type.try &.accept visitor
      @body.try &.accept visitor
    end

    def clone_without_location
      clone = FunDef.new(@name, @args.clone, @return_type.clone, @varargs, @body.clone, @real_name)
      clone.name_location = name_location
      clone
    end

    def name_size
      @name.size
    end

    def_equals_and_hash @name, @args, @return_type, @varargs, @body, @real_name
  end

  class TypeDef < ASTNode
    property name : String
    property doc : String?
    property type_spec : ASTNode
    property name_location : Location?

    def initialize(@name, @type_spec)
    end

    def accept_children(visitor)
      @type_spec.accept visitor
    end

    def clone_without_location
      clone = TypeDef.new(@name, @type_spec.clone)
      clone.name_location = name_location
      clone
    end

    def_equals_and_hash @name, @type_spec
  end

  # A c struct/union definition inside a lib declaration
  class CStructOrUnionDef < ASTNode
    property name : String
    property doc : String?
    property body : ASTNode
    property? union : Bool

    def initialize(@name, body = nil, @union = false)
      @body = Expressions.from(body)
    end

    def accept_children(visitor)
      @body.accept visitor
    end

    def clone_without_location
      CStructOrUnionDef.new(@name, @body.clone, @union)
    end

    def_equals_and_hash @name, @union, @body
  end

  class EnumDef < ASTNode
    property name : Path
    property members : Array(ASTNode)
    property base_type : ASTNode?
    property doc : String?
    property visibility = Visibility::Public

    def initialize(@name, @members = [] of ASTNode, @base_type = nil)
    end

    def accept_children(visitor)
      @members.each &.accept visitor
      @base_type.try &.accept visitor
    end

    def clone_without_location
      EnumDef.new(@name, @members.clone, @base_type.clone)
    end

    def_equals_and_hash @name, @members, @base_type
  end

  class ExternalVar < ASTNode
    property name : String
    property doc : String?
    property type_spec : ASTNode
    property real_name : String?

    def initialize(@name, @type_spec, @real_name = nil)
    end

    def accept_children(visitor)
      @type_spec.accept visitor
    end

    def clone_without_location
      ExternalVar.new(@name, @type_spec.clone, @real_name)
    end

    def_equals_and_hash @name, @type_spec, @real_name
  end

  class Alias < ASTNode
    property name : Path
    property value : ASTNode
    property doc : String?
    property visibility = Visibility::Public

    def initialize(@name : Path, @value : ASTNode)
    end

    def accept_children(visitor)
      @value.accept visitor
    end

    def clone_without_location
      Alias.new(@name.clone, @value.clone)
    end

    def_equals_and_hash @name, @value
  end

  class Metaclass < ASTNode
    property name : ASTNode

    def initialize(@name)
    end

    def accept_children(visitor)
      @name.accept visitor
    end

    def clone_without_location
      Metaclass.new(@name.clone)
    end

    def_equals_and_hash name
  end

  # obj as to
  class Cast < ASTNode
    property obj : ASTNode
    property to : ASTNode

    def initialize(@obj : ASTNode, @to : ASTNode)
    end

    def accept_children(visitor)
      @obj.accept visitor
      @to.accept visitor
    end

    def clone_without_location
      Cast.new(@obj.clone, @to.clone)
    end

    def end_location
      @end_location || @to.end_location
    end

    def_equals_and_hash @obj, @to
  end

  # obj.as?(to)
  class NilableCast < ASTNode
    property obj
    property to

    def initialize(@obj : ASTNode, @to : ASTNode)
    end

    def accept_children(visitor)
      @obj.accept visitor
      @to.accept visitor
    end

    def clone_without_location
      NilableCast.new(@obj.clone, @to.clone)
    end

    def end_location
      @end_location || @to.end_location
    end

    def_equals_and_hash @obj, @to
  end

  # typeof(exp, exp, ...)
  class TypeOf < ASTNode
    property expressions : Array(ASTNode)

    def initialize(@expressions)
    end

    def accept_children(visitor)
      @expressions.each &.accept visitor
    end

    def clone_without_location
      TypeOf.new(@expressions.clone)
    end

    def_equals_and_hash expressions
  end

  class Annotation < ASTNode
    property path : Path
    property args : Array(ASTNode)
    property named_args : Array(NamedArgument)?
    property doc : String?

    def initialize(@path, @args = [] of ASTNode, @named_args = nil)
    end

    def accept_children(visitor)
      @path.accept visitor
      @args.each &.accept visitor
      @named_args.try &.each &.accept visitor
    end

    def clone_without_location
      Annotation.new(@path.clone, @args.clone, @named_args.clone)
    end

    def_equals_and_hash path, args, named_args
  end

  # A macro expression,
  # surrounded by {{ ... }} (output = true)
  # or by {% ... %} (output = false)
  class MacroExpression < ASTNode
    property exp : ASTNode
    property? output : Bool

    def initialize(@exp : ASTNode, @output = true)
    end

    def accept_children(visitor)
      @exp.accept visitor
    end

    def clone_without_location
      MacroExpression.new(@exp.clone, @output)
    end

    def_equals_and_hash exp, output?
  end

  # Free text that is part of a macro
  class MacroLiteral < ASTNode
    property value : String

    def initialize(@value : String)
    end

    def clone_without_location
      self
    end

    def_equals_and_hash value
  end

  class MacroVerbatim < UnaryExpression
    def clone_without_location
      MacroVerbatim.new(@exp.clone)
    end
  end

  # if inside a macro
  #
  #     {% 'if' cond %}
  #       then
  #     {% 'else' %}
  #       else
  #     {% 'end' %}
  class MacroIf < ASTNode
    property cond : ASTNode
    property then : ASTNode
    property else : ASTNode
    property? is_unless : Bool

    def initialize(@cond, a_then = nil, a_else = nil, @is_unless : Bool = false)
      @then = Expressions.from a_then
      @else = Expressions.from a_else
    end

    def accept_children(visitor)
      @cond.accept visitor
      @then.accept visitor
      @else.accept visitor
    end

    def clone_without_location
      MacroIf.new(@cond.clone, @then.clone, @else.clone, @is_unless)
    end

    def_equals_and_hash @cond, @then, @else, @is_unless
  end

  # for inside a macro:
  #
  #    {% for x1, x2, ..., xn in exp %}
  #      body
  #    {% end %}
  class MacroFor < ASTNode
    property vars : Array(Var)
    property exp : ASTNode
    property body : ASTNode

    def initialize(@vars, @exp, @body)
    end

    def accept_children(visitor)
      @vars.each &.accept visitor
      @exp.accept visitor
      @body.accept visitor
    end

    def clone_without_location
      MacroFor.new(@vars.clone, @exp.clone, @body.clone)
    end

    def_equals_and_hash @vars, @exp, @body
  end

  # A uniquely named variable inside a macro (like %var)
  class MacroVar < ASTNode
    property name : String
    property exps : Array(ASTNode)?

    def initialize(@name : String, @exps = nil)
    end

    def accept_children(visitor)
      @exps.try &.each &.accept visitor
    end

    def clone_without_location
      MacroVar.new(@name, @exps.clone)
    end

    def_equals_and_hash @name, @exps
  end

  # An underscore matches against any type
  class Underscore < ASTNode
    def ==(other : self)
      true
    end

    def clone_without_location
      Underscore.new
    end

    def_hash
  end

  class Splat < UnaryExpression
    def clone_without_location
      Splat.new(@exp.clone)
    end
  end

  class DoubleSplat < UnaryExpression
    def clone_without_location
      DoubleSplat.new(@exp.clone)
    end
  end

  class MagicConstant < ASTNode
    property name : Token::Kind

    def initialize(@name : Token::Kind)
    end

    def clone_without_location
      MagicConstant.new(@name)
    end

    def expand_node(location, end_location)
      case name
      when .magic_line?
        MagicConstant.expand_line_node(location)
      when .magic_end_line?
        MagicConstant.expand_line_node(end_location)
      when .magic_file?
        MagicConstant.expand_file_node(location)
      when .magic_dir?
        MagicConstant.expand_dir_node(location)
      else
        raise "BUG: unknown magic constant: #{name}"
      end
    end

    def self.expand_line_node(location)
      NumberLiteral.new(expand_line(location))
    end

    def self.expand_line(location)
      (location.try(&.expanded_location) || location).try(&.line_number) || 0
    end

    def self.expand_file_node(location)
      StringLiteral.new(expand_file(location))
    end

    def self.expand_file(location)
      location.try(&.original_filename.to_s) || "?"
    end

    def self.expand_dir_node(location)
      StringLiteral.new(expand_dir(location))
    end

    def self.expand_dir(location)
      location.try(&.dirname) || "?"
    end

    def_equals_and_hash name
  end

  class Asm < ASTNode
    property text : String
    property outputs : Array(AsmOperand)?
    property inputs : Array(AsmOperand)?
    property clobbers : Array(String)?
    property? volatile : Bool
    property? alignstack : Bool
    property? intel : Bool
    property? can_throw : Bool

    def initialize(@text, @outputs = nil, @inputs = nil, @clobbers = nil, @volatile = false, @alignstack = false, @intel = false, @can_throw = false)
    end

    def accept_children(visitor)
      @outputs.try &.each &.accept visitor
      @inputs.try &.each &.accept visitor
    end

    def clone_without_location
      Asm.new(@text, @outputs.clone, @inputs.clone, @clobbers, @volatile, @alignstack, @intel, @can_throw)
    end

    def_equals_and_hash text, outputs, inputs, clobbers, volatile?, alignstack?, intel?, can_throw?
  end

  class AsmOperand < ASTNode
    property constraint : String
    property exp : ASTNode

    def initialize(@constraint : String, @exp : ASTNode)
    end

    def accept_children(visitor)
      @exp.accept visitor
    end

    def clone_without_location
      AsmOperand.new(@constraint, @exp)
    end

    def_equals_and_hash constraint, exp
  end

  enum Visibility : Int8
    Public
    Protected
    Private
  end
end

require "./to_s"
