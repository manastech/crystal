require "spec"
require "../../../src/compiler/crystal/formatter"

private def assert_format(input, output = input, strict = false, flags = nil, file = __FILE__, line = __LINE__, focus = false)
  it "formats #{input.inspect}", file, line, focus: focus do
    output = "#{output}\n" unless strict
    result = Crystal.format(input, flags: flags)
    unless result == output
      message = <<-ERROR
        Expected

        ~~~
        #{input}
        ~~~

        to format to:

        ~~~
        #{output}
        ~~~

        but got:

        ~~~
        #{result}
        ~~~

          assert_format #{input.inspect}, #{result.chomp.inspect}
        ERROR

      fail message, file: file, line: line
    end

    # Check idempotency
    result2 = Crystal.format(result, flags: flags)
    unless result == result2
      fail "Idempotency failed:\nBefore: #{result.inspect}\nAfter:  #{result2.inspect}", file: file, line: line
    end
  end
end

describe Crystal::Formatter do
  assert_format "", "", strict: true

  assert_format "nil"

  assert_format "true"
  assert_format "false"

  assert_format "'\\n'"
  assert_format "'a'"
  assert_format "'\\u{0123}'"

  assert_format ":foo"
  assert_format ":\"foo\""

  assert_format "()"
  assert_format "(())"

  assert_format "1"
  assert_format "1   ;    2", "1; 2"
  assert_format "1   ;\n    2", "1\n2"
  assert_format "1\n\n2", "1\n\n2"
  assert_format "1\n\n\n2", "1\n\n2"
  assert_format "1_234", "1_234"
  assert_format "0x1234_u32", "0x1234_u32"
  assert_format "0_u64", "0_u64"
  assert_format "0u64", "0u64"
  assert_format "0i64", "0i64"

  assert_format "   1", "1"
  assert_format "\n\n1", "1"
  assert_format "\n# hello\n1", "# hello\n1"
  assert_format "\n# hello\n\n1", "# hello\n\n1"
  assert_format "\n# hello\n\n\n1", "# hello\n\n1"
  assert_format "\n   # hello\n\n1", "# hello\n\n1"

  assert_format %("hello")
  assert_format %(%(hello))
  assert_format %(%<hello>)
  assert_format %(%[hello])
  assert_format %(%{hello})
  assert_format %("hel\\nlo")
  assert_format %("hel\nlo")

  assert_format "[] of Foo"
  assert_format "[\n]   of   \n   Foo  ", "[] of Foo"
  assert_format "[1, 2, 3]"
  assert_format "[1, 2, 3] of Foo"
  assert_format "  [   1  ,    2  ,    3  ]  ", "[1, 2, 3]"
  assert_format "[1, 2, 3,  ]", "[1, 2, 3]"
  assert_format "[1,\n2,\n3]", "[1,\n 2,\n 3]"
  assert_format "[1,\n2,\n3\n]", "[1,\n 2,\n 3,\n]"
  assert_format "[\n1,\n2,\n3]", "[\n  1,\n  2,\n  3,\n]"
  assert_format "[\n  [\n    1,\n  ], [\n    2,\n  ], [\n    3,\n  ],\n]"
  assert_format "[\n  {\n    1 => 2,\n  }, {\n    3 => 4,\n  }, {\n    5 => 6,\n  },\n]"
  assert_format "if 1\n[   1  ,    2  ,    3  ]\nend", "if 1\n  [1, 2, 3]\nend"
  assert_format "    [   1,   \n   2   ,   \n   3   ]   ", "[1,\n 2,\n 3]"
  assert_format "Set { 1 , 2 }", "Set{1, 2}"
  assert_format "[\n1,\n\n2]", "[\n  1,\n\n  2,\n]"
  assert_format "[ # foo\n  1,\n]"
  assert_format "Set{ # foo\n  1,\n}"
  assert_format "begin\n  array[\n    0 # Zero\n  ]\nend"
  assert_format "begin\n  array[\n    0, # Zero\n  ]\nend"
  assert_format "[\n  # foo\n] of String"
  assert_format "[\n# foo\n] of String", "[\n  # foo\n] of String"

  assert_format "{1, 2, 3}"
  assert_format "{ {1, 2, 3} }"
  assert_format "{ {1 => 2} }"
  assert_format "{ {1, 2, 3} => 4 }"
  assert_format "{ {foo: 2} }"
  assert_format "{ # foo\n  1,\n}"

  assert_format "{ * 1 * 2,\n*\n3, 4 }", "{*1 * 2,\n *3, 4}"
  assert_format "[ * [ * [ 1 ] ], *    \n[ 2] ]", "[*[*[1]], *[2]]"

  assert_format "{  } of  A   =>   B", "{} of A => B"
  assert_format "{ 1   =>   2 }", "{1 => 2}"
  assert_format "{ 1   =>   2 ,   3  =>  4 }", "{1 => 2, 3 => 4}"
  assert_format "{ 1   =>   2 ,\n   3  =>  4 }", "{1 => 2,\n 3 => 4}"
  assert_format "{\n1   =>   2 ,\n   3  =>  4 }", "{\n  1 => 2,\n  3 => 4,\n}"
  assert_format "{ foo:  1 }", "{foo: 1}"
  assert_format "{ \"foo\":  1 }", "{\"foo\": 1}"
  assert_format "{ \"foo\" =>  1 }", "{\"foo\" => 1}"
  assert_format "{ 1   =>   2 ,\n\n   3  =>  4 }", "{1 => 2,\n\n 3 => 4}"
  assert_format "foo({\nbar: 1,\n})", "foo({\n  bar: 1,\n})"
  assert_format "{ # foo\n  1 => 2,\n}"

  assert_format "Foo"
  assert_format "Foo:: Bar", "Foo::Bar"
  assert_format "Foo:: Bar", "Foo::Bar"
  assert_format "::Foo:: Bar", "::Foo::Bar"
  assert_format "Foo(  )", "Foo()"
  assert_format "Foo( A , 1 )", "Foo(A, 1)"
  assert_format "Foo( x:  Int32  )", "Foo(x: Int32)"
  assert_format "Foo( x:  Int32  ,  y: Float64 )", "Foo(x: Int32, y: Float64)"
  assert_format "Foo(  * T, { * A  ,*\n  B } )", "Foo(*T, {*A, *B})"
  assert_format "Foo( Bar(  ) )", "Foo(Bar())"

  assert_format "NamedTuple(a: Int32,)", "NamedTuple(a: Int32)"
  assert_format "NamedTuple(\n  a: Int32,\n)"
  assert_format "NamedTuple(\n  a: Int32,)", "NamedTuple(\n  a: Int32,\n)"
  assert_format "class Foo\n  NamedTuple(\n    a: Int32,\n  )\nend"

  assert_format "::Tuple(T)"
  assert_format "::NamedTuple(T)"
  assert_format "::Pointer(T)"
  assert_format "::StaticArray(T)"

  assert_format "Tuple()"
  assert_format "::Tuple()"
  assert_format "NamedTuple()"
  assert_format "::NamedTuple()"

  %w(if unless).each do |keyword|
    assert_format "#{keyword} a\n2\nend", "#{keyword} a\n  2\nend"
    assert_format "#{keyword} a\n2\n3\nend", "#{keyword} a\n  2\n  3\nend"
    assert_format "#{keyword} a\n2\nelse\nend", "#{keyword} a\n  2\nelse\nend"
    assert_format "#{keyword} a\nelse\n2\nend", "#{keyword} a\nelse\n  2\nend"
    assert_format "#{keyword} a\n2\nelse\n3\nend", "#{keyword} a\n  2\nelse\n  3\nend"
    assert_format "#{keyword} a\n2\n3\nelse\n4\n5\nend", "#{keyword} a\n  2\n  3\nelse\n  4\n  5\nend"
    assert_format "#{keyword} a\n#{keyword} b\n3\nelse\n4\nend\nend", "#{keyword} a\n  #{keyword} b\n    3\n  else\n    4\n  end\nend"
    assert_format "#{keyword} a\n#{keyword} b\nelse\n4\nend\nend", "#{keyword} a\n  #{keyword} b\n  else\n    4\n  end\nend"
    assert_format "#{keyword} a\n    # hello\n 2\nend", "#{keyword} a\n  # hello\n  2\nend"
    assert_format "#{keyword} a\n2; 3\nelse\n3\nend", "#{keyword} a\n  2; 3\nelse\n  3\nend"
  end

  assert_format "if 1\n2\nelsif\n3\n4\nend", "if 1\n  2\nelsif 3\n  4\nend"
  assert_format "if 1\n2\nelsif\n3\n4\nelsif 5\n6\nend", "if 1\n  2\nelsif 3\n  4\nelsif 5\n  6\nend"
  assert_format "if 1\n2\nelsif\n3\n4\nelse\n6\nend", "if 1\n  2\nelsif 3\n  4\nelse\n  6\nend"

  assert_format "{% if 1 %}\n  2\n{% end %}\ndef foo\nend"

  assert_format "if 1\n2\nend\nif 3\nend", "if 1\n  2\nend\nif 3\nend"
  assert_format "if 1\nelse\n2\nend\n3", "if 1\nelse\n  2\nend\n3"

  assert_format "1 ? 2 : 3"
  assert_format "1 ?\n  2    :   \n 3", "1 ? 2 : 3"

  assert_format "1   if   2", "1 if 2"
  assert_format "1   unless   2", "1 unless 2"

  assert_format "[] of Int32\n1"

  assert_format "(1)"
  assert_format "  (  1;  2;   3  )  ", "(1; 2; 3)"
  assert_format "(\n  a = 1\n  a\n)"
  assert_format "begin; 1; end", "begin\n  1\nend"
  assert_format "begin\n1\n2\n3\nend", "begin\n  1\n  2\n  3\nend"
  assert_format "begin\n1 ? 2 : 3\nend", "begin\n  1 ? 2 : 3\nend"
  assert_format "begin\n  begin\n\n  end\nend"
  assert_format "begin\n  ()\nend"

  assert_format "def   foo  \n  end", "def foo\nend"
  assert_format "def foo\n1\nend", "def foo\n  1\nend"
  assert_format "def foo\n\n1\n\nend", "def foo\n  1\nend"
  assert_format "def foo()\n1\nend", "def foo\n  1\nend"
  assert_format "def foo   (   )   \n1\nend", "def foo\n  1\nend"
  assert_format "def self . foo\nend", "def self.foo\nend"
  assert_format "def   foo (  x )  \n  end", "def foo(x)\nend"
  assert_format "def   foo (  x , y )  \n  end", "def foo(x, y)\nend"
  assert_format "def   foo (  x , y , )  \n  end", "def foo(x, y)\nend"
  assert_format "def   foo (  x , y ,\n)  \n  end", "def foo(x, y)\nend"
  assert_format "def   foo (  x ,\n y )  \n  end", "def foo(x,\n        y)\nend"
  assert_format "def   foo (\nx ,\n y )  \n  end", "def foo(\n  x,\n  y,\n)\nend"
  assert_format "class Foo\ndef   foo (\nx ,\n y )  \n  end\nend", "class Foo\n  def foo(\n    x,\n    y,\n  )\n  end\nend"
  assert_format "def   foo (  @x)  \n  end", "def foo(@x)\nend"
  assert_format "def   foo (  @x, @y)  \n  end", "def foo(@x, @y)\nend"
  assert_format "def   foo (  @@x)  \n  end", "def foo(@@x)\nend"
  assert_format "def   foo (  &@block)  \n  end", "def foo(&@block)\nend"
  assert_format "def   foo (  @select)  \n  end", "def foo(@select)\nend"
  assert_format "def   foo (  @@select)  \n  end", "def foo(@@select)\nend"
  assert_format "def   foo (  bar  @select)  \n  end", "def foo(bar @select)\nend"
  assert_format "def   foo (  bar  @@select)  \n  end", "def foo(bar @@select)\nend"
  assert_format "def foo(a, &@b)\nend"
  assert_format "def   foo (  x  =   1 )  \n  end", "def foo(x = 1)\nend"
  assert_format "def   foo (  x  :  Int32 )  \n  end", "def foo(x : Int32)\nend"
  assert_format "def   foo (  x  :  self )  \n  end", "def foo(x : self)\nend"
  assert_format "def   foo (  x  :  Foo.class )  \n  end", "def foo(x : Foo.class)\nend"
  assert_format "def   foo (  x  :   Int32  =  1 )  \n  end", "def foo(x : Int32 = 1)\nend"
  assert_format "abstract  def   foo  \n  1", "abstract def foo\n\n1"
  assert_format "def foo( & block )\nend", "def foo(&block)\nend"
  assert_format "def foo( & )\nend", "def foo(&)\nend"
  assert_format "def foo( & \n )\nend", "def foo(&)\nend"
  assert_format "def foo( x , & block )\nend", "def foo(x, &block)\nend"
  assert_format "def foo( x , & block  : Int32 )\nend", "def foo(x, &block : Int32)\nend"
  assert_format "def foo( x , & block  : Int32 ->)\nend", "def foo(x, &block : Int32 ->)\nend"
  assert_format "def foo( x , & block  : Int32->Float64)\nend", "def foo(x, &block : Int32 -> Float64)\nend"
  assert_format "def foo( x , & block  :   ->)\nend", "def foo(x, &block : ->)\nend"
  assert_format "def foo( x , & : Int32 )\nend", "def foo(x, & : Int32)\nend"
  assert_format "def foo(&: Int32)\nend", "def foo(& : Int32)\nend"
  assert_format "def foo(&block: Int32)\nend", "def foo(&block : Int32)\nend"
  assert_format "def foo( x , * y )\nend", "def foo(x, *y)\nend"
  assert_format "class Bar\nprotected def foo(x)\na=b(c)\nend\nend", "class Bar\n  protected def foo(x)\n    a = b(c)\n  end\nend"
  assert_format "def foo=(x)\nend"
  assert_format "def +(x)\nend"
  assert_format "def   foo  :  Int32 \n  end", "def foo : Int32\nend"
  assert_format "def   foo ( x )  :  Int32 \n  end", "def foo(x) : Int32\nend"
  assert_format "def foo: Int32\nend", "def foo : Int32\nend"
  assert_format "def %(x)\n  1\nend"
  assert_format "def //(x)\n  1\nend"
  assert_format "def `(x)\n  1\nend"
  assert_format "def /(x)\n  1\nend"
  assert_format "def foo(x : X)  forall   X ,   Y; end", "def foo(x : X) forall X, Y; end"
  assert_format "def foo(x)\n  self // x\nend"
  assert_format "def foo(x)\n  case self // x\n  when 2\n    3\n  end\nend"
  assert_format "def foo(x)\n  case 1\n  when self // 2\n    3\n  end\nend"
  assert_format "def foo(x)\n  case //\n  when //\n    3\n  end\nend"
  assert_format "foo self // 1"
  assert_format "foo(self // 1)"
  assert_format "foo x, self // 1"
  assert_format "{x => self // 1}"
  assert_format "foo(//, //)"
  assert_format "foo(a: 1 // 2)"
  assert_format "foo(a: //)"
  assert_format "foo(a: //, b: //)"

  assert_format "def foo(a : T) forall T \n  #\nend", "def foo(a : T) forall T\n  #\nend"
  assert_format "def foo(a : T, b : U) forall T, U\n  #\nend", "def foo(a : T, b : U) forall T, U\n  #\nend"
  assert_format "def foo(a : T, b : U) forall T, U         #\n  #\nend", "def foo(a : T, b : U) forall T, U #\n  #\nend"
  assert_format "def foo(a : T) forall T\n  #\n\nend", "def foo(a : T) forall T\n  #\nend"
  assert_format "def foo(a : T) forall T\n  #\n\n\nend", "def foo(a : T) forall T\n  #\nend"
  assert_format "def foo\n  1\n  #\nrescue\nend"
  assert_format "def foo\n  1 #\nrescue\nend"
  assert_format "def foo\n  1 #\nrescue\nend"
  assert_format "def foo\n  1\n  #\n\n\nrescue\nend", "def foo\n  1\n  #\nrescue\nend"

  assert_format "def foo(@[MyAnn] v); end"
  assert_format "def foo(@[MyAnn] &); end"
  assert_format "def foo(@[MyAnn] &block); end"
  assert_format "def foo(@[MyAnn] & : String -> Nil); end"
  assert_format "def foo(  @[MyAnn]  v  ); end", "def foo(@[MyAnn] v); end"
  assert_format "def foo(@[AnnOne] @[AnnTwo] v); end"
  assert_format "def foo(@[AnnOne]   @[AnnTwo] v); end", "def foo(@[AnnOne] @[AnnTwo] v); end"
  assert_format "def foo(@[AnnOne]   @[AnnTwo]   &  ); end", "def foo(@[AnnOne] @[AnnTwo] &); end"
  assert_format "def foo(@[AnnOne]   @[AnnTwo]   &block : Int32 ->  ); end", "def foo(@[AnnOne] @[AnnTwo] &block : Int32 ->); end"
  assert_format <<-CRYSTAL
  def foo(
    @[MyAnn] bar,
  ); end
  CRYSTAL

  assert_format <<-CRYSTAL
  def foo(
    foo,
    @[MyAnn] &block
  ); end
  CRYSTAL

  assert_format <<-CRYSTAL
  def foo(
    foo,
    @[MyAnn]
    &block
  ); end
  CRYSTAL

  assert_format <<-CRYSTAL
  def foo(
    foo,

    @[MyAnn]
    &block
  ); end
  CRYSTAL

  assert_format <<-CRYSTAL
  def foo(
    foo,

    @[MyAnn]
    @[MyAnn]
    & : Nil -> Nil
  ); end
  CRYSTAL

  assert_format <<-CRYSTAL, <<-CRYSTAL
  def foo(
     @[MyAnn]   bar
  ); end
  CRYSTAL
  def foo(
    @[MyAnn] bar,
  ); end
  CRYSTAL

  assert_format <<-CRYSTAL
  def foo(
    @[MyAnn]
    bar,
  ); end
  CRYSTAL

  assert_format <<-CRYSTAL
  def foo(
    @[MyAnn]
    @[MyAnn]
    bar,
  ); end
  CRYSTAL

  assert_format <<-CRYSTAL
  def foo(
    @[MyAnn]
    @[MyAnn]
    bar,
    @[MyAnn] baz,
  ); end
  CRYSTAL

  assert_format <<-CRYSTAL
  def foo(
    @[MyAnn]
    @[MyAnn]
    bar,

    @[MyAnn] baz,
  ); end
  CRYSTAL

  assert_format <<-CRYSTAL, <<-CRYSTAL
  def foo(
     @[MyAnn]
   bar
  ); end
  CRYSTAL
  def foo(
    @[MyAnn]
    bar,
  ); end
  CRYSTAL

  assert_format <<-CRYSTAL, <<-CRYSTAL
  def foo(
     @[MyAnn]
   bar
  ); end
  CRYSTAL
  def foo(
    @[MyAnn]
    bar,
  ); end
  CRYSTAL

  assert_format <<-CRYSTAL
  def foo(
    @[MyAnn]
    @[MyAnn]
    bar,
    @[MyAnn] @[MyAnn] baz,
    @[MyAnn]
    @[MyAnn]
    biz,
  ); end
  CRYSTAL

  assert_format <<-CRYSTAL
  def foo(
    @[MyAnn]
    @[MyAnn]
    bar,

    @[MyAnn] @[MyAnn] baz,

    @[MyAnn]
    @[MyAnn]
    biz,
  ); end
  CRYSTAL

  assert_format <<-CRYSTAL, <<-CRYSTAL
  def foo(
    @[MyAnn]
    @[MyAnn]
    bar,

    @[MyAnn]  @[MyAnn]  baz,

    @[MyAnn]

    @[MyAnn]

    biz
  ); end
  CRYSTAL
  def foo(
    @[MyAnn]
    @[MyAnn]
    bar,

    @[MyAnn] @[MyAnn] baz,

    @[MyAnn]
    @[MyAnn]
    biz,
  ); end
  CRYSTAL

  assert_format <<-CRYSTAL, <<-CRYSTAL
    module M
      @[MyAnn(
        1

      )]
    end
    CRYSTAL
    module M
      @[MyAnn(
        1
      )]
    end
    CRYSTAL

  assert_format "loop do\n  1\nrescue\n  2\nend"
  assert_format "loop do\n  1\n  loop do\n    2\n  rescue\n    3\n  end\n  4\nend"

  assert_format "foo"
  assert_format "foo()"
  assert_format "foo(  )", "foo()"
  assert_format "foo  1", "foo 1"
  assert_format "foo  1  ,   2", "foo 1, 2"
  assert_format "foo(  1  ,   2 )", "foo(1, 2)"

  assert_format "foo . bar", "foo.bar"
  assert_format "foo . bar()", "foo.bar"
  assert_format "foo . bar( x , y )", "foo.bar(x, y)"
  assert_format "foo do  \n x \n end", "foo do\n  x\nend"
  assert_format "foo do  | x | \n x \n end", "foo do |x|\n  x\nend"
  assert_format "foo do  | x , y | \n x \n end", "foo do |x, y|\n  x\nend"
  assert_format "if 1\nfoo do  | x , y | \n x \n end\nend", "if 1\n  foo do |x, y|\n    x\n  end\nend"
  assert_format "foo do   # hello\nend", "foo do # hello\nend"
  assert_format "foo{}", "foo { }"
  assert_format "foo{|x| x}", "foo { |x| x }"
  assert_format "foo{|x|\n x}", "foo { |x|\n  x\n}"
  assert_format "foo   &.bar", "foo &.bar"
  assert_format "foo   &.bar( 1 , 2 )", "foo &.bar(1, 2)"
  assert_format "foo.bar  &.baz( 1 , 2 )", "foo.bar &.baz(1, 2)"
  assert_format "foo   &.bar", "foo &.bar"
  assert_format "foo   &.==(2)", "foo &.==(2)"
  assert_format "foo   &.>=(2)", "foo &.>=(2)"
  assert_format "join io, &.inspect"
  assert_format "foo . bar  =  1", "foo.bar = 1"
  assert_format "foo  x:  1", "foo x: 1"
  assert_format "foo  x:  1,  y:  2", "foo x: 1, y: 2"
  assert_format "foo a , b ,  x:  1", "foo a, b, x: 1"
  assert_format "foo a , *b", "foo a, *b"
  assert_format "foo a , **b", "foo a, **b"
  assert_format "foo   &bar", "foo &bar"
  assert_format "foo 1 ,  &bar", "foo 1, &bar"
  assert_format "foo(&.bar)"
  assert_format "foo.bar(&.baz)"
  assert_format "foo(1, &.bar)"
  assert_format "foo(1,\n  &.bar)"
  assert_format "foo(1, # foo\n  &.bar)"
  assert_format "::foo(1, 2)"
  assert_format "args.any? &.name.baz"
  assert_format "foo(\n  1, 2)", "foo(\n  1, 2)"
  assert_format "foo(\n1,\n 2  \n)", "foo(\n  1,\n  2\n)"
  assert_format "foo(\n1,\n\n 2  \n)", "foo(\n  1,\n\n  2\n)"
  assert_format "foo(\n  1,\n  # 2,\n  3,\n)"
  assert_format "foo(\n  1,\n  # 2,\n  # 3,\n)"
  assert_format "foo 1,\n2", "foo 1,\n  2"
  assert_format "foo 1, a: 1,\nb: 2,\nc: 3", "foo 1, a: 1,\n  b: 2,\n  c: 3"
  assert_format "foo 1,\na: 1,\nb: 2,\nc: 3", "foo 1,\n  a: 1,\n  b: 2,\n  c: 3"
  assert_format "foo bar:baz, qux:other", "foo bar: baz, qux: other"
  assert_format "foo(\n  1, 2, &block)", "foo(\n  1, 2, &block)"
  assert_format "foo(\n  1, 2,\n&block)", "foo(\n  1, 2,\n  &block)"
  assert_format "foo(\n  1,\n  2\n) do\n  1\nend"
  assert_format "foo 1, a: 1,\nb: 2,\nc: 3,\n&block", "foo 1, a: 1,\n  b: 2,\n  c: 3,\n  &block"
  assert_format "foo 1, do\n2\nend", "foo 1 do\n  2\nend"
  assert_format "a.b &.[c]?\n1"
  assert_format "a.b &.[c]\n1"
  assert_format "foo(1, 2,)", "foo(1, 2)"
  assert_format "foo(1, 2,\n)", "foo(1, 2)"
  assert_format "foo(1,\n2,\n)", "foo(1,\n  2,\n)"
  assert_format "foo(out x)", "foo(out x)"
  assert_format "foo(\n  1,\n  a: 1,\n  b: 2,\n)"
  assert_format "foo(1, ) { }", "foo(1) { }"
  assert_format "foo(1, ) do\nend", "foo(1) do\nend"
  assert_format "foo {;1}", "foo { 1 }"
  assert_format "foo {;;1}", "foo { 1 }"
  assert_format "foo.%(bar)"
  assert_format "foo.% bar"
  assert_format "foo.bar(&.%(baz))"
  assert_format "foo.bar(&.% baz)"
  assert_format "if 1\n  foo(\n    bar\n    # comment\n  )\nend"
  assert_format "if 1\n  foo(\n    bar,\n    # comment\n  )\nend"

  assert_format "foo.bar\n.baz", "foo.bar\n  .baz"
  assert_format "foo.bar.baz\n.qux", "foo.bar.baz\n  .qux"
  assert_format "foo\n.bar\n.baz", "foo\n  .bar\n  .baz"

  assert_format "foo.\nbar", "foo\n  .bar"

  assert_format "foo   &.is_a?(T)", "foo &.is_a?(T)"
  assert_format "foo   &.responds_to?(:foo)", "foo &.responds_to?(:foo)"

  assert_format "foo(\n  1,\n  &.foo\n)"

  %w(return break next yield).each do |keyword|
    assert_format keyword
    assert_format "#{keyword}( 1 )", "#{keyword}(1)"
    assert_format "#{keyword}  1", "#{keyword} 1"
    assert_format "#{keyword}( 1 , 2 )", "#{keyword}(1, 2)"
    assert_format "#{keyword}  1 ,  2", "#{keyword} 1, 2"
    assert_format "#{keyword}  *1", "#{keyword} *1"
    assert_format "#{keyword}  1  , *2", "#{keyword} 1, *2"
    assert_format "#{keyword}  *1  ,2", "#{keyword} *1, 2"
    assert_format "#{keyword}  *1  , *2", "#{keyword} *1, *2"
    assert_format "#{keyword}( *1  , *2 )", "#{keyword}(*1, *2)"

    unless keyword == "yield"
      assert_format "#{keyword} { 1 ,  2 }", "#{keyword} {1, 2}"
      assert_format "#{keyword} {1, 2}, 3"
      assert_format "#{keyword} 1, {2, 3}"
      assert_format "#{keyword} {1, 2}, {3, 4}"
      assert_format "#{keyword} { {1, 2}, {3, 4} }"
      assert_format "#{keyword} { {1, 2}, {3, 4} }, 5"
    end
  end

  assert_format "yield 1\n2", "yield 1\n2"
  assert_format "yield 1 , \n2", "yield 1,\n  2"
  assert_format "yield(1 , \n2)", "yield(1,\n  2)"
  assert_format "yield(\n1 , \n2)", "yield(\n  1,\n  2)"

  assert_format "with foo yield bar"

  context "adds `&` to yielding methods that don't have a block parameter (#8764)" do
    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo
        yield
      end
      CRYSTAL
      def foo(&)
        yield
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo()
        yield
      end
      CRYSTAL
      def foo(&)
        yield
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo(
      )
        yield
      end
      CRYSTAL
      def foo(&)
        yield
      end
      CRYSTAL

    # #13091
    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo # bar
        yield
      end
      CRYSTAL
      def foo(&) # bar
        yield
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo(x)
        yield
      end
      CRYSTAL
      def foo(x, &)
        yield
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo(x ,)
        yield
      end
      CRYSTAL
      def foo(x, &)
        yield
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo(x,
      y)
        yield
      end
      CRYSTAL
      def foo(x,
              y, &)
        yield
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo(x,
      y,)
        yield
      end
      CRYSTAL
      def foo(x,
              y, &)
        yield
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo(x
      )
        yield
      end
      CRYSTAL
      def foo(x,
              &)
        yield
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo(x,
      )
        yield
      end
      CRYSTAL
      def foo(x,
              &)
        yield
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo(
      x)
        yield
      end
      CRYSTAL
      def foo(
        x, &
      )
        yield
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo(
      x, y)
        yield
      end
      CRYSTAL
      def foo(
        x, y, &
      )
        yield
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo(
      x,
      y)
        yield
      end
      CRYSTAL
      def foo(
        x,
        y, &
      )
        yield
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo(
      x,
      )
        yield
      end
      CRYSTAL
      def foo(
        x,
        &
      )
        yield
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo(a, **b)
        yield
      end
      CRYSTAL
      def foo(a, **b, &)
        yield
      end
      CRYSTAL

    assert_format "macro f\n yield\n {{ yield }}\nend"
  end

  assert_format <<-CRYSTAL
    def foo(
      a,
      b,
    )
    end
    CRYSTAL

  assert_format <<-CRYSTAL
    def foo(
      a, b,
    )
    end
    CRYSTAL

  assert_format <<-CRYSTAL
    macro foo(
      a,
      *b,
    )
    end
    CRYSTAL

  assert_format <<-CRYSTAL
    macro foo(
      a,
      **b,
    )
    end
    CRYSTAL

  context "adds trailing comma to def multi-line normal, splat, and double splat parameters" do
    assert_format <<-CRYSTAL, <<-CRYSTAL
      macro foo(
        a,
        b
      )
      end
      CRYSTAL
      macro foo(
        a,
        b,
      )
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      macro foo(
        a,
        *b
      )
      end
      CRYSTAL
      macro foo(
        a,
        *b,
      )
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      fun foo(
        a : Int32,
        b : Int32
      )
      end
      CRYSTAL
      fun foo(
        a : Int32,
        b : Int32,
      )
      end
      CRYSTAL

    assert_format <<-CRYSTAL
      fun foo(
        a : Int32,
        ...
      )
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo(
        a,
        b
      )
      end
      CRYSTAL
      def foo(
        a,
        b,
      )
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo(
        a : Int32,
        b : Int32
      )
      end
      CRYSTAL
      def foo(
        a : Int32,
        b : Int32,
      )
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo(
        a : Int32,
        b : Int32 = 1
      )
      end
      CRYSTAL
      def foo(
        a : Int32,
        b : Int32 = 1,
      )
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo(
        a,
        b c
      )
      end
      CRYSTAL
      def foo(
        a,
        b c,
      )
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo(
        a,
        @[Ann] b
      )
      end
      CRYSTAL
      def foo(
        a,
        @[Ann] b,
      )
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo(
        a,
        @[Ann]
        b
      )
      end
      CRYSTAL
      def foo(
        a,
        @[Ann]
        b,
      )
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo(
        a, b
      )
      end
      CRYSTAL
      def foo(
        a, b,
      )
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo(
        a, b,
        c, d
      )
      end
      CRYSTAL
      def foo(
        a, b,
        c, d,
      )
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo(
        a, # Foo
        b # Bar
      )
      end
      CRYSTAL
      def foo(
        a, # Foo
        b, # Bar
      )
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo(
        a,
        *b
      )
      end
      CRYSTAL
      def foo(
        a,
        *b,
      )
      end
      CRYSTAL

    assert_format <<-CRYSTAL, <<-CRYSTAL
      def foo(
        a,
        **b
      )
      end
      CRYSTAL
      def foo(
        a,
        **b,
      )
      end
      CRYSTAL

    assert_format <<-CRYSTAL
      def foo(
        a,
        &block
      )
      end
      CRYSTAL

    assert_format <<-CRYSTAL
      def foo(
        a,
      )
      end
      CRYSTAL

    assert_format <<-CRYSTAL
      def foo(a)
      end
      CRYSTAL

    assert_format <<-CRYSTAL
      def foo(a, b)
      end
      CRYSTAL

    assert_format <<-CRYSTAL
      def foo(a, *args)
      end
      CRYSTAL

    assert_format <<-CRYSTAL
      def foo(a, *args, &block)
      end
      CRYSTAL

    assert_format <<-CRYSTAL
      def foo(a, **kwargs)
      end
      CRYSTAL

    assert_format <<-CRYSTAL
      def foo(a, **kwargs, &block)
      end
      CRYSTAL

    assert_format <<-CRYSTAL
      def foo(a, &block)
      end
      CRYSTAL
  end

  assert_format "1   +   2", "1 + 2"
  assert_format "1   &+   2", "1 &+ 2"
  assert_format "1   >   2", "1 > 2"
  assert_format "1   *   2", "1 * 2"
  assert_format "1*2", "1*2"
  assert_format "1/2", "1/2"
  assert_format "1 / 2", "1 / 2"
  assert_format "10/a", "10/a"
  assert_format "10 / a", "10 / a"
  assert_format "1 // 2", "1 // 2"
  assert_format "10//a", "10//a"
  assert_format "10 // a", "10 // a"
  assert_format "10**a", "10**a"
  assert_format "10 ** a", "10 ** a"
  assert_format %(" " * 2)
  assert_format "foo.bar / 2\n", "foo.bar / 2"

  assert_format "! 1", "!1"
  assert_format "- 1", "-1"
  assert_format "~ 1", "~1"
  assert_format "+ 1", "+1"
  assert_format "&- 1", "&-1"
  assert_format "&+ 1", "&+1"
  assert_format "a-1", "a - 1"
  assert_format "a+1", "a + 1"
  assert_format "a&-1", "a &- 1"
  assert_format "a&+1", "a &+ 1"
  assert_format "1 + \n2", "1 +\n  2"
  assert_format "1 +  # foo\n2", "1 + # foo\n  2"
  assert_format "a = 1 +  #    foo\n2", "a = 1 + #    foo\n    2"
  assert_format "1+2*3", "1 + 2*3"
  assert_format "1&+2&*3", "1 &+ 2 &* 3"

  assert_format "foo(1 + \n2)", "foo(1 +\n    2)"
  assert_format "foo(1 &+ \n2)", "foo(1 &+\n    2)"

  assert_format "foo(1 &- 2)"

  assert_format "foo[]", "foo[]"
  assert_format "foo[ 1 , 2 ]", "foo[1, 2]"
  assert_format "foo[ 1,  2 ]?", "foo[1, 2]?"
  assert_format "foo[] =1", "foo[] = 1"
  assert_format "foo[ 1 , 2 ]   =3", "foo[1, 2] = 3"

  assert_format "foo.[]"
  assert_format "foo.[ 1 , 2 ]", "foo.[1, 2]"
  assert_format "foo.[ 1,  2 ]?", "foo.[1, 2]?"
  assert_format "foo.[] =1", "foo.[] = 1"
  assert_format "foo.[ 1 , 2 ]   =3", "foo.[1, 2] = 3"

  assert_format "1  ||  2", "1 || 2"
  assert_format "a  ||  b", "a || b"
  assert_format "1  &&  2", "1 && 2"
  assert_format "1 &&\n2", "1 &&\n  2"
  assert_format "1 &&\n2 &&\n3", "1 &&\n  2 &&\n  3"
  assert_format "1 && # foo\n  2 &&\n  3"
  assert_format "if 0\n1 &&\n2 &&\n3\nend", "if 0\n  1 &&\n    2 &&\n    3\nend"
  assert_format "if 1 &&\n2 &&\n3\n4\nend", "if 1 &&\n   2 &&\n   3\n  4\nend"
  assert_format "if 1 &&\n   (2 || 3)\n  1\nelse\n  2\nend"
  assert_format "while 1 &&\n2 &&\n3\n4\nend", "while 1 &&\n      2 &&\n      3\n  4\nend"

  assert_format "def foo(x =  __FILE__ )\nend", "def foo(x = __FILE__)\nend"

  assert_format "a=1", "a = 1"

  assert_format "while 1\n2\nend", "while 1\n  2\nend"
  assert_format "until 1\n2\nend", "until 1\n  2\nend"

  assert_format "a = begin\n1\n2\nend", "a = begin\n  1\n  2\nend"
  assert_format "a = if 1\n2\n3\nend", "a = if 1\n      2\n      3\n    end"
  assert_format "a = if 1\n2\nelse\n3\nend", "a = if 1\n      2\n    else\n      3\n    end"
  assert_format "a = if 1\n2\nelsif 3\n4\nend", "a = if 1\n      2\n    elsif 3\n      4\n    end"
  assert_format "a = [\n1,\n2]", "a = [\n  1,\n  2,\n]"
  assert_format "a = while 1\n2\nend", "a = while 1\n  2\nend"
  assert_format "a = case 1\nwhen 2\n3\nend", "a = case 1\n    when 2\n      3\n    end"
  assert_format "a = case 1\nwhen 2\n3\nelse\n4\nend", "a = case 1\n    when 2\n      3\n    else\n      4\n    end"
  assert_format "a = \nif 1\n2\nend", "a =\n  if 1\n    2\n  end"
  assert_format "a, b = \nif 1\n2\nend", "a, b =\n  if 1\n    2\n  end"
  assert_format "a = b = 1\na, b =\n  b, a"
  assert_format "a = # foo\n  bar(1)"
  assert_format "a = \\\n  # foo\n  bar(1)"
  assert_format "a = \\\n  # foo\n  nil"
  assert_format "a : String = if 1\n\"One\"\nelse\"Zero\"\nend", "a : String = if 1\n               \"One\"\n             else\n               \"Zero\"\n             end"
  assert_format "a : String = case 1\nwhen 2\n3\nend", "a : String = case 1\n             when 2\n               3\n             end"
  assert_format "a : String = \nif 1\n1\nelse\n2\nend", "a : String =\n  if 1\n    1\n  else\n    2\n  end"

  assert_format %(require   "foo"), %(require "foo")

  assert_format "private   getter   foo", "private getter foo"

  assert_format %("foo \#{ 1  +  2 }"), %("foo \#{1 + 2}")
  assert_format %("foo \#{ 1 } \#{ __DIR__ }"), %("foo \#{1} \#{__DIR__}")
  assert_format %("foo \#{ __DIR__ }"), %("foo \#{__DIR__}")
  assert_format "__FILE__", "__FILE__"
  assert_format "__DIR__", "__DIR__"
  assert_format "__LINE__", "__LINE__"

  assert_format %q("\\\"\#\a\b\n\r\t\v\f\e")
  assert_format %q("\a\c\b\d"), %q("\ac\bd")
  assert_format %q("\\\"\#\a\b\n\r\t#{foo}\v\f\e")
  assert_format %q("\a\c#{foo}\b\d"), %q("\ac#{foo}\bd")

  assert_format %("\#{foo = 1\n}"), %("\#{foo = 1}")
  assert_format %("\#{\n  foo = 1\n}")
  assert_format %("\#{\n  foo = 1}"), %("\#{\n  foo = 1\n}")
  assert_format %("\#{ # foo\n  foo = 1\n}")
  assert_format %("\#{"foo"}")
  assert_format %("\#{"\#{foo}"}")
  assert_format %("foo\#{"bar"} Baz \#{"qux"} ")
  assert_format %("1\#{"4\#{"\#{"2"}"}3"}3\#{__DIR__}4\#{5}6")
  assert_format %("1\#{"\#{"2"}"}3\#{"4"}5")

  assert_format "%w(one   two  three)", "%w(one two three)"
  assert_format "%i(one   two  three)", "%i(one two three)"
  assert_format "%w{one(   two(  three)}", "%w{one( two( three)}"
  assert_format "%i{one(   two(  three)}", "%i{one( two( three)}"

  assert_format "/foo/"
  assert_format "/foo/imx"
  assert_format "/foo \#{ bar }/", "/foo \#{bar}/"
  assert_format "%r(foo \#{ bar })", "%r(foo \#{bar})"
  assert_format "foo(/ /)"
  assert_format "foo(1, / /)"
  assert_format "/ /"
  assert_format "begin\n  / /\nend"
  assert_format "a = / /"
  assert_format "1 == / /"
  assert_format "if / /\nend"
  assert_format "while / /\nend"
  assert_format "[/ /, / /]"
  assert_format "{/ / => / /, / / => / /}"
  assert_format "case / /\nwhen / /, /x/\n  / /\nend"
  assert_format "case / /\nwhen /x/, / /\n  / /\nend"
  assert_format "/\#{1}/imx"

  assert_format "`foo`"
  assert_format "`foo \#{ bar }`", "`foo \#{bar}`"
  assert_format "%x(foo \#{ bar })", "%x(foo \#{bar})"

  assert_format "module   Moo \n\n 1  \n\nend", "module Moo\n  1\nend"
  assert_format "class   Foo \n\n 1  \n\nend", "class Foo\n  1\nend"
  assert_format "struct   Foo \n\n 1  \n\nend", "struct Foo\n  1\nend"
  assert_format "class   Foo  < \n  Bar \n\n 1  \n\nend", "class Foo < Bar\n  1\nend"
  assert_format "module Moo ( T )\nend", "module Moo(T)\nend"
  assert_format "class Foo ( T )\nend", "class Foo(T)\nend"
  assert_format "class Foo ( *T, U )\nend", "class Foo(*T, U)\nend"
  assert_format "abstract  class Foo\nend", "abstract class Foo\nend"
  assert_format "class Foo;end", "class Foo; end"
  assert_format "class Foo; 1; end", "class Foo\n  1\nend"
  assert_format "module Foo;end", "module Foo; end"
  assert_format "module Foo; 1; end", "module Foo\n  1\nend"
  assert_format "module Foo ( U, *T ); 1; end", "module Foo(U, *T)\n  1\nend"
  assert_format "enum Foo;end", "enum Foo; end"
  assert_format "enum Foo; A = 1; end", "enum Foo\n  A = 1\nend"

  assert_format "@a", "@a"
  assert_format "@@a", "@@a"
  assert_format "$~", "$~"
  assert_format "$~.bar", "$~.bar"
  assert_format "$~ = 1", "$~ = 1"
  assert_format "$?", "$?"
  assert_format "$?.bar", "$?.bar"
  assert_format "$? = 1", "$? = 1"
  assert_format "$1", "$1"
  assert_format "$1.bar", "$1.bar"
  assert_format "$0", "$0"
  assert_format "$0.bar", "$0.bar"
  assert_format "$1?"

  assert_format "foo . is_a? ( Bar )", "foo.is_a?(Bar)"
  assert_format "foo . responds_to?( :bar )", "foo.responds_to?(:bar)"
  assert_format "foo . is_a? Bar", "foo.is_a? Bar"
  assert_format "foo . responds_to? :bar", "foo.responds_to? :bar"
  assert_format "foo.responds_to? :bar\n1"

  assert_format "include  Foo", "include Foo"
  assert_format "extend  Foo", "extend Foo"

  assert_format "x  :   Int32", "x : Int32"
  assert_format "x  :   Int32*", "x : Int32*"
  assert_format "x  :   Int32**", "x : Int32**"
  assert_format "x  :   A  |  B", "x : A | B"
  assert_format "x  :   A?", "x : A?"
  assert_format "x  :   Int32[ 8 ]", "x : Int32[8]"
  assert_format "x  :   (A | B)", "x : (A | B)"
  assert_format "x  :   (A -> B)", "x : (A -> B)"
  assert_format "x  :   (A -> )", "x : (A ->)"
  assert_format "x  :   (A -> B)?", "x : (A -> B)?"
  assert_format "x  :   {A, B}", "x : {A, B}"
  assert_format "x : { {A, B}, {C, D} }"
  assert_format "x : {A, B, }", "x : {A, B}"
  assert_format "x: Int32", "x : Int32"
  assert_format "class Foo\n@x  : Int32\nend", "class Foo\n  @x : Int32\nend"
  assert_format "class Foo\n@x  :  Int32\nend", "class Foo\n  @x : Int32\nend"
  assert_format "class Foo\nx = 1\nend", "class Foo\n  x = 1\nend"
  assert_format "x  =   uninitialized   Int32", "x = uninitialized Int32"
  assert_format "x  :   Int32  =   1", "x : Int32 = 1"

  assert_format "def foo\n@x  :  Int32\nend", "def foo\n  @x : Int32\nend"
  assert_format "def foo\n@x   =  uninitialized   Int32\nend", "def foo\n  @x = uninitialized Int32\nend"

  assert_format "x = 1\nx    +=   1", "x = 1\nx += 1"
  assert_format "x[ y ] += 1", "x[y] += 1"
  assert_format "@x   ||=   1", "@x ||= 1"
  assert_format "@x   &&=   1", "@x &&= 1"
  assert_format "@x[ 1 ]   ||=   2", "@x[1] ||= 2"
  assert_format "@x[ 1 ]   &&=   2", "@x[1] &&= 2"
  assert_format "@x[ 1 ]   +=   2", "@x[1] += 2"
  assert_format "foo.bar   +=   2", "foo.bar += 2"
  assert_format "a[b] ||= c"

  assert_format "case  1 \n when 2 \n 3 \n end", "case 1\nwhen 2\n  3\nend"
  assert_format "case  1 \n when 2 \n 3 \n else \n 4 \n end", "case 1\nwhen 2\n  3\nelse\n  4\nend"
  assert_format "case  1 \n when 2 , 3 \n 4 \n end", "case 1\nwhen 2, 3\n  4\nend"
  assert_format "case  1 \n when 2 ,\n 3 \n 4 \n end", "case 1\nwhen 2,\n     3\n  4\nend"
  assert_format "case  1 \n when 2 ; 3 \n end", "case 1\nwhen 2; 3\nend"
  assert_format "case  1 \n when 2 ;\n 3 \n end", "case 1\nwhen 2\n  3\nend"
  assert_format "case  1 \n when 2 ; 3 \n when 4 ; 5\nend", "case 1\nwhen 2; 3\nwhen 4; 5\nend"
  assert_format "case  1 \n when 2 then 3 \n end", "case 1\nwhen 2 then 3\nend"
  assert_format "case  1 \n when 2 then \n 3 \n end", "case 1\nwhen 2\n  3\nend"
  assert_format "case  1 \n when 2 \n 3 \n when 4 \n 5 \n end", "case 1\nwhen 2\n  3\nwhen 4\n  5\nend"
  assert_format "if 1\ncase 1\nwhen 2\n3\nend\nend", "if 1\n  case 1\n  when 2\n    3\n  end\nend"
  assert_format "case  1 \n when  .foo? \n 3 \n end", "case 1\nwhen .foo?\n  3\nend"
  assert_format "case 1\nwhen 1 then\n2\nwhen 3\n4\nend", "case 1\nwhen 1\n  2\nwhen 3\n  4\nend"
  assert_format "case  1 \n when 2 \n 3 \n else 4 \n end", "case 1\nwhen 2\n  3\nelse 4\nend"
  assert_format "case 1\nwhen 1, # 1\n     2, # 2\n     3  # 3\n  1\nend"
  assert_format "a = case 1\n    when 1, # 1\n         2, # 2\n         3  # 3\n      1\n    end"
  assert_format "a = 1\ncase\nwhen 2\nelse\n  a /= 3\nend"
  assert_format "case 1\nend"
  assert_format "case 1\nelse\n  2\nend"
  assert_format "case\nend"
  assert_format "case 1\nend"
  assert_format "case\nend"
  assert_format "case\nelse\n  1\nend"

  assert_format "case  1 \n in Int32 \n 3 \n end", "case 1\nin Int32\n  3\nend"

  assert_format <<-CRYSTAL
    case 0
    when 0 then 1; 2
    # Comments
    end
    CRYSTAL

  assert_format "select   \n when  foo \n 2 \n end", "select\nwhen foo\n  2\nend"
  assert_format "select   \n when  foo \n 2 \n when bar \n 3 \n end", "select\nwhen foo\n  2\nwhen bar\n  3\nend"
  assert_format "select   \n when  foo  then  2 \n end", "select\nwhen foo then 2\nend"
  assert_format "select   \n when  foo  ;  2 \n end", "select\nwhen foo; 2\nend"
  assert_format "select   \n when  foo \n 2 \n else \n 3 \n end", "select\nwhen foo\n  2\nelse\n  3\nend"
  assert_format "def foo\nselect   \n when  foo \n 2 \n else \n 3 \nend\nend", "def foo\n  select\n  when foo\n    2\n  else\n    3\n  end\nend"
  assert_format "select\nwhen foo\n  # foo\n  # bar\nelse\n  # foo\n  # bar\nend"
  assert_format "select\nwhen foo # foo\n  # bar\nelse # foo\n  # bar\nend"
  assert_format "begin\n  select\n  when foo\n    # foo\n    # bar\n  else\n    # foo\n    # bar\n  end\nend"

  assert_format "foo.@bar"

  assert_format "@[Foo]"
  assert_format "@[Foo()]", "@[Foo]"
  assert_format "@[Foo( 1, 2 )]", "@[Foo(1, 2)]"
  assert_format "@[Foo( 1, 2, foo: 3 )]", "@[Foo(1, 2, foo: 3)]"
  assert_format "@[Foo]\ndef foo\nend"
  assert_format "@[Foo(\n  1,\n)]"
  assert_format "@[Foo::Bar]"
  assert_format "@[::Foo::Bar]"

  assert_format "1.as   Int32", "1.as Int32"
  assert_format "foo.bar. as   Int32", "foo.bar.as Int32"
  assert_format "1\n.as(Int32)", "1\n  .as(Int32)"

  assert_format "1.as?   Int32", "1.as? Int32"
  assert_format "foo.bar. as?   Int32", "foo.bar.as? Int32"
  assert_format "1\n.as?(Int32)", "1\n  .as?(Int32)"

  assert_format "1 .. 2", "1..2"
  assert_format "1 ... 2", "1...2"
  assert_format "(1 .. )", "(1..)"
  assert_format " .. 2", "..2"

  assert_format "1..\n2"
  assert_format "1\n.."
  assert_format "1\n..2"
  assert_format "...\n2"
  assert_format "1\n..\n2"

  assert_format "typeof( 1, 2, 3 )", "typeof(1, 2, 3)"
  assert_format "sizeof( Int32 )", "sizeof(Int32)"
  assert_format "instance_sizeof( Int32 )", "instance_sizeof(Int32)"
  assert_format "alignof( Int32 )", "alignof(Int32)"
  assert_format "instance_alignof( Int32 )", "instance_alignof(Int32)"
  assert_format "offsetof( String, @length )", "offsetof(String, @length)"
  assert_format "pointerof( @a )", "pointerof(@a)"

  assert_format "_ = 1"
  assert_format "あ.い = 1"

  assert_format "a , b  = 1  ,  2", "a, b = 1, 2"
  assert_format "a[1] , b[2] = 1  ,  2", "a[1], b[2] = 1, 2"
  assert_format " * a = 1 ", "*a = 1"
  assert_format " _ , *_ ,\na.foo  ,a.bar  =  1  ,  2,3", "_, *_, a.foo, a.bar = 1, 2, 3"
  assert_format "あ.い, う.え.お = 1, 2"

  assert_format "begin\n1\nensure\n2\nend", "begin\n  1\nensure\n  2\nend"
  assert_format "begin\n1\nrescue\n3\nensure\n2\nend", "begin\n  1\nrescue\n  3\nensure\n  2\nend"
  assert_format "begin\n1\nrescue   ex\n3\nend", "begin\n  1\nrescue ex\n  3\nend"
  assert_format "begin\n1\nrescue   ex   :   Int32 \n3\nend", "begin\n  1\nrescue ex : Int32\n  3\nend"
  assert_format "begin\n1\nrescue   ex   :   Int32  |  Float64  \n3\nend", "begin\n  1\nrescue ex : Int32 | Float64\n  3\nend"
  assert_format "begin\n1\nrescue   ex\n3\nelse\n4\nend", "begin\n  1\nrescue ex\n  3\nelse\n  4\nend"
  assert_format "begin\n1\nrescue   Int32 \n3\nend", "begin\n  1\nrescue Int32\n  3\nend"
  assert_format "if 1\nbegin\n2\nensure\n3\nend\nend", "if 1\n  begin\n    2\n  ensure\n    3\n  end\nend"
  assert_format "1 rescue 2"
  assert_format "1 ensure 2"
  assert_format "begin\n  call\n  # comment\nrescue\n  call\n  # comment\nelse\n  call\n  # comment\nensure\n  call\n  # comment\nend"

  assert_format "def foo\n1\nrescue\n2\nend", "def foo\n  1\nrescue\n  2\nend"
  assert_format "def foo\n1\nensure\n2\nend", "def foo\n  1\nensure\n  2\nend"
  assert_format "class Foo\ndef foo\n1\nensure\n2\nend\nend", "class Foo\n  def foo\n    1\n  ensure\n    2\n  end\nend"
  assert_format "def run\n\nrescue\n  2\n  3\nend"

  assert_format "def foo(@x)\n\nrescue\nend"

  assert_format "macro foo\nend"
  assert_format "macro foo=(x)\nend"
  assert_format "macro []=(x, y)\nend"
  assert_format "macro foo()\nend", "macro foo\nend"
  assert_format "macro foo( x , y )\nend", "macro foo(x, y)\nend"
  assert_format "macro foo( x  =   1, y  =  2,  &block)\nend", "macro foo(x = 1, y = 2, &block)\nend"
  assert_format "macro foo\n  1 + 2\nend"
  assert_format "macro foo\n  if 1\n 1 + 2\n end\nend", "macro foo\n  if 1\n    1 + 2\n  end\nend"
  assert_format "macro foo\n  {{1 + 2}}\nend", "macro foo\n  {{1 + 2}}\nend"
  assert_format "macro foo\n  {{ 1 + 2 }}\nend", "macro foo\n  {{ 1 + 2 }}\nend"
  assert_format "macro foo\n  {% 1 + 2 %}\nend", "macro foo\n  {% 1 + 2 %}\nend"
  assert_format "macro foo\n  {{ 1 + 2 }}\\\nend", "macro foo\n  {{ 1 + 2 }}\\\nend"
  assert_format "macro foo\n  {{ 1 + 2 }}\\\n 1\n end", "macro foo\n  {{ 1 + 2 }}\\\n 1\n end"
  assert_format "macro foo\n  {%1 + 2%}\\\nend", "macro foo\n  {% 1 + 2 %}\\\nend"
  assert_format "macro foo\n  {% if 1 %} 2 {% end %}\nend"
  assert_format "macro foo\n  {% unless 1 %} 2 {% end %}\nend"
  assert_format "macro foo\n  {% if 1 %} 2 {% else %} 3 {% end %}\nend"
  assert_format "macro foo\n  {% if 1 %}\\ 2 {% else %}\\ 3 {% end %}\\\nend"
  assert_format "macro foo\n  {% for x in y %} 2 {% end %}\nend"
  assert_format "macro foo\n  {% for x in y %}\\ 2 {% end %}\\\nend"
  assert_format "macro foo\n  %foo\nend"
  assert_format "macro foo\n  %foo{x.id+2}\nend", "macro foo\n  %foo{x.id + 2}\nend"
  assert_format "macro foo\n  %foo{x,y}\nend", "macro foo\n  %foo{x, y}\nend"
  assert_format "def foo : Int32\n  1\nend"
  assert_format "class Foo\n  macro foo\n    1\n  end\nend"
  assert_format "   {{ 1 + 2 }}", "{{ 1 + 2 }}"
  assert_format "  {% for x in y %} 2 {% end %}", "{% for x in y %} 2 {% end %}"
  assert_format "  {% if 1 %} 2 {% end %}", "{% if 1 %} 2 {% end %}"
  assert_format "  {% if 1 %} {% if 2 %} 2 {% end %} {% end %}", "{% if 1 %} {% if 2 %} 2 {% end %} {% end %}"
  assert_format "if 1\n  {% if 2 %} {% end %}\nend"
  assert_format "if 1\n  {% for x in y %} {% end %}\nend"
  assert_format "if 1\n  {{1 + 2}}\nend"
  assert_format "def foo : self | Nil\n  nil\nend"
  assert_format "macro foo(x)\n  {% if 1 %} 2 {% end %}\nend"
  assert_format "macro foo()\n  {% if 1 %} 2 {% end %}\nend", "macro foo\n  {% if 1 %} 2 {% end %}\nend"
  assert_format "macro flags\n  {% if 1 %}\\\n  {% end %}\\\nend"
  assert_format "macro flags\n  {% if 1 %}\\\n 1 {% else %}\\\n {% end %}\\\nend"
  assert_format "macro flags\n  {% if 1 %}{{1}}a{{2}}{% end %}\\\nend"
  assert_format "  {% begin %} 2 {% end %}", "{% begin %} 2 {% end %}"
  assert_format "macro foo\n  \\{\nend"
  assert_format "macro foo\n  {% if 1 %} 2 {% elsif 3 %} 4 {% else %} 5 {% end %}\nend"
  assert_format "macro [](x)\nend"
  assert_format "macro foo\n  {% if true %}if true{% end %}\n  {% if true %}end{% end %}\nend"
  assert_format "macro foo\n    1  +  2 \n    end", "macro foo\n  1 + 2\nend"
  assert_format "class Foo\n macro foo\n    1  +  2 \n    end\n end", "class Foo\n  macro foo\n    1 + 2\n  end\nend"
  assert_format "macro foo\n    def   bar  \n  end \n    end", "macro foo\n  def bar\n  end\nend"

  assert_format "def foo\na = bar do\n1\nend\nend", "def foo\n  a = bar do\n    1\n  end\nend"
  assert_format "def foo\nend\ndef bar\nend", "def foo\nend\n\ndef bar\nend"
  assert_format "private def foo\nend\nprivate def bar\nend", "private def foo\nend\n\nprivate def bar\nend"
  assert_format "a = 1\ndef bar\nend", "a = 1\n\ndef bar\nend"
  assert_format "def foo\nend\n\n\n\ndef bar\nend", "def foo\nend\n\ndef bar\nend"
  assert_format "def foo\nend;def bar\nend", "def foo\nend\n\ndef bar\nend"
  assert_format "class Foo\nend\nclass Bar\nend", "class Foo\nend\n\nclass Bar\nend"

  assert_format "alias  Foo  =   Bar", "alias Foo = Bar"
  assert_format "alias  Foo::Bar  =   Baz", "alias Foo::Bar = Baz"
  assert_format "alias A = (B)"
  assert_format "alias A = (B) -> C"
  assert_format "alias Foo=Bar", "alias Foo = Bar"
  assert_format "alias Foo= Bar", "alias Foo = Bar"
  assert_format "alias Foo =Bar", "alias Foo = Bar"
  assert_format "alias Foo::Bar=Baz", "alias Foo::Bar = Baz"
  assert_format "alias Foo::Bar= Baz", "alias Foo::Bar = Baz"
  assert_format "alias Foo::Bar =Baz", "alias Foo::Bar = Baz"
  assert_format <<-CRYSTAL, <<-CRYSTAL
    alias Foo=
    Bar
    CRYSTAL
    alias Foo = Bar
    CRYSTAL
  assert_format "lib Foo\nend"
  assert_format "lib Foo\ntype  Foo  =   Bar\nend", "lib Foo\n  type Foo = Bar\nend"
  assert_format "lib Foo\nfun foo\nend", "lib Foo\n  fun foo\nend"
  assert_format "lib Foo\n  fun Bar\nend"
  assert_format "lib Foo\n  fun bar = Bar\nend"
  assert_format "lib Foo\n  fun Foo = Bar\nend"
  assert_format "lib Foo\nfun foo  :  Int32\nend", "lib Foo\n  fun foo : Int32\nend"
  assert_format "lib Foo\nfun foo()  :  Int32\nend", "lib Foo\n  fun foo : Int32\nend"
  assert_format "lib Foo\nfun foo ()  :  Int32\nend", "lib Foo\n  fun foo : Int32\nend"
  assert_format "lib Foo\nfun foo(x   :   Int32, y   :   Float64)  :  Int32\nend", "lib Foo\n  fun foo(x : Int32, y : Float64) : Int32\nend"
  assert_format "lib Foo\nfun foo(x : Int32,\ny : Float64) : Int32\nend", "lib Foo\n  fun foo(x : Int32,\n          y : Float64) : Int32\nend"
  assert_format "lib Foo\nfun foo( ... )  :  Int32\nend", "lib Foo\n  fun foo(...) : Int32\nend"
  assert_format "lib Foo\nfun foo(x : Int32, ... )  :  Int32\nend", "lib Foo\n  fun foo(x : Int32, ...) : Int32\nend"
  assert_format "lib Foo\n  fun foo(Int32) : Int32\nend"
  assert_format "fun foo(x : Int32) : Int32\n  1\nend"
  assert_format "fun foo(\n  x : Int32,\n  ...\n) : Int32\n  1\nend"
  assert_format <<-CRYSTAL
    lib Foo
      fun foo = bar(Int32) : Int32
    end
    CRYSTAL
  assert_format <<-CRYSTAL
    lib Foo
      fun foo =
        bar : Void
    end
    CRYSTAL
  assert_format <<-CRYSTAL, <<-CRYSTAL
    lib Foo
      fun foo =


        bar : Void
    end
    CRYSTAL
    lib Foo
      fun foo =
        bar : Void
    end
    CRYSTAL
  assert_format <<-CRYSTAL
    lib Foo
      fun foo =
        bar(Int32) : Int32
    end
    CRYSTAL
  assert_format <<-CRYSTAL, <<-CRYSTAL
    lib Foo
      fun foo =


        bar(Int32) : Int32
    end
    CRYSTAL
    lib Foo
      fun foo =
        bar(Int32) : Int32
    end
    CRYSTAL
  assert_format <<-CRYSTAL, <<-CRYSTAL
    lib Foo
      fun foo =
        bar(Int32,
        Int32) : Int32
    end
    CRYSTAL
    lib Foo
      fun foo =
        bar(Int32,
            Int32) : Int32
    end
    CRYSTAL
  assert_format "lib Foo\n  fun foo = bar(Int32) : Int32\nend"
  assert_format <<-CRYSTAL
    lib Foo
      fun foo = "bar"(Int32) : Int32
    end
    CRYSTAL
  assert_format <<-CRYSTAL
    lib Foo
      fun foo =
        "bar"(Int32) : Int32
    end
    CRYSTAL
  assert_format <<-CRYSTAL
    lib Foo
      fun foo =
        "bar"(Int32) : Int32
      # comment
    end
    CRYSTAL
  assert_format "lib Foo\n  $foo  :  Int32 \nend", "lib Foo\n  $foo : Int32\nend"
  assert_format "lib Foo\n  $foo = hello  :  Int32 \nend", "lib Foo\n  $foo = hello : Int32\nend"
  assert_format "lib Foo\nalias  Foo  =  Bar -> \n$a : Int32\nend", "lib Foo\n  alias Foo = Bar ->\n  $a : Int32\nend"
  assert_format "lib Foo\nstruct Foo\nend\nend", "lib Foo\n  struct Foo\n  end\nend"
  assert_format "lib Foo\nstruct Foo\nx  :  Int32\nend\nend", "lib Foo\n  struct Foo\n    x : Int32\n  end\nend"
  assert_format "lib Foo\nstruct Foo\nx  :  Int32\ny : Float64\nend\nend", "lib Foo\n  struct Foo\n    x : Int32\n    y : Float64\n  end\nend"
  assert_format "lib Foo\nstruct Foo\nx  ,  y  :  Int32\nend\nend", "lib Foo\n  struct Foo\n    x, y : Int32\n  end\nend"
  assert_format "lib Foo\nstruct Foo\nx  ,  y  , z :  Int32\nend\nend", "lib Foo\n  struct Foo\n    x, y, z : Int32\n  end\nend"
  assert_format "lib Foo\nunion Foo\nend\nend", "lib Foo\n  union Foo\n  end\nend"

  assert_format "SomeLib.UppercasedFunCall"
  assert_format "SomeLib.UppercasedFunCall 1, 2"

  assert_format "enum Foo\nend"
  assert_format "enum Foo\nA  \nend", "enum Foo\n  A\nend"
  assert_format "enum Foo\nA = 1\nend", "enum Foo\n  A = 1\nend"
  assert_format "enum Foo : Int32\nA = 1\nend", "enum Foo : Int32\n  A = 1\nend"
  assert_format "enum Foo : Int32\nA = 1\ndef foo\n1\nend\nend", "enum Foo : Int32\n  A = 1\n\n  def foo\n    1\n  end\nend"
  assert_format "lib Bar\n  enum Foo\n  end\nend"
  assert_format "lib Bar\n  enum Foo\n    A\n  end\nend"
  assert_format "lib Bar\n  enum Foo\n    A = 1\n  end\nend"

  assert_format "lib Foo::Bar\nend"

  %w(foo foo= foo? foo!).each do |method|
    assert_format "->#{method}"
    assert_format "foo = 1\n->foo.#{method}"
    assert_format "->Foo.#{method}"
    assert_format "->@foo.#{method}"
    assert_format "->@@foo.#{method}"
    assert_format "-> :: #{method}", "->::#{method}"
    assert_format "-> :: Foo . #{method}", "->::Foo.#{method}"
  end

  assert_format "foo = 1\n->foo.bar(Int32)"
  assert_format "foo = 1\n->foo.bar(Int32*)"
  assert_format "foo = 1\n->foo.bar=(Int32)"
  assert_format "foo = 1\n->foo.[](Int32)"
  assert_format "foo = 1\n->foo.[]=(Int32)"

  assert_format "->{ x }", "-> { x }"
  assert_format "->{\nx\n}", "-> {\n  x\n}"
  assert_format "->do\nx\nend", "-> do\n  x\nend"
  assert_format "->( ){ x }", "-> { x }"
  assert_format "->() do x end", "-> do x end"
  assert_format "->( x , y )   { x }", "->(x, y) { x }"
  assert_format "->( x : Int32 , y )   { x }", "->(x : Int32, y) { x }"
  assert_format "->{ x }", "-> { x }"

  # #13232
  assert_format "->{}", "-> { }"
  assert_format "->(){}", "-> { }"
  assert_format "->{1}", "-> { 1 }"
  assert_format "->(x : Int32) {}", "->(x : Int32) { }"
  assert_format "-> : Int32 {}", "-> : Int32 { }"
  assert_format "->do\nend", "-> do\nend"
  assert_format "-> : Int32 {}", "-> : Int32 { }"

  # Allows whitespace around proc literal, but doesn't enforce them
  assert_format "-> { }"
  assert_format "-> { 1 }"
  assert_format "->(x : Int32) { }"
  assert_format "-> : Int32 { }"
  assert_format "-> do\nend"

  assert_format "-> : Int32 { }"
  assert_format "-> : Int32 | String { 1 }"
  assert_format "-> : Array(Int32) {}", "-> : Array(Int32) { }"
  assert_format "-> : Int32? {}", "-> : Int32? { }"
  assert_format "-> : Int32* {}", "-> : Int32* { }"
  assert_format "-> : Int32[1] {}", "-> : Int32[1] { }"
  assert_format "-> : {Int32, String} {}", "-> : {Int32, String} { }"
  assert_format "-> : {Int32} { String }"
  assert_format "-> : {x: Int32, y: String} {}", "-> : {x: Int32, y: String} { }"
  assert_format "->\n:\nInt32\n{\n}", "-> : Int32 {\n}"
  assert_format "->( x )\n:\nInt32 { }", "->(x) : Int32 { }"
  assert_format "->: Int32 do\nx\nend", "-> : Int32 do\n  x\nend"

  {:+, :-, :*, :/, :^, :>>, :<<, :|, :&, :&+, :&-, :&*, :&**}.each do |sym|
    assert_format ":#{sym}"
  end

  assert_format ":\"foo bar\""

  assert_format %("foo" \\\n "bar"), %("foo" \\\n"bar")
  assert_format %("foo" \\\n "bar" \\\n "baz"), %("foo" \\\n"bar" \\\n"baz")
  assert_format %("foo \#{bar}" \\\n "baz"), %("foo \#{bar}" \\\n"baz")

  assert_format %(asm("nop"))
  assert_format %(asm(\n"nop"\n)), %(asm(\n  "nop"\n))
  assert_format %(asm("nop" : : )), %(asm("nop"))
  assert_format %(asm("nop" :: )), %(asm("nop"))
  assert_format %(asm("nop" :: "r"(0))), %(asm("nop" :: "r"(0)))
  assert_format %(asm("nop" : "a"(0) )), %(asm("nop" : "a"(0)))
  assert_format %(asm("nop" : "a"(0), "b"(1) )), %(asm("nop" : "a"(0), "b"(1)))
  assert_format %(asm("nop" : "a"(0) : "b"(1) )), %(asm("nop" : "a"(0) : "b"(1)))
  assert_format %(asm("nop" : "a"(0) : "b"(1), "c"(2) )), %(asm("nop" : "a"(0) : "b"(1), "c"(2)))
  assert_format %(asm("nop" : "a"(0)\n: "b"(1), "c"(2) )), %(asm("nop" : "a"(0)\n          : "b"(1), "c"(2)))
  assert_format %(asm("nop" : "a"(0), "b"(1)\n: "c"(2), "d"(3) )), %(asm("nop" : "a"(0), "b"(1)\n          : "c"(2), "d"(3)))
  assert_format %(asm("nop" : "a"(0),\n"b"(1)\n: "c"(2), "d"(3) )), %(asm("nop" : "a"(0),\n            "b"(1)\n          : "c"(2), "d"(3)))
  assert_format %(asm("nop" : "a"(0)\n: "b"(1),\n"c"(2) )), %(asm("nop" : "a"(0)\n          : "b"(1),\n            "c"(2)))
  assert_format %(asm(\n"nop" : "a"(0), "b"(1) )), %(asm(\n  "nop" : "a"(0), "b"(1)\n))
  assert_format %(asm("nop"\n: "a"(0) )), %(asm("nop"\n        : "a"(0)))
  assert_format %(asm("nop" ::: "eax" )), %(asm("nop" ::: "eax"))
  assert_format %(asm("nop" ::: "eax" ,  "ebx" )), %(asm("nop" ::: "eax", "ebx"))
  assert_format %(asm("nop" :::: "volatile" )), %(asm("nop" :::: "volatile"))
  assert_format %(asm("nop" :::: "volatile"  , "alignstack"  ,  "intel"   )), %(asm("nop" :::: "volatile", "alignstack", "intel"))
  assert_format %(asm("nop" ::: "eax" ,  "ebx" :   "volatile"  ,  "alignstack" )), %(asm("nop" ::: "eax", "ebx" : "volatile", "alignstack"))
  assert_format %(asm("a" : "b"(c) : "d"(e) :: "volatile"))
  assert_format %(asm("a" : "b"(1), "c"(2) : "d"(3) : : "volatile")), %(asm("a" : "b"(1), "c"(2) : "d"(3) :: "volatile"))

  assert_format %(asm("a" : "b"(c)\n)), %(asm("a" : "b"(c)))
  assert_format %(asm("a" :: "d"(e)\n)), %(asm("a" :: "d"(e)))
  assert_format %(asm("a" ::: "f"\n)), %(asm("a" ::: "f"))
  assert_format %(asm("a" :::: "volatile"\n)), %(asm("a" :::: "volatile"))
  assert_format %(asm("a" : : : : "volatile")), %(asm("a" :::: "volatile"))
  assert_format %(asm("a" :: : : "volatile")), %(asm("a" :::: "volatile"))
  assert_format %(asm("a" : :: : "volatile")), %(asm("a" :::: "volatile"))
  assert_format %(asm("a" : : :: "volatile")), %(asm("a" :::: "volatile"))
  assert_format %(asm("a" : "b"(c) : "d"(e)\n        : "f"))
  assert_format %(asm("a" : "b"(c) : "d"(e)\n        : "f",\n          "g"))
  assert_format %(asm("a" ::: "a"\n        : "volatile",\n          "intel"))

  assert_format <<-CRYSTAL, <<-CRYSTAL
    asm(
    # foo
    "nop"
    # bar
    )
    CRYSTAL
    asm(
      # foo
      "nop"
      # bar
    )
    CRYSTAL

  assert_format <<-CRYSTAL, <<-CRYSTAL
    asm(
      # the assembly template string, following the
      # syntax for LLVM's integrated assembler
      "nop" :               # output operands
    "=r"(foo), "=r"(bar) : # input operands
    "r"(1), "r"(baz) :     # names of clobbered registers
    "eax", "memory" :      # optional flags, corresponding to the LLVM IR
      # sideeffect / alignstack / inteldialect / unwind attributes
    "volatile", "alignstack", "intel", "unwind"
    )
    CRYSTAL
    asm(
      # the assembly template string, following the
      # syntax for LLVM's integrated assembler
      "nop" :                # output operands
      "=r"(foo), "=r"(bar) : # input operands
      "r"(1), "r"(baz) :     # names of clobbered registers
      "eax", "memory" :      # optional flags, corresponding to the LLVM IR
      # sideeffect / alignstack / inteldialect / unwind attributes
      "volatile", "alignstack", "intel", "unwind"
    )
    CRYSTAL

  assert_format "1 # foo\n1234 # bar", "1    # foo\n1234 # bar"
  assert_format "1234 # foo\n1 # bar", "1234 # foo\n1    # bar"
  assert_format "1#foo", "1 # foo"
  assert_format "1 # foo\n1234 # bar\n\n10 # bar", "1    # foo\n1234 # bar\n\n10 # bar"
  assert_format "# foo\na = 1 # bar"
  assert_format "#### ###"
  assert_format "#######"
  assert_format "x\n# foo\n\n# bar"

  assert_format "A = 1\nFOO = 2\n\nEX = 3", "A   = 1\nFOO = 2\n\nEX = 3"
  assert_format "FOO = 2\nA = 1", "FOO = 2\nA   = 1"
  assert_format "FOO = 2 + 3\nA = 1 - 10", "FOO = 2 + 3\nA   = 1 - 10"
  assert_format "private FOO = 2\nprivate A = 1", "private FOO = 2\nprivate A   = 1"
  assert_format "enum Baz\nA = 1\nFOO = 2\n\nEX = 3\nend", "enum Baz\n  A   = 1\n  FOO = 2\n\n  EX = 3\nend"
  assert_format "enum Baz\nA = 1\nFOO\n\nEX = 3\nend", "enum Baz\n  A   = 1\n  FOO\n\n  EX = 3\nend"

  assert_format "1   # foo", "1 # foo"
  assert_format "1  # foo\n2  # bar", "1 # foo\n2 # bar"
  assert_format "1  #foo  \n2  #bar", "1 # foo\n2 # bar"
  assert_format "if 1\n2  # foo\nend", "if 1\n  2 # foo\nend"
  assert_format "if 1\nelse\n2  # foo\nend", "if 1\nelse\n  2 # foo\nend"
  assert_format "if # some comment\n 2 # another\n 3 # final \n end # end ", "if  # some comment\n2   # another\n  3 # final\nend # end"
  assert_format "while 1\n2  # foo\nend", "while 1\n  2 # foo\nend"
  assert_format "def foo\n2  # foo\nend", "def foo\n  2 # foo\nend"
  assert_format "if 1\n# nothing\nend", "if 1\n  # nothing\nend"
  assert_format "if 1\nelse\n# nothing\nend", "if 1\nelse\n  # nothing\nend"
  assert_format "if 1 # foo\n2\nend", "if 1 # foo\n  2\nend"
  assert_format "if 1  # foo\nend", "if 1 # foo\nend"
  assert_format "while 1  # foo\nend", "while 1 # foo\nend"
  assert_format "while 1\n# nothing\nend", "while 1\n  # nothing\nend"
  assert_format "class Foo  # foo\nend", "class Foo # foo\nend"
  assert_format "class Foo\n# nothing\nend", "class Foo\n  # nothing\nend"
  assert_format "module Foo  # foo\nend", "module Foo # foo\nend"
  assert_format "module Foo\n# nothing\nend", "module Foo\n  # nothing\nend"
  assert_format "case 1 # foo\nwhen 2\nend", "case 1 # foo\nwhen 2\nend"
  assert_format "def foo\n# hello\n1\nend", "def foo\n  # hello\n  1\nend"
  assert_format "struct Foo(T)\n# bar\n1\nend", "struct Foo(T)\n  # bar\n  1\nend"
  assert_format "struct Foo\n  # bar\n  # baz\n1\nend", "struct Foo\n  # bar\n  # baz\n  1\nend"
  assert_format "(size - 1).downto(0) do |i|\n  yield @buffer[i]\nend"
  assert_format "(a).b { }\nc"
  assert_format "begin\n  a\nend.b { }\nc"
  assert_format "if a\n  b &c\nend"
  assert_format "foo (1).bar"
  assert_format "foo a: 1\nb"
  assert_format "if 1\n2 && 3\nend", "if 1\n  2 && 3\nend"
  assert_format "if 1\n  node.is_a?(T)\nend"
  assert_format "case 1\nwhen 2\n#comment\nend", "case 1\nwhen 2\n  # comment\nend"
  assert_format "case 1\nwhen 2\n\n#comment\nend", "case 1\nwhen 2\n  # comment\nend"
  assert_format "1 if 2\n# foo", "1 if 2\n# foo"
  assert_format "1 if 2\n# foo\n3"
  assert_format "1\n2\n# foo"
  assert_format "1\n2  \n  # foo", "1\n2\n# foo"
  assert_format "if 1\n2\n3\n# foo\nend", "if 1\n  2\n  3\n  # foo\nend"
  assert_format "def foo\n1\n2\n# foo\nend", "def foo\n  1\n  2\n  # foo\nend"
  assert_format "if 1\nif 2\n3 # foo\nend\nend", "if 1\n  if 2\n    3 # foo\n  end\nend"
  assert_format "class Foo\n1\n\n# foo\nend", "class Foo\n  1\n\n  # foo\nend"
  assert_format "module Foo\n1\n\n# foo\nend", "module Foo\n  1\n\n  # foo\nend"
  assert_format "if 1\n1\n\n# foo\nend", "if 1\n  1\n\n  # foo\nend"
  assert_format "while true\n1\n\n# foo\nend", "while true\n  1\n\n  # foo\nend"
  assert_format "def foo\nend\n\ndef bar\nend\n\n# foo"
  assert_format "1 && (\n  2 || 3\n)"
  assert_format "class Foo\n  def foo\n    # nothing\n  end\nend"
  assert_format "while 1 # foo\n  # bar\n  2\nend", "while 1 # foo\n  # bar\n  2\nend"
  assert_format "foo(\n # foo\n1,\n\n # bar\n2,  \n)", "foo(\n  # foo\n  1,\n\n  # bar\n  2,\n)"
  assert_format "foo do;\n1; end", "foo do\n  1\nend"
  assert_format "if 1;\n2; end", "if 1\n  2\nend"
  assert_format "while 1;\n2; end", "while 1\n  2\nend"
  assert_format "if 1;\n2;\nelse;\n3;\nend", "if 1\n  2\nelse\n  3\nend"
  assert_format "if 1;\n2;\nelsif 3;\n4;\nend", "if 1\n  2\nelsif 3\n  4\nend"
  assert_format "def foo\n  1\n  2\nrescue IO\n  1\nend"
  assert_format "def execute\n  begin\n    1\n  ensure\n    2\n  end\n  3\nend"
  assert_format "foo.bar=(2)\n1"
  assert_format "inner &.color=(@color)\n1"
  assert_format "ary.size = (1).to_i"
  assert_format "b &.[c].d"
  assert_format "b &.[c]?.d"
  assert_format "a &.b[c]?"
  assert_format "+ a + d", "+a + d"
  assert_format "  ((1) + 2)", "((1) + 2)"
  assert_format "if 1\n  ((1) + 2)\nend"

  assert_format "def   foo(x   :  self ?) \n  end", "def foo(x : self?)\nend"
  assert_format "def foo(x : (self)?)\nend"

  assert_format "  macro foo\n  end\n\n  :+", "macro foo\nend\n\n:+"
  assert_format "[\n1, # a\n2, # b\n 3 # c\n]", "[\n  1, # a\n  2, # b\n  3, # c\n]"
  assert_format "[\n  a() # b\n]", "[\n  a(), # b\n]"
  assert_format "[\n  a(), # b\n]", "[\n  a(), # b\n]"
  assert_format "[\n  a(),\n]", "[\n  a(),\n]"
  assert_format "if 1\n[\n  a() # b\n]\nend", "if 1\n  [\n    a(), # b\n  ]\nend"
  assert_format "foo(\n# x\n1,\n\n# y\nz: 2\n)", "foo(\n  # x\n  1,\n\n  # y\n  z: 2\n)"
  assert_format "foo(\n# x\n1,\n\n# y\nz: 2,\n\n# a\nb: 3)", "foo(\n  # x\n  1,\n\n  # y\n  z: 2,\n\n  # a\n  b: 3)"
  assert_format "foo(\n 1, # hola\n2, # chau\n )", "foo(\n  1, # hola\n  2, # chau\n)"
  assert_format "foo (1)", "foo(1)"
  assert_format "foo (1), 2"
  assert_format "foo (1; 2)"
  assert_format "foo ((1) ? 2 : 3)", "foo((1) ? 2 : 3)"
  assert_format "foo((1..3))"
  assert_format "foo ()"
  assert_format "foo ( )", "foo ()"
  assert_format "def foo(\n\n#foo\nx,\n\n#bar\nz\n)\nend", "def foo(\n  # foo\n  x,\n\n  # bar\n  z,\n)\nend"
  assert_format "def foo(\nx, #foo\nz #bar\n)\nend", "def foo(\n  x, # foo\n  z, # bar\n)\nend"
  assert_format "a = 1;;; b = 2", "a = 1; b = 2"
  assert_format "a = 1\n;\nb = 2", "a = 1\nb = 2"
  assert_format "foo do\n  # bar\nend"
  assert_format "abstract def foo\nabstract def bar"
  assert_format "if 1\n  ->{ 1 }\nend", "if 1\n  -> { 1 }\nend"
  assert_format "foo.bar do\n  baz\n    .b\nend"
  assert_format "coco.lala\nfoo\n  .bar"
  assert_format "foo.bar = \n1", "foo.bar =\n  1"
  assert_format "foo.bar += \n1", "foo.bar +=\n  1"
  assert_format "->{}", "-> { }"
  assert_format "foo &.[a] = 1"
  assert_format "[\n  # foo\n  1,\n\n  # bar\n  2,\n]"
  assert_format "[c.x]\n  .foo"
  assert_format "foo([\n  1,\n  2,\n  3,\n])"
  assert_format "bar = foo([\n  1,\n  2,\n  3,\n])"
  assert_format "foo({\n  1 => 2,\n  3 => 4,\n  5 => 6,\n})"
  assert_format "bar = foo({\n        1 => 2,\n        3 => 4,\n        5 => 6,\n      })", "bar = foo({\n  1 => 2,\n  3 => 4,\n  5 => 6,\n})"
  assert_format "foo(->{\n  1 + 2\n})", "foo(-> {\n  1 + 2\n})"
  assert_format "bar = foo(->{\n  1 + 2\n})", "bar = foo(-> {\n  1 + 2\n})"
  assert_format "foo(->do\n  1 + 2\nend)", "foo(-> do\n  1 + 2\nend)"
  assert_format "bar = foo(->do\n  1 + 2\nend)", "bar = foo(-> do\n  1 + 2\nend)"
  assert_format "bar = foo(->{\n  1 + 2\n})", "bar = foo(-> {\n  1 + 2\n})"
  assert_format "case 1\nwhen 2\n  3\n  # foo\nelse\n  4\n  # bar\nend"
  assert_format "1 #=> 2", "1 # => 2"
  assert_format "1 #=>2", "1 # => 2"
  assert_format "foo(\n  [\n    1,\n    2,\n  ],\n  [\n    3,\n    4,\n  ]\n)"
  assert_format "%w(\n  one two\n  three four\n)"
  assert_format "a = %w(\n  one two\n  three four\n)"
  assert_format "foo &.bar do\n  1 + 2\nend"
  assert_format "a = foo &.bar do\n  1 + 2\nend"
  assert_format "foo(bar([\n  1,\n]))"
  assert_format "a = foo(bar([\n  1,\n]))"
  assert_format "foo(baz1 do\nend)"
  assert_format "a = foo(baz1 do\nend)"
  assert_format "foo(bar(baz3 do\nend))"
  assert_format "a = foo(bar(baz3 do\nend))"
  assert_format "foo(bar(\n  1,\n  2,\n))"
  assert_format "a = foo(bar(\n  1,\n  2,\n))"
  # assert_format "a = foo(bar([\n          1,\n          2,\n        ]),\n        3,\n       )"
  assert_format "foo(1, 2, {\n  foo: 1,\n  bar: 2,\n})"
  assert_format "a = foo(1, 2, {\n  foo: 1,\n  bar: 2,\n})"
  assert_format "foo([\n  1,\n  bar do\n  end,\n  [\n    2,\n  ],\n])"
  assert_format "foo(bar(\n  1,\n  baz(\n    2,\n    3,\n  )\n))"
  assert_format "foo(bar(\n  1,\n  baz(2,\n      3,\n     )\n))", "foo(bar(\n  1,\n  baz(2,\n    3,\n  )\n))"
  assert_format "foo({\n  1 => 2,\n  3 => {\n    4 => 5,\n  },\n})"
  assert_format "foo([\n  1, 2,\n  3, 4,\n])"
  assert_format "foo(baz(x, y) do\n  1 + 2\nend)"
  assert_format "case 1\nwhen \"foo\"     ; 3\nwhen \"lalalala\"; 4\nelse             5\nend"
  assert_format "case 1\nwhen \"foo\"      then 3\nwhen \"lalalala\" then 4\nelse                 5\nend"
  assert_format "case 1        # foo\nwhen 2 then 3 # bar\nwhen 4 then 5 # baz\nelse        6 # zzz\nend"
  assert_format "case 1\nwhen 8     then 1\nwhen 16    then 2\nwhen 256   then 3\nwhen 'a'   then 5\nwhen \"foo\" then 6\nelse            4\nend"
  assert_format "case 1\nwhen 1      then 1\nwhen 123    then 2\nwhen 1..123 then 3\nelse             4\nend"
  assert_format "macro bar\n  1\nend\n\ncase 1\nwhen  2 then 3\nwhen 45 then 6\nend"
  assert_format "{\n         1 => 2,\n        10 => 30,\n        30 => 40,\n  \"foobar\" => 50,\n  \"coco\"   => 60,\n}"
  assert_format "{1 => 2, 3 => 4}\n{5234234 => 234098234, 7 => 8}"
  assert_format "{\n    1 => 2, 3 => 4,\n  567 => 8910,\n}", "{\n  1 => 2, 3 => 4,\n  567 => 8910,\n}"
  assert_format "{\n  foo:    1,\n  b:      2,\n  barbaz: 3,\n}"
  assert_format "{\n  a:   1,\n  foo: bar,\n}"
  assert_format "%(\n1\n)\n\n{\n    1 => 2,\n  234 => 5,\n}"
  assert_format "class Actor\n  macro inherited\nend\nend\n", "class Actor\n  macro inherited\n  end\nend"
  assert_format "class Actor\n  macro inherited\n\nend\nend\n", "class Actor\n  macro inherited\n  end\nend"
  assert_format "{\n  \"foo\":    1,\n  \"babraz\": 2,\n}"
  assert_format "def foo\n  ((((((((((((((((0_u64\n    ) | ptr[0]) << 8\n    ) | ptr[1]) << 8\n    ) | ptr[2]) << 8\n    ) | ptr[3]) << 8\n    ) | ptr[4]) << 8\n    ) | ptr[5]) << 8\n    ) | ptr[6]) << 8\n    ) | ptr[7])\nend"
  assert_format "yield (1).foo"
  assert_format "module Ton\n  macro foo\n    class {{name.id}}\n    end\n  end\nend"
  assert_format "a = 1\na ||= begin\n  1\nend"
  assert_format "if 1\n  return foo(\n    1,\n    2,\n  )\nend"
  assert_format "1\nyield\n2"
  assert_format "if 1\n  [\n    1,\n  ].none?\nend"
  assert_format "# foo\ndef foo\nend\n# bar\ndef bar\nend", "# foo\ndef foo\nend\n\n# bar\ndef bar\nend"
  assert_format "<<-FOO\n1\nFOO\n\n{\n   1 => 2,\n  10 => 3,\n}"
  assert_format "p = Foo[1, 2, 3,\n        4, 5, 6,\n       ]", "p = Foo[1, 2, 3,\n  4, 5, 6,\n]"
  assert_format "p = Foo[\n  1, 2, 3,\n  4, 5, 6\n]\n", "p = Foo[\n  1, 2, 3,\n  4, 5, 6,\n]"
  assert_format "[1, 2,\n  3, 4]\n", "[1, 2,\n 3, 4]"
  assert_format "{1 => 2,\n  3 => 4, # lala\n}\n", "{1 => 2,\n 3 => 4, # lala\n}"
  assert_format "A = 10\nFOO = 123\nBARBAZ = 1234\n", "A      =   10\nFOO    =  123\nBARBAZ = 1234"
  assert_format "enum Foo\n  A      =   10\n  FOO    =  123\n  BARBAZ = 1234\nend\n", "enum Foo\n  A      =   10\n  FOO    =  123\n  BARBAZ = 1234\nend"
  assert_format "1\n# hello\n\n\n", "1\n# hello"
  assert_format "def foo\n  a = 1; # foo\n  a = 2; # bar\nend\n", "def foo\n  a = 1 # foo\n  a = 2 # bar\nend"
  assert_format "# Hello\n#\n# ```\n# puts 1+2 # bye\n# 1+2 # hello\n#\n# 1+2\n# ```\n\n# ```\n# puts 1+2\n\n# ```\n# puts 1+2\n\n# Hola\n#\n#     1+2\n#     foo do\n#     3+4\n#     end\n\n# Hey\n#\n#     1+2\n#     foo do\n#     3+4\n#     end\n#\n# ```\n# 1+2\n# ```\n#\n#     1+2\n#\n# Bye\n", "# Hello\n#\n# ```\n# puts 1 + 2 # bye\n# 1 + 2      # hello\n#\n# 1 + 2\n# ```\n\n# ```\n# puts 1+2\n\n# ```\n# puts 1+2\n\n# Hola\n#\n#     1+2\n#     foo do\n#     3+4\n#     end\n\n# Hey\n#\n#     1+2\n#     foo do\n#     3+4\n#     end\n#\n# ```\n# 1 + 2\n# ```\n#\n#     1+2\n#\n# Bye"
  assert_format "# Hello\n#\n# ```cr\n#   1\n# ```\n# Bye", "# Hello\n#\n# ```\n# 1\n# ```\n# Bye"
  assert_format "# Hello\n#\n# ```crystal\n#   1\n# ```\n# Bye", "# Hello\n#\n# ```\n# 1\n# ```\n# Bye"
  assert_format "macro foo\n  {% for value, i in values %}\\\n    {% if true %}\\\n    {% end %}\\\n    {{ 1 }}/\n  {% end %}\\\nend\n\n{\n  1 => 2,\n  1234 => 5,\n}\n", "macro foo\n  {% for value, i in values %}\\\n    {% if true %}\\\n    {% end %}\\\n    {{ 1 }}/\n  {% end %}\\\nend\n\n{\n     1 => 2,\n  1234 => 5,\n}"
  assert_format "a = \"\n\"\n1    # 1\n12 # 2\n", "a = \"\n\"\n1  # 1\n12 # 2"
  assert_format "enum Foo\n  A;   B;   C\nend\n", "enum Foo\n  A; B; C\nend"
  assert_format "# ```\n# macro foo\n#   1\n# end\n# ```\n", "# ```\n# macro foo\n#   1\n# end\n# ```"
  assert_format "class Foo\n  # ```\n  # 1\n  # ```\nend\n", "class Foo\n  # ```\n  # 1\n  # ```\nend"
  assert_format "# Here is the doc of a method, and contains an example:\n#\n# ```\n# result = foo\n#\n# puts result\n# ```\ndef foo\n  # ...\nend\n", "# Here is the doc of a method, and contains an example:\n#\n# ```\n# result = foo\n#\n# puts result\n# ```\ndef foo\n  # ...\nend"
  assert_format "foo(\n  a: 1,\n  b: 2,\n  )\n", "foo(\n  a: 1,\n  b: 2,\n)"
  assert_format "  case 1\n  when 2\n    3\n  else #:newline, :eof\n    1 if 2\n    return 3\n  end\n", "case 1\nwhen 2\n  3\nelse # :newline, :eof\n  1 if 2\n  return 3\nend"
  assert_format "a = 1 if 1 == 2 ||\n  3 == 4\n", "a = 1 if 1 == 2 ||\n         3 == 4"
  assert_format "{ A: 1 }\n", "{A: 1}"
  assert_format "class Foo\n  enum Bar\n  A; B; C;\n  D; E; F\nend\nend\n", "class Foo\n  enum Bar\n    A; B; C\n    D; E; F\n  end\nend"
  assert_format "x.is_a? T\n3\n", "x.is_a? T\n3"
  assert_format "a = begin\n  1\nend\n\na =\nbegin\n  1\nend\n\na = if 1\n  2\nend\n\nb = 1\nb ||= begin\n  2\nend\n\nb ||= if 1\n  2\nend\n\nb += if 1\n  2\nend\n\nb +=\nif 1\n  2\nend\n\na, b = begin\n  1\nend\n\na, b =\nbegin\n  1\nend\n\nc[x] = begin\n  2\nend\n\nc[x] =\nbegin\n  2\nend\n\nc[x] = if 1\n  2\nend\n\nc[x] ||= begin 1\n  2\nend\n\nc[x] ||= if 1\n  2\nend\n\nc[x] += if 1\n  2\nend\n\nc[x] += begin 1\n  2\nend\n\nc[x] +=\nbegin\n  1\n  2\nend\n\nfoo.bar = begin\nend\n\nfoo.bar =\nbegin\nend\n\nfoo.bar = if\n  2\nend\n\nfoo.bar += begin\n  2\nend\n\nfoo.bar += if\n  2\nend\n\n", "a = begin\n  1\nend\n\na =\n  begin\n    1\n  end\n\na = if 1\n      2\n    end\n\nb = 1\nb ||= begin\n  2\nend\n\nb ||= if 1\n        2\n      end\n\nb += if 1\n       2\n     end\n\nb +=\n  if 1\n    2\n  end\n\na, b = begin\n  1\nend\n\na, b =\n  begin\n    1\n  end\n\nc[x] = begin\n  2\nend\n\nc[x] =\n  begin\n    2\n  end\n\nc[x] = if 1\n         2\n       end\n\nc[x] ||= begin\n  1\n  2\nend\n\nc[x] ||= if 1\n           2\n         end\n\nc[x] += if 1\n          2\n        end\n\nc[x] += begin\n  1\n  2\nend\n\nc[x] +=\n  begin\n    1\n    2\n  end\n\nfoo.bar = begin\n\nend\n\nfoo.bar =\n  begin\n\n  end\n\nfoo.bar = if 2\n          end\n\nfoo.bar += begin\n  2\nend\n\nfoo.bar += if 2\n           end"
  assert_format "module Foo\n  1 # bar\nend\n\nmodule Foo\n  1\n  # bar\nend\n\nmodule Foo\n  1\n\n  # bar\nend\n\nmodule Foo\n  1\n  2\n  # bar\nend\n\nmodule Foo\n  1\n  2\n\n  # bar\nend\n\nif 1\n  1\n  # bar\nend\n\nif 1\n  1\n\n  # bar\nend\n\n1\n2\n# foo\n\n1\n2\n\n# foo\n", "module Foo\n  1 # bar\nend\n\nmodule Foo\n  1\n  # bar\nend\n\nmodule Foo\n  1\n\n  # bar\nend\n\nmodule Foo\n  1\n  2\n  # bar\nend\n\nmodule Foo\n  1\n  2\n\n  # bar\nend\n\nif 1\n  1\n  # bar\nend\n\nif 1\n  1\n\n  # bar\nend\n\n1\n2\n# foo\n\n1\n2\n\n# foo"
  assert_format "begin\n  #hola\n  1\nend\n", "begin\n  # hola\n  1\nend"
  assert_format "begin\nend\n\n# a\n", "begin\n\nend\n\n# a"
  assert_format "begin\n  1\nend\n\n1\n", "begin\n  1\nend\n\n1"
  assert_format "{\n  \"a\" => 1, \"b\" => 2,\n  \"foo\" => 3, \"bar\" => 4,\n  \"coconio\" => 5, \"lala\" => 6,\n}\n", "{\n  \"a\" => 1, \"b\" => 2,\n  \"foo\" => 3, \"bar\" => 4,\n  \"coconio\" => 5, \"lala\" => 6,\n}"
  assert_format "if 1\n  foo(\n    1,\n    2 # lala\n    )\nend\n", "if 1\n  foo(\n    1,\n    2 # lala\n  )\nend"
  assert_format "case foo\nwhen 1\n  # A\nelse\n# B\nend\n", "case foo\nwhen 1\n  # A\nelse\n  # B\nend"
  assert_format "return 1\n# end"
  assert_format "case\n# hello\nwhen 1\n  2\nend"
  assert_format "case 1\nwhen 2 # a\n  # b\nend"
  assert_format "case 1\nelse # foo\n  # bar\nend"

  assert_format "{} of A => B\n{} of Foo => Bar"

  assert_format "<<-HTML\n  \#{1}x\n  HTML"
  assert_format "<<-HTML\n  \#{1}x\n  y\n  HTML"
  assert_format "<<-HTML\n  \#{1}x\n  y\n  z\n  HTML"
  assert_format %(<<-HTML\n  \#{"foo"}\n  HTML)
  assert_format %(<<-HTML\n  \#{__FILE__}\n  HTML)
  assert_format %(<<-HTML\n  \#{"fo\#{"o"}"}\n  HTML)
  assert_format %(<<-HTML\n  \#{"foo"}\#{1}\n  HTML)
  assert_format %(<<-HTML\n  foo\n  \#{"foo"}\n  HTML)
  assert_format %(<<-HTML\n  \#{"foo"}\n  \#{"bar"}\n  HTML)

  assert_format "  <<-HTML\n   foo\n  HTML", "<<-HTML\n foo\nHTML"
  assert_format "  <<-HTML\n   \#{1}\n  HTML", "<<-HTML\n \#{1}\nHTML"
  assert_format "  <<-HTML\n  \#{1} \#{2}\n  HTML", "<<-HTML\n\#{1} \#{2}\nHTML"
  assert_format "  <<-HTML\n  foo\nHTML", "<<-HTML\n  foo\nHTML"

  assert_format "<<-HTML\n  hello \n  HTML"
  assert_format "<<-HTML\n  hello \n  world   \n  HTML"
  assert_format "  <<-HTML\n    hello \n    world   \n    HTML", "<<-HTML\n  hello \n  world   \n  HTML"

  assert_format "x, y = <<-FOO, <<-BAR\n  hello\n  FOO\n  world\n  BAR"
  assert_format "x, y, z = <<-FOO, <<-BAR, <<-BAZ\n  hello\n  FOO\n  world\n  BAR\n  qux\nBAZ"

  assert_format "<<-FOO\nFOO"

  assert_format "<<-FOO\n#{"foo"}\nFOO"
  assert_format "<<-FOO\n#{"foo"}bar\nFOO"
  assert_format "<<-FOO\nbar#{"foo"}\nFOO"
  assert_format "<<-FOO\nbar#{"foo"}bar\nFOO"
  assert_format "<<-FOO\nfoo\n#{"foo"}\nFOO"
  assert_format "<<-FOO\nfoo\n#{1}\nFOO"

  assert_format "#!shebang\n1 + 2"

  assert_format "   {{\n1 + 2 }}", "{{\n  1 + 2\n}}"
  assert_format "   {{\n1 + 2\n   }}", "{{\n  1 + 2\n}}"
  assert_format "   {%\na = 1 %}", "{%\n  a = 1\n%}"
  assert_format "   {%\na = 1\n   %}", "{%\n  a = 1\n%}"

  assert_format "macro foo\n  {{\n1 + 2 }}\nend", "macro foo\n  {{\n    1 + 2\n  }}\nend"
  assert_format "macro foo\n  def bar\n    {{\n      1 + 2\n    }}\n  end\nend"
  assert_format "foo &.[]"
  assert_format "foo &.[](1, 2)"
  assert_format "foo &.[](  1, 2  )", "foo &.[](1, 2)"
  assert_format "foo &.[]?"
  assert_format "foo &.[]?(1, 2)"
  assert_format "foo &.[]?(  1, 2  )", "foo &.[]?(1, 2)"
  assert_format "foo &.[]=(1, 2)"
  assert_format "foo &.[]=(  1, 2  )", "foo &.[]=(1, 2)"

  assert_format "foo &.@bar"
  assert_format "foo(&.@bar)"

  assert_format "foo[&.bar]"
  assert_format "foo[1, &.bar]"
  assert_format "foo[x: 1, &.bar]"
  assert_format "foo[&.bar]?"
  assert_format "foo[1, &.bar]?"
  assert_format "foo[x: 1, &.bar]?"
  assert_format "foo[&.bar] = 1"
  assert_format "foo[1, &.bar] = 1"
  assert_format "foo[x: 1, &.bar] = 1"
  assert_format "foo[&.bar] ||= 1"
  assert_format "foo[1, &.bar] ||= 1"
  assert_format "foo[x: 1, &.bar] ||= 1"

  assert_format "foo.[]"
  assert_format "foo.[1]"
  assert_format "foo.[] = 1"
  assert_format "foo.[1, 2] = 3"

  %w(<= == >= != []= ===).each do |operator|
    assert_format "1.#{operator} { 3 }"
    assert_format "1.#{operator}() { 3 }"
    assert_format "1.#{operator}(2) { 3 }"
    assert_format "1.#{operator} do\nend"
  end

  assert_format "@foo : Int32 # comment\n\ndef foo\nend"
  assert_format "getter foo # comment\n\ndef foo\nend"
  assert_format "getter foo : Int32 # comment\n\ndef foo\nend"

  assert_format "a &.b.as C", "a &.b.as C"
  assert_format "a &.b.c.as C", "a &.b.c.as C"
  assert_format "a(&.b.c.as C)", "a(&.b.c.as C)"

  assert_format "a &.b.as(C)"
  assert_format "a &.b.c.as(C)"
  assert_format "a(&.b.c.as(C))"

  assert_format "foo : self?"
  assert_format "foo : self? | A"
  assert_format "foo : (self)?"

  assert_format "foo : (A) | D"
  assert_format "foo : (F(A)) | D"
  assert_format "foo : (   A  |  B   )", "foo : (A | B)"

  # #11179
  assert_format "foo : Pointer(Foo)*"
  assert_format "foo : Foo*****"
  assert_format "foo : Foo * * * * *", "foo : Foo*****"
  assert_format "foo : StaticArray(Foo, 12)[34]"

  assert_format "def   foo(x   :  (A | B)) \n  end", "def foo(x : (A | B))\nend"
  assert_format "foo : (String -> String?) | (String)"
  assert_format "foo : (Array(String)?) | String"
  assert_format "foo : (String -> Array(String)?) | (String -> Array(String)) | Nil"
  assert_format "module Readline\n  @@completion_proc : (String -> Array(String)?) | (String -> Array(String)) | Nil\nend"
  assert_format "alias A = (B(C, (C | D)) | E)"
  assert_format "alias A = ((B(C | D) | E) | F)"
  assert_format "alias A = ({A, (B)})"
  assert_format "alias A = (   A  |  B   )", "alias A = (A | B)"

  assert_format "foo : A(B)\nbar : C"
  assert_format "foo : (A -> B)\nbar : C"
  assert_format "def foo(x : A(B), y)\nend"
  assert_format "alias X = (A, B) ->\nbar : C"
  assert_format "def foo : A(B)\n  nil\nend"
  assert_format "def foo : (A, B) ->\n  nil\nend"
  assert_format "def foo : (A | B(C))\n  nil\nend"
  assert_format "def foo : A | B(C)\n  nil\nend"
  assert_format "def foo(x : (   A  |  B   )) : (   A  |  B   )\nend", "def foo(x : (A | B)) : (A | B)\nend"

  assert_format "foo &.bar.is_a?(Baz)"
  assert_format "foo &.bar.responds_to?(:baz)"

  assert_format "foo &.nil?"
  assert_format "foo &.bar.nil?"
  assert_format "foo &.nil?()", "foo &.nil?"
  assert_format "foo &.bar.nil?()", "foo &.bar.nil?"

  assert_format "1 if nil?\na.b + c"

  assert_format "foo(<<-X,\na\nX\n  1)"
  assert_format "def bar\n  foo(<<-X,\n  a\n  X\n    1)\nend"
  assert_format %(run("a", 1))

  assert_format "foo.bar # comment\n  .baz"
  assert_format "foo.bar(1) # comment\n  .baz"

  assert_format "foo[bar.baz]\n  .qux"

  assert_format "bla.select(&.all?{ |x| x } )", "bla.select(&.all? { |x| x })"
  assert_format "def foo\n  <<-FOO\n  foo \#{1}\n  FOO\nend"

  assert_format "@x : A(B | C)?"

  assert_format "page= <<-HTML\n  foo\nHTML", "page = <<-HTML\n  foo\nHTML"
  assert_format "page= <<-HTML\n  \#{1}foo\nHTML", "page = <<-HTML\n  \#{1}foo\nHTML"

  assert_format "self.as(Int32)"
  assert_format "foo.as ( Int32* )", "foo.as(Int32*)"
  assert_format "foo.as   Int32*", "foo.as Int32*"
  assert_format "foo.as(T).bar"
  assert_format "foo &.as(T)"
  assert_format "foo &.bar.as(T)"
  assert_format "foo &.as(T).bar"
  assert_format "foo &.as?(T).bar"
  assert_format "foo &.is_a?(T).bar"
  assert_format "foo &.responds_to?(:foo).bar"

  assert_format "foo.as? ( Int32* )", "foo.as?(Int32*)"
  assert_format "foo.as?   Int32*", "foo.as? Int32*"
  assert_format "foo.as?(T).bar"
  assert_format "foo &.as?(T)"
  assert_format "foo &.bar.as?(T)"

  assert_format "def foo(x, *, z)\nend"
  assert_format "macro foo(x, *, z)\nend"

  assert_format "def foo(x, *, y, **z)\nend"
  assert_format "def foo(**z)\nend"
  assert_format "def foo(*y, **z)\nend"
  assert_format "def foo(**z, &block)\nend"
  assert_format "def foo(x, **z)\nend"
  assert_format "def foo(x, **z, &block)\nend"
  assert_format "def foo(**z : Foo)\nend"

  assert_format "def foo(x y)\nend"
  assert_format "def foo(x @y)\nend"
  assert_format "def foo(x @@y)\nend"

  assert_format " Array( {x:  Int32,   y:  String } )", "Array({x: Int32, y: String})"

  assert_format "foo { | a, ( b , c ) | a + b + c }", "foo { |a, (b, c)| a + b + c }"
  assert_format "foo { | a, ( b , c, ), | a + b + c }", "foo { |a, (b, c)| a + b + c }"
  assert_format "foo { | a, ( _ , c ) | a + c }", "foo { |a, (_, c)| a + c }"
  assert_format "foo { | a, ( b , (c, d) ) | a + b + c }", "foo { |a, (b, (c, d))| a + b + c }"
  assert_format "foo { | ( a, *b , c ) | a }", "foo { |(a, *b, c)| a }"

  assert_format "def foo\n  {{@type}}\nend"

  assert_format "[\n  1, # foo\n  3,\n]"
  assert_format "[\n  1, 2, # foo\n  3,\n]"
  assert_format "[\n  1, 2, # foo\n  3, 4,\n]"
  assert_format "foo { |x, *y| }"

  assert_format %(foo "bar": 1, "baz qux": 2)
  assert_format %(foo("bar": 1, "baz qux": 2))

  assert_format %(Foo("bar": Int32, "baz qux": Float64))
  assert_format %(x : {"foo bar": Int32})

  assert_format %(def foo("bar baz" qux)\nend)
  assert_format "{ {{FOO}}, nil}", "{ {{FOO}}, nil }"
  assert_format "{ {% begin %}1{% end %}, nil }"
  assert_format "{ {% for x in 1..2 %}3{% end %}, nil }"
  assert_format "{ %() }"
  assert_format "{ %w() }"
  assert_format "{ {1}.foo, 2 }"

  assert_format "String?"
  assert_format "String???"
  assert_format "Foo::Bar?"
  assert_format "Foo::Bar(T, U?)?"
  assert_format "Union(Foo::Bar?, Baz?, Qux(T, U?))"

  assert_format "lib Foo\n  {% if 1 %}\n    fun foo\n  {% end %}\nend\n\nmacro bar\n  1\nend"

  assert_format "x : Int32 |\nString", "x : Int32 |\n    String"

  assert_format %(foo("bar" \\\n"baz")), %(foo("bar" \\\n    "baz"))
  assert_format %(foo("b\#{1}" \\\n"baz")), %(foo("b\#{1}" \\\n    "baz"))

  assert_format "foo(A |\nB |\nC)", "foo(A |\n    B |\n    C)"
  assert_format "def foo\n  case x\n  # z\n  when 1\n  end\nend"
  assert_format "foo { |x| (x).a }"
  assert_format "def foo(\n  &block\n)\nend"
  assert_format "def foo(a,\n        &block)\nend"
  assert_format "def foo(\n  a,\n  &block\n)\nend"
  assert_format "def foo(a,\n        *b)\nend"
  assert_format "def foo(a, # comment\n        *b)\nend", "def foo(a, # comment\n        *b)\nend"
  assert_format "def foo(a,\n        **b)\nend"
  assert_format "def foo(\n  **a\n)\n  1\nend", "def foo(\n  **a,\n)\n  1\nend"
  assert_format "def foo(**a,)\n  1\nend", "def foo(**a)\n  1\nend"
  assert_format "def foo(\n  **a # comment\n)\n  1\nend", "def foo(\n  **a, # comment\n)\n  1\nend"
  assert_format "def foo(\n  **a\n  # comment\n)\n  1\nend", "def foo(\n  **a,\n  # comment\n)\n  1\nend"
  assert_format "def foo(\n  **a\n\n  # comment\n)\n  1\nend", "def foo(\n  **a,\n\n  # comment\n)\n  1\nend"
  assert_format "def foo(**b, # comment\n        &block)\nend"
  assert_format "def foo(a, **b, # comment\n        &block)\nend"

  assert_format "1 +\n  # foo\n  2"
  assert_format "1 +\n  # foo\n  2"
  assert_format "1 ||\n  # foo\n  2"
  assert_format "foo(1 ||\n    # foo\n    2)"

  assert_format "x = a do\n  1 ||\n    2\nend"
  assert_format "case 1\nwhen a; 2\nelse; b\nend", "case 1\nwhen a; 2\nelse    b\nend"
  assert_format "case 1\nwhen a; 2\nelse; ; b\nend", "case 1\nwhen a; 2\nelse    b\nend"

  assert_format "as Foo"
  assert_format "as? Foo"
  assert_format "is_a? Foo"
  assert_format "responds_to? :foo"
  assert_format "nil?"

  assert_format "Union(Int32, String)?"

  assert_format "<<-HEREDOC\n  \#{foo}\n  H\#{bar}\n  HEREDOC"
  assert_format "foo[a, b: 2]"

  assert_format "def a\n  {\n    1, # x\n    # y\n  }\nend"
  assert_format "def a\n  [\n    1, # x\n    # y\n  ]\nend"
  assert_format "def a\n  b(\n    1, # x\n    # y\n  )\nend"
  assert_format "def a\n  b(\n    1, # x\n    # y\n    2\n  )\nend"
  assert_format "def a\n  b(\n    a: 1, # x\n    # y\n    b: 2\n  )\nend"
  assert_format "def a\n  b(\n    1, # x\n    # y\n    a: 1, # x\n    # y\n    b: 2 # z\n  )\nend"

  assert_format "def foo(a, **b : Int32)\nend"

  assert_format "foo\n  \nbar", "foo\n\nbar"

  assert_format "\"\" + <<-END\n  bar\n  END"

  assert_format "1 + \\\n2", "1 + \\\n  2"
  assert_format "1 + \\\n2 + \\\n3", "1 + \\\n  2 + \\\n  3"
  assert_format "1 + \\\n2\n3", "1 + \\\n  2\n3"
  assert_format "1 \\\n+ 2", "1 \\\n  + 2"
  assert_format "foo \\\nbar", "foo \\\n  bar"
  assert_format "1 \\\nif 2", "1 \\\n  if 2"
  assert_format "1 \\\nrescue 2", "1 \\\n  rescue 2"
  assert_format "1 \\\nensure 2", "1 \\\n  ensure 2"
  assert_format "foo bar, \\\nbaz", "foo bar,\n  baz"
  assert_format "x 1, \\\n  2", "x 1,\n  2"
  assert_format "begin\n  1 + \\\n    2\n  3\nend"
  assert_format "begin\n  1 \\\n    + 2\n  3\nend"
  assert_format "foo \\\n  1,\n  2"
  assert_format "foo \\\n  foo: 1,\n  bar: 2"
  assert_format "foo \\\n  1,\n  2\n\nbar \\\n  foo: 1,\n  bar: 2"

  assert_format "alias X = ((Y, Z) ->)"

  assert_format "def x(@y = ->(z) {})\nend", "def x(@y = ->(z) { })\nend"

  assert_format "class X; annotation  FooAnnotation  ;  end ; end", "class X\n  annotation FooAnnotation; end\nend"
  assert_format "class X\n annotation  FooAnnotation  \n  end \n end", "class X\n  annotation FooAnnotation\n  end\nend"

  assert_format "macro foo\n{% verbatim do %}1 + 2{% end %}\nend"
  assert_format "{% verbatim do %}{{1}} + {{2}}{% end %}"
  assert_format "foo({% verbatim do %}{{1}} + {{2}}{% end %})"

  assert_format "{% foo <<-X\nbar\nX\n%}"
  assert_format "foo do\n  {% foo <<-X\n  bar\n  X\n  %}\nend"
  assert_format "{{ foo <<-X\nbar\nX\n}}"
  assert_format "foo do\n  {{ foo <<-X\n  bar\n  X\n  }}\nend"
  assert_format "[foo <<-X\nbar\nX\n]"
  assert_format "foo do\n  [foo <<-X\n  bar\n  X\n  ]\nend"
  assert_format "{1 => foo <<-X\nbar\nX\n}"
  assert_format "foo do\n  {1 => foo <<-X\n  bar\n  X\n  }\nend"
  assert_format "bar do\n  foo <<-X\n  bar\n  X\nend"
  assert_format "foo do\n  bar do\n    foo <<-X\n    bar\n    X\n  end\nend"
  assert_format "call(foo <<-X\nbar\nX\n)"
  assert_format "bar do\n  call(foo <<-X\n  bar\n  X\n  )\nend"

  assert_format "[\n  <<-EOF,\n  foo\n  EOF\n]"
  assert_format "[\n  <<-EOF,\n  foo\n  EOF\n  <<-BAR,\n  bar\n  BAR\n]"
  assert_format "Hash{\n  foo => <<-EOF,\n  foo\n  EOF\n}"
  assert_format "Hash{\n  foo => <<-EOF,\n  foo\n  EOF\n  bar => <<-BAR,\n  bar\n  BAR\n}"
  assert_format "Hash{\n  foo => <<-EOF\n  foo\n  EOF\n}"
  assert_format "{\n  <<-KEY => 1,\n  key\n  KEY\n}"

  # #10734
  assert_format " <<-EOF\n 1\nEOF", "<<-EOF\n 1\nEOF"
  assert_format "  <<-EOF\n   1\n EOF", "<<-EOF\n  1\nEOF"
  assert_format "x =  <<-EOF\n 1\nEOF", "x = <<-EOF\n 1\nEOF"
  assert_format "  <<-EOF\n 1\n  2\n EOF", "<<-EOF\n1\n 2\nEOF"

  # #10735
  assert_format "{\n  variables => true,\n  query     => <<-HEREDOC,\n    foo\n  HEREDOC\n}"
  assert_format "{\n  variables => true,\n  query     => <<-HEREDOC,\n    foo\n  HEREDOC\n  foo => true,\n}"
  assert_format "{\n  query     => <<-HEREDOC,\n    foo\n  HEREDOC\n}", "{\n  query => <<-HEREDOC,\n    foo\n  HEREDOC\n}"
  assert_format "begin\n  query = <<-HEREDOC\n    foo\n  HEREDOC\nend"

  assert_format "begin 0[1] rescue 2 end"
  assert_format "begin\n 0[1] rescue 2 end", "begin 0[1] rescue 2 end"

  assert_format "{%\n  if 1\n    2\n  end\n%}"

  assert_format <<-CRYSTAL
    # ```text
    #  1  +  2
    # ```
    CRYSTAL

  assert_format <<-CRYSTAL
    # ```text
    # 1 + 2
    # ```
    #
    # ```
    # 3 + 4
    # ```
    CRYSTAL

  assert_format <<-CRYSTAL
    X(typeof(begin
      e.is_a?(Y) ? 1 : 2
    end))
    CRYSTAL

  assert_format <<-CRYSTAL
    X(typeof(begin
      e.is_a?(Y)
    end))
    CRYSTAL

  # Keep trailing spaces in macros.
  assert_format(
    "macro foo\n" +
    "  <<-FOO\n" +
    "    hello  \n" +
    "  FOO\n" +
    "end"
  )
  assert_format(
    "{% verbatim do %}\n" +
    "  <<-FOO\n" +
    "    hello  \n" +
    "  FOO\n" +
    "{% end %}"
  )
  assert_format(
    "{% if true %}\n" +
    "  <<-FOO\n" +
    "    hello  \n" +
    "  FOO\n" +
    "{% end %}"
  )
  assert_format(
    "{% for a in %w() %}\n" +
    "  <<-FOO\n" +
    "    hello  \n" +
    "  FOO\n" +
    "{% end %}"
  )
  assert_format(
    "macro foo\n" +
    "  {{x}}" +
    "  <<-FOO\n" +
    "    hello  \n" +
    "  FOO\n" +
    "end"
  )

  # But remove trailing space in macro expression.
  assert_format(
    "macro foo\n" +
    "  1  \n" +
    "  {{  \n" +
    "    42  \n" +
    "  }}  \n" +
    "  2  \n" +
    "end",
    "macro foo\n" +
    "  1  \n" +
    "  {{\n" +
    "    42\n" +
    "  }}  \n" +
    "  2  \n" +
    "end"
  )

  # #7443
  assert_format "long_variable_name = [{\n  :foo => 1,\n}, {\n  :bar => 2,\n}]"
  assert_format "long_variable_name = [\n  {\n    :foo => 1,\n  }, {\n    :bar => 2,\n  },\n]"
  assert_format "long_variable_name = [\n  {\n    :foo => 1,\n  },\n  {\n    :bar => 2,\n  },\n]"
  assert_format "long_variable_name = [1, 2, 3,\n                      4, 5, 6]"
  assert_format "long_variable_name = [1, 2, 3, # foo\n                      4, 5, 6]"

  # #7599
  assert_format "def foo # bar\n  # baz\nend"
  assert_format "def foo(x) # bar\n  # baz\nend"
  assert_format "def foo(x) : Int32 # bar\n  # baz\nend"
  assert_format "def foo(x) forall T # bar\n  # baz\nend"

  # #7608
  assert_format "enum E\n  A # hello\n  B # hello;  C # hello\nend"

  # #7631
  assert_format "x.try &.[] 123"
  assert_format "x.try &.[]= 123, 456"

  # #7684
  assert_format "foo(\n  <<-HERE,\n  hello\n  HERE\n  1,\n)"
  assert_format "foo(\n  <<-HERE,\n  hello\n  HERE\n  foo: 1,\n)"
  assert_format "foo(\n  <<-HERE,\n  hello\n  HERE\n  # foo\n  foo: 1,\n)"

  # #7614
  assert_format "@[ Foo ]\ndef foo\nend", "@[Foo]\ndef foo\nend"
  assert_format "@[ Foo(foo: 1) ]\ndef foo\nend", "@[Foo(foo: 1)]\ndef foo\nend"
  assert_format "@[Foo(\n  foo: 1\n)]\ndef foo\nend"
  assert_format "@[Foo(\n  foo: 1,\n)]\ndef foo\nend"

  # #7550
  assert_format "foo\n  .bar(\n    1\n  )"
  assert_format "foo\n  .bar\n  .baz(\n    1\n  )"
  assert_format "foo.bar\n  .baz(\n    1\n  )"

  assert_format <<-CRYSTAL,
    def foo
      {% if flag?(:foo) %}
        foo  +  bar
      {% else %}
        baz  +  qux
      {% end %}
    end
    CRYSTAL
    <<-CRYSTAL
    def foo
      {% if flag?(:foo) %}
        foo + bar
      {% else %}
        baz + qux
      {% end %}
    end
    CRYSTAL

  assert_format <<-CRYSTAL,
    def foo
      {% for x in y %}
        foo  +  bar
      {% end %}
    end
    CRYSTAL
    <<-CRYSTAL
    def foo
      {% for x in y %}
        foo + bar
      {% end %}
    end
    CRYSTAL

  assert_format <<-CRYSTAL,
    x = {% if flag?(:foo) %}
          foo  +  bar
        {% else %}
          baz  +  qux
        {% end %}
    CRYSTAL
    <<-CRYSTAL
    x = {% if flag?(:foo) %}
          foo + bar
        {% else %}
          baz + qux
        {% end %}
    CRYSTAL

  assert_format <<-CRYSTAL
    {% if flag?(:freebsd) %}
      1 + 2
    {% end %}

    case x
    when 1234 then 1
    else           x
    end
    CRYSTAL

  assert_format <<-CRYSTAL
    {% if z %}
      1
    {% end %}

    def foo
      z =
        123 + # foo
          4   # bar

      1
    end
    CRYSTAL

  assert_format <<-CRYSTAL
    lib LibFoo
      {% begin %}
        fun foo : Int32
      {% end %}
    end
    CRYSTAL

  assert_format <<-CRYSTAL
    lib LibFoo
      struct Bar
        {% begin %}
          x : Int32
        {% end %}
      end
    end
    CRYSTAL

  assert_format <<-CRYSTAL
    enum Foo
      {% begin %}
        A
        B
        C
      {% end %}
    end
    CRYSTAL

  assert_format <<-CRYSTAL
    a = 1
    b, c = 2, 3
    {% begin %}
      a |= 1
      b |= 2
      c |= 3
    {% end %}
    CRYSTAL

  assert_format <<-CRYSTAL
    lib LibFoo
      {% begin %}
        fun x = y(Int32)
      {% end %}
    end
    CRYSTAL

  assert_format <<-CRYSTAL
    {% begin %}
      "
        foo"
    {% end %}
    CRYSTAL

  assert_format <<-CRYSTAL,
    {% if z %}
      class   Foo
      end
    {% end %}
    CRYSTAL
    <<-CRYSTAL
    {% if z %}
      class Foo
      end
    {% end %}
    CRYSTAL

  assert_format <<-CRYSTAL
    {% if true %}
      # x
    {% end %}
    CRYSTAL

  assert_format <<-CRYSTAL
    {% if true %}
      # x
      # y
    {% end %}
    CRYSTAL

  assert_format <<-CRYSTAL
    {% if true %}
      # x
      #
    {% end %}

    # ```
    # x
    # ```
    CRYSTAL

  assert_format <<-CRYSTAL
    def foo(x)
      {% if true %}
        x = x + 2
      {% end %}
    end
    CRYSTAL

  assert_format <<-CRYSTAL
    def foo(x)
      {% if true %}
        # comment
        Foo = 1
        B   = 2
      {% end %}
    end
    CRYSTAL

  assert_format <<-CRYSTAL
    def foo(x)
      {% if true %}
        \\{% if true %}
          x = 1
        \\{% else %}
          x = 2
        \\{% end %}
        \\{% for x in y %}
          x = 1
        \\{% end %}
        \\{{x}}
        \\{% x %}
      {% end %}
    end
    CRYSTAL

  it "gives proper line number in syntax error inside macro" do
    source = <<-CRYSTAL
      a = 1
      b = 2

      {% begin %}
        c |= 3
      {% end %}
    CRYSTAL

    ex = expect_raises(Crystal::SyntaxException) do
      Crystal.format(source)
    end
    ex.line_number.should eq(5)
  end

  # #8197
  assert_format <<-CRYSTAL
    foo
      .foo1(bar
        .bar1
        .bar2)
    CRYSTAL

  assert_format <<-CRYSTAL
    foo.foo1(
      bar
        .bar1
        .bar2)
    CRYSTAL

  assert_format "[] of (Array(T))"
  assert_format "[] of (((Array(T))))"

  assert_format <<-CRYSTAL
    macro foo # bar
      baz
    end
    CRYSTAL

  assert_format "a.!"
  assert_format "a &.!"
  assert_format "a &.a.!"
  assert_format "a &.!.!"

  assert_format <<-CRYSTAL, <<-CRYSTAL
    ->{
      # first comment
      puts "hi"
      # second comment
    }
    CRYSTAL
    -> {
      # first comment
      puts "hi"
      # second comment
    }
    CRYSTAL

  # #9014
  assert_format <<-CRYSTAL
    {%
      unless true
        1
      end
    %}
    CRYSTAL

  assert_format <<-CRYSTAL
    {%
      unless true
        1
      else
        2
      end
    %}
    CRYSTAL

  assert_format <<-CRYSTAL
    {%
      if true
        1
      else
        2
      end
    %}
    CRYSTAL

  # #4626
  assert_format <<-CRYSTAL
    1 # foo
    / 1 /
    CRYSTAL

  assert_format <<-CRYSTAL
    1 # foo
    / #{1} /
    CRYSTAL

  assert_format <<-CRYSTAL,
    def foo
      # Comment


    end
    CRYSTAL
    <<-CRYSTAL
    def foo
      # Comment
    end
    CRYSTAL

  assert_format <<-CRYSTAL,
    def foo
      1
      # Comment


    end
    CRYSTAL
    <<-CRYSTAL
    def foo
      1
      # Comment
    end
    CRYSTAL

  assert_format <<-CRYSTAL
    def foo
      1
    end

    # Comment

    def bar
      2
    end
    CRYSTAL

  assert_format <<-CRYSTAL
    require "foo"

    @x : Int32

    class Bar
    end
    CRYSTAL

  assert_format <<-CRYSTAL
    x = <<-FOO
      hello
      FOO

    def bar
    end
    CRYSTAL

  assert_format <<-CRYSTAL, <<-CRYSTAL
    begin
      1
      # Comment


    end
    CRYSTAL
    begin
      1
      # Comment
    end
    CRYSTAL

  assert_format <<-CRYSTAL, <<-CRYSTAL
    begin
      # Comment


    end
    CRYSTAL
    begin
      # Comment
    end
    CRYSTAL

  assert_format <<-CRYSTAL
    foo 1, # comment
      do
      end
    CRYSTAL

  assert_format <<-CRYSTAL
    foo 1, # comment
      # bar
      do
      end
    CRYSTAL

  # #10190
  assert_format <<-CRYSTAL
    foo(
      1,
    ) do
      2
    end
    CRYSTAL

  assert_format <<-CRYSTAL
    foo(
      1,
    ) {
      2
    }
    CRYSTAL

  # #11079
  assert_format <<-CRYSTAL
    foo = [1, [2,
               3],
           4]
    CRYSTAL

  assert_format <<-CRYSTAL
    foo = {1, {2,
               3},
           4}
    CRYSTAL

  # #10817
  assert_format <<-CRYSTAL
    def func # comment
      (1 + 2) / 3
    end
    CRYSTAL

  # #10943
  assert_format <<-CRYSTAL
    foo do # a
      # b
      bar
    end
    CRYSTAL

  # #10499
  assert_format <<-CRYSTAL
    case nil
    else nil; nil # comment
    end
    CRYSTAL

  assert_format <<-CRYSTAL
    case nil
    else nil; nil
    # comment
    end
    CRYSTAL

  # #12493
  assert_format <<-CRYSTAL
    select
    # when foo
    when bar
      break
    end
    CRYSTAL

  assert_format <<-CRYSTAL
    select # some comment
    when bar
      break
    end
    CRYSTAL

  # #12378
  assert_format <<-CRYSTAL
    macro foo
      macro bar
        \\{% begin %}
          \\\\{% puts %}
        \\{% end %}
      end
    end
    CRYSTAL

  # #12964
  assert_format <<-CRYSTAL
    begin
      begin
        a
        # b
      end
    end
    CRYSTAL

  it do
    expect_raises(Crystal::SyntaxException) do
      Crystal.format <<-CRYSTAL
        lib A
          struct B
            {% begin %}
              x : Int32
              else
            {% end %}
          end
        end
        CRYSTAL
    end
  end

  # #14256
  assert_format <<-CRYSTAL
    foo bar # comment

    # doc
    def baz; end
    CRYSTAL

  # CVE-2021-42574
  describe "Unicode bi-directional control characters" do
    ['\u202A', '\u202B', '\u202C', '\u202D', '\u202E', '\u2066', '\u2067', '\u2068', '\u2069'].each do |char|
      assert_format %("#{char}"), %("#{char.unicode_escape}")
      assert_format %("\\c#{char}"), %("c#{char.unicode_escape}")
      assert_format %("#{char}\#{1}"), %("#{char.unicode_escape}\#{1}")
      assert_format %("\\c#{char}\#{1}"), %("c#{char.unicode_escape}\#{1}")
      assert_format %(%(#{char})), %(%(#{char.unicode_escape}))
      assert_format %(%Q(#{char})), %(%Q(#{char.unicode_escape}))
      assert_format %(%Q(#{char}\#{1})), %(%Q(#{char.unicode_escape}\#{1}))
      assert_format %(<<-EOS\n#{char}\nEOS), %(<<-EOS\n#{char.unicode_escape}\nEOS)
      assert_format %(<<-EOS\n#{char}\#{1}\nEOS), %(<<-EOS\n#{char.unicode_escape}\#{1}\nEOS)
      assert_format %(def foo("#{char}" x)\nend), %(def foo("#{char.unicode_escape}" x)\nend)
      assert_format %(foo("#{char}": 1)), %(foo("#{char.unicode_escape}": 1))
      assert_format %(NamedTuple("#{char}": Int32)), %(NamedTuple("#{char.unicode_escape}": Int32))
      assert_format %({"#{char}": 1}), %({"#{char.unicode_escape}": 1})

      # the following contexts do not accept escape sequences, escaping these
      # control characters would alter the meaning of the source code
      assert_format %(/#{char}/)
      assert_format %(%r(#{char}))
      assert_format %(%q(#{char}))
      assert_format %(%w(#{char}))
      assert_format %(%i(#{char}))
      assert_format %(/#{char}\#{1}/)
      assert_format %(%r(#{char}\#{1}))
      assert_format %(<<-'EOS'\n#{char}\nEOS)
    end
  end
end
