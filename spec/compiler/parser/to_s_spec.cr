require "../../support/syntax"

private def expect_to_s(original, expected = original, emit_doc = false, file = __FILE__, line = __LINE__, focus = false)
  it "does to_s of #{original.inspect}", file, line, focus: focus do
    str = IO::Memory.new expected.bytesize

    source = original
    if source.is_a?(String)
      parser = Parser.new source
      parser.wants_doc = emit_doc
      node = parser.parse
      node.to_s(str, emit_doc: emit_doc)
      str.to_s.should eq(expected), file: file, line: line

      # Check keeping information for `to_s` on clone
      cloned = node.clone
      str.clear
      cloned.to_s(str, emit_doc: emit_doc)
      str.to_s.should eq(expected), file: file, line: line
    else
      source.to_s.should eq(expected), file: file, line: line
    end
  end
end

describe "ASTNode#to_s" do
  expect_to_s "([] of T).foo"
  expect_to_s "({} of K => V).foo"
  expect_to_s "foo(bar)"
  expect_to_s "(~1).foo"
  expect_to_s "1 && (a = 2)"
  expect_to_s "(a = 2) && 1"
  expect_to_s "foo(a.as(Int32))"
  expect_to_s "(1 + 2).as(Int32)", "(1 + 2).as(Int32)"
  expect_to_s "a.as?(Int32)"
  expect_to_s "(1 + 2).as?(Int32)", "(1 + 2).as?(Int32)"
  expect_to_s "@foo.bar"
  expect_to_s %(:foo)
  expect_to_s %(:"{")
  expect_to_s %(%r())
  expect_to_s %(%r()imx)
  expect_to_s %(/hello world/)
  expect_to_s %(/hello world/imx)
  expect_to_s %(/\\s/)
  expect_to_s %(/\\?/)
  expect_to_s %(/\\(group\\)/)
  expect_to_s %(/\\//), "/\\//"
  expect_to_s %(/\#{1 / 2}/)
  expect_to_s %<%r(/)>, %(/\\//)
  expect_to_s %(/ /), %(/\\ /)
  expect_to_s %(%r( )), %(/\\ /)
  expect_to_s %(foo &.bar), %(foo(&.bar))
  expect_to_s %(foo &.bar(1, 2, 3)), %(foo(&.bar(1, 2, 3)))
  expect_to_s %(foo x: 1, y: 2, &.bar), %(foo(x: 1, y: 2, &.bar))
  expect_to_s %(foo { |i| i.bar { i } }), "foo do |i|\n  i.bar do\n    i\n  end\nend"
  expect_to_s %(foo do |k, v|\n  k.bar(1, 2, 3)\nend)
  expect_to_s %(foo(3, &.*(2)))
  expect_to_s %(return begin\n  1\n  2\nend)
  expect_to_s %(macro foo\n  %bar = 1\nend)
  expect_to_s %(macro foo\n  %bar = 1; end)
  expect_to_s %(macro foo\n  %bar{1, x} = 1\nend)
  expect_to_s %({% foo %})
  expect_to_s %({{ foo }})
  expect_to_s %({% if foo %}\n  foo_then\n{% end %})
  expect_to_s %({% if foo %}\n  foo_then\n{% else %}\n  foo_else\n{% end %})
  expect_to_s %({% for foo in bar %}\n  {{ foo }}\n{% end %})
  expect_to_s %(macro foo\n  {% for foo in bar %}\n    {{ foo }}\n  {% end %}\nend)
  expect_to_s %[1.as(Int32)]
  expect_to_s %[(1 || 1.1).as(Int32)], %[(1 || 1.1).as(Int32)]
  expect_to_s %[1 & 2 & (3 | 4)], %[(1 & 2) & (3 | 4)]
  expect_to_s %[(1 & 2) & (3 | 4)]
  expect_to_s "def foo(x : T = 1)\nend"
  expect_to_s "def foo(@[Foo] x : T = 1)\nend"
  expect_to_s "def foo(x : X, y : Y) forall X, Y\nend"
  expect_to_s "def foo(x : X, @[Foo] y : Y) forall X, Y\nend"
  expect_to_s %(foo : A | (B -> C))
  expect_to_s %(foo : (A | B).class)
  expect_to_s %[%("\#{foo}")], %["\\"\#{foo}\\""]
  expect_to_s "class Foo\n  private def bar\n  end\nend"
  expect_to_s "foo(&.==(2))"
  expect_to_s "foo.nil?"
  expect_to_s "foo._bar"
  expect_to_s "foo._bar(1)"
  expect_to_s "_foo.bar"
  expect_to_s "1.responds_to?(:to_s)"
  expect_to_s "1.responds_to?(:\"&&\")"
  expect_to_s "macro foo(&block)\nend"
  expect_to_s "macro foo(&)\nend"
  expect_to_s "macro foo(*, __var var)\nend"
  expect_to_s "macro foo(*, var)\nend"
  expect_to_s "macro foo(*var)\nend"
  expect_to_s "macro foo(@[Foo] &)\nend"
  expect_to_s "macro foo(@[Foo] &block)\nend"
  expect_to_s "macro foo(x, *y)\nend"
  expect_to_s "macro foo(x, @[Foo] *y)\nend"
  expect_to_s "macro foo(@[Foo] x, @[Foo] *y)\nend"
  expect_to_s "{ {1, 2, 3} }"
  expect_to_s "{ {1 => 2} }"
  expect_to_s "{ {1, 2, 3} => 4 }"
  expect_to_s "{ {foo: 2} }"
  expect_to_s "def foo(*args)\nend"
  expect_to_s "def foo(@[Foo] *args)\nend"
  expect_to_s "def foo(*args : _)\nend"
  expect_to_s "def foo(**args)\nend"
  expect_to_s "def foo(@[Foo] **args)\nend"
  expect_to_s "def foo(**args : T)\nend"
  expect_to_s "def foo(x, **args)\nend"
  expect_to_s "def foo(x, @[Foo] **args)\nend"
  expect_to_s "def foo(x, **args, &block)\nend"
  expect_to_s "def foo(@[Foo] x, @[Bar] **args, @[Baz] &block)\nend"

  # 14216
  expect_to_s "def foo(x, **args, &block : _ -> _)\nend"
  expect_to_s "def foo(x, **args, &block : (_ -> _))\nend", "def foo(x, **args, &block : _ -> _)\nend"
  expect_to_s "def foo(& : ->)\nend"
  expect_to_s "def foo(& : (->))\nend", "def foo(& : ->)\nend"
  expect_to_s "def foo(x : (T -> U) -> V, *args : (T -> U) -> V, y : (T -> U) -> V, **opts : (T -> U) -> V, & : (T -> U) -> V) : ((T -> U) -> V)\nend"
  expect_to_s "foo(x : (T -> U) -> V, W)"
  expect_to_s "foo[x : (T -> U) -> V, W]"
  expect_to_s "foo[x : (T -> U) -> V, W] = 1"
  expect_to_s "lib LibFoo\n  fun foo(x : (T -> U) -> V, W) : ((T -> U) -> V)\nend"

  expect_to_s "lib LibFoo\n  fun foo(x : (T -> U) | V)\nend"
  expect_to_s "lib LibFoo\n  fun foo(x : Foo((T -> U)))\nend"
  expect_to_s "lib LibFoo\n  fun foo(x : (T -> U).class)\nend"
  expect_to_s "def foo(x : (T -> U) | V)\nend"
  expect_to_s "def foo(x : Foo((T -> U)))\nend"
  expect_to_s "def foo(x : (T -> U).class)\nend"
  expect_to_s "foo(x : (T -> U) | V)"
  expect_to_s "foo(x : Foo((T -> U)))"
  expect_to_s "foo(x : (T -> U).class)"

  expect_to_s "macro foo(@[Foo] id)\nend"
  expect_to_s "macro foo(**args)\nend"
  expect_to_s "macro foo(@[Foo] **args)\nend"
  expect_to_s "macro foo(x, **args)\nend"
  expect_to_s "macro foo(x, @[Foo] **args)\nend"
  expect_to_s "def foo(x y)\nend"
  expect_to_s "def foo(@[Foo] x y)\nend"
  expect_to_s %(foo("bar baz": 2))
  expect_to_s %(Foo("bar baz": Int32))
  expect_to_s %(Foo())
  expect_to_s %({"foo bar": 1})
  expect_to_s %(def foo("bar baz" qux)\nend)
  expect_to_s "foo()"
  expect_to_s "/a/x"
  expect_to_s "1_f32", "1_f32"
  expect_to_s "1_f64", "1_f64"
  expect_to_s "1.0", "1.0"
  expect_to_s "1e10_f64", "1e10"
  expect_to_s "!a"
  expect_to_s "!(1 < 2)"
  expect_to_s "!a.b && true"
  expect_to_s "(1 + 2)..3"
  expect_to_s "macro foo\n{{ @type }}\nend"
  expect_to_s "macro foo\n\\{{ @type }}\nend"
  expect_to_s "macro foo\n{% @type %}\nend"
  expect_to_s "macro foo\n\\{%@type %}\nend"
  expect_to_s "enum A : B\nend"
  expect_to_s "# doc\ndef foo\nend", emit_doc: true
  expect_to_s "class Foo\n  # doc\n  def foo\n  end\nend", emit_doc: true
  expect_to_s "foo[x, y, a: 1, b: 2]"
  expect_to_s "foo[x, y, a: 1, b: 2] = z"
  expect_to_s %(@[Foo(1, 2, a: 1, b: 2)])
  expect_to_s %(lib Foo\nend)
  expect_to_s %(lib LibC\n  fun getchar(Int, Float)\nend)
  expect_to_s %(fun foo(a : Void, b : Void, ...) : Void\nend)
  expect_to_s %(fun foo\nend)
  expect_to_s %(lib Foo\n  struct Foo\n    a : Void\n    b : Void\n  end\nend)
  expect_to_s %(lib Foo\n  union Foo\n    a : Int\n    b : Int32\n  end\nend)
  expect_to_s %(lib Foo\n  FOO = 0\nend)
  expect_to_s <<-CRYSTAL, <<-CRYSTAL
    lib Foo
      A = Pointer(Void).new(0)
      struct B
        x : Void*
        y : Int[1]
      end
      fun c(Void*) : Char[2]*
    end
    CRYSTAL
    lib Foo
      A = Pointer(Void).new(0)
      struct B
        x : ::Pointer(Void)
        y : ::StaticArray(Int, 1)
      end
      fun c(::Pointer(Void)) : ::Pointer(::StaticArray(Char, 2))
    end
    CRYSTAL
  expect_to_s %(lib LibC\n  fun getch = "get.char"\nend)
  expect_to_s %(lib Foo::Bar\nend)
  expect_to_s %(enum Foo\n  A = 0\n  B\nend)
  expect_to_s %(alias Foo = Void)
  expect_to_s %(alias Foo::Bar = Void)
  expect_to_s %(type(Foo = Void))
  expect_to_s %(return true ? 1 : 2)
  expect_to_s %(1 <= 2 <= 3)
  expect_to_s %((1 <= 2) <= 3)
  expect_to_s %(1 <= (2 <= 3))
  expect_to_s %(case 1; when .foo?; 2; end), %(case 1\nwhen .foo?\n  2\nend)
  expect_to_s %(case 1; in .foo?; 2; end), %(case 1\nin .foo?\n  2\nend)
  expect_to_s %(case 1; when .!; 2; when .< 0; 3; end), %(case 1\nwhen .!\n  2\nwhen .<(0)\n  3\nend)
  expect_to_s %(case 1\nwhen .[](2)\n  3\nwhen .[]=(4)\n  5\nend)
  expect_to_s %({(1 + 2)})
  expect_to_s %({foo: (1 + 2)})
  expect_to_s %q("#{(1 + 2)}")
  expect_to_s %({(1 + 2) => (3 + 4)})
  expect_to_s %([(1 + 2)] of Int32)
  expect_to_s %(foo(1, (2 + 3), bar: (4 + 5)))
  expect_to_s %(if (1 + 2\n3)\n  4\nend)
  expect_to_s "%x(whoami)", "`whoami`"
  expect_to_s %(begin\n  ()\nend)
  expect_to_s %(begin\n  (1)\nend)
  expect_to_s %(begin\n  (@x = x).is_a?(Foo)\nend)
  expect_to_s %(begin\n  (1)\n  2\nend)
  expect_to_s %(if 1\n  begin\n    2\n  end\nelse\n  begin\n    3\n  end\nend)
  expect_to_s %(foo do\n  begin\n    bar\n  end\nend)
  expect_to_s %q("\e\0\""), %q("\e\u0000\"")
  expect_to_s %q("#{1}\0"), %q("#{1}\u0000")
  expect_to_s %q(%r{\/\0}), %q(/\/\0/)
  expect_to_s %q(%r{#{1}\/\0}), %q(/#{1}\/\0/)
  expect_to_s %q(`\n\0`), %q(`\n\u0000`)
  expect_to_s %q(`#{1}\n\0`), %q(`#{1}\n\u0000`)
  expect_to_s Call.new("`", Call.new("String".path, "interpolation", "x".var, global: true)), %q(`#{::String.interpolation(x)}`)
  expect_to_s "macro foo\n{% verbatim do %}1{% end %}\nend"
  expect_to_s Assign.new("x".var, Expressions.new([1.int32, 2.int32] of ASTNode)), "x = (1\n2\n)"
  expect_to_s "foo.*"
  expect_to_s "foo.%"
  expect_to_s "&+1"
  expect_to_s "&-1"
  expect_to_s "1.&*"
  expect_to_s "1.&**"
  expect_to_s "1.~(2)"
  expect_to_s "1.~(2) do\nend"
  expect_to_s "1.+ do\nend"
  expect_to_s "1.[](2) do\nend"
  expect_to_s "1.[]="
  expect_to_s "1[&.foo]"
  expect_to_s "1[&.foo]?"
  expect_to_s "1[&.foo] = 2"
  expect_to_s "1[2, x: 3, &.foo]"
  expect_to_s "1[2, x: 3, &.foo]?"
  expect_to_s "1[2, x: 3, &.foo] = 4"
  expect_to_s "1.+(a: 2)"
  expect_to_s "1.+(&block)"
  expect_to_s "1.//(2, a: 3)"
  expect_to_s "1.//(2, &block)"
  expect_to_s <<-'CR'
    {% verbatim do %}
      1{{ 2 }}
      3{{ 4 }}
    {% end %}
    CR

  expect_to_s <<-'CR', <<-'CR'
    {% for foo in bar %}
      {{ if true
           foo
           bar
         end }}
    {% end %}
    CR
    {% for foo in bar %}
      {{ if true
      foo
      bar
    end }}
    {% end %}
    CR

  expect_to_s "{% a = 1 %}"
  expect_to_s "{{ a = 1 }}"
  expect_to_s "{%\n  1\n  2\n  3\n%}"
  expect_to_s "{%\n  1\n%}"
  expect_to_s "{%\n  2 + 2\n%}"
  expect_to_s "{%\n  a = 1 %}"
  expect_to_s "{% a = 1\n%}"

  expect_to_s <<-'CR', <<-'CR'
    macro finished
      {% verbatim do %}
        {%
          10

          # Foo

          20
        %}
      {% end %}
    end
    CR
    macro finished
      {% verbatim do %}
        {%
          10



          20
        %}
      {% end %}
    end
    CR

  expect_to_s <<-'CR', <<-'CR'
    macro finished
      {% verbatim do %}
        {%
          10

          # Foo
          20
        %}
      {% end %}
    end
    CR
    macro finished
      {% verbatim do %}
        {%
          10


          20
        %}
      {% end %}
    end
    CR

  expect_to_s <<-'CR', <<-'CR'
    macro finished
      {% verbatim do %}
        {%
          10

          # Foo

          20
          30

          # Bar

          40
        %}
        {%
          50
          60
        %}
      {% end %}
    end
    CR
    macro finished
      {% verbatim do %}
        {%
          10



          20
          30



          40
        %}
        {%
          50
          60
        %}
      {% end %}
    end
    CR

  expect_to_s <<-'CR'
    macro finished
      {% verbatim do %}
        {%
          10
          20
        %}
      {% end %}
    end
    CR

  expect_to_s <<-'CR'
    macro finished
      {% verbatim do %}
        {%
          10
        %}
      {% end %}
    end
    CR

  expect_to_s <<-'CR'
    macro finished
      {% verbatim do %}
        {%

          a = 1 %}
      {% end %}
    end
    CR

  expect_to_s <<-'CR'
    macro finished
      {% verbatim do %}
        {%


          a = 1
          b = 2 %}
      {% end %}
    end
    CR

  expect_to_s <<-'CR', <<-'CR'
    macro finished
      {% verbatim do %}
        {% a = 1
           b = 2

        %}
      {% end %}
    end
    CR
    macro finished
      {% verbatim do %}
        {%     a = 1
        b = 2

        %}
      {% end %}
    end
    CR

  expect_to_s %(asm("nop" ::::))
  expect_to_s %(asm("nop" : "a"(1), "b"(2) : "c"(3), "d"(4) : "e", "f" : "volatile", "alignstack", "intel"))
  expect_to_s %(asm("nop" :: "c"(3), "d"(4) ::))
  expect_to_s %(asm("nop" :::: "volatile"))
  expect_to_s %(asm("nop" :: "a"(1) :: "volatile"))
  expect_to_s %(asm("nop" ::: "e" : "volatile"))
  expect_to_s %(asm("bl trap" :::: "unwind"))
  expect_to_s %[(1..)]
  expect_to_s %[..3]
  expect_to_s "offsetof(Foo, @bar)"
  expect_to_s "def foo(**options, &block)\nend"
  expect_to_s "macro foo\n  123\nend"
  expect_to_s "if true\n  (1)\nend"
  expect_to_s "if true\n  (1)\n  2\nend"
  expect_to_s "begin\n  (1)\nrescue\nend"
  expect_to_s "begin\n  (1)\n  2\nrescue\nend"
  expect_to_s %[他.说("你好")]
  expect_to_s %[他.说 = "你好"]
  expect_to_s %[あ.い, う.え.お = 1, 2]
  expect_to_s "-> : Int32 do\nend"
  expect_to_s "->(x : Int32, y : Bool) : Char do\n  'a'\nend"
  expect_to_s "->::foo(Int32, String)"
  expect_to_s "->::Foo::Bar.foo"
  expect_to_s "yield(1)"
  expect_to_s "foo { |(x, y)| x }", <<-CODE
    foo do |(x, y)|
      x
    end
    CODE
  expect_to_s "foo { |(x, (y, z))| x }", <<-CODE
    foo do |(x, (y, z))|
      x
    end
    CODE
  expect_to_s "def foo\n  yield\nend", "def foo(&)\n  yield\nend"
  expect_to_s "def foo(x)\n  yield\nend", "def foo(x, &)\n  yield\nend"
  expect_to_s "def foo(**x)\n  yield\nend", "def foo(**x, &)\n  yield\nend"
  expect_to_s "macro foo(x)\n  yield\nend"
  expect_to_s <<-CRYSTAL
    select
    when foo
      select
      when bar
        1
      else
        2
      end
    else
      select
      when baz
        3
      else
        4
      end
    end
    CRYSTAL
end
