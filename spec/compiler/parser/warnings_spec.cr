require "../../support/syntax"

private def assert_parser_warning(source, message, *, file = __FILE__, line = __LINE__)
  parser = Parser.new(source)
  parser.filename = "/test.cr"
  parser.parse

  warnings = parser.warnings.infos
  warnings.size.should eq(1), file: file, line: line
  warnings[0].should contain(message), file: file, line: line
end

private def assert_no_parser_warning(source, *, file = __FILE__, line = __LINE__)
  parser = Parser.new(source)
  parser.filename = "/test.cr"
  parser.parse

  warnings = parser.warnings.infos
  warnings.should eq([] of String), file: file, line: line
end

describe "Parser warnings" do
  it "warns on suffix-less UInt64 literals > Int64::MAX" do
    values = [
      "9223372036854775808", # Int64::MAX + 1
      "9999999999999999999",
      "10000000000000000000",
      "18446744073709551615", # UInt64::MAX
      "0x8000_0000_0000_0000",
      "0xFFFF_FFFF_FFFF_FFFF",
    ]

    values.each do |value|
      assert_parser_warning value, "Warning: #{value} doesn't fit in an Int64, try using the suffix u64 or i128"
      assert_parser_warning "Foo(#{value})", "Warning: #{value} doesn't fit in an Int64, try using the suffix u64 or i128"
      assert_parser_warning "{{ #{value} }}", "Warning: #{value} doesn't fit in an Int64, try using the suffix u64 or i128"
    end
  end

  describe "warns on missing space before colon" do
    it "in block param type restriction" do
      assert_parser_warning("def foo(&block: Foo)\nend", "warning in /test.cr:1\nWarning: space required before colon in type restriction (run `crystal tool format` to fix this)")
      assert_no_parser_warning("def foo(&block : Foo)\nend")
      assert_no_parser_warning("def foo(&@foo)\nend")
    end

    it "in anonymous block param type restriction" do
      assert_parser_warning("def foo(&: Foo)\nend", "warning in /test.cr:1\nWarning: space required before colon in type restriction (run `crystal tool format` to fix this)")
      assert_no_parser_warning("def foo(& : Foo)\nend")
      assert_no_parser_warning("def foo(&)\nend")
    end

    it "in type declaration" do
      assert_parser_warning("x: Int32", "warning in /test.cr:1\nWarning: space required before colon in type declaration (run `crystal tool format` to fix this)")
      assert_no_parser_warning("x : Int32")
      assert_parser_warning("class Foo\n@x: Int32\nend", "warning in /test.cr:2\nWarning: space required before colon in type declaration (run `crystal tool format` to fix this)")
      assert_no_parser_warning("class Foo\n@x : Int32\nend")
      assert_parser_warning("class Foo\n@@x: Int32\nend", "warning in /test.cr:2\nWarning: space required before colon in type declaration (run `crystal tool format` to fix this)")
      assert_no_parser_warning("class Foo\n@@x : Int32\nend")
    end

    it "in return type restriction" do
      assert_parser_warning("def foo: Foo\nend", "warning in /test.cr:1\nWarning: space required before colon in return type restriction (run `crystal tool format` to fix this)")
      assert_no_parser_warning("def foo : Foo\nend")
    end
  end

  Char::Reader.new("abcdefghjklmnopstuvyzABCDEFGHIJKLMNOPRSTUVWXYZ").each do |letter|
    it "warns on single-letter macro fresh variable %#{letter}" do
      assert_parser_warning <<-EOS, "Warning: don't use single-letter fresh variable identifiers"
        macro foo
          {% for i in 1..6 %}
            %#{letter}{i} = {{ i }}
          {% end %}
        end
        EOS
    end
  end
end
