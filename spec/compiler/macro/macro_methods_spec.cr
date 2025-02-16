require "../../spec_helper"
require "../../support/env"

private def declare_class_var(container : ClassVarContainer, name, var_type : Type, annotations = nil)
  var = MetaTypeVar.new(name)
  var.owner = container
  var.type = var_type
  var.annotations = annotations
  var.bind_to var
  var.freeze_type = var_type
  container.class_vars[name] = var
end

private def exit_code_command(code)
  {% if flag?(:win32) %}
    %(cmd.exe /c "exit #{code}")
  {% else %}
    case code
    when 0
      "true"
    when 1
      "false"
    else
      "/bin/sh -c 'exit #{code}'"
    end
  {% end %}
end

private def shell_command(command)
  {% if flag?(:win32) %}
    "cmd.exe /c #{Process.quote(command)}"
  {% else %}
    "/bin/sh -c #{Process.quote(command)}"
  {% end %}
end

private def newline
  {% if flag?(:win32) %}
    "\r\n"
  {% else %}
    "\n"
  {% end %}
end

module Crystal
  describe Macro do
    describe "node methods" do
      describe "location" do
        location = Location.new("foo.cr", 1, 2)

        it "filename" do
          assert_macro "{{x.filename}}", %("foo.cr"), {x: "hello".string.tap { |n| n.location = location }}
        end

        it "line_number" do
          assert_macro "{{x.line_number}}", %(1), {x: "hello".string.tap { |n| n.location = location }}
        end

        it "column number" do
          assert_macro "{{x.column_number}}", %(2), {x: "hello".string.tap { |n| n.location = location }}
        end

        it "end line_number" do
          assert_macro "{{x.end_line_number}}", %(1), {x: "hello".string.tap { |n| n.end_location = location }}
        end

        it "end column number" do
          assert_macro "{{x.end_column_number}}", %(2), {x: "hello".string.tap { |n| n.end_location = location }}
        end
      end

      describe "stringify" do
        it "expands macro with stringify call on string" do
          assert_macro "{{x.stringify}}", "\"\\\"hello\\\"\"", {x: "hello".string}
        end

        it "expands macro with stringify call on symbol" do
          assert_macro "{{x.stringify}}", %(":hello"), {x: "hello".symbol}
        end

        it "expands macro with stringify call on call" do
          assert_macro "{{x.stringify}}", %("hello"), {x: "hello".call}
        end

        it "expands macro with stringify call on number" do
          assert_macro "{{x.stringify}}", %("1"), {x: 1.int32}
        end
      end

      describe "symbolize" do
        it "expands macro with symbolize call on string" do
          assert_macro "{{x.symbolize}}", ":\"\\\"hello\\\"\"", {x: "hello".string}
        end

        it "expands macro with symbolize call on symbol" do
          assert_macro "{{x.symbolize}}", ":\":hello\"", {x: "hello".symbol}
        end

        it "expands macro with symbolize call on id" do
          assert_macro "{{x.id.symbolize}}", ":hello", {x: "hello".string}
        end
      end

      describe "id" do
        it "expands macro with id call on string" do
          assert_macro "{{x.id}}", "hello", {x: "hello".string}
        end

        it "expands macro with id call on symbol" do
          assert_macro "{{x.id}}", "hello", {x: "hello".symbol}
        end

        it "expands macro with id call on char" do
          assert_macro "{{x.id}}", "є", {x: CharLiteral.new('є')}
        end

        it "expands macro with id call on call" do
          assert_macro "{{x.id}}", "hello", {x: "hello".call}
        end

        it "expands macro with id call on number" do
          assert_macro "{{x.id}}", %(1), {x: 1.int32}
        end

        it "expands macro with id call on path" do
          assert_macro "{{x.id}}", %(Foo), {x: Path.new("Foo")}
        end

        it "expands macro with id call on global path" do
          assert_macro "{{x.id}}", %(::Foo), {x: Path.new("Foo", global: true)}
        end
      end

      it "executes == on numbers (true)" do
        assert_macro "{%if 1 == 1%}hello{%else%}bye{%end%}", "hello"
      end

      it "executes == on numbers (false)" do
        assert_macro "{%if 1 == 2%}hello{%else%}bye{%end%}", "bye"
      end

      it "executes != on numbers (true)" do
        assert_macro "{%if 1 != 2%}hello{%else%}bye{%end%}", "hello"
      end

      it "executes != on numbers (false)" do
        assert_macro "{%if 1 != 1%}hello{%else%}bye{%end%}", "bye"
      end

      it "executes == on symbols (true) (#240)" do
        assert_macro "{{:foo == :foo}}", "true"
      end

      it "executes == on symbols (false) (#240)" do
        assert_macro "{{:foo == :bar}}", "false"
      end

      describe "class_name" do
        it "executes class_name" do
          assert_macro "{{:foo.class_name}}", "\"SymbolLiteral\""
        end

        it "executes class_name" do
          assert_macro "{{x.class_name}}", "\"MacroId\"", {x: MacroId.new("hello")}
        end

        it "executes class_name" do
          assert_macro "{{x.class_name}}", "\"StringLiteral\"", {x: "hello".string}
        end

        it "executes class_name" do
          assert_macro "{{x.class_name}}", "\"SymbolLiteral\"", {x: "hello".symbol}
        end

        it "executes class_name" do
          assert_macro "{{x.class_name}}", "\"NumberLiteral\"", {x: 1.int32}
        end

        it "executes class_name" do
          assert_macro "{{x.class_name}}", "\"ArrayLiteral\"", {x: ArrayLiteral.new([Path.new("Foo"), Path.new("Bar")] of ASTNode)}
        end
      end

      describe "#nil?" do
        it "NumberLiteral" do
          assert_macro "{{ 1.nil? }}", "false"
        end

        it "NilLiteral" do
          assert_macro "{{ nil.nil? }}", "true"
        end

        it "Nop" do
          assert_macro "{{ x.nil? }}", "true", {x: Nop.new}
        end
      end

      describe "#is_a?" do
        it "union argument" do
          assert_macro %({{ x.is_a?(NumberLiteral | StringLiteral) }}), "true", {x: 1.int32}
          assert_macro %({{ x.is_a?(NumberLiteral | StringLiteral) }}), "true", {x: "hello".string}
          assert_macro %({{ x.is_a?(NumberLiteral | StringLiteral) }}), "false", {x: "hello".symbol}

          assert_macro %({{ x.is_a?(NumberLiteral | StringLiteral | SymbolLiteral) }}), "true", {x: 1.int32}
          assert_macro %({{ x.is_a?(NumberLiteral | StringLiteral | SymbolLiteral) }}), "true", {x: "hello".string}
          assert_macro %({{ x.is_a?(NumberLiteral | StringLiteral | SymbolLiteral) }}), "true", {x: "hello".symbol}
          assert_macro %({{ x.is_a?(NumberLiteral | StringLiteral | SymbolLiteral) }}), "false", {x: "hello".call}
        end

        it "union argument, mergeable" do
          assert_macro %({{ x.is_a?(NumberLiteral | ASTNode) }}), "true", {x: 1.int32}
          assert_macro %({{ x.is_a?(NumberLiteral | ASTNode) }}), "true", {x: "hello".string}
        end

        it "union argument, duplicate type" do
          assert_macro %({{ x.is_a?(NumberLiteral | NumberLiteral) }}), "true", {x: 1.int32}
          assert_macro %({{ x.is_a?(NumberLiteral | NumberLiteral) }}), "false", {x: "hello".string}
        end

        it "union argument, contains NoReturn" do
          assert_macro %({{ x.is_a?(NumberLiteral | NoReturn) }}), "true", {x: 1.int32}
          assert_macro %({{ x.is_a?(NumberLiteral | NoReturn) }}), "false", {x: "hello".string}
        end

        it "union argument, undefined types" do
          assert_macro %({{ x.is_a?(NumberLiteral | String) }}), "true", {x: 1.int32}
          assert_macro %({{ x.is_a?(NumberLiteral | String) }}), "false", {x: "hello".string}
          assert_macro %({{ x.is_a?(Int32 | String) }}), "false", {x: 1.int32}
        end

        it "union argument, unimplemented types" do
          assert_macro %({{ x.is_a?(ClassDef) }}), "true", {x: ClassDef.new("Foo".path)}
          assert_macro %({{ x.is_a?(ModuleDef) }}), "false", {x: ClassDef.new("Foo".path)}
        end
      end

      describe "#doc" do
        it "returns an empty string if there are no docs on the node (wants_doc = false)" do
          assert_macro "{{ x.doc }}", %(""), {x: Call.new("some_call")}
        end

        it "returns the call's docs if present (wants_doc = true)" do
          assert_macro "{{ x.doc }}", %("Some docs"), {x: Call.new("some_call").tap { |c| c.doc = "Some docs" }}
        end

        it "returns a multiline comment" do
          assert_macro "{{ x.doc }}", %("Some\\nmulti\\nline\\ndocs"), {x: Call.new("some_call").tap { |c| c.doc = "Some\nmulti\nline\ndocs" }}
        end
      end

      describe "#doc_comment" do
        it "returns an empty MacroId if there are no docs on the node (wants_doc = false)" do
          assert_macro "{{ x.doc_comment }}", %(), {x: Call.new("some_call")}
        end

        it "returns the call's docs if present as a MacroId (wants_doc = true)" do
          assert_macro "{{ x.doc_comment }}", %(Some docs), {x: Call.new("some_call").tap { |c| c.doc = "Some docs" }}
        end

        it "ensures each newline has a `#` prefix" do
          assert_macro "{{ x.doc_comment }}", %(Some\n# multi\n# line\n# docs), {x: Call.new("some_call").tap { |c| c.doc = "Some\nmulti\nline\ndocs" }}
        end
      end
    end

    describe "number methods" do
      it "executes > (true)" do
        assert_macro "{%if 2 > 1%}hello{%else%}bye{%end%}", "hello"
      end

      it "executes > (false)" do
        assert_macro "{%if 2 > 3%}hello{%else%}bye{%end%}", "bye"
      end

      it "executes >= (true)" do
        assert_macro "{%if 1 >= 1%}hello{%else%}bye{%end%}", "hello"
      end

      it "executes >= (false)" do
        assert_macro "{%if 2 >= 3%}hello{%else%}bye{%end%}", "bye"
      end

      it "executes < (true)" do
        assert_macro "{%if 1 < 2%}hello{%else%}bye{%end%}", "hello"
      end

      it "executes < (false)" do
        assert_macro "{%if 3 < 2%}hello{%else%}bye{%end%}", "bye"
      end

      it "executes <= (true)" do
        assert_macro "{%if 1 <= 1%}hello{%else%}bye{%end%}", "hello"
      end

      it "executes <= (false)" do
        assert_macro "{%if 3 <= 2%}hello{%else%}bye{%end%}", "bye"
      end

      it "executes <=>" do
        assert_macro "{{1 <=> -1}}", "1"
      end

      it "executes <=> (returns nil)" do
        assert_macro "{{0.0/0.0 <=> -1}}", "nil"
      end

      it "executes +" do
        assert_macro "{{1 + 2}}", "3"
      end

      it "executes + and preserves type" do
        assert_macro "{{1_u64 + 2_u64}}", "3_u64"
      end

      it "executes -" do
        assert_macro "{{1 - 2}}", "-1"
      end

      it "executes *" do
        assert_macro "{{2 * 3}}", "6"
      end

      # MathInterpreter only works with Integer and left / right : Float
      #
      # it "executes /" do
      #   assert_macro "{{5 / 3}}", "1"
      # end

      it "executes //" do
        assert_macro "{{5 // 3}}", "1"
      end

      it "executes %" do
        assert_macro "{{5 % 3}}", "2"
      end

      it "preserves integer size (#10713)" do
        assert_macro "{{ 3000000000u64 % 2 }}", "0_u64"
      end

      it "executes &" do
        assert_macro "{{5 & 3}}", "1"
      end

      it "executes |" do
        assert_macro "{{5 | 3}}", "7"
      end

      it "executes ^" do
        assert_macro "{{5 ^ 3}}", "6"
      end

      it "executes **" do
        assert_macro "{{2 ** 3}}", "8"
      end

      it "executes <<" do
        assert_macro "{{1 << 2}}", "4"
      end

      it "executes >>" do
        assert_macro "{{4 >> 2}}", "1"
      end

      it "executes + with float" do
        assert_macro "{{1.5 + 2.6}}", "4.1"
      end

      it "executes unary +" do
        assert_macro "{{+3}}", "+3"
      end

      it "executes unary -" do
        assert_macro "{{-(3)}}", "-3"
        assert_macro "{{-(3_i128)}}", "-3_i128"
      end

      it "executes unary ~" do
        assert_macro "{{~1}}", "-2"
      end

      it "executes kind" do
        assert_macro "{{-128i8.kind}}", ":i8"
        assert_macro "{{1e-123_f32.kind}}", ":f32"
        assert_macro "{{1.0.kind}}", ":f64"
        assert_macro "{{0xde7ec7ab1e_u64.kind}}", ":u64"
        assert_macro "{{1_u128.kind}}", ":u128"
        assert_macro "{{-20i128.kind}}", ":i128"
      end

      it "#to_number" do
        assert_macro "{{ 4_u8.to_number }}", "4"
        assert_macro "{{ 2147483648.to_number }}", "2147483648"
        assert_macro "{{ 1_f32.to_number }}", "1.0"
        assert_macro "{{ 4_u128.to_number }}", "4"
        assert_macro "{{ -20i128.to_number }}", "-20"
      end

      it "executes math operations using U/Int128" do
        assert_macro "{{18446744073709551615_u128 + 1}}", "18446744073709551616_u128"
        assert_macro "{{18446744073709551_i128 - 1_u128}}", "18446744073709550_i128"
        assert_macro "{{18446744073709551615_u128 * 10}}", "184467440737095516150_u128"
        assert_macro "{{18446744073709551610_u128 // 10}}", "1844674407370955161_u128"
      end
    end

    describe "char methods" do
      it "executes ord" do
        assert_macro %({{'a'.ord}}), %(97)
        assert_macro %({{'龍'.ord}}), %(40845)
      end

      it "executes zero?" do
        assert_macro "", "{{0.zero?}}", [] of ASTNode, "true"
        assert_macro "", "{{1.zero?}}", [] of ASTNode, "false"

        assert_macro "", "{{0.0.zero?}}", [] of ASTNode, "true"
        assert_macro "", "{{0.1.zero?}}", [] of ASTNode, "false"
      end
    end

    describe "string methods" do
      it "executes string == string" do
        assert_macro %({{"foo" == "foo"}}), %(true)
        assert_macro %({{"foo" == "bar"}}), %(false)
      end

      it "executes string != string" do
        assert_macro %({{"foo" != "foo"}}), %(false)
        assert_macro %({{"foo" != "bar"}}), %(true)
      end

      it "executes split without arguments" do
        assert_macro %({{"1 2 3".split}}), %(["1", "2", "3"] of ::String)
      end

      it "executes split with argument" do
        assert_macro %({{"1-2-3".split('-')}}), %(["1", "2", "3"] of ::String)
      end

      it "executes split with char argument" do
        assert_macro %({{"1-2-3".split('-')}}), %(["1", "2", "3"] of ::String)
      end

      it "executes strip" do
        assert_macro %({{"  hello   ".strip}}), %("hello")
      end

      it "executes downcase" do
        assert_macro %({{"HELLO".downcase}}), %("hello")
      end

      it "executes upcase" do
        assert_macro %({{"hello".upcase}}), %("HELLO")
      end

      it "executes capitalize" do
        assert_macro %({{"hello".capitalize}}), %("Hello")
      end

      it "executes chars" do
        assert_macro %({{x.chars}}), %(['1', '2', '3'] of ::Char), {x: StringLiteral.new("123")}
      end

      it "executes lines" do
        assert_macro %({{x.lines}}), %(["1", "2", "3"] of ::String), {x: StringLiteral.new("1\n2\n3")}
      end

      it "executes size" do
        assert_macro %({{"hello".size}}), "5"
      end

      it "executes count" do
        assert_macro %({{"aabbcc".count('a')}}), "2"
      end

      it "executes empty" do
        assert_macro %({{"hello".empty?}}), "false"
      end

      it "executes [] with inclusive range" do
        assert_macro %({{"hello"[1..-2]}}), %("ell")
      end

      it "executes [] with exclusive range" do
        assert_macro %({{"hello"[1...-2]}}), %("el")
      end

      it "executes [] with computed range" do
        assert_macro %({{"hello"[[1].size..-2]}}), %("ell")
      end

      it "executes [] with incomplete range" do
        assert_macro %({{"hello"[1..]}}), %("ello")
        assert_macro %({{"hello"[1..nil]}}), %("ello")
        assert_macro %({{"hello"[...3]}}), %("hel")
        assert_macro %({{"hello"[nil...3]}}), %("hel")
        assert_macro %({{"hello"[..]}}), %("hello")
        assert_macro %({{"hello"[nil..nil]}}), %("hello")
      end

      it "executes string chomp" do
        assert_macro %({{"hello\n".chomp}}), %("hello")
      end

      it "executes string starts_with? char (true)" do
        assert_macro %({{"hello".starts_with?('h')}}), %(true)
      end

      it "executes string starts_with? char (false)" do
        assert_macro %({{"hello".starts_with?('e')}}), %(false)
      end

      it "executes string starts_with? string (true)" do
        assert_macro %({{"hello".starts_with?("hel")}}), %(true)
      end

      it "executes string starts_with? string (false)" do
        assert_macro %({{"hello".starts_with?("hi")}}), %(false)
      end

      it "executes string ends_with? char (true)" do
        assert_macro %({{"hello".ends_with?('o')}}), %(true)
      end

      it "executes string ends_with? char (false)" do
        assert_macro %({{"hello".ends_with?('e')}}), %(false)
      end

      it "executes string ends_with? string (true)" do
        assert_macro %({{"hello".ends_with?("llo")}}), %(true)
      end

      it "executes string ends_with? string (false)" do
        assert_macro %({{"hello".ends_with?("tro")}}), %(false)
      end

      it "executes string + string" do
        assert_macro %({{"hello" + " world"}}), %("hello world")
      end

      it "executes string + char" do
        assert_macro %({{"hello" + 'w'}}), %("hellow")
      end

      it "executes string =~ (false)" do
        assert_macro %({{"hello" =~ /hei/}}), %(false)
      end

      it "executes string =~ (true)" do
        assert_macro %({{"hello" =~ /ell/}}), %(true)
      end

      it "executes string > string" do
        assert_macro %({{"fooa" > "foo"}}), %(true)
        assert_macro %({{"foo" > "fooa"}}), %(false)
      end

      it "executes string > macroid" do
        assert_macro %({{"fooa" > "foo".id}}), %(true)
        assert_macro %({{"foo" > "fooa".id}}), %(false)
      end

      it "executes string < string" do
        assert_macro %({{"fooa" < "foo"}}), %(false)
        assert_macro %({{"foo" < "fooa"}}), %(true)
      end

      it "executes string < macroid" do
        assert_macro %({{"fooa" < "foo".id}}), %(false)
        assert_macro %({{"foo" < "fooa".id}}), %(true)
      end

      it "executes tr" do
        assert_macro %({{"hello".tr("e", "o")}}), %("hollo")
      end

      it "executes gsub" do
        assert_macro %({{"hello".gsub(/e|o/, "a")}}), %("halla")
      end

      it "executes scan" do
        assert_macro %({{"Crystal".scan(/(Cr)(?<name1>y)(st)(?<name2>al)/)}}), %([{0 => "Crystal", 1 => "Cr", "name1" => "y", 3 => "st", "name2" => "al"} of ::Int32 | ::String => ::String | ::Nil] of ::Hash(::Int32 | ::String, ::String | ::Nil))
        assert_macro %({{"Crystal".scan(/(Cr)?(stal)/)}}), %([{0 => "stal", 1 => nil, 2 => "stal"} of ::Int32 | ::String => ::String | ::Nil] of ::Hash(::Int32 | ::String, ::String | ::Nil))
        assert_macro %({{"Ruby".scan(/Crystal/)}}), %([] of ::Hash(::Int32 | ::String, ::String | ::Nil))
      end

      it "executes camelcase" do
        assert_macro %({{"foo_bar".camelcase}}), %("FooBar")
      end

      it "executes camelcase with lower" do
        assert_macro %({{"foo_bar".camelcase(lower: true)}}), %("fooBar")
      end

      it "executes camelcase with invalid lower arg type" do
        assert_macro_error %({{"foo_bar".camelcase(lower: 99)}}), "named argument 'lower' to StringLiteral#camelcase must be a bool, not NumberLiteral"
      end

      it "executes underscore" do
        assert_macro %({{"FooBar".underscore}}), %("foo_bar")
      end

      it "executes titleize" do
        assert_macro %({{"hello world".titleize}}), %("Hello World")
      end

      it "executes to_utf16" do
        assert_macro %({{"hello".to_utf16}}), "(::Slice(::UInt16).literal(104_u16, 101_u16, 108_u16, 108_u16, 111_u16, 0_u16))[0, 5]"
        assert_macro %({{"TEST 😐🐙 ±∀ の".to_utf16}}), "(::Slice(::UInt16).literal(84_u16, 69_u16, 83_u16, 84_u16, 32_u16, 55357_u16, 56848_u16, 55357_u16, 56345_u16, 32_u16, 177_u16, 8704_u16, 32_u16, 12398_u16, 0_u16))[0, 14]"
      end

      it "executes to_i" do
        assert_macro %({{"1234".to_i}}), %(1234)
      end

      it "executes to_i(base)" do
        assert_macro %({{"1234".to_i(16)}}), %(4660)
      end

      it "executes string includes? char (true)" do
        assert_macro %({{"spice".includes?('s')}}), %(true)
        assert_macro %({{"spice".includes?('p')}}), %(true)
        assert_macro %({{"spice".includes?('i')}}), %(true)
        assert_macro %({{"spice".includes?('c')}}), %(true)
        assert_macro %({{"spice".includes?('e')}}), %(true)
      end

      it "executes string includes? char (false)" do
        assert_macro %({{"spice".includes?('S')}}), %(false)
        assert_macro %({{"spice".includes?(' ')}}), %(false)
        assert_macro %({{"spice".includes?('!')}}), %(false)
        assert_macro %({{"spice".includes?('b')}}), %(false)
      end

      it "executes string includes? string (true)" do
        assert_macro %({{"spice".includes?("s")}}), %(true)
        assert_macro %({{"spice".includes?("e")}}), %(true)
        assert_macro %({{"spice".includes?("sp")}}), %(true)
        assert_macro %({{"spice".includes?("ce")}}), %(true)
        assert_macro %({{"spice".includes?("pic")}}), %(true)
      end

      it "executes string includes? string (false)" do
        assert_macro %({{"spice".includes?("Spi")}}), %(false)
        assert_macro %({{"spice".includes?(" spi")}}), %(false)
        assert_macro %({{"spice".includes?("ce ")}}), %(false)
        assert_macro %({{"spice".includes?("b")}}), %(false)
        assert_macro %({{"spice".includes?("spice ")}}), %(false)
      end
    end

    describe "macro id methods" do
      it "forwards methods to string" do
        assert_macro %({{x.ends_with?("llo")}}), %(true), {x: MacroId.new("hello")}
        assert_macro %({{x.ends_with?("tro")}}), %(false), {x: MacroId.new("hello")}
        assert_macro %({{x.starts_with?("hel")}}), %(true), {x: MacroId.new("hello")}
        assert_macro %({{x.chomp}}), %(hello), {x: MacroId.new("hello\n")}
        assert_macro %({{x.upcase}}), %(HELLO), {x: MacroId.new("hello")}
        assert_macro %({{x.titleize}}), %(Hello World), {x: MacroId.new("hello world")}
        assert_macro %({{x.includes?("el")}}), %(true), {x: MacroId.new("hello")}
        assert_macro %({{x.includes?("he")}}), %(true), {x: MacroId.new("hello")}
        assert_macro %({{x.includes?("EL")}}), %(false), {x: MacroId.new("hello")}
        assert_macro %({{x.includes?("cat")}}), %(false), {x: MacroId.new("hello")}
      end

      it "compares with string" do
        assert_macro %({{x == "foo"}}), %(true), {x: MacroId.new("foo")}
        assert_macro %({{"foo" == x}}), %(true), {x: MacroId.new("foo")}

        assert_macro %({{x == "bar"}}), %(false), {x: MacroId.new("foo")}
        assert_macro %({{"bar" == x}}), %(false), {x: MacroId.new("foo")}

        assert_macro %({{x != "foo"}}), %(false), {x: MacroId.new("foo")}
        assert_macro %({{"foo" != x}}), %(false), {x: MacroId.new("foo")}

        assert_macro %({{x != "bar"}}), %(true), {x: MacroId.new("foo")}
        assert_macro %({{"bar" != x}}), %(true), {x: MacroId.new("foo")}
      end

      it "compares with symbol" do
        assert_macro %({{x == :foo}}), %(true), {x: MacroId.new("foo")}
        assert_macro %({{:foo == x}}), %(true), {x: MacroId.new("foo")}

        assert_macro %({{x == :bar}}), %(false), {x: MacroId.new("foo")}
        assert_macro %({{:bar == x}}), %(false), {x: MacroId.new("foo")}

        assert_macro %({{x != :foo}}), %(false), {x: MacroId.new("foo")}
        assert_macro %({{:foo != x}}), %(false), {x: MacroId.new("foo")}

        assert_macro %({{x != :bar}}), %(true), {x: MacroId.new("foo")}
        assert_macro %({{:bar != x}}), %(true), {x: MacroId.new("foo")}
      end
    end

    describe "symbol methods" do
      it "forwards methods to string" do
        assert_macro %({{x.ends_with?("llo")}}), %(true), {x: "hello".symbol}
        assert_macro %({{x.ends_with?("tro")}}), %(false), {x: "hello".symbol}
        assert_macro %({{x.starts_with?("hel")}}), %(true), {x: "hello".symbol}
        assert_macro %({{x.chomp}}), %(:hello), {x: SymbolLiteral.new("hello\n")}
        assert_macro %({{x.upcase}}), %(:HELLO), {x: "hello".symbol}
        assert_macro %({{x.titleize}}), %(:"Hello World"), {x: "hello world".symbol}
        assert_macro %({{x.includes?("el")}}), %(true), {x: "hello".symbol}
        assert_macro %({{x.includes?("he")}}), %(true), {x: "hello".symbol}
        assert_macro %({{x.includes?("EL")}}), %(false), {x: "hello".symbol}
        assert_macro %({{x.includes?("cat")}}), %(false), {x: "hello".symbol}
      end

      it "executes symbol == symbol" do
        assert_macro %({{:foo == :foo}}), %(true)
        assert_macro %({{:foo == :bar}}), %(false)
      end

      it "executes symbol != symbol" do
        assert_macro %({{:foo != :foo}}), %(false)
        assert_macro %({{:foo != :bar}}), %(true)
      end
    end

    describe "and methods" do
      it "executes left" do
        assert_macro %({{x.left}}), %(1), {x: And.new(1.int32, 2.int32)}
      end

      it "executes right" do
        assert_macro %({{x.right}}), %(2), {x: And.new(1.int32, 2.int32)}
      end
    end

    describe "or methods" do
      it "executes left" do
        assert_macro %({{x.left}}), %(1), {x: Or.new(1.int32, 2.int32)}
      end

      it "executes right" do
        assert_macro %({{x.right}}), %(2), {x: Or.new(1.int32, 2.int32)}
      end
    end

    describe ArrayLiteral do
      it "executes index 0" do
        assert_macro %({{[1, 2, 3][0]}}), "1"
      end

      it "executes index 1" do
        assert_macro %({{[1, 2, 3][1]}}), "2"
      end

      it "executes index out of bounds" do
        assert_macro %({{[1, 2, 3][3]}}), "nil"
      end

      it "executes size" do
        assert_macro %({{[1, 2, 3].size}}), "3"
      end

      it "executes empty?" do
        assert_macro %({{[1, 2, 3].empty?}}), "false"
      end

      it "executes identify" do
        assert_macro %({{"A::B".identify}}), "\"A__B\""
        assert_macro %({{"A".identify}}), "\"A\""
      end

      it "executes join" do
        assert_macro %({{[1, 2, 3].join ", "}}), %("1, 2, 3")
      end

      it "executes join with strings" do
        assert_macro %({{["a", "b"].join ", "}}), %("a, b")
      end

      it "executes map" do
        assert_macro %({{[1, 2, 3].map { |e| e == 2 }}}), "[false, true, false]"
      end

      it "executes reduce with no initial value" do
        assert_macro %({{[1, 2, 3].reduce { |acc, val| acc * val }}}), "6"
      end

      it "executes reduce with initial value" do
        assert_macro %({{[1, 2, 3].reduce(4) { |acc, val| acc * val }}}), "24"
        assert_macro %({{[1, 2, 3].reduce([] of NumberLiteral) { |acc, val| acc = [val]+acc }}}), "[3, 2, 1]"
      end

      it "executes map with constants" do
        assert_macro %({{x.map { |e| e.id }}}), "[Foo, Bar]", {x: ArrayLiteral.new([Path.new("Foo"), Path.new("Bar")] of ASTNode)}
      end

      it "executes map with arg" do
        assert_macro %({{x.map { |e| e.id }}}), "[hello]", {x: ArrayLiteral.new(["hello".call] of ASTNode)}
      end

      describe "#map_with_index" do
        context "with both arguments" do
          it "returns the resulting array" do
            assert_macro %({{[1, 2, 3].map_with_index { |e, idx| e == 2 || idx <= 1 }}}), %([true, true, false])
          end
        end

        context "without the index argument" do
          it "returns the resulting array" do
            assert_macro %({{[1, 2, 3].map_with_index { |e| e }}}), %([1, 2, 3])
          end
        end

        context "without the element argument" do
          it "returns the resulting array" do
            assert_macro %({{[1, 2, 3].map_with_index { |_, idx| idx }}}), %([0, 1, 2])
          end
        end

        context "without either argument" do
          it "returns the resulting array" do
            assert_macro %({{[1, 2, 3].map_with_index { 7 }}}), %([7, 7, 7])
          end
        end
      end

      it "#each" do
        assert_macro(
          %({% begin %}{% values = [] of Nil %}{% [1, 2, 3].each { |v| values << v } %}{{values}}{% end %}),
          %([1, 2, 3])
        )
      end

      describe "#each_with_index" do
        context "with both arguments" do
          it "builds the correct array" do
            assert_macro(
              %({% begin %}{% values = [] of Nil %}{% [1, 2, 3].each_with_index { |v, idx| values << (v + idx) } %}{{values}}{% end %}),
              %([1, 3, 5])
            )
          end
        end

        context "without the index argument" do
          it "builds the correct array" do
            assert_macro(
              %({% begin %}{% values = [] of Nil %}{% [1, 2, 3].each_with_index { |v| values << v } %}{{values}}{% end %}),
              %([1, 2, 3])
            )
          end
        end

        context "without the element argument" do
          it "builds the correct array" do
            assert_macro(
              %({% begin %}{% values = [] of Nil %}{% [1, 2, 3].each_with_index { |_, idx| values << idx } %}{{values}}{% end %}),
              %([0, 1, 2])
            )
          end
        end

        context "without either argument" do
          it "builds the correct array" do
            assert_macro(
              %({% begin %}{% values = [] of Nil %}{% [1, 2, 3].each_with_index { values << 7 } %}{{values}}{% end %}),
              %([7, 7, 7])
            )
          end
        end
      end

      it "executes select" do
        assert_macro %({{[1, 2, 3].select { |e| e == 1 }}}), "[1]"
      end

      it "executes reject" do
        assert_macro %({{[1, 2, 3].reject { |e| e == 1 }}}), "[2, 3]"
      end

      it "executes find (finds)" do
        assert_macro %({{[1, 2, 3].find { |e| e == 2 }}}), "2"
      end

      it "executes find (doesn't find)" do
        assert_macro %({{[1, 2, 3].find { |e| e == 4 }}}), "nil"
      end

      it "executes any? (true)" do
        assert_macro %({{[1, 2, 3].any? { |e| e == 1 }}}), "true"
      end

      it "executes any? (false)" do
        assert_macro %({{[1, 2, 3].any? { |e| e == 4 }}}), "false"
      end

      it "executes all? (true)" do
        assert_macro %({{[1, 1, 1].all? { |e| e == 1 }}}), "true"
      end

      it "executes all? (false)" do
        assert_macro %({{[1, 2, 1].all? { |e| e == 1 }}}), "false"
      end

      it "executes first" do
        assert_macro %({{[1, 2, 3].first}}), "1"
      end

      it "executes last" do
        assert_macro %({{[1, 2, 3].last}}), "3"
      end

      it "executes splat" do
        assert_macro %({{[1, 2, 3].splat}}), "1, 2, 3"
      end

      it "executes splat with symbols and strings" do
        assert_macro %({{[:foo, "hello", 3].splat}}), %(:foo, "hello", 3)
      end

      it "executes splat with splat" do
        assert_macro %({{*[1, 2, 3]}}), "1, 2, 3"
      end

      it "executes is_a?" do
        assert_macro %({{[1, 2, 3].is_a?(ArrayLiteral)}}), "true"
        assert_macro %({{[1, 2, 3].is_a?(ASTNode)}}), "true"
        assert_macro %({{[1, 2, 3].is_a?(NumberLiteral)}}), "false"
      end

      it "creates an array literal with a var" do
        assert_macro %({% a = [x] %}{{a[0]}}), "1", {x: 1.int32}
      end

      it "executes sort with numbers" do
        assert_macro %({{[3, 2, 1].sort}}), "[1, 2, 3]"
      end

      it "executes sort with strings" do
        assert_macro %({{["c", "b", "a"].sort}}), %(["a", "b", "c"])
      end

      it "executes sort with ids" do
        assert_macro %({{["c".id, "b".id, "a".id].sort}}), %([a, b, c])
      end

      it "executes sort with ids and strings" do
        assert_macro %({{["c".id, "b", "a".id].sort}}), %([a, "b", c])
      end

      it "executes sort_by" do
        assert_macro %({{["abc", "a", "ab"].sort_by { |x| x.size }}}), %(["a", "ab", "abc"])
      end

      it "calls block exactly once for each element in #sort_by" do
        assert_macro <<-CRYSTAL, %(5)
          {{ (i = 0; ["abc", "a", "ab", "abcde", "abcd"].sort_by { i += 1 }; i) }}
          CRYSTAL
      end

      it "executes uniq" do
        assert_macro %({{[1, 1, 1, 2, 3, 1, 2, 3, 4].uniq}}), %([1, 2, 3, 4])
      end

      it "executes unshift" do
        assert_macro %({% x = [1]; x.unshift(2); %}{{x}}), %([2, 1])
      end

      it "executes push" do
        assert_macro %({% x = [1]; x.push(2); x << 3 %}{{x}}), %([1, 2, 3])
      end

      it "executes includes?" do
        assert_macro %({{ [1, 2, 3].includes?(1) }}), %(true)
        assert_macro %({{ [1, 2, 3].includes?(4) }}), %(false)
      end

      describe "#+" do
        context "with TupleLiteral argument" do
          it "concatenates the literals into an ArrayLiteral" do
            assert_macro %({{ [1, 2] + {3, 4, 5} }}), %([1, 2, 3, 4, 5])
          end
        end

        context "with ArrayLiteral argument" do
          it "concatenates the literals into an ArrayLiteral" do
            assert_macro %({{ [1, 2] + [3, 4, 5] }}), %([1, 2, 3, 4, 5])
          end
        end
      end

      describe "#-" do
        context "with TupleLiteral argument" do
          it "removes the elements in RHS from LHS into an ArrayLiteral" do
            assert_macro %({{ [1, 2, 3, 4] - {1, 3, 5} }}), %([2, 4])
          end
        end

        context "with ArrayLiteral argument" do
          it "removes the elements in RHS from LHS into an ArrayLiteral" do
            assert_macro %({{ [1, 2, 3, 4] - [1, 3, 5] }}), %([2, 4])
          end
        end
      end

      it "executes [] with range" do
        assert_macro %({{ [1, 2, 3, 4][1...-1] }}), %([2, 3])
      end

      it "executes [] with computed range" do
        assert_macro %({{ [1, 2, 3, 4][[1].size...-1] }}), %([2, 3])
      end

      it "executes [] with incomplete range" do
        assert_macro %({{ [1, 2, 3, 4][1..] }}), %([2, 3, 4])
        assert_macro %({{ [1, 2, 3, 4][1..nil] }}), %([2, 3, 4])
        assert_macro %({{ [1, 2, 3, 4][...2] }}), %([1, 2])
        assert_macro %({{ [1, 2, 3, 4][nil...2] }}), %([1, 2])
        assert_macro %({{ [1, 2, 3, 4][..] }}), %([1, 2, 3, 4])
        assert_macro %({{ [1, 2, 3, 4][nil..nil] }}), %([1, 2, 3, 4])
      end

      it "executes [] with two numbers" do
        assert_macro %({{ [1, 2, 3, 4, 5][1, 3] }}), %([2, 3, 4])
      end

      it "executes []=" do
        assert_macro %({% a = [0]; a[0] = 2 %}{{a[0]}}), "2"
      end

      it "executes of" do
        assert_macro %({{ x.of }}), %(Int64), {x: ArrayLiteral.new([] of ASTNode, of: Path.new("Int64"))}
      end

      it "executes of (nop)" do
        assert_macro %({{ [1, 2, 3].of }}), %()
      end

      it "executes type" do
        assert_macro %({{ x.type }}), %(Deque), {x: ArrayLiteral.new([] of ASTNode, name: Path.new("Deque"))}
      end

      it "executes type (nop)" do
        assert_macro %({{ [1, 2, 3].type }}), %()
      end
    end

    describe HashLiteral do
      it "executes size" do
        assert_macro %({{{:a => 1, :b => 3}.size}}), "2"
      end

      it "executes empty?" do
        assert_macro %({{{:a => 1}.empty?}}), "false"
      end

      it "executes []" do
        assert_macro %({{{:a => 1}[:a]}}), "1"
      end

      it "executes [] not found" do
        assert_macro %({{{:a => 1}[:b]}}), "nil"
      end

      it "executes keys" do
        assert_macro %({{{:a => 1, :b => 2}.keys}}), "[:a, :b]"
      end

      it "executes values" do
        assert_macro %({{{:a => 1, :b => 2}.values}}), "[1, 2]"
      end

      it "executes map" do
        assert_macro %({{{:a => 1, :b => 2}.map {|k, v| k == :a && v == 1}}}), "[true, false]"
      end

      it "executes is_a?" do
        assert_macro %({{{:a => 1}.is_a?(HashLiteral)}}), "true"
        assert_macro %({{{:a => 1}.is_a?(ASTNode)}}), "true"
        assert_macro %({{{:a => 1}.is_a?(RangeLiteral)}}), "false"
      end

      it "executes []=" do
        assert_macro %({% a = {} of Nil => Nil; a[1] = 2 %}{{a[1]}}), "2"
      end

      it "creates a hash literal with a var" do
        assert_macro %({% a = {:a => x} %}{{a[:a]}}), "1", {x: 1.int32}
      end

      it "executes to_a" do
        assert_macro %({{{:a => 1, :b => 3}.to_a}}), "[{:a, 1}, {:b, 3}]"
      end

      it "executes of_key" do
        of = HashLiteral::Entry.new(Path.new("String"), Path.new("UInt8"))
        assert_macro %({{ x.of_key }}), %(String), {x: HashLiteral.new([] of HashLiteral::Entry, of: of)}
      end

      it "executes of_key (nop)" do
        assert_macro %({{ {'z' => 6, 'a' => 9}.of_key }}), %()
      end

      it "executes of_value" do
        of = HashLiteral::Entry.new(Path.new("String"), Path.new("UInt8"))
        assert_macro %({{ x.of_value }}), %(UInt8), {x: HashLiteral.new([] of HashLiteral::Entry, of: of)}
      end

      it "executes of_value (nop)" do
        assert_macro %({{ {'z' => 6, 'a' => 9}.of_value }}), %()
      end

      it "executes has_key?" do
        assert_macro %({{ {'z' => 6, 'a' => 9}.has_key?('z') }}), %(true)
        assert_macro %({{ {'z' => 6, 'a' => 9}.has_key?('x') }}), %(false)
        assert_macro %({{ {'z' => nil, 'a' => 9}.has_key?('z') }}), %(true)
      end

      it "executes type" do
        assert_macro %({{ x.type }}), %(Headers), {x: HashLiteral.new([] of HashLiteral::Entry, name: Path.new("Headers"))}
      end

      it "executes type (nop)" do
        assert_macro %({{ {'z' => 6, 'a' => 9}.type }}), %()
      end

      it "executes double splat" do
        assert_macro %({{**{1 => 2, 3 => 4}}}), "1 => 2, 3 => 4"
      end

      it "executes double splat" do
        assert_macro %({{{1 => 2, 3 => 4}.double_splat}}), "1 => 2, 3 => 4"
      end

      it "executes double splat with arg" do
        assert_macro %({{{1 => 2, 3 => 4}.double_splat(", ")}}), "1 => 2, 3 => 4, "
      end

      describe "#each" do
        context "with both arguments" do
          it "builds the correct array" do
            assert_macro(
              %({% begin %}{% values = [] of Nil %}{% {"k1" => "v1", "k2" => "v2"}.each { |k, v| values << {k, v} } %}{{values}}{% end %}),
              %([{"k1", "v1"}, {"k2", "v2"}])
            )
          end
        end

        context "without the value argument" do
          it "builds the correct array" do
            assert_macro(
              %({% begin %}{% values = [] of Nil %}{% {"k1" => "v1", "k2" => "v2"}.each { |k| values << k } %}{{values}}{% end %}),
              %(["k1", "k2"])
            )
          end
        end

        context "without the key argument" do
          it "builds the correct array" do
            assert_macro(
              %({% begin %}{% values = [] of Nil %}{% {"k1" => "v1", "k2" => "v2"}.each { |_, v| values << v } %}{{values}}{% end %}),
              %(["v1", "v2"])
            )
          end
        end

        context "without either argument" do
          it "builds the correct array" do
            assert_macro(
              %({% begin %}{% values = [] of Nil %}{% {"k1" => "v1", "k2" => "v2"}.each { values << {"k3", "v3"} } %}{{values}}{% end %}),
              %([{"k3", "v3"}, {"k3", "v3"}])
            )
          end
        end
      end
    end

    describe NamedTupleLiteral do
      it "executes size" do
        assert_macro %({{{a: 1, b: 3}.size}}), "2"
      end

      it "executes empty?" do
        assert_macro %({{{a: 1}.empty?}}), "false"
      end

      it "executes []" do
        assert_macro %({{{a: 1}[:a]}}), "1"
        assert_macro %({{{a: 1}["a"]}}), "1"
      end

      it "executes [] not found" do
        assert_macro %({{{a: 1}[:b]}}), "nil"
        assert_macro %({{{a: 1}["b"]}}), "nil"
      end

      it "executes [] with invalid key type" do
        assert_macro_error %({{{a: 1}[true]}}), "argument to [] must be a symbol or string, not BoolLiteral"
      end

      it "executes keys" do
        assert_macro %({{{a: 1, b: 2}.keys}}), "[a, b]"
      end

      it "executes values" do
        assert_macro %({{{a: 1, b: 2}.values}}), "[1, 2]"
      end

      it "executes map" do
        assert_macro %({{{a: 1, b: 2}.map {|k, v| k.stringify == "a" && v == 1}}}), "[true, false]"
      end

      it "executes is_a?" do
        assert_macro %({{{a: 1}.is_a?(NamedTupleLiteral)}}), "true"
        assert_macro %({{{a: 1}.is_a?(ASTNode)}}), "true"
        assert_macro %({{{a: 1}.is_a?(RangeLiteral)}}), "false"
      end

      it "executes []=" do
        assert_macro %({% a = {a: 1}; a[:a] = 2 %}{{a[:a]}}), "2"
        assert_macro %({% a = {a: 1}; a["a"] = 2 %}{{a["a"]}}), "2"
      end

      it "executes has_key?" do
        assert_macro %({{{a: 1}.has_key?("a")}}), "true"
        assert_macro %({{{a: 1}.has_key?(:a)}}), "true"
        assert_macro %({{{a: nil}.has_key?("a")}}), "true"
        assert_macro %({{{a: nil}.has_key?("b")}}), "false"
        assert_macro_error %({{{a: 1}.has_key?(true)}}), "expected 'NamedTupleLiteral#has_key?' first argument to be a SymbolLiteral, StringLiteral or MacroId, not BoolLiteral"
      end

      it "creates a named tuple literal with a var" do
        assert_macro %({% a = {a: x} %}{{a[:a]}}), "1", {x: 1.int32}
      end

      it "executes to_a" do
        assert_macro %({{{a: 1, b: 3}.to_a}}), "[{a, 1}, {b, 3}]"
      end

      it "executes double splat" do
        assert_macro %({{**{a: 1, "foo bar": 2, "+": 3}}}), %(a: 1, "foo bar": 2, "+": 3)
      end

      it "executes double splat" do
        assert_macro %({{{a: 1, "foo bar": 2, "+": 3}.double_splat}}), %(a: 1, "foo bar": 2, "+": 3)
      end

      it "executes double splat with arg" do
        assert_macro %({{{a: 1, "foo bar": 2, "+": 3}.double_splat(", ")}}), %(a: 1, "foo bar": 2, "+": 3, )
      end

      describe "#each" do
        context "with both arguments" do
          it "builds the correct array" do
            assert_macro(
              %({% begin %}{% values = [] of Nil %}{% {k1: "v1", k2: "v2"}.each { |k, v| values << {k, v} } %}{{values}}{% end %}),
              %([{k1, "v1"}, {k2, "v2"}])
            )
          end
        end

        context "without the value argument" do
          it "builds the correct array" do
            assert_macro(
              %({% begin %}{% values = [] of Nil %}{% {k1: "v1", k2: "v2"}.each { |k| values << k } %}{{values}}{% end %}),
              %([k1, k2])
            )
          end
        end

        context "without the key argument" do
          it "builds the correct array" do
            assert_macro(
              %({% begin %}{% values = [] of Nil %}{% {k1: "v1", k2: "v2"}.each { |_, v| values << v } %}{{values}}{% end %}),
              %(["v1", "v2"])
            )
          end
        end

        context "without either argument" do
          it "builds the correct array" do
            assert_macro(
              %({% begin %}{% values = [] of Nil %}{% {k1: "v1", k2: "v2"}.each { values << {"k3", "v3"} } %}{{values}}{% end %}),
              %([{"k3", "v3"}, {"k3", "v3"}])
            )
          end
        end
      end
    end

    describe TupleLiteral do
      it "executes [] with 0" do
        assert_macro %({{ {1, 2, 3}[0] }}), "1"
      end

      it "executes [] with 1" do
        assert_macro %({{ {1, 2, 3}[1] }}), "2"
      end

      it "executes [] out of bounds" do
        assert_macro %({{ {1, 2, 3}[3] }}), "nil"
      end

      it "executes [] with range" do
        assert_macro %({{ {1, 2, 3, 4}[1...-1] }}), %({2, 3})
      end

      it "executes [] with computed range" do
        assert_macro %({{ {1, 2, 3, 4}[[1].size...-1] }}), %({2, 3})
      end

      it "executes [] with incomplete range" do
        assert_macro %({{ {1, 2, 3, 4}[1..] }}), %({2, 3, 4})
        assert_macro %({{ {1, 2, 3, 4}[1..nil] }}), %({2, 3, 4})
        assert_macro %({{ {1, 2, 3, 4}[...2] }}), %({1, 2})
        assert_macro %({{ {1, 2, 3, 4}[nil...2] }}), %({1, 2})
        assert_macro %({{ {1, 2, 3, 4}[..] }}), %({1, 2, 3, 4})
        assert_macro %({{ {1, 2, 3, 4}[nil..nil] }}), %({1, 2, 3, 4})
      end

      it "executes size" do
        assert_macro %({{ {1, 2, 3}.size }}), "3"
      end

      it "executes empty?" do
        assert_macro %({{ {1, 2, 3}.empty? }}), "false"
      end

      it "executes join" do
        assert_macro %({{ {1, 2, 3}.join ", " }}), %("1, 2, 3")
      end

      it "executes join with strings" do
        assert_macro %({{ {"a", "b"}.join ", " }}), %("a, b")
      end

      it "executes map" do
        assert_macro %({{ {1, 2, 3}.map { |e| e == 2 } }}), "{false, true, false}"
      end

      it "executes map with constants" do
        assert_macro %({{x.map { |e| e.id }}}), "{Foo, Bar}", {x: TupleLiteral.new([Path.new("Foo"), Path.new("Bar")] of ASTNode)}
      end

      it "executes map with arg" do
        assert_macro %({{x.map { |e| e.id }}}), "{hello}", {x: TupleLiteral.new(["hello".call] of ASTNode)}
      end

      describe "#map_with_index" do
        context "with both arguments" do
          it "returns the resulting tuple" do
            assert_macro %({{{1, 2, 3}.map_with_index { |e, idx| e == 2 || idx <= 1 }}}), %({true, true, false})
          end
        end

        context "without the index argument" do
          it "returns the resulting tuple" do
            assert_macro %({{{1, 2, 3}.map_with_index { |e| e }}}), %({1, 2, 3})
          end
        end

        context "without the element argument" do
          it "returns the resulting tuple" do
            assert_macro %({{{1, 2, 3}.map_with_index { |_, idx| idx }}}), %({0, 1, 2})
          end
        end

        context "without either argument" do
          it "returns the resulting tuple" do
            assert_macro %({{{1, 2, 3}.map_with_index { 7 }}}), %({7, 7, 7})
          end
        end
      end

      it "#each" do
        assert_macro(
          %({% begin %}{% values = [] of Nil %}{% {1, 2, 3}.each { |v| values << v } %}{{values}}{% end %}),
          %([1, 2, 3])
        )
      end

      describe "#each_with_index" do
        context "with both arguments" do
          it "builds the correct array" do
            assert_macro(
              %({% begin %}{% values = [] of Nil %}{% {1, 2, 3}.each_with_index { |v, idx| values << (v + idx) } %}{{values}}{% end %}),
              %([1, 3, 5])
            )
          end
        end

        context "without the index argument" do
          it "builds the correct array" do
            assert_macro(
              %({% begin %}{% values = [] of Nil %}{% {1, 2, 3}.each_with_index { |v| values << v } %}{{values}}{% end %}),
              %([1, 2, 3])
            )
          end
        end

        context "without the element argument" do
          it "builds the correct array" do
            assert_macro(
              %({% begin %}{% values = [] of Nil %}{% {1, 2, 3}.each_with_index { |_, idx| values << idx } %}{{values}}{% end %}),
              %([0, 1, 2])
            )
          end
        end

        context "without either argument" do
          it "builds the correct array" do
            assert_macro(
              %({% begin %}{% values = [] of Nil %}{% {1, 2, 3}.each_with_index { values << 7 } %}{{values}}{% end %}),
              %([7, 7, 7])
            )
          end
        end
      end

      it "executes select" do
        assert_macro %({{ {1, 2, 3}.select { |e| e == 1 } }}), "{1}"
      end

      it "executes reject" do
        assert_macro %({{ {1, 2, 3}.reject { |e| e == 1 } }}), "{2, 3}"
      end

      it "executes find (finds)" do
        assert_macro %({{ {1, 2, 3}.find { |e| e == 2 } }}), "2"
      end

      it "executes find (doesn't find)" do
        assert_macro %({{ {1, 2, 3}.find { |e| e == 4 } }}), "nil"
      end

      it "executes any? (true)" do
        assert_macro %({{ {1, 2, 3}.any? { |e| e == 1 } }}), "true"
      end

      it "executes any? (false)" do
        assert_macro %({{ {1, 2, 3}.any? { |e| e == 4 } }}), "false"
      end

      it "executes all? (true)" do
        assert_macro %({{ {1, 1, 1}.all? { |e| e == 1 } }}), "true"
      end

      it "executes all? (false)" do
        assert_macro %({{ {1, 2, 1}.all? { |e| e == 1 } }}), "false"
      end

      it "executes first" do
        assert_macro %({{ {1, 2, 3}.first }}), "1"
      end

      it "executes last" do
        assert_macro %({{ {1, 2, 3}.last }}), "3"
      end

      it "executes splat" do
        assert_macro %({{ {1, 2, 3}.splat }}), "1, 2, 3"
      end

      it "executes splat with arg" do
        assert_macro %({{ {1, 2, 3}.splat(", ") }}), "1, 2, 3, "
      end

      it "executes splat with symbols and strings" do
        assert_macro %({{ {:foo, "hello", 3}.splat }}), %(:foo, "hello", 3)
      end

      it "executes splat with splat" do
        assert_macro %({{ *{1, 2, 3} }}), "1, 2, 3"
      end

      it "executes is_a?" do
        assert_macro %({{ {1, 2, 3}.is_a?(TupleLiteral) }}), "true"
        assert_macro %({{ {1, 2, 3}.is_a?(ASTNode) }}), "true"
        assert_macro %({{ {1, 2, 3}.is_a?(ArrayLiteral) }}), "false"
      end

      it "creates a tuple literal with a var" do
        assert_macro %({% a = {x} %}{{a[0]}}), "1", {x: 1.int32}
      end

      it "executes sort with numbers" do
        assert_macro %({{ {3, 2, 1}.sort }}), "{1, 2, 3}"
      end

      it "executes sort with strings" do
        assert_macro %({{ {"c", "b", "a"}.sort }}), %({"a", "b", "c"})
      end

      it "executes sort with ids" do
        assert_macro %({{ {"c".id, "b".id, "a".id}.sort }}), %({a, b, c})
      end

      it "executes sort with ids and strings" do
        assert_macro %({{ {"c".id, "b", "a".id}.sort }}), %({a, "b", c})
      end

      it "executes uniq" do
        assert_macro %({{ {1, 1, 1, 2, 3, 1, 2, 3, 4}.uniq }}), %({1, 2, 3, 4})
      end

      it "executes unshift" do
        assert_macro %({% x = {1}; x.unshift(2); %}{{x}}), %({2, 1})
      end

      it "executes push" do
        assert_macro %({% x = {1}; x.push(2); x << 3 %}{{x}}), %({1, 2, 3})
      end

      it "executes includes?" do
        assert_macro %({{ {1, 2, 3}.includes?(1) }}), %(true)
        assert_macro %({{ {1, 2, 3}.includes?(4) }}), %(false)
      end

      describe "#+" do
        context "with TupleLiteral argument" do
          it "concatenates the literals into a TupleLiteral" do
            assert_macro %({{ {1, 2} + {3, 4, 5} }}), %({1, 2, 3, 4, 5})
          end
        end

        context "with ArrayLiteral argument" do
          it "concatenates the literals into a TupleLiteral" do
            assert_macro %({{ {1, 2} + [3, 4, 5] }}), %({1, 2, 3, 4, 5})
          end
        end
      end

      describe "#-" do
        context "with TupleLiteral argument" do
          it "removes the elements in RHS from LHS into a TupleLiteral" do
            assert_macro %({{ {1, 2, 3, 4} - {1, 3, 5} }}), %({2, 4})
          end
        end

        context "with ArrayLiteral argument" do
          it "removes the elements in RHS from LHS into a TupleLiteral" do
            assert_macro %({{ {1, 2, 3, 4} - [1, 3, 5] }}), %({2, 4})
          end
        end
      end
    end

    describe "regex methods" do
      it "executes source" do
        assert_macro %({{ /rëgéx/i.source }}), %("rëgéx")
      end

      it "executes options" do
        assert_macro %({{ //.options }}), %([] of ::Symbol)
        assert_macro %({{ /a/i.options }}), %([:i] of ::Symbol)
        assert_macro %({{ /re/mix.options }}), %([:i, :m, :x] of ::Symbol)
      end
    end

    describe "metavar methods" do
      it "executes nothing" do
        assert_macro %({{x}}), %(foo), {x: MetaMacroVar.new("foo", Program.new.int32)}
      end

      it "executes name" do
        assert_macro %({{x.name}}), %(foo), {x: MetaMacroVar.new("foo", Program.new.int32)}
      end

      it "executes id" do
        assert_macro %({{x.id}}), %(foo), {x: MetaMacroVar.new("foo", Program.new.int32)}
      end

      it "executes is_a?" do
        assert_macro %({{x.is_a?(MetaVar)}}), %(true), {x: MetaMacroVar.new("foo", Program.new.int32)}
      end
    end

    describe "block methods" do
      it "executes body" do
        assert_macro %({{x.body}}), "1", {x: Block.new(body: 1.int32)}
      end

      it "executes args" do
        assert_macro %({{x.args}}), "[x, y]", {x: Block.new(["x".var, "y".var])}
      end

      it "executes splat_index" do
        assert_macro %({{x.splat_index}}), "1", {x: Block.new(["x".var, "y".var], splat_index: 1)}
        assert_macro %({{x.splat_index}}), "nil", {x: Block.new(["x".var, "y".var])}
      end
    end

    describe "expressions methods" do
      it "executes expressions" do
        assert_macro %({{x.body.expressions[0]}}), "some_call", {x: Block.new(body: Expressions.new(["some_call".call, "some_other_call".call] of ASTNode))}
      end
    end

    it "executes assign" do
      assert_macro %({{a = 1}}{{a}}), "11"
    end

    it "executes assign without output" do
      assert_macro %({% a = 1 %}{{a}}), "1"
    end

    describe TypeNode do
      describe "#includers" do
        it "returns an array of types `self` is directly included in" do
          assert_type(%(
            module Foo
            end

            module Baz
              module Tar
                include Baz
              end
            end

            abstract class Parent
            end

            module Enumt(T)
              include Baz
            end

            class Bar < Parent
              include Foo
              include Baz
            end

            struct Str
              include Enumt(String)
              include Baz
            end

            struct Gen(T)
              include Baz
            end

            abstract struct AStr
              include Baz
            end

            abstract class ACla
              include Baz
            end

            class SubT(T)
              include Baz
            end

            class ChildT(T) < SubT(T)
              include Enumt(T)
            end

            class Witness < ChildT(String)
            end

            {
              {% if Baz.includers.map(&.stringify).sort == %w(ACla AStr Bar Baz::Tar Enumt(T) Gen(T) Str SubT(T)) %} 1 {% else %} 'a' {% end %},
              {% if Enumt.includers.map(&.stringify).sort == %w(ChildT(String) ChildT(T) Str) %} 1 {% else %} 'a' {% end %},
              {% if Enumt(String).includers.map(&.stringify).sort == %w(ChildT(String) Str) %} 1 {% else %} 'a' {% end %},
            }
            )) { tuple_of([int32, int32, int32]) }
        end
      end

      describe "#name" do
        describe "simple type" do
          it "returns the name of the type" do
            assert_macro("{{x.name}}", "String") do |program|
              {x: TypeNode.new(program.string)}
            end
          end
        end

        describe "namespaced type" do
          it "should return the FQN of the type" do
            assert_macro("{{type.name}}", "SomeModule::SomeType") do |program|
              mod = NonGenericModuleType.new(program, program, "SomeModule")

              klass = NonGenericClassType.new(program, mod, "SomeType", program.reference)

              {type: TypeNode.new(klass)}
            end
          end
        end

        describe "generic type" do
          it "includes the generic_args of the type by default" do
            assert_macro("{{klass.name}}", "SomeType(A, B)") do |program|
              {klass: TypeNode.new(GenericClassType.new(program, program, "SomeType", program.object, ["A", "B"]))}
            end
          end

          it "includes the generic_args of the instantiated type by default" do
            assert_macro("{{Array(Int32).name}}", "Array(Int32)")
          end
        end

        describe "generic instance" do
          it "prints generic type arguments" do
            assert_macro("{{klass.name}}", "Foo(Int32, 3)") do |program|
              generic_type = GenericClassType.new(program, program, "Foo", program.reference, ["T", "U"])
              {klass: TypeNode.new(generic_type.instantiate([program.int32, 3.int32] of TypeVar))}
            end
          end

          it "prints empty splat type var" do
            assert_macro("{{klass.name}}", "Foo()") do |program|
              generic_type = GenericClassType.new(program, program, "Foo", program.reference, ["T"])
              generic_type.splat_index = 0
              {klass: TypeNode.new(generic_type.instantiate([] of TypeVar))}
            end
          end

          it "prints multiple arguments for splat type var" do
            assert_macro("{{klass.name}}", "Foo(Int32, String)") do |program|
              generic_type = GenericClassType.new(program, program, "Foo", program.reference, ["T"])
              generic_type.splat_index = 0
              {klass: TypeNode.new(generic_type.instantiate([program.int32, program.string] of TypeVar))}
            end
          end

          it "does not print extra commas for empty splat type var (1)" do
            assert_macro("{{klass.name}}", "Foo(Int32)") do |program|
              generic_type = GenericClassType.new(program, program, "Foo", program.reference, ["T", "U"])
              generic_type.splat_index = 1
              {klass: TypeNode.new(generic_type.instantiate([program.int32] of TypeVar))}
            end
          end

          it "does not print extra commas for empty splat type var (2)" do
            assert_macro("{{klass.name}}", "Foo(Int32)") do |program|
              generic_type = GenericClassType.new(program, program, "Foo", program.reference, ["T", "U"])
              generic_type.splat_index = 0
              {klass: TypeNode.new(generic_type.instantiate([program.int32] of TypeVar))}
            end
          end

          it "does not print extra commas for empty splat type var (3)" do
            assert_macro("{{klass.name}}", "Foo(Int32, String)") do |program|
              generic_type = GenericClassType.new(program, program, "Foo", program.reference, ["T", "U", "V"])
              generic_type.splat_index = 1
              {klass: TypeNode.new(generic_type.instantiate([program.int32, program.string] of TypeVar))}
            end
          end
        end

        describe :generic_args do
          describe true do
            it "includes the generic_args of the type" do
              assert_macro("{{klass.name(generic_args: true)}}", "SomeType(A, B)") do |program|
                {klass: TypeNode.new(GenericClassType.new(program, program, "SomeType", program.object, ["A", "B"]))}
              end
            end

            it "includes the generic_args of the instantiated type" do
              assert_macro("{{Array(Int32).name(generic_args: true)}}", "Array(Int32)")
            end
          end

          describe false do
            it "does not include the generic_args of the type" do
              assert_macro("{{klass.name(generic_args: false)}}", "SomeType") do |program|
                {klass: TypeNode.new(GenericClassType.new(program, program, "SomeType", program.object, ["A", "B"]))}
              end
            end

            it "does not include the generic_args of the instantiated type" do
              assert_macro("{{Array(Int32).name(generic_args: false)}}", "Array")
            end
          end

          describe "with an invalid type argument" do
            it "should raise the proper exception" do
              assert_macro_error("{{x.name(generic_args: 99)}}", "named argument 'generic_args' to TypeNode#name must be a BoolLiteral, not NumberLiteral") do |program|
                {x: TypeNode.new(program.string)}
              end
            end
          end
        end
      end

      describe "#id" do
        it "does not include trailing + for virtual type" do
          assert_macro("{{klass.id}}", "Foo") do |program|
            foo = NonGenericClassType.new(program, program, "Foo", program.reference)
            bar = NonGenericClassType.new(program, program, "Bar", foo)
            {klass: TypeNode.new(foo.virtual_type)}
          end
        end
      end

      describe "#warning" do
        it "emits a warning at a specific node" do
          assert_warning <<-CRYSTAL, "Oh noes"
            macro test(node)
              {% node.warning "Oh noes" %}
            end

            test 10
          CRYSTAL
        end
      end

      describe "#instance_vars" do
        it "executes instance_vars" do
          assert_macro("{{x.instance_vars.map &.stringify}}", %(["bytesize", "length", "c"])) do |program|
            {x: TypeNode.new(program.string)}
          end
        end

        it "errors when called from top-level scope" do
          assert_error <<-CRYSTAL, "`TypeNode#instance_vars` cannot be called in the top-level scope: instance vars are not yet initialized"
            class Foo
            end
            {{ Foo.instance_vars }}
          CRYSTAL
        end

        it "does not error when called from def scope" do
          assert_type <<-CRYSTAL { |program| program.string }
            module Moo
            end
            def moo
              {{ Moo.instance_vars.stringify }}
            end
            moo
          CRYSTAL
        end
      end

      it "executes class vars" do
        assert_macro("{{x.class_vars.map &.name}}", %([class_var])) do |program|
          klass = NonGenericClassType.new(program, program, "SomeType", program.reference)
          declare_class_var(klass, "@@class_var", program.string)
          {x: TypeNode.new(klass)}
        end
      end

      it "executes class vars (with inheritance)" do
        assert_macro("{{x.class_vars.map &.name}}", %([child_class_var, base_class_var, mod_class_var])) do |program|
          base_class = NonGenericClassType.new(program, program, "BaseType", program.reference)
          declare_class_var(base_class, "@@base_class_var", program.string)
          mod = NonGenericModuleType.new(program, program, "SomeModule")
          declare_class_var(mod, "@@mod_class_var", program.string)
          base_class.include mod
          child_class = NonGenericClassType.new(program, program, "ChildType", base_class)
          declare_class_var(child_class, "@@child_class_var", program.string)
          {x: TypeNode.new(child_class)}
        end
      end

      it "executes instance_vars on metaclass" do
        assert_macro("{{x.class.instance_vars.map &.stringify}}", %([])) do |program|
          klass = NonGenericClassType.new(program, program, "SomeType", program.reference)
          klass.declare_instance_var("@var", program.string)
          {x: TypeNode.new(klass)}
        end
      end

      it "executes class_vars on metaclass" do
        assert_macro("{{x.class.class_vars.map &.stringify}}", %([])) do |program|
          klass = NonGenericClassType.new(program, program, "SomeType", program.reference)
          declare_class_var(klass, "@@class_var", program.string)
          {x: TypeNode.new(klass)}
        end
      end

      it "executes instance_vars on symbol type" do
        assert_macro("{{x.instance_vars.map &.stringify}}", %([])) do |program|
          {x: TypeNode.new(program.symbol)}
        end
      end

      it "executes class_vars on symbol type" do
        assert_macro("{{x.class_vars.map &.stringify}}", %([])) do |program|
          {x: TypeNode.new(program.symbol)}
        end
      end

      it "executes methods" do
        assert_macro("{{x.methods.map &.name}}", %([foo])) do |program|
          klass = NonGenericClassType.new(program, program, "SomeType", program.reference)
          a_def = Def.new "foo"
          klass.add_def a_def
          {x: TypeNode.new(klass)}
        end
      end

      it "executes class methods" do
        assert_macro("{{x.class.methods.map &.name}}", %([allocate])) do |program|
          klass = NonGenericClassType.new(program, program, "SomeType", program.reference)
          {x: TypeNode.new(klass)}
        end
      end

      it "executes ancestors" do
        assert_macro("{{x.ancestors}}", %([SomeModule, Reference, Object])) do |program|
          mod = NonGenericModuleType.new(program, program, "SomeModule")
          klass = NonGenericClassType.new(program, program, "SomeType", program.reference)
          klass.include mod

          {x: TypeNode.new(klass)}
        end
      end

      it "executes ancestors (with generic)" do
        assert_macro("{{x.ancestors}}", %([SomeGenericModule(String), SomeGenericType(String), Reference, Object])) do |program|
          generic_type = GenericClassType.new(program, program, "SomeGenericType", program.reference, ["T"])
          generic_mod = GenericModuleType.new(program, program, "SomeGenericModule", ["T"])
          type_var = {"T" => TypeNode.new(program.string)} of String => ASTNode
          type = GenericClassInstanceType.new(program, generic_type, program.reference, type_var)
          mod = GenericModuleInstanceType.new(program, generic_mod, type_var)

          klass = NonGenericClassType.new(program, program, "SomeType", type)
          klass.include mod

          {x: TypeNode.new(klass)}
        end
      end

      it "executes superclass" do
        assert_macro("{{x.superclass}}", %(Reference)) do |program|
          {x: TypeNode.new(program.string)}
        end
      end

      it "executes size of tuple" do
        assert_macro("{{x.size}}", "2") do |program|
          {x: TypeNode.new(program.tuple_of([program.int32, program.string] of TypeVar))}
        end
      end

      it "executes size of tuple metaclass" do
        assert_macro("{{x.size}}", "2") do |program|
          {x: TypeNode.new(program.tuple_of([program.int32, program.string] of TypeVar).metaclass)}
        end
      end

      it "executes type_vars" do
        assert_macro("{{x.type_vars.map &.stringify}}", %(["A", "B"])) do |program|
          {x: TypeNode.new(GenericClassType.new(program, program, "SomeType", program.object, ["A", "B"]))}
        end
        assert_macro("{{x.type_vars.map &.stringify}}", %(["Int32", "String"])) do |program|
          generic_class = GenericClassType.new(program, program, "SomeType", program.object, ["A", "B"])
          {x: TypeNode.new(generic_class.instantiate([program.int32, program.string] of TypeVar))}
        end
        assert_macro("{{x.type_vars.map &.stringify}}", %(["Tuple(Int32, String)"])) do |program|
          generic_class = GenericClassType.new(program, program, "SomeType", program.object, ["T"])
          generic_class.splat_index = 0
          {x: TypeNode.new(generic_class.instantiate([program.int32, program.string] of TypeVar))}
        end
        assert_macro("{{x.type_vars.map &.stringify}}", %(["Tuple()"])) do |program|
          generic_class = GenericClassType.new(program, program, "SomeType", program.object, ["T"])
          generic_class.splat_index = 0
          {x: TypeNode.new(generic_class.instantiate([] of TypeVar))}
        end
      end

      it "executes class" do
        assert_macro("{{x.class.name}}", "String.class") do |program|
          {x: TypeNode.new(program.string)}
        end
      end

      it "executes instance" do
        assert_macro("{{x.class.instance}}", "String") do |program|
          {x: TypeNode.new(program.string)}
        end
      end

      it "executes ==" do
        assert_macro("{{x == Reference}}", "false") do |program|
          {x: TypeNode.new(program.string)}
        end
        assert_macro("{{x == String}}", "true") do |program|
          {x: TypeNode.new(program.string)}
        end
      end

      it "executes !=" do
        assert_macro("{{x != Reference}}", "true") do |program|
          {x: TypeNode.new(program.string)}
        end
        assert_macro("{{x != String}}", "false") do |program|
          {x: TypeNode.new(program.string)}
        end
      end

      it "== and != devirtualize generic type arguments (#10730)" do
        assert_type(%(
          class A
          end

          class B < A
          end

          module Foo(T)
            def self.foo
              {
                {% if T == A %} 1 {% else %} 'a' {% end %},
                {% if T != A %} 1 {% else %} 'a' {% end %},
              }
            end
          end

          Foo(A).foo
          )) { tuple_of([int32, char]) }
      end

      it "executes <" do
        assert_macro("{{x < Reference}}", "true") do |program|
          {x: TypeNode.new(program.string)}
        end
        assert_macro("{{x < String}}", "false") do |program|
          {x: TypeNode.new(program.string)}
        end
      end

      it "executes <=" do
        assert_macro("{{x <= Reference}}", "true") do |program|
          {x: TypeNode.new(program.string)}
        end
        assert_macro("{{x <= String}}", "true") do |program|
          {x: TypeNode.new(program.string)}
        end
      end

      it "executes >" do
        assert_macro("{{x > Reference}}", "false") do |program|
          {x: TypeNode.new(program.reference)}
        end
        assert_macro("{{x > String}}", "true") do |program|
          {x: TypeNode.new(program.reference)}
        end
      end

      it "executes >=" do
        assert_macro("{{x >= Reference}}", "true") do |program|
          {x: TypeNode.new(program.reference)}
        end
        assert_macro("{{x >= String}}", "true") do |program|
          {x: TypeNode.new(program.reference)}
        end
      end

      describe "#abstract?" do
        it NonGenericModuleType do
          assert_macro("{{type.abstract?}}", "false") do |program|
            mod = NonGenericModuleType.new(program, program, "SomeModule")

            {type: TypeNode.new(mod)}
          end
        end

        it GenericModuleType do
          assert_macro("{{type.abstract?}}", "false") do |program|
            generic_mod = GenericModuleType.new(program, program, "SomeGenericModule", ["T"])

            {type: TypeNode.new(generic_mod)}
          end
        end

        describe NonGenericClassType do
          describe "class" do
            it "abstract" do
              assert_macro("{{type.abstract?}}", "true") do |program|
                klass = NonGenericClassType.new(program, program, "SomeType", program.reference)
                klass.abstract = true

                {type: TypeNode.new(klass)}
              end
            end

            it "non-abstract" do
              assert_macro("{{type.abstract?}}", "false") do |program|
                klass = NonGenericClassType.new(program, program, "SomeType", program.reference)

                {type: TypeNode.new(klass)}
              end
            end
          end

          describe "struct" do
            it "abstract" do
              assert_macro("{{type.abstract?}}", "true") do |program|
                klass = NonGenericClassType.new(program, program, "SomeType", program.reference)
                klass.abstract = true
                klass.struct = true

                {type: TypeNode.new(klass)}
              end
            end

            it "non-abstract" do
              assert_macro("{{type.abstract?}}", "false") do |program|
                klass = NonGenericClassType.new(program, program, "SomeType", program.reference)
                klass.struct = true

                {type: TypeNode.new(klass)}
              end
            end
          end
        end

        describe GenericClassType do
          describe "class" do
            it "abstract" do
              assert_macro("{{type.abstract?}}", "true") do |program|
                klass = GenericClassType.new(program, program, "SomeGenericType", program.reference, ["T"])
                klass.abstract = true

                {type: TypeNode.new(klass)}
              end
            end

            it "non-abstract" do
              assert_macro("{{type.abstract?}}", "false") do |program|
                klass = GenericClassType.new(program, program, "SomeGenericType", program.reference, ["T"])

                {type: TypeNode.new(klass)}
              end
            end
          end

          describe "struct" do
            it "abstract" do
              assert_macro("{{type.abstract?}}", "true") do |program|
                klass = GenericClassType.new(program, program, "SomeGenericType", program.reference, ["T"])
                klass.abstract = true
                klass.struct = true

                {type: TypeNode.new(klass)}
              end
            end

            it "non-abstract" do
              assert_macro("{{type.abstract?}}", "false") do |program|
                klass = GenericClassType.new(program, program, "SomeGenericType", program.reference, ["T"])
                klass.struct = true

                {type: TypeNode.new(klass)}
              end
            end
          end
        end
      end

      describe "#union?" do
        it true do
          assert_macro("{{x.union?}}", "true") do |program|
            {x: TypeNode.new(program.union_of(program.string, program.nil))}
          end
        end

        it false do
          assert_macro("{{x.union?}}", "false") do |program|
            {x: TypeNode.new(program.string)}
          end
        end
      end

      describe "#module?" do
        it NonGenericModuleType do
          assert_macro("{{type.module?}}", "true") do |program|
            mod = NonGenericModuleType.new(program, program, "SomeModule")

            {type: TypeNode.new(mod)}
          end
        end

        it GenericModuleType do
          assert_macro("{{type.module?}}", "true") do |program|
            generic_mod = GenericModuleType.new(program, program, "SomeGenericModule", ["T"])

            {type: TypeNode.new(generic_mod)}
          end
        end

        describe NonGenericClassType do
          it "class" do
            assert_macro("{{type.module?}}", "false") do |program|
              klass = NonGenericClassType.new(program, program, "SomeType", program.reference)

              {type: TypeNode.new(klass)}
            end
          end

          it "struct" do
            assert_macro("{{type.module?}}", "false") do |program|
              klass = NonGenericClassType.new(program, program, "SomeType", program.reference)
              klass.struct = true

              {type: TypeNode.new(klass)}
            end
          end
        end

        describe GenericClassType do
          it "class" do
            assert_macro("{{type.module?}}", "false") do |program|
              klass = GenericClassType.new(program, program, "SomeGenericType", program.reference, ["T"])

              {type: TypeNode.new(klass)}
            end
          end

          it "struct" do
            assert_macro("{{type.module?}}", "false") do |program|
              klass = GenericClassType.new(program, program, "SomeGenericType", program.reference, ["T"])
              klass.struct = true

              {type: TypeNode.new(klass)}
            end
          end
        end
      end

      describe "#class?" do
        it NonGenericModuleType do
          assert_macro("{{type.class?}}", "false") do |program|
            mod = NonGenericModuleType.new(program, program, "SomeModule")

            {type: TypeNode.new(mod)}
          end
        end

        it GenericModuleType do
          assert_macro("{{type.class?}}", "false") do |program|
            generic_mod = GenericModuleType.new(program, program, "SomeGenericModule", ["T"])

            {type: TypeNode.new(generic_mod)}
          end
        end

        describe NonGenericClassType do
          it "class" do
            assert_macro("{{type.class?}}", "true") do |program|
              klass = NonGenericClassType.new(program, program, "SomeType", program.reference)

              {type: TypeNode.new(klass)}
            end
          end

          it "struct" do
            assert_macro("{{type.class?}}", "false") do |program|
              klass = NonGenericClassType.new(program, program, "SomeType", program.reference)
              klass.struct = true

              {type: TypeNode.new(klass)}
            end
          end
        end

        describe GenericClassType do
          it "class" do
            assert_macro("{{type.class?}}", "true") do |program|
              klass = GenericClassType.new(program, program, "SomeGenericType", program.reference, ["T"])

              {type: TypeNode.new(klass)}
            end
          end

          it "struct" do
            assert_macro("{{type.class?}}", "false") do |program|
              klass = GenericClassType.new(program, program, "SomeGenericType", program.reference, ["T"])
              klass.struct = true

              {type: TypeNode.new(klass)}
            end
          end
        end
      end

      describe "#struct?" do
        it NonGenericModuleType do
          assert_macro("{{type.struct?}}", "false") do |program|
            mod = NonGenericModuleType.new(program, program, "SomeModule")

            {type: TypeNode.new(mod)}
          end
        end

        it GenericModuleType do
          assert_macro("{{type.struct?}}", "false") do |program|
            generic_mod = GenericModuleType.new(program, program, "SomeGenericModule", ["T"])

            {type: TypeNode.new(generic_mod)}
          end
        end

        describe NonGenericClassType do
          it "class" do
            assert_macro("{{type.struct?}}", "false") do |program|
              klass = NonGenericClassType.new(program, program, "SomeType", program.reference)

              {type: TypeNode.new(klass)}
            end
          end

          it "struct" do
            assert_macro("{{type.struct?}}", "true") do |program|
              klass = NonGenericClassType.new(program, program, "SomeType", program.reference)
              klass.struct = true

              {type: TypeNode.new(klass)}
            end
          end
        end

        describe GenericClassType do
          it "class" do
            assert_macro("{{type.struct?}}", "false") do |program|
              klass = GenericClassType.new(program, program, "SomeGenericType", program.reference, ["T"])

              {type: TypeNode.new(klass)}
            end
          end

          it "struct" do
            assert_macro("{{type.struct?}}", "true") do |program|
              klass = GenericClassType.new(program, program, "SomeGenericType", program.reference, ["T"])
              klass.struct = true

              {type: TypeNode.new(klass)}
            end
          end
        end
      end

      describe "#nilable?" do
        it false do
          assert_macro("{{x.nilable?}}", "false") do |program|
            {x: TypeNode.new(program.string)}
          end

          assert_macro("{{x.nilable?}}", "false") do |program|
            {x: TypeNode.new(program.union_of(program.string, program.int32))}
          end

          assert_macro("{{x.nilable?}}", "false") do |program|
            {x: TypeNode.new(program.no_return)}
          end

          assert_macro("{{x.nilable?}}", "false") do |program|
            {x: TypeNode.new(program.class_type)}
          end

          assert_macro("{{x.nilable?}}", "false") do |program|
            {x: TypeNode.new(program.reference)}
          end
        end

        it true do
          assert_macro("{{x.nilable?}}", "true") do |program|
            {x: TypeNode.new(program.nil_type)}
          end

          assert_macro("{{x.nilable?}}", "true") do |program|
            {x: TypeNode.new(program.union_of(program.string, program.nil))}
          end

          assert_macro("{{x.nilable?}}", "true") do |program|
            {x: TypeNode.new(program.value)}
          end

          assert_macro("{{x.nilable?}}", "true") do |program|
            {x: TypeNode.new(program.object)}
          end

          assert_macro("{{x.nilable?}}", "true") do |program|
            mod = NonGenericModuleType.new(program, program, "SomeModule")
            program.nil_type.include mod
            {x: TypeNode.new(mod)}
          end

          assert_type(<<-CRYSTAL) { int32 }
            class Foo(T)
            end

            alias Bar = Foo(Bar)?

            {{ Bar.nilable? ? 1 : 'a' }}
            CRYSTAL
        end
      end

      it "executes resolve" do
        assert_macro("{{x.resolve}}", "String") do |program|
          {x: TypeNode.new(program.string)}
        end
      end

      it "executes resolve?" do
        assert_macro("{{x.resolve?}}", "String") do |program|
          {x: TypeNode.new(program.string)}
        end
      end

      it "executes union_types (union)" do
        assert_macro("{{x.union_types}}", %([Bool, Int32])) do |program|
          {x: TypeNode.new(program.union_of(program.int32, program.bool))}
        end
      end

      it "executes union_types (non-union)" do
        assert_macro("{{x.union_types}}", %([Int32])) do |program|
          {x: TypeNode.new(program.int32)}
        end
      end

      describe "executes private?" do
        it false do
          assert_macro("{{x.private?}}", "false") do |program|
            klass = GenericClassType.new(program, program, "SomeGenericType", program.reference, ["T"])

            {x: TypeNode.new(klass)}
          end
        end

        it true do
          assert_macro("{{x.private?}}", "true") do |program|
            klass = GenericClassType.new(program, program, "SomeGenericType", program.reference, ["T"])
            klass.private = true

            {x: TypeNode.new(klass)}
          end
        end
      end

      describe "public?" do
        it false do
          assert_macro("{{x.public?}}", "false") do |program|
            klass = GenericClassType.new(program, program, "SomeGenericType", program.reference, ["T"])
            klass.private = true

            {x: TypeNode.new(klass)}
          end
        end

        it true do
          assert_macro("{{x.public?}}", "true") do |program|
            klass = GenericClassType.new(program, program, "SomeGenericType", program.reference, ["T"])

            {x: TypeNode.new(klass)}
          end
        end
      end

      describe "visibility" do
        it :public do
          assert_macro("{{x.visibility}}", ":public") do |program|
            klass = GenericClassType.new(program, program, "SomeGenericType", program.reference, ["T"])

            {x: TypeNode.new(klass)}
          end
        end

        it :private do
          assert_macro("{{x.visibility}}", ":private") do |program|
            klass = GenericClassType.new(program, program, "SomeGenericType", program.reference, ["T"])
            klass.private = true

            {x: TypeNode.new(klass)}
          end
        end
      end

      describe "#has_inner_pointers?" do
        it "works on structs" do
          assert_macro("{{x.has_inner_pointers?}}", %(false)) do |program|
            klass = NonGenericClassType.new(program, program, "SomeType", program.struct)
            klass.struct = true
            klass.declare_instance_var("@var", program.int32)
            {x: TypeNode.new(klass)}
          end

          assert_macro("{{x.has_inner_pointers?}}", %(true)) do |program|
            klass = NonGenericClassType.new(program, program, "SomeType", program.struct)
            klass.struct = true
            klass.declare_instance_var("@var", program.string)
            {x: TypeNode.new(klass)}
          end
        end

        it "works on references" do
          assert_macro("{{x.has_inner_pointers?}}", %(true)) do |program|
            klass = NonGenericClassType.new(program, program, "SomeType", program.reference)
            {x: TypeNode.new(klass)}
          end
        end

        it "works on ReferenceStorage" do
          assert_macro("{{x.has_inner_pointers?}}", %(false)) do |program|
            reference_storage = GenericReferenceStorageType.new program, program, "ReferenceStorage", program.struct, ["T"]
            klass = NonGenericClassType.new(program, program, "SomeType", program.reference)
            klass.declare_instance_var("@var", program.int32)
            {x: TypeNode.new(reference_storage.instantiate([klass] of TypeVar))}
          end

          assert_macro("{{x.has_inner_pointers?}}", %(true)) do |program|
            reference_storage = GenericReferenceStorageType.new program, program, "ReferenceStorage", program.struct, ["T"]
            klass = NonGenericClassType.new(program, program, "SomeType", program.reference)
            klass.declare_instance_var("@var", program.string)
            {x: TypeNode.new(reference_storage.instantiate([klass] of TypeVar))}
          end
        end

        it "works on primitive values" do
          assert_macro("{{x.has_inner_pointers?}}", %(false)) do |program|
            {x: TypeNode.new(program.int32)}
          end

          assert_macro("{{x.has_inner_pointers?}}", %(true)) do |program|
            {x: TypeNode.new(program.void)}
          end

          assert_macro("{{x.has_inner_pointers?}}", %(true)) do |program|
            {x: TypeNode.new(program.pointer_of(program.int32))}
          end

          assert_macro("{{x.has_inner_pointers?}}", %(true)) do |program|
            {x: TypeNode.new(program.proc_of(program.void))}
          end
        end

        it "errors when called from top-level scope" do
          assert_error <<-CRYSTAL, "`TypeNode#has_inner_pointers?` cannot be called in the top-level scope: instance vars are not yet initialized"
            class Foo
            end
            {{ Foo.has_inner_pointers? }}
          CRYSTAL
        end

        it "does not error when called from def scope" do
          assert_type <<-CRYSTAL { |program| program.bool }
            module Moo
            end
            def moo
              {{ Moo.has_inner_pointers? }}
            end
            moo
          CRYSTAL
        end
      end
    end

    describe "type declaration methods" do
      it "executes var" do
        assert_macro %({{x.var}}), "some_name", {x: TypeDeclaration.new(Var.new("some_name"), Path.new("SomeType"))}
      end

      it "executes var when instance var" do
        assert_macro %({{x.var}}), "@some_name", {x: TypeDeclaration.new(InstanceVar.new("@some_name"), Path.new("SomeType"))}
      end

      it "executes type" do
        assert_macro %({{x.type}}), "SomeType", {x: TypeDeclaration.new(Var.new("some_name"), Path.new("SomeType"))}
      end

      it "executes value" do
        assert_macro %({{x.value}}), "1", {x: TypeDeclaration.new(Var.new("some_name"), Path.new("SomeType"), 1.int32)}
      end
    end

    describe "uninitialized var methods" do
      it "executes var" do
        assert_macro %({{x.var}}), "some_name", {x: UninitializedVar.new(Var.new("some_name"), Path.new("SomeType"))}
      end

      it "executes type" do
        assert_macro %({{x.type}}), "SomeType", {x: UninitializedVar.new(Var.new("some_name"), Path.new("SomeType"))}
      end
    end

    describe "proc notation methods" do
      it "gets single input" do
        assert_macro %({{x.inputs}}), "[SomeType]", {x: ProcNotation.new(([Path.new("SomeType")] of ASTNode), Path.new("SomeResult"))}
      end

      it "gets single output" do
        assert_macro %({{x.output}}), "SomeResult", {x: ProcNotation.new(([Path.new("SomeType")] of ASTNode), Path.new("SomeResult"))}
      end

      it "gets multiple inputs" do
        assert_macro %({{x.inputs}}), "[SomeType, OtherType]", {x: ProcNotation.new([Path.new("SomeType"), Path.new("OtherType")] of ASTNode)}
      end

      it "gets empty output" do
        assert_macro %({{x.output}}), "nil", {x: ProcNotation.new([Path.new("SomeType")] of ASTNode)}
      end

      it "executes resolve" do
        assert_macro %({{x.resolve}}), "Proc(Int32, String)", {x: ProcNotation.new(([Path.new("Int32")] of ASTNode), Path.new("String"))}

        assert_macro_error(%({{x.resolve}}), "undefined constant Foo") do
          {x: ProcNotation.new(([Path.new("Foo")] of ASTNode))}
        end

        assert_macro_error(%({{x.resolve}}), "undefined constant Foo") do
          {x: ProcNotation.new(([] of ASTNode), Path.new("Foo"))}
        end
      end

      it "executes resolve?" do
        assert_macro %({{x.resolve?}}), "Proc(Int32, String)", {x: ProcNotation.new(([Path.new("Int32")] of ASTNode), Path.new("String"))}
        assert_macro %({{x.resolve?}}), "nil", {x: ProcNotation.new(([Path.new("Foo")] of ASTNode))}
        assert_macro %({{x.resolve?}}), "nil", {x: ProcNotation.new(([] of ASTNode), Path.new("Foo"))}
      end
    end

    describe "proc literal methods" do
      it "executes body" do
        assert_macro %({{x.body}}), "1", {x: ProcLiteral.new(Def.new("->", body: 1.int32))}
      end

      it "executes args" do
        assert_macro %({{x.args}}), "[z]", {x: ProcLiteral.new(Def.new("->", [Arg.new("z")]))}
      end

      it "executes return_type" do
        assert_macro %({{x.return_type}}), "Int32", {x: ProcLiteral.new(Def.new("->", return_type: "Int32".path))}
        assert_macro %({{x.return_type}}), "", {x: ProcLiteral.new(Def.new("->"))}
      end
    end

    describe "proc pointer methods" do
      it "executes obj when present" do
        assert_macro %({{x.obj}}), "some_object", {x: ProcPointer.new(Var.new("some_object"), "method", [] of ASTNode)}
      end

      it "executes obj when absent" do
        assert_macro %({{x.obj}}), "nil", {x: ProcPointer.new(NilLiteral.new, "method", [] of ASTNode)}
      end

      it "executes name" do
        assert_macro %({{x.name}}), "method", {x: ProcPointer.new(Var.new("some_object"), "method", [] of ASTNode)}
      end

      it "executes args when empty" do
        assert_macro %({{x.args}}), "[]", {x: ProcPointer.new(Var.new("some_object"), "method", [] of ASTNode)}
      end

      it "executes args when not empty" do
        assert_macro %({{x.args}}), "[SomeType, OtherType]", {x: ProcPointer.new(Var.new("some_object"), "method", [Path.new("SomeType"), Path.new("OtherType")] of ASTNode)}
      end

      it "executes global?" do
        assert_macro %({{x.global?}}), "false", {x: ProcPointer.new(nil, "method")}
        assert_macro %({{x.global?}}), "true", {x: ProcPointer.new(nil, "method", global: true)}
        assert_macro %({{x.global?}}), "false", {x: ProcPointer.new(Path.global("Foo"), "method")}
      end
    end

    describe "def methods" do
      it "executes name" do
        assert_macro %({{x.name}}), "some_def", {x: Def.new("some_def")}
      end

      it "executes body" do
        assert_macro %({{x.body}}), "1", {x: Def.new("some_def", body: 1.int32)}
      end

      it "executes args" do
        assert_macro %({{x.args}}), "[z]", {x: Def.new("some_def", [Arg.new("z")])}
      end

      it "executes splat_index" do
        assert_macro %({{x.splat_index}}), "1", {x: Def.new("some_def", ["x".arg, "y".arg], splat_index: 1)}
        assert_macro %({{x.splat_index}}), "nil", {x: Def.new("some_def")}
      end

      it "executes double_splat" do
        assert_macro %({{x.double_splat}}), "s", {x: Def.new("some_def", ["x".arg, "y".arg], double_splat: "s".arg)}
        assert_macro %({{x.double_splat}}), "", {x: Def.new("some_def")}
      end

      it "executes block_arg" do
        assert_macro %({{x.block_arg}}), "b", {x: Def.new("some_def", ["x".arg, "y".arg], block_arg: "b".arg)}
        assert_macro %({{x.block_arg}}), "", {x: Def.new("some_def")}
      end

      it "executes accepts_block?" do
        assert_macro %({{x.accepts_block?}}), "true", {x: Def.new("some_def", ["x".arg, "y".arg], block_arity: 1)}
        assert_macro %({{x.accepts_block?}}), "false", {x: Def.new("some_def")}
      end

      it "executes return_type" do
        assert_macro %({{x.return_type}}), "b", {x: Def.new("some_def", ["x".arg, "y".arg], return_type: "b".arg)}
        assert_macro %({{x.return_type}}), "", {x: Def.new("some_def")}
      end

      it "executes free_vars" do
        assert_macro %({{x.free_vars}}), "[] of ::NoReturn", {x: Def.new("some_def")}
        assert_macro %({{x.free_vars}}), "[T]", {x: Def.new("some_def", free_vars: %w(T))}
        assert_macro %({{x.free_vars}}), "[T, U, V]", {x: Def.new("some_def", free_vars: %w(T U V))}
      end

      it "executes receiver" do
        assert_macro %({{x.receiver}}), "self", {x: Def.new("some_def", receiver: Var.new("self"))}
      end

      it "executes abstract?" do
        assert_macro %({{x.abstract?}}), "false", {x: Def.new("some_def")}
        assert_macro %({{x.abstract?}}), "true", {x: Def.new("some_def", abstract: true)}
      end

      it "executes visibility" do
        assert_macro %({{x.visibility}}), ":public", {x: Def.new("some_def")}
        assert_macro %({{x.visibility}}), ":private", {x: Def.new("some_def").tap { |d| d.visibility = Visibility::Private }}
      end
    end

    describe External do
      it "executes is_a?" do
        assert_macro %({{x.is_a?(External)}}), "true", {x: External.new("foo", [] of Arg, Nop.new, "foo")}
        assert_macro %({{x.is_a?(Def)}}), "true", {x: External.new("foo", [] of Arg, Nop.new, "foo")}
        assert_macro %({{x.is_a?(ASTNode)}}), "true", {x: External.new("foo", [] of Arg, Nop.new, "foo")}
      end
    end

    describe Primitive do
      it "executes name" do
        assert_macro %({{x.name}}), %(:abc), {x: Primitive.new("abc")}
        assert_macro %({{x.name}}), %(:"x.y.z"), {x: Primitive.new("x.y.z")}
      end
    end

    describe "macro methods" do
      it "executes name" do
        assert_macro %({{x.name}}), "some_macro", {x: Macro.new("some_macro")}
      end

      it "executes body" do
        assert_macro %({{x.body}}), "1", {x: Macro.new("some_macro", body: 1.int32)}
      end

      it "executes args" do
        assert_macro %({{x.args}}), "[z]", {x: Macro.new("some_macro", [Arg.new("z")])}
      end

      it "executes splat_index" do
        assert_macro %({{x.splat_index}}), "1", {x: Macro.new("some_macro", ["x".arg, "y".arg], splat_index: 1)}
        assert_macro %({{x.splat_index}}), "nil", {x: Macro.new("some_macro")}
      end

      it "executes double_splat" do
        assert_macro %({{x.double_splat}}), "s", {x: Macro.new("some_macro", ["x".arg, "y".arg], double_splat: "s".arg)}
        assert_macro %({{x.double_splat}}), "", {x: Macro.new("some_macro")}
      end

      it "executes block_arg" do
        assert_macro %({{x.block_arg}}), "b", {x: Macro.new("some_macro", ["x".arg, "y".arg], block_arg: "b".arg)}
        assert_macro %({{x.block_arg}}), "", {x: Macro.new("some_macro")}
      end

      it "executes visibility" do
        assert_macro %({{x.visibility}}), ":public", {x: Macro.new("some_macro")}
        assert_macro %({{x.visibility}}), ":private", {x: Macro.new("some_macro").tap { |d| d.visibility = Visibility::Private }}
      end
    end

    describe MacroExpression do
      it "executes exp" do
        assert_macro %({{x.exp}}), "nil", {x: MacroExpression.new(NilLiteral.new)}
      end

      it "executes output?" do
        assert_macro %({{x.output?}}), "false", {x: MacroExpression.new(NilLiteral.new, output: false)}
        assert_macro %({{x.output?}}), "true", {x: MacroExpression.new(1.int32, output: true)}
      end
    end

    describe "macro if methods" do
      it "executes cond" do
        assert_macro %({{x.cond}}), "true", {x: MacroIf.new(BoolLiteral.new(true), NilLiteral.new)}
      end

      it "executes then" do
        assert_macro %({{x.then}}), "\"test\"", {x: MacroIf.new(BoolLiteral.new(true), StringLiteral.new("test"), StringLiteral.new("foo"))}
      end

      it "executes else" do
        assert_macro %({{x.else}}), "\"foo\"", {x: MacroIf.new(BoolLiteral.new(true), StringLiteral.new("test"), StringLiteral.new("foo"))}
      end

      it "executes is_unless?" do
        assert_macro %({{x.is_unless?}}), "true", {x: MacroIf.new(BoolLiteral.new(true), StringLiteral.new("test"), StringLiteral.new("foo"), is_unless: true)}
        assert_macro %({{x.is_unless?}}), "false", {x: MacroIf.new(BoolLiteral.new(false), StringLiteral.new("test"), StringLiteral.new("foo"), is_unless: false)}
      end
    end

    describe "macro for methods" do
      it "executes vars" do
        assert_macro %({{x.vars}}), "[bar]", {x: MacroFor.new([Var.new("bar")], Var.new("foo"), Call.new("puts", [Var.new("bar")] of ASTNode))}
      end

      it "executes exp" do
        assert_macro %({{x.exp}}), "foo", {x: MacroFor.new([Var.new("bar")], Var.new("foo"), Call.new("puts", [Var.new("bar")] of ASTNode))}
      end

      it "executes body" do
        assert_macro %({{x.body}}), "puts(bar)", {x: MacroFor.new([Var.new("bar")], Var.new("foo"), Call.new("puts", [Var.new("bar")] of ASTNode))}
      end
    end

    describe MacroLiteral do
      it "executes value" do
        assert_macro %({{x.value}}), "foo(1)", {x: MacroLiteral.new("foo(1)")}
        assert_macro %({{x.value}}), "", {x: MacroLiteral.new("")}
      end
    end

    describe MacroVar do
      it "executes name" do
        assert_macro %({{x.name}}), "foo", {x: MacroVar.new("foo")}
      end

      it "executes expressions" do
        assert_macro %({{x.expressions}}), "[] of ::NoReturn", {x: MacroVar.new("foo")}
        assert_macro %({{x.expressions}}), "[x, 1]", {x: MacroVar.new("bar", [Var.new("x"), 1.int32] of ASTNode)}
      end
    end

    describe "unary expression methods" do
      it "executes exp" do
        assert_macro %({{x.exp}}), "some_call", {x: Not.new("some_call".call)}
      end

      it "executes is_a?" do
        assert_macro %({{ x.is_a?(Not) }}), "true", {x: Not.new("some_call".call)}
        assert_macro %({{ x.is_a?(Splat) }}), "false", {x: Not.new("some_call".call)}
        assert_macro %({{ x.is_a?(UnaryExpression) }}), "true", {x: Not.new("some_call".call)}
        assert_macro %({{ x.is_a?(ASTNode) }}), "true", {x: Not.new("some_call".call)}
        assert_macro %({{ x.is_a?(TypeNode) }}), "false", {x: Not.new("some_call".call)}
      end
    end

    describe "offsetof methods" do
      it "executes type" do
        assert_macro %({{x.type}}), "SomeType", {x: OffsetOf.new("SomeType".path, "@some_ivar".instance_var)}
      end

      it "executes offset" do
        assert_macro %({{x.offset}}), "@some_ivar", {x: OffsetOf.new("SomeType".path, "@some_ivar".instance_var)}
      end
    end

    describe Include do
      foo = Include.new("Foo".path)
      bar = Include.new(Generic.new("Bar".path, ["Int32".path] of ASTNode))

      it "executes name" do
        assert_macro %({{x.name}}), "Foo", {x: foo}
        assert_macro %({{x.name}}), "Bar(Int32)", {x: bar}
      end
    end

    describe Extend do
      foo = Extend.new("Foo".path)
      bar = Extend.new(Generic.new("Bar".path, ["Int32".path] of ASTNode))

      it "executes name" do
        assert_macro %({{x.name}}), "Foo", {x: foo}
        assert_macro %({{x.name}}), "Bar(Int32)", {x: bar}
      end
    end

    describe Alias do
      node = Alias.new("Foo".path, Generic.new(Path.new(["Bar", "Baz"], global: true), ["T".path] of ASTNode))

      it "executes name" do
        assert_macro %({{x.name}}), %(Foo), {x: node}
      end

      it "executes type" do
        assert_macro %({{x.type}}), %(::Bar::Baz(T)), {x: node}
      end
    end

    describe "visibility modifier methods" do
      node = VisibilityModifier.new(Visibility::Protected, Def.new("some_def"))

      it "executes visibility" do
        assert_macro %({{x.visibility}}), ":protected", {x: node}
      end

      it "executes exp" do
        assert_macro %({{x.exp}}), "def some_def\nend", {x: node}
      end
    end

    describe "is_a methods" do
      node = IsA.new("var".var, Path.new("Int32"))

      it "executes receiver" do
        assert_macro %({{x.receiver}}), "var", {x: node}
      end

      it "executes arg" do
        assert_macro %({{x.arg}}), "Int32", {x: node}
      end
    end

    describe "responds_to methods" do
      node = RespondsTo.new("var".var, "to_i")

      it "executes receiver" do
        assert_macro %({{x.receiver}}), "var", {x: node}
      end

      it "executes name" do
        assert_macro %({{x.name}}), %("to_i"), {x: node}
      end
    end

    describe "metaclass methods" do
      node = Metaclass.new(Path.new("Int32"))

      it "executes instance" do
        assert_macro %({{x.instance}}), "Int32", {x: node}
      end

      it "executes resolve" do
        assert_macro %({{x.resolve}}), %(Int32.class), {x: node}
        assert_macro %({{x.resolve}}), %(Array(T).class), {x: Metaclass.new(Path.new("Array"))}

        assert_macro_error(%({{x.resolve}}), "undefined constant Foo") do
          {x: Metaclass.new(Path.new("Foo"))}
        end
      end

      it "executes resolve?" do
        assert_macro %({{x.resolve?}}), %(Int32.class), {x: node}
        assert_macro %({{x.resolve?}}), %(Array(T).class), {x: Metaclass.new(Path.new("Array"))}
        assert_macro %({{x.resolve?}}), %(nil), {x: Metaclass.new(Path.new("Foo"))}
      end
    end

    describe "require methods" do
      it "executes path" do
        assert_macro %({{x.path}}), %("json"), {x: Require.new("json")}
      end
    end

    describe "call methods" do
      it "executes name" do
        assert_macro %({{x.name}}), "some_call", {x: "some_call".call}
      end

      it "executes args" do
        assert_macro %({{x.args}}), "[1, 3]", {x: Call.new("some_call", [1.int32, 3.int32] of ASTNode)}
      end

      it "executes receiver" do
        assert_macro %({{x.receiver}}), "1", {x: Call.new(1.int32, "some_call")}
      end

      it "executes block" do
        assert_macro %({{x.block}}), "do\nend", {x: Call.new(1.int32, "some_call", block: Block.new)}
      end

      it "executes block arg" do
        assert_macro %({{x.block_arg}}), "bl", {x: Call.new(1.int32, "some_call", block_arg: "bl".arg)}
      end

      it "executes block arg (nop)" do
        assert_macro %({{x.block_arg}}), "", {x: Call.new(1.int32, "some_call")}
      end

      it "executes named args" do
        assert_macro %({{x.named_args}}), "[a: 1, b: 2]", {x: Call.new(1.int32, "some_call", named_args: [NamedArgument.new("a", 1.int32), NamedArgument.new("b", 2.int32)])}
      end

      it "executes named args name" do
        assert_macro %({{x.named_args[0].name}}), "a", {x: Call.new(1.int32, "some_call", named_args: [NamedArgument.new("a", 1.int32), NamedArgument.new("b", 2.int32)])}
      end

      it "executes named args value" do
        assert_macro %({{x.named_args[0].value}}), "1", {x: Call.new(1.int32, "some_call", named_args: [NamedArgument.new("a", 1.int32), NamedArgument.new("b", 2.int32)])}
      end

      it "executes global?" do
        assert_macro %({{x.global?}}), "false", {x: Call.new(1.int32, "some_call")}
        assert_macro %({{x.global?}}), "true", {x: Call.new("some_call", global: true)}
      end
    end

    describe "arg methods" do
      it "executes name" do
        arg = "into".arg
        assert_macro %({{x.name}}), "into", {x: arg}
        arg.name = "array" # internal
        assert_macro %({{x.name}}), "into", {x: arg}
      end

      it "executes internal_name" do
        arg = "into".arg
        assert_macro %({{x.internal_name}}), "into", {x: arg}
        arg.name = "array"
        assert_macro %({{x.internal_name}}), "array", {x: arg}
      end

      it "executes default_value" do
        assert_macro %({{x.default_value}}), "1", {x: "some_arg".arg(default_value: 1.int32)}
      end

      it "executes restriction" do
        assert_macro %({{x.restriction}}), "T", {x: "some_arg".arg(restriction: "T".path)}
      end
    end

    describe "cast methods" do
      it "executes obj" do
        assert_macro %({{x.obj}}), "x", {x: Cast.new("x".call, "Int32".path)}
      end

      it "executes to" do
        assert_macro %({{x.to}}), "Int32", {x: Cast.new("x".call, "Int32".path)}
      end
    end

    describe "nilable cast methods" do
      it "executes obj" do
        assert_macro %({{x.obj}}), "x", {x: NilableCast.new("x".call, "Int32".path)}
      end

      it "executes to" do
        assert_macro %({{x.to}}), "Int32", {x: NilableCast.new("x".call, "Int32".path)}
      end
    end

    describe TypeOf do
      it "executes args" do
        assert_macro %({{x.args}}), "[1, 'a', Foo]", {x: TypeOf.new([1.int32, CharLiteral.new('a'), "Foo".path])}
      end
    end

    describe "case methods" do
      describe "when" do
        case_node = Case.new(1.int32, [When.new([2.int32, 3.int32] of ASTNode, 4.int32)], 5.int32, exhaustive: false)

        it "executes cond" do
          assert_macro %({{x.cond}}), "1", {x: case_node}
        end

        it "executes whens" do
          assert_macro %({{x.whens}}), "[when 2, 3\n  4\n]", {x: case_node}
        end

        it "executes when conds" do
          assert_macro %({{x.whens[0].conds}}), "[2, 3]", {x: case_node}
        end

        it "executes when body" do
          assert_macro %({{x.whens[0].body}}), "4", {x: case_node}
        end

        it "executes when exhaustive?" do
          assert_macro %({{x.whens[0].exhaustive?}}), "false", {x: case_node}
        end

        it "executes else" do
          assert_macro %({{x.else}}), "5", {x: case_node}
        end

        it "executes exhaustive?" do
          assert_macro %({{x.exhaustive?}}), "false", {x: case_node}
        end
      end

      describe "in" do
        case_node = Case.new(1.int32, [When.new([2.int32, 3.int32] of ASTNode, 4.int32)], 5.int32, exhaustive: true)

        it "executes whens" do
          assert_macro %({{x.whens}}), "[in 2, 3\n  4\n]", {x: case_node}
        end

        it "executes when exhaustive?" do
          assert_macro %({{x.whens[0].exhaustive?}}), "true", {x: case_node}
        end

        it "executes exhaustive?" do
          assert_macro %({{x.exhaustive?}}), "true", {x: case_node}
        end
      end
    end

    describe Select do
      it "executes whens" do
        assert_macro %({{x.whens}}), "[when foo\n  1\n]", {x: Select.new([When.new("foo".call, 1.int32)])}
        assert_macro %({{x.whens}}), "[when x = y\n  1\n, when bar\n]", {x: Select.new([When.new(Assign.new("x".var, "y".var), 1.int32), When.new("bar".call)])}
      end

      it "executes else" do
        assert_macro %({{x.else}}), "", {x: Select.new([When.new("foo".call)])}
        assert_macro %({{x.else}}), "1", {x: Select.new([When.new("foo".call)], 1.int32)}
        assert_macro %({{x.else}}), "nil", {x: Select.new([When.new("foo".call)], NilLiteral.new)}
      end
    end

    describe "if methods" do
      if_node = If.new(1.int32, 2.int32, 3.int32)

      it "executes cond" do
        assert_macro %({{x.cond}}), "1", {x: if_node}
      end

      it "executes then" do
        assert_macro %({{x.then}}), "2", {x: if_node}
      end

      it "executes else" do
        assert_macro %({{x.else}}), "3", {x: if_node}
      end

      it "executes else (nop)" do
        assert_macro %({{x.else}}), "", {x: If.new(1.int32, 2.int32)}
      end
    end

    describe "while methods" do
      while_node = While.new(1.int32, 2.int32)

      it "executes cond" do
        assert_macro %({{x.cond}}), "1", {x: while_node}
      end

      it "executes body" do
        assert_macro %({{x.body}}), "2", {x: while_node}
      end
    end

    describe "control expression methods" do
      it "executes exp" do
        assert_macro %({{x.exp}}), "1", {x: Break.new(1.int32)}
        assert_macro %({{x.exp}}), "1", {x: Next.new(1.int32)}
        assert_macro %({{x.exp}}), "1", {x: Return.new(1.int32)}
      end

      it "executes exp (nop)" do
        assert_macro %({{x.exp}}), "", {x: Break.new}
        assert_macro %({{x.exp}}), "", {x: Next.new}
        assert_macro %({{x.exp}}), "", {x: Return.new}
      end
    end

    describe "yield methods" do
      it "executes expressions" do
        assert_macro %({{x.expressions}}), "[]", {x: Yield.new}
        assert_macro %({{x.expressions}}), "[1]", {x: Yield.new([1.int32] of ASTNode)}
        assert_macro %({{x.expressions}}), "[1, 2]", {x: Yield.new([1.int32, 2.int32] of ASTNode)}
      end

      it "executes scope" do
        assert_macro %({{x.scope}}), "1", {x: Yield.new(scope: 1.int32)}
        assert_macro %({{x.scope}}), "nil", {x: Yield.new(scope: NilLiteral.new)}
      end

      it "executes scope (nop)" do
        assert_macro %({{x.scope}}), "", {x: Yield.new}
      end
    end

    describe "exception handler methods" do
      # begin
      #   1
      # rescue ex : Int32
      #   2
      # rescue Char | String
      # else
      #   3
      # ensure
      #   4
      # end
      begin_node = ExceptionHandler.new(1.int32, [Rescue.new(2.int32, ["Int32".path] of ASTNode, "ex"), Rescue.new(Nop.new, ["Char".path, "String".path] of ASTNode)], 3.int32, 4.int32)

      it "executes body" do
        assert_macro %({{x.body}}), "1", {x: begin_node}
      end

      it "executes rescues" do
        assert_macro %({{x.rescues}}), "[rescue ex : Int32\n  2\n, rescue Char | String\n]", {x: begin_node}
      end

      it "executes rescue body" do
        assert_macro %({{x.rescues[0].body}}), "2", {x: begin_node}
        assert_macro %({{x.rescues[1].body}}), "", {x: begin_node}
      end

      it "executes rescue types" do
        assert_macro %({{x.rescues[0].types}}), "[Int32]", {x: begin_node}
        assert_macro %({{x.rescues[1].types}}), "[Char, String]", {x: begin_node}
        assert_macro %({{x.types}}), "nil", {x: Rescue.new(1.int32)}
      end

      it "executes rescue name" do
        assert_macro %({{x.rescues[0].name}}), "ex", {x: begin_node}
        assert_macro %({{x.rescues[1].name}}), "", {x: begin_node}
      end

      it "executes else" do
        assert_macro %({{x.else}}), "3", {x: begin_node}
      end

      it "executes else (nop)" do
        assert_macro %({{x.else}}), "", {x: ExceptionHandler.new(Nop.new)}
      end

      it "executes ensure" do
        assert_macro %({{x.ensure}}), "4", {x: begin_node}
      end

      it "executes ensure (nop)" do
        assert_macro %({{x.ensure}}), "", {x: ExceptionHandler.new(Nop.new)}
      end
    end

    describe "assign methods" do
      it "executes target" do
        assert_macro %({{x.target}}), "foo", {x: Assign.new("foo".var, 2.int32)}
      end

      it "executes value" do
        assert_macro %({{x.value}}), "2", {x: Assign.new("foo".var, 2.int32)}
      end
    end

    describe "multi_assign methods" do
      multi_assign_node = MultiAssign.new(["foo".var, "bar".var] of ASTNode, [2.int32, "a".string] of ASTNode)

      it "executes targets" do
        assert_macro %({{x.targets}}), %([foo, bar]), {x: multi_assign_node}
      end

      it "executes values" do
        assert_macro %({{x.values}}), %([2, "a"]), {x: multi_assign_node}
      end
    end

    describe "instancevar methods" do
      it "executes name" do
        assert_macro %({{x.name}}), %(ivar), {x: InstanceVar.new("ivar")}
      end
    end

    describe "instancevar methods" do
      it "executes name" do
        assert_macro %({{x.name}}), %(ivar), {x: InstanceVar.new("ivar")}
      end
    end

    describe "readinstancevar methods" do
      it "executes obj" do
        assert_macro %({{x.obj}}), %(obj), {x: ReadInstanceVar.new("obj".var, "ivar")}
      end

      it "executes name" do
        assert_macro %({{x.name}}), %(ivar), {x: ReadInstanceVar.new("obj".var, "ivar")}
      end
    end

    describe "classvar methods" do
      it "executes name" do
        assert_macro %({{x.name}}), %(cvar), {x: ClassVar.new("cvar")}
      end
    end

    describe "global methods" do
      it "executes name" do
        assert_macro %({{x.name}}), %(gvar), {x: Global.new("gvar")}
      end
    end

    describe "splat methods" do
      it "executes exp" do
        assert_macro %({{x.exp}}), "2", {x: 2.int32.splat}
      end
    end

    describe "generic methods" do
      it "executes name" do
        assert_macro %({{x.name}}), "Foo", {x: Generic.new("Foo".path, ["T".path] of ASTNode)}
      end

      it "executes type_vars" do
        assert_macro %({{x.type_vars}}), "[T, U]", {x: Generic.new("Foo".path, ["T".path, "U".path] of ASTNode)}
        assert_macro %({{x.type_vars}}), "[]", {x: Generic.new("Foo".path, [] of ASTNode)}
      end

      it "executes named_args" do
        assert_macro %({{x.named_args}}), "{x: U, y: V}", {x: Generic.new("Foo".path, [] of ASTNode, named_args: [NamedArgument.new("x", "U".path), NamedArgument.new("y", "V".path)])}
      end

      it "executes resolve" do
        assert_macro %({{x.resolve}}), %(Array(String)), {x: Generic.new("Array".path, ["String".path] of ASTNode)}

        assert_macro_error %({{x.resolve}}), "undefined constant Foo", {x: Generic.new("Foo".path, ["String".path] of ASTNode)}
        assert_macro_error %({{x.resolve}}), "undefined constant Foo", {x: Generic.new("Array".path, ["Foo".path] of ASTNode)}
      end

      it "executes resolve?" do
        assert_macro %({{x.resolve?}}), %(Array(String)), {x: Generic.new("Array".path, ["String".path] of ASTNode)}
        assert_macro %({{x.resolve?}}), %(nil), {x: Generic.new("Foo".path, ["String".path] of ASTNode)}
        assert_macro %({{x.resolve?}}), %(nil), {x: Generic.new("Array".path, ["Foo".path] of ASTNode)}
      end

      it "executes types" do
        assert_macro %({{x.types}}), "[Foo(T)]", {x: Generic.new("Foo".path, ["T".path] of ASTNode)}
      end
    end

    describe "union methods" do
      it "executes types" do
        assert_macro %({{x.types}}), "[Int32, String]", {x: Crystal::Union.new(["Int32".path, "String".path] of ASTNode)}
      end

      it "executes resolve" do
        assert_macro %({{x.resolve}}), "(Int32 | String)", {x: Crystal::Union.new(["Int32".path, "String".path] of ASTNode)}
      end

      it "executes resolve?" do
        assert_macro %({{x.resolve?}}), "(Int32 | String)", {x: Crystal::Union.new(["Int32".path, "String".path] of ASTNode)}
        assert_macro %({{x.resolve?}}), "nil", {x: Crystal::Union.new(["Int32".path, "Unknown".path] of ASTNode)}
      end
    end

    describe RangeLiteral do
      it "executes begin" do
        assert_macro %({{x.begin}}), "1", {x: RangeLiteral.new(1.int32, 2.int32, true)}
      end

      it "executes end" do
        assert_macro %({{x.end}}), "2", {x: RangeLiteral.new(1.int32, 2.int32, true)}
      end

      it "executes excludes_end?" do
        assert_macro %({{x.excludes_end?}}), "true", {x: RangeLiteral.new(1.int32, 2.int32, true)}
      end

      it "executes map" do
        assert_macro %({{x.map(&.stringify)}}), %(["1", "2", "3"]), {x: RangeLiteral.new(1.int32, 3.int32, false)}
        assert_macro %({{x.map(&.stringify)}}), %(["1", "2"]), {x: RangeLiteral.new(1.int32, 3.int32, true)}
      end

      it "executes to_a" do
        assert_macro %({{x.to_a}}), %([1, 2, 3]), {x: RangeLiteral.new(1.int32, 3.int32, false)}
        assert_macro %({{x.to_a}}), %([1, 2]), {x: RangeLiteral.new(1.int32, 3.int32, true)}
      end

      it "#each" do
        assert_macro(
          %({% begin %}{% values = [] of Nil %}{% (1..3).each { |v| values << v } %}{{values}}{% end %}),
          %([1, 2, 3])
        )
      end
    end

    describe "path methods" do
      it "executes names" do
        assert_macro %({{x.names}}), %([String]), {x: Path.new("String")}
        assert_macro %({{x.names}}), %([Foo, Bar]), {x: Path.new("Foo", "Bar")}
      end

      it "executes global?" do
        assert_macro %({{x.global?}}), %(false), {x: Path.new("Foo")}
        assert_macro %({{x.global?}}), %(true), {x: Path.new("Foo", global: true)}
      end

      # TODO: remove deprecated tests
      it "executes global" do
        assert_macro %({{x.global}}), %(false), {x: Path.new("Foo")}
        assert_macro %({{x.global}}), %(true), {x: Path.new("Foo", global: true)}
      end

      it "executes resolve" do
        assert_macro %({{x.resolve}}), %(String), {x: Path.new("String")}

        assert_macro_error %({{x.resolve}}), "undefined constant Foo", {x: Path.new("Foo")}
      end

      it "executes resolve?" do
        assert_macro %({{x.resolve?}}), %(String), {x: Path.new("String")}
        assert_macro %({{x.resolve?}}), %(nil), {x: Path.new("Foo")}
      end

      it "executes types" do
        assert_macro %({{x.types}}), %([String]), {x: Path.new("String")}
      end
    end

    describe "annotation methods" do
      it "executes name" do
        assert_macro %({{x.name}}), %(Foo), {x: Annotation.new(Path.new("Foo"))}
        assert_macro %({{x.name}}), %(Foo::Bar), {x: Annotation.new(Path.new("Foo", "Bar"))}
      end

      it "executes [] with NumberLiteral" do
        assert_macro %({{x[y]}}), %(42), {
          x: Annotation.new(Path.new("Foo"), [42.int32] of ASTNode),
          y: 0.int32,
        }
      end

      it "executes [] with SymbolLiteral" do
        assert_macro %({{x[y]}}), %(42), {
          x: Annotation.new(Path.new("Foo"), [] of ASTNode, [NamedArgument.new("foo", 42.int32)]),
          y: "foo".symbol,
        }
      end

      it "executes [] with StringLiteral" do
        assert_macro %({{x[y]}}), %(42), {
          x: Annotation.new(Path.new("Foo"), [] of ASTNode, [NamedArgument.new("foo", 42.int32)]),
          y: "foo".string,
        }
      end

      it "executes [] with MacroId" do
        assert_macro %({{x[y]}}), %(42), {
          x: Annotation.new(Path.new("Foo"), [] of ASTNode, [NamedArgument.new("foo", 42.int32)]),
          y: MacroId.new("foo"),
        }
      end

      it "executes [] with other ASTNode, but raises an error" do
        assert_macro_error %({{x[y]}}), "argument to [] must be a number, symbol or string, not BoolLiteral", {
          x: Annotation.new(Path.new("Foo"), [] of ASTNode),
          y: true.bool,
        }
      end
    end

    describe ClassDef do
      class_def = ClassDef.new(Path.new("Foo"), abstract: true, superclass: Path.new("Parent"))
      struct_def = ClassDef.new(Path.new("Foo", "Bar", global: true), type_vars: %w(A B C D), splat_index: 2, struct: true, body: CharLiteral.new('a'))

      it "executes kind" do
        assert_macro %({{x.kind}}), %(class), {x: class_def}
        assert_macro %({{x.kind}}), %(struct), {x: struct_def}
      end

      it "executes name" do
        assert_macro %({{x.name}}), %(Foo), {x: class_def}
        assert_macro %({{x.name}}), %(::Foo::Bar(A, B, *C, D)), {x: struct_def}

        assert_macro %({{x.name(generic_args: true)}}), %(Foo), {x: class_def}
        assert_macro %({{x.name(generic_args: true)}}), %(::Foo::Bar(A, B, *C, D)), {x: struct_def}

        assert_macro %({{x.name(generic_args: false)}}), %(Foo), {x: class_def}
        assert_macro %({{x.name(generic_args: false)}}), %(::Foo::Bar), {x: struct_def}

        assert_macro_error %({{x.name(generic_args: 99)}}), "named argument 'generic_args' to ClassDef#name must be a BoolLiteral, not NumberLiteral", {x: class_def}
      end

      it "executes superclass" do
        assert_macro %({{x.superclass}}), %(Parent), {x: class_def}
        assert_macro %({{x.superclass}}), %(Parent(*T)), {x: ClassDef.new(Path.new("Foo"), superclass: Generic.new(Path.new("Parent"), [Splat.new(Path.new("T"))] of ASTNode))}
        assert_macro %({{x.superclass}}), %(), {x: struct_def}
      end

      it "executes type_vars" do
        assert_macro %({{x.type_vars}}), %([] of ::NoReturn), {x: class_def}
        assert_macro %({{x.type_vars}}), %([A, B, C, D]), {x: struct_def}
      end

      it "executes splat_index" do
        assert_macro %({{x.splat_index}}), %(nil), {x: class_def}
        assert_macro %({{x.splat_index}}), %(2), {x: struct_def}
      end

      it "executes body" do
        assert_macro %({{x.body}}), %(), {x: class_def}
        assert_macro %({{x.body}}), %('a'), {x: struct_def}
      end

      it "executes abstract?" do
        assert_macro %({{x.abstract?}}), %(true), {x: class_def}
        assert_macro %({{x.abstract?}}), %(false), {x: struct_def}
      end

      it "executes struct?" do
        assert_macro %({{x.struct?}}), %(false), {x: class_def}
        assert_macro %({{x.struct?}}), %(true), {x: struct_def}
      end
    end

    describe ModuleDef do
      module_def1 = ModuleDef.new(Path.new("Foo"))
      module_def2 = ModuleDef.new(Path.new("Foo", "Bar", global: true), type_vars: %w(A B C D), splat_index: 2, body: CharLiteral.new('a'))

      it "executes kind" do
        assert_macro %({{x.kind}}), %(module), {x: module_def1}
        assert_macro %({{x.kind}}), %(module), {x: module_def2}
      end

      it "executes name" do
        assert_macro %({{x.name}}), %(Foo), {x: module_def1}
        assert_macro %({{x.name}}), %(::Foo::Bar(A, B, *C, D)), {x: module_def2}

        assert_macro %({{x.name(generic_args: true)}}), %(Foo), {x: module_def1}
        assert_macro %({{x.name(generic_args: true)}}), %(::Foo::Bar(A, B, *C, D)), {x: module_def2}

        assert_macro %({{x.name(generic_args: false)}}), %(Foo), {x: module_def1}
        assert_macro %({{x.name(generic_args: false)}}), %(::Foo::Bar), {x: module_def2}

        assert_macro_error %({{x.name(generic_args: 99)}}), "named argument 'generic_args' to ModuleDef#name must be a BoolLiteral, not NumberLiteral", {x: module_def1}
      end

      it "executes type_vars" do
        assert_macro %({{x.type_vars}}), %([] of ::NoReturn), {x: module_def1}
        assert_macro %({{x.type_vars}}), %([A, B, C, D]), {x: module_def2}
      end

      it "executes splat_index" do
        assert_macro %({{x.splat_index}}), %(nil), {x: module_def1}
        assert_macro %({{x.splat_index}}), %(2), {x: module_def2}
      end

      it "executes body" do
        assert_macro %({{x.body}}), %(), {x: module_def1}
        assert_macro %({{x.body}}), %('a'), {x: module_def2}
      end
    end

    describe EnumDef do
      enum_def = EnumDef.new(Path.new("Foo", "Bar", global: true), [Path.new("X")] of ASTNode, Path.global("Int32"))

      it "executes kind" do
        assert_macro %({{x.kind}}), %(enum), {x: enum_def}
      end

      it "executes name" do
        assert_macro %({{x.name}}), %(::Foo::Bar), {x: enum_def}
        assert_macro %({{x.name(generic_args: true)}}), %(::Foo::Bar), {x: enum_def}
        assert_macro %({{x.name(generic_args: false)}}), %(::Foo::Bar), {x: enum_def}
        assert_macro_error %({{x.name(generic_args: 99)}}), "named argument 'generic_args' to EnumDef#name must be a BoolLiteral, not NumberLiteral", {x: enum_def}
      end

      it "executes base_type" do
        assert_macro %({{x.base_type}}), %(::Int32), {x: enum_def}
        assert_macro %({{x.base_type}}), %(), {x: EnumDef.new(Path.new("Baz"))}
      end

      it "executes body" do
        assert_macro %({{x.body}}), %(X), {x: enum_def}
      end
    end

    describe AnnotationDef do
      annotation_def = AnnotationDef.new(Path.new("Foo", "Bar", global: true))

      it "executes kind" do
        assert_macro %({{x.kind}}), %(annotation), {x: annotation_def}
      end

      it "executes name" do
        assert_macro %({{x.name}}), %(::Foo::Bar), {x: annotation_def}
        assert_macro %({{x.name(generic_args: true)}}), %(::Foo::Bar), {x: annotation_def}
        assert_macro %({{x.name(generic_args: false)}}), %(::Foo::Bar), {x: annotation_def}
        assert_macro_error %({{x.name(generic_args: 99)}}), "named argument 'generic_args' to AnnotationDef#name must be a BoolLiteral, not NumberLiteral", {x: annotation_def}
      end

      it "executes body" do
        assert_macro %({{x.body}}), %(), {x: annotation_def}
      end
    end

    describe LibDef do
      lib_def = LibDef.new(Path.new("Foo", "Bar", global: true), FunDef.new("foo"))

      it "executes kind" do
        assert_macro %({{x.kind}}), %(lib), {x: lib_def}
      end

      it "executes name" do
        assert_macro %({{x.name}}), %(::Foo::Bar), {x: lib_def}
        assert_macro %({{x.name(generic_args: true)}}), %(::Foo::Bar), {x: lib_def}
        assert_macro %({{x.name(generic_args: false)}}), %(::Foo::Bar), {x: lib_def}
        assert_macro_error %({{x.name(generic_args: 99)}}), "named argument 'generic_args' to LibDef#name must be a BoolLiteral, not NumberLiteral", {x: lib_def}
      end

      it "executes body" do
        assert_macro %({{x.body}}), %(fun foo), {x: lib_def}
      end
    end

    describe CStructOrUnionDef do
      c_struct_def = CStructOrUnionDef.new("Foo", TypeDeclaration.new("x".var, "Int".path))
      c_union_def = CStructOrUnionDef.new("Bar", Include.new("Foo".path), union: true)

      it "executes kind" do
        assert_macro %({{x.kind}}), %(struct), {x: c_struct_def}
        assert_macro %({{x.kind}}), %(union), {x: c_union_def}
      end

      it "executes name" do
        assert_macro %({{x.name}}), %(Foo), {x: c_struct_def}
        assert_macro %({{x.name(generic_args: true)}}), %(Foo), {x: c_struct_def}
        assert_macro %({{x.name(generic_args: false)}}), %(Foo), {x: c_struct_def}
        assert_macro_error %({{x.name(generic_args: 99)}}), "named argument 'generic_args' to CStructOrUnionDef#name must be a BoolLiteral, not NumberLiteral", {x: c_struct_def}
      end

      it "executes body" do
        assert_macro %({{x.body}}), %(x : Int), {x: c_struct_def}
        assert_macro %({{x.body}}), %(include Foo), {x: c_union_def}
      end

      it "executes union?" do
        assert_macro %({{x.union?}}), %(false), {x: c_struct_def}
        assert_macro %({{x.union?}}), %(true), {x: c_union_def}
      end
    end

    describe FunDef do
      lib_fun = FunDef.new("foo")
      top_level_fun = FunDef.new("bar", [Arg.new("x", restriction: "Int32".path), Arg.new("", restriction: "Char".path)], "Void".path, true, 1.int32, "y.z")
      top_level_fun2 = FunDef.new("baz", body: Nop.new)

      it "executes name" do
        assert_macro %({{x.name}}), %(foo), {x: lib_fun}
        assert_macro %({{x.name}}), %(bar), {x: top_level_fun}
      end

      it "executes real_name" do
        assert_macro %({{x.real_name}}), %(), {x: lib_fun}
        assert_macro %({{x.real_name}}), %("y.z"), {x: top_level_fun}
      end

      it "executes args" do
        assert_macro %({{x.args}}), %([]), {x: lib_fun}
        assert_macro %({{x.args}}), %([x : Int32,  : Char]), {x: top_level_fun}
      end

      it "executes variadic?" do
        assert_macro %({{x.variadic?}}), %(false), {x: lib_fun}
        assert_macro %({{x.variadic?}}), %(true), {x: top_level_fun}
      end

      it "executes return_type" do
        assert_macro %({{x.return_type}}), %(), {x: lib_fun}
        assert_macro %({{x.return_type}}), %(Void), {x: top_level_fun}
      end

      it "executes body" do
        assert_macro %({{x.body}}), %(), {x: lib_fun}
        assert_macro %({{x.body}}), %(1), {x: top_level_fun}
        assert_macro %({{x.body}}), %(), {x: top_level_fun2}
      end

      it "executes has_body?" do
        assert_macro %({{x.has_body?}}), %(false), {x: lib_fun}
        assert_macro %({{x.has_body?}}), %(true), {x: top_level_fun}
        assert_macro %({{x.has_body?}}), %(true), {x: top_level_fun2}
      end
    end

    describe TypeDef do
      type_def = TypeDef.new("Foo", Path.new("Bar", "Baz", global: true))

      it "executes name" do
        assert_macro %({{x.name}}), %(Foo), {x: type_def}
      end

      it "executes type" do
        assert_macro %({{x.type}}), %(::Bar::Baz), {x: type_def}
      end
    end

    describe ExternalVar do
      external_var1 = ExternalVar.new("foo", Path.new("Bar", "Baz"))
      external_var2 = ExternalVar.new("X", Generic.new(Path.global("Pointer"), ["Char".path] of ASTNode), real_name: "y.z")

      it "executes name" do
        assert_macro %({{x.name}}), %(foo), {x: external_var1}
        assert_macro %({{x.name}}), %(X), {x: external_var2}
      end

      it "executes real_name" do
        assert_macro %({{x.real_name}}), %(), {x: external_var1}
        assert_macro %({{x.real_name}}), %("y.z"), {x: external_var2}
      end

      it "executes type" do
        assert_macro %({{x.type}}), %(Bar::Baz), {x: external_var1}
        assert_macro %({{x.type}}), %(::Pointer(Char)), {x: external_var2}
      end
    end

    describe Asm do
      asm1 = Asm.new("nop")
      asm2 = Asm.new(
        text: "foo",
        outputs: [AsmOperand.new("=r", "x".var), AsmOperand.new("=r", "y".var)],
        inputs: [AsmOperand.new("i", 1.int32), AsmOperand.new("r", 2.int32)],
        clobbers: %w(rax memory),
        volatile: true,
        alignstack: true,
        intel: true,
        can_throw: true,
      )

      it "executes text" do
        assert_macro %({{x.text}}), %("nop"), {x: asm1}
        assert_macro %({{x.text}}), %("foo"), {x: asm2}
      end

      it "executes outputs" do
        assert_macro %({{x.outputs}}), %([] of ::NoReturn), {x: asm1}
        assert_macro %({{x.outputs}}), %(["=r"(x), "=r"(y)]), {x: asm2}
      end

      it "executes inputs" do
        assert_macro %({{x.inputs}}), %([] of ::NoReturn), {x: asm1}
        assert_macro %({{x.inputs}}), %(["i"(1), "r"(2)]), {x: asm2}
      end

      it "executes clobbers" do
        assert_macro %({{x.clobbers}}), %([] of ::NoReturn), {x: asm1}
        assert_macro %({{x.clobbers}}), %(["rax", "memory"]), {x: asm2}
      end

      it "executes volatile?" do
        assert_macro %({{x.volatile?}}), %(false), {x: asm1}
        assert_macro %({{x.volatile?}}), %(true), {x: asm2}
      end

      it "executes alignstack?" do
        assert_macro %({{x.alignstack?}}), %(false), {x: asm1}
        assert_macro %({{x.alignstack?}}), %(true), {x: asm2}
      end

      it "executes intel?" do
        assert_macro %({{x.intel?}}), %(false), {x: asm1}
        assert_macro %({{x.intel?}}), %(true), {x: asm2}
      end

      it "executes can_throw?" do
        assert_macro %({{x.can_throw?}}), %(false), {x: asm1}
        assert_macro %({{x.can_throw?}}), %(true), {x: asm2}
      end
    end

    describe AsmOperand do
      asm_operand1 = AsmOperand.new("=r", "x".var)
      asm_operand2 = AsmOperand.new("i", 1.int32)

      it "executes constraint" do
        assert_macro %({{x.constraint}}), %("=r"), {x: asm_operand1}
        assert_macro %({{x.constraint}}), %("i"), {x: asm_operand2}
      end

      it "executes exp" do
        assert_macro %({{x.exp}}), %(x), {x: asm_operand1}
        assert_macro %({{x.exp}}), %(1), {x: asm_operand2}
      end
    end

    describe "env" do
      it "has key" do
        with_env("FOO": "foo") do
          assert_macro %({{env("FOO")}}), %("foo")
        end
      end

      it "doesn't have key" do
        with_env("FOO": nil) do
          assert_macro %({{env("FOO")}}), %(nil)
        end
      end
    end

    describe "flag?" do
      it "has flag" do
        assert_macro %({{flag?(:foo)}}), %(true), flags: "foo"
      end

      it "doesn't have flag" do
        assert_macro %({{flag?(:foo)}}), %(false)
      end
    end

    it "compares versions" do
      assert_macro %({{compare_versions("1.10.3", "1.2.3")}}), %(1)
    end

    describe "#warning" do
      it "emits a top level warning" do
        assert_warning <<-CRYSTAL, "Oh noes"
          macro test
            {% warning "Oh noes" %}
          end

          test
        CRYSTAL
      end
    end

    describe "#parse_type" do
      it "path" do
        assert_type(%[class Bar; end; {{ parse_type("Bar").is_a?(Path) ? 1 : 'a'}}]) { int32 }
        assert_type(%[class Bar; end; {{ parse_type(:Bar.id.stringify).is_a?(Path) ? 1 : 'a'}}]) { int32 }
      end

      it "generic" do
        assert_type(%[class Foo(A, B); end; {{ parse_type("Foo(Int32, String)").resolve.type_vars.size == 2 ? 1 : 'a' }}]) { int32 }
      end

      it "union - |" do
        assert_type(%[class Foo; end; class Bar; end; {{ parse_type("Foo|Bar").resolve.union_types.size == 2 ? 1 : 'a' }}]) { int32 }
      end

      it "union - Union" do
        assert_type(%[class Foo; end; class Bar; end; {{ parse_type("Union(Foo,Bar)").resolve.union_types.size == 2 ? 1 : 'a' }}]) { int32 }
      end

      it "union - in generic" do
        assert_type(%[{{ parse_type("Array(Int32 | String)").resolve.type_vars[0].union_types.size == 2 ? 1 : 'a' }}]) { int32 }
      end

      it "proc" do
        assert_type(%[{{ parse_type("String, Int32 -> Bool").inputs.size == 2 ? 1 : 'a' }}]) { int32 }
        assert_type(%[{{ parse_type("String, Int32 -> Bool").output.resolve == Bool ? 1 : 'a' }}]) { int32 }
      end

      it "metaclass" do
        assert_type(%[{{ parse_type("Int32.class").resolve == Int32.class ? 1 : 'a' }}]) { int32 }
        assert_type(%[{{ parse_type("Int32").resolve == Int32.instance ? 1 : 'a' }}]) { int32 }
      end

      it "raises on empty string" do
        expect_raises(Crystal::TypeException, "argument to parse_type cannot be an empty value") do
          assert_macro %({{parse_type ""}}), %(nil)
        end
      end

      it "raises on extra unparsed tokens before the type" do
        expect_raises(Crystal::TypeException, %(Invalid type name: "100Foo")) do
          assert_macro %({{parse_type "100Foo" }}), %(nil)
        end
      end

      it "raises on extra unparsed tokens after the type" do
        expect_raises(Crystal::TypeException, %(Invalid type name: "Foo(Int32)100")) do
          assert_macro %({{parse_type "Foo(Int32)100" }}), %(nil)
        end
      end

      it "raises on non StringLiteral arguments" do
        expect_raises(Crystal::TypeException, "argument to parse_type must be a StringLiteral, not SymbolLiteral") do
          assert_macro %({{parse_type :Foo }}), %(nil)
        end
      end

      it "exposes syntax warnings" do
        assert_warning %({% parse_type "Foo(0x8000_0000_0000_0000)" %}), "Warning: 0x8000_0000_0000_0000 doesn't fit in an Int64, try using the suffix u64 or i128"
      end
    end

    describe "printing" do
      it "puts" do
        String.build do |io|
          assert_macro(%({% puts foo %}), "") do |program|
            program.stdout = io
            {foo: "bar".string}
          end
        end.should eq %(bar\n)
      end

      it "print" do
        String.build do |io|
          assert_macro(%({% print foo %}), "") do |program|
            program.stdout = io
            {foo: "bar".string}
          end
        end.should eq %(bar)
      end

      it "p" do
        String.build do |io|
          assert_macro(%({% p foo %}), "") do |program|
            program.stdout = io
            {foo: "bar".string}
          end
        end.should eq %("bar"\n)
      end

      it "p!" do
        String.build do |io|
          assert_macro("{% p! foo %}", "") do |program|
            program.stdout = io
            {foo: "bar".string}
          end
        end.should eq %(foo # => "bar"\n)
      end

      it "pp" do
        String.build do |io|
          assert_macro("{% pp foo %}", "") do |program|
            program.stdout = io
            {foo: "bar".string}
          end
        end.should eq %("bar"\n)
      end

      it "pp!" do
        String.build do |io|
          assert_macro("{% pp! foo %}", "") do |program|
            program.stdout = io
            {foo: "bar".string}
          end
        end.should eq %(foo # => "bar"\n)
      end
    end
  end

  describe "file_exists?" do
    context "with absolute path" do
      it "returns true if file exists" do
        run(%q<
          {{file_exists?("#{__DIR__}/../data/build")}} ? 10 : 20
          >, filename: __FILE__).to_i.should eq(10)
      end

      it "returns false if file doesn't exist" do
        run(%q<
          {{file_exists?("#{__DIR__}/../data/build_foo")}} ? 10 : 20
          >, filename: __FILE__).to_i.should eq(20)
      end
    end

    context "with relative path" do
      it "reads file (exists)" do
        run(%q<
          {{file_exists?("spec/compiler/data/build")}} ? 10 : 20
          >, filename: __FILE__).to_i.should eq(10)
      end

      it "reads file (doesn't exist)" do
        run(%q<
          {{file_exists?("spec/compiler/data/build_foo")}} ? 10 : 20
          >, filename: __FILE__).to_i.should eq(20)
      end
    end
  end

  describe "read_file" do
    context "with absolute path" do
      it "reads file (exists)" do
        run(%q<
          {{read_file("#{__DIR__}/../data/build")}}
          >, filename: __FILE__).to_string.should eq(File.read("#{__DIR__}/../data/build"))
      end

      it "reads file (doesn't exist)" do
        assert_error <<-CRYSTAL,
          {{read_file("#{__DIR__}/../data/build_foo")}}
          CRYSTAL
          "Error opening file with mode 'r'"
      end
    end

    context "with relative path" do
      it "reads file (exists)" do
        run(%q<
          {{read_file("spec/compiler/data/build")}}
          >, filename: __FILE__).to_string.should eq(File.read("spec/compiler/data/build"))
      end

      it "reads file (doesn't exist)" do
        assert_error <<-CRYSTAL,
          {{read_file("spec/compiler/data/build_foo")}}
          CRYSTAL
          "Error opening file with mode 'r'"
      end
    end
  end

  describe "read_file?" do
    context "with absolute path" do
      it "reads file (doesn't exist)" do
        run(%q<
          {{read_file?("#{__DIR__}/../data/build_foo")}} ? 10 : 20
          >, filename: __FILE__).to_i.should eq(20)
      end
    end

    context "with relative path" do
      it "reads file (doesn't exist)" do
        run(%q<
          {{read_file?("spec/compiler/data/build_foo")}} ? 10 : 20
          >, filename: __FILE__).to_i.should eq(20)
      end
    end
  end

  describe ".system" do
    it "command does not exist" do
      assert_error %({{ `commanddoesnotexist` }}), "error executing command: commanddoesnotexist"
    end

    it "successful command" do
      assert_macro %({{ `#{exit_code_command(0)}` }}), ""
    end

    it "successful command with output" do
      assert_macro %({{ `#{shell_command("echo foobar")}` }}), "foobar#{newline}"
    end

    it "failing command" do
      assert_error %({{ `#{exit_code_command(1)}` }}), "error executing command: #{exit_code_command(1)}, got exit status 1"
      assert_error %({{ `#{exit_code_command(2)}` }}), "error executing command: #{exit_code_command(2)}, got exit status 2"
      assert_error %({{ `#{exit_code_command(127)}` }}), "error executing command: #{exit_code_command(127)}, got exit status 127"
    end
  end

  describe "error reporting" do
    it "reports wrong number of arguments" do
      assert_macro_error %({{[1, 2, 3].push}}), "wrong number of arguments for macro 'ArrayLiteral#push' (given 0, expected 1)"
    end

    it "reports wrong number of arguments, with optional parameters" do
      assert_macro_error %({{1.+(2, 3)}}), "wrong number of arguments for macro 'NumberLiteral#+' (given 2, expected 0..1)"
      assert_macro_error %({{[1][]}}), "wrong number of arguments for macro 'ArrayLiteral#[]' (given 0, expected 1..2)"
    end

    it "reports unexpected block" do
      assert_macro_error %({{[1, 2, 3].shuffle { |x| }}}), "macro 'ArrayLiteral#shuffle' is not expected to be invoked with a block, but a block was given"
    end

    it "reports missing block" do
      assert_macro_error %({{[1, 2, 3].reduce}}), "macro 'ArrayLiteral#reduce' is expected to be invoked with a block, but no block was given"
    end

    it "reports unexpected named argument" do
      assert_macro_error %({{"".starts_with?(other: "")}}), "named arguments are not allowed here"
    end

    it "reports unexpected named argument (2)" do
      assert_macro_error %({{"".camelcase(foo: "")}}), "no named parameter 'foo'"
    end

    # there are no macro methods with required named parameters

    it "uses correct name for top-level macro methods" do
      assert_macro_error %({{flag?}}), "wrong number of arguments for macro '::flag?' (given 0, expected 1)"
    end
  end

  describe "immutability of returned container literals (#10818)" do
    it "Annotation#args" do
      node = Annotation.new(Path.new("Foo"), [42.int32, "a".string] of ASTNode)
      assert_macro %({{ (x.args << "a"; x.args.size) }}), "2", {x: node}
    end

    it "Generic#type_vars" do
      node = Generic.new("Foo".path, ["Bar".path, "Int32".path] of ASTNode)
      assert_macro %({{ (x.type_vars << "a"; x.type_vars.size) }}), "2", {x: node}
    end

    it "MultiAssign#targets" do
      node = MultiAssign.new(["foo".var, "bar".var] of ASTNode, [2.int32, "a".string] of ASTNode)
      assert_macro %({{ (x.targets << "a"; x.targets.size) }}), "2", {x: node}
    end

    it "MultiAssign#values" do
      node = MultiAssign.new(["foo".var, "bar".var] of ASTNode, [2.int32, "a".string] of ASTNode)
      assert_macro %({{ (x.values << "a"; x.values.size) }}), "2", {x: node}
    end

    it "ProcNotation#inputs" do
      node = ProcNotation.new([Path.new("SomeType"), Path.new("OtherType")] of ASTNode)
      assert_macro %({{ (x.inputs << "a"; x.inputs.size) }}), "2", {x: node}
    end

    it "ProcPointer#args" do
      node = ProcPointer.new(Var.new("some_object"), "method", [Path.new("SomeType"), Path.new("OtherType")] of ASTNode)
      assert_macro %({{ (x.args << "a"; x.args.size) }}), "2", {x: node}
    end

    it "StringInterpolation#expressions" do
      node = StringInterpolation.new(["fo".string, 1.int32, "o".string] of ASTNode)
      assert_macro %({{ (x.expressions << "a"; x.expressions.size) }}), "3", {x: node}
    end

    it "Union#types" do
      node = Crystal::Union.new(["Int32".path, "String".path] of ASTNode)
      assert_macro %({{ (x.types << "a"; x.types.size) }}), "2", {x: node}
    end

    it "When#conds" do
      node = When.new([2.int32, 3.int32] of ASTNode, 4.int32)
      assert_macro %({{ (x.conds << "a"; x.conds.size) }}), "2", {x: node}
    end
  end
end
