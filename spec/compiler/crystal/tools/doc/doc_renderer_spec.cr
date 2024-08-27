require "../../../spec_helper"

private def assert_code_link(obj, before, after = before)
  renderer = Doc::MarkdDocRenderer.new(obj, Markd::Options.new)
  renderer.expand_code_links(before).should eq(after)
end

private def it_renders(context, input, output, file = __FILE__, line = __LINE__)
  it "renders #{input.inspect}", file, line do
    c = context
    c ||= begin
      program = Program.new
      generator = Doc::Generator.new(program, [""])
      generator.type(program)
    end
    options = Markd::Options.new
    document = Markd::Parser.parse(input, options)
    renderer = Doc::MarkdDocRenderer.new(c, options)

    renderer.render(document).chomp.should eq(output), file: file, line: line
  end
end

describe Doc::MarkdDocRenderer do
  describe "expand_code_links" do
    program = semantic("
      class Base
        def foo
        end
        def bar
        end
        def self.baz
        end

        def foo2(a, b)
        end
        def foo3(a, b, c)
        end

        def que?
        end
        def one!(one)
        end

        def <=(other)
        end

        class Nested
          CONST = true

          def foo
          end
        end
      end

      class Sub < Base
        def foo
        end
      end

      class A
        def foo; end
        def bar; end
        def self.baz; end
      end
      ", wants_doc: true).program
    generator = Doc::Generator.new(program, [""])

    base = generator.type(program.types["Base"])
    base_foo = base.lookup_method("foo").not_nil!
    sub = generator.type(program.types["Sub"])
    sub_foo = sub.lookup_method("foo").not_nil!
    nested = generator.type(program.types["Base"].types["Nested"])
    nested_foo = nested.lookup_method("foo").not_nil!
    single_char_class = generator.type(program.types["A"])
    single_char_class_foo = single_char_class.lookup_method("foo").not_nil!

    it "finds sibling methods" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "bar", %(<a href="Base.html#bar-instance-method">#bar</a>))
        assert_code_link(obj, "baz", %(<a href="Base.html#baz-class-method">.baz</a>))
      end
    end

    it "finds sibling methods" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "#bar", %(<a href="Base.html#bar-instance-method">#bar</a>))
        assert_code_link(obj, ".baz", %(<a href="Base.html#baz-class-method">.baz</a>))
      end
    end

    it "matches methods on single-character class names" do
      {single_char_class, single_char_class_foo}.each do |obj|
        assert_code_link(obj, "#bar", %(<a href="A.html#bar-instance-method">#bar</a>))
        assert_code_link(obj, ".baz", %(<a href="A.html#baz-class-method">.baz</a>))
      end
    end

    it "doesn't spuriously match range literals" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "(0..baz)")
        assert_code_link(obj, "(0...baz)")
        assert_code_link(obj, "0..baz")
        assert_code_link(obj, "0...baz")
      end
    end

    it "doesn't find substrings for methods" do
      assert_code_link(base_foo, "not bar")
      assert_code_link(base_foo, "bazzy")
    end

    it "doesn't find sibling methods of wrong type" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "Wrong#bar")
        assert_code_link(obj, "Wrong.bar")
      end
    end

    it "doesn't find sibling methods with fake receiver" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "wrong#bar")
        assert_code_link(obj, "wrong.bar")
      end
    end

    it "finds sibling methods with self receiver" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "self.bar", %(self<a href="Base.html#bar-instance-method">.bar</a>))
      end
    end

    it "doesn't find parents' methods" do
      {sub, sub_foo, nested, nested_foo}.each do |obj|
        assert_code_link(obj, "bar")
        assert_code_link(obj, "baz")
      end
    end

    it "doesn't find parents' methods" do
      {sub, sub_foo, nested, nested_foo}.each do |obj|
        assert_code_link(obj, "#bar")
        assert_code_link(obj, ".baz")
      end
    end

    it "doesn't match with different separator" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, ",baz")
        assert_code_link(obj, "Base:bar", %(<a href="Base.html">Base</a>:bar))
      end
    end

    it "finds method with args" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "foo2(a, b)", %(<a href="Base.html#foo2%28a%2Cb%29-instance-method">#foo2(a, b)</a>))
        assert_code_link(obj, "#foo2(a, a)", %(<a href="Base.html#foo2%28a%2Cb%29-instance-method">#foo2(a, a)</a>))
        assert_code_link(obj, "Base#foo2(a, a)", %(<a href="Base.html#foo2%28a%2Cb%29-instance-method">Base#foo2(a, a)</a>))
      end
    end

    it "finds method with zero args" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "bar()", %(<a href="Base.html#bar-instance-method">#bar()</a>))
        assert_code_link(obj, "#bar()", %(<a href="Base.html#bar-instance-method">#bar()</a>))
        assert_code_link(obj, "Base#bar()", %(<a href="Base.html#bar-instance-method">Base#bar()</a>))
      end
    end

    it "doesn't find method with wrong number of args" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "#foo2(a, a, a, a)")
        assert_code_link(obj, "#bar(a)")
      end
    end

    it "doesn't find method with wrong number of args" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "Base#foo2(a)")
        assert_code_link(obj, "Base#bar(a)")
      end
    end

    it "finds method with unspecified args" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "foo2", %(<a href="Base.html#foo2%28a%2Cb%29-instance-method">#foo2</a>))
        assert_code_link(obj, "#foo2", %(<a href="Base.html#foo2%28a%2Cb%29-instance-method">#foo2</a>))
        assert_code_link(obj, "Base#foo2", %(<a href="Base.html#foo2%28a%2Cb%29-instance-method">Base#foo2</a>))
      end
    end

    it "finds method with args even with empty brackets" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "foo2()", %(<a href="Base.html#foo2%28a%2Cb%29-instance-method">#foo2()</a>))
        assert_code_link(obj, "#foo2()", %(<a href="Base.html#foo2%28a%2Cb%29-instance-method">#foo2()</a>))
        assert_code_link(obj, "Base#foo2()", %(<a href="Base.html#foo2%28a%2Cb%29-instance-method">Base#foo2()</a>))
      end
    end

    it "finds method with question mark" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "que?", %(<a href="Base.html#que%3F-instance-method">#que?</a>))
        assert_code_link(obj, "#que?", %(<a href="Base.html#que%3F-instance-method">#que?</a>))
        assert_code_link(obj, "Base#que?", %(<a href="Base.html#que%3F-instance-method">Base#que?</a>))
      end
    end

    it "finds method with exclamation mark" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "one!(one)", %(<a href="Base.html#one%21%28one%29-instance-method">#one!(one)</a>))
        assert_code_link(obj, "#one!(one)", %(<a href="Base.html#one%21%28one%29-instance-method">#one!(one)</a>))
        assert_code_link(obj, "Base#one!(one)", %(<a href="Base.html#one%21%28one%29-instance-method">Base#one!(one)</a>))
      end
    end

    it "finds operator method" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "<=(other)", %(<a href="Base.html#%3C%3D%28other%29-instance-method">#<=(other)</a>))
        assert_code_link(obj, "#<=(other)", %(<a href="Base.html#%3C%3D%28other%29-instance-method">#<=(other)</a>))
        assert_code_link(obj, "Base#<=(other)", %(<a href="Base.html#%3C%3D%28other%29-instance-method">Base#<=(other)</a>))
      end
    end

    it "finds operator method with unspecified args" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "<=", %(<a href="Base.html#%3C%3D%28other%29-instance-method">#<=</a>))
        assert_code_link(obj, "#<=", %(<a href="Base.html#%3C%3D%28other%29-instance-method">#<=</a>))
        assert_code_link(obj, "Base#<=", %(<a href="Base.html#%3C%3D%28other%29-instance-method">Base#<=</a>))
      end
    end

    it "finds methods of a type" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "Base#bar", %(<a href="Base.html#bar-instance-method">Base#bar</a>))
        assert_code_link(obj, "Base.baz", %(<a href="Base.html#baz-class-method">Base.baz</a>))
      end
    end

    it "finds method of an absolute type" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "::Base::Nested#foo", %(<a href="Base/Nested.html#foo-instance-method">::Base::Nested#foo</a>))
        assert_code_link(obj, "::Base.baz", %(<a href="Base.html#baz-class-method">::Base.baz</a>))
      end
    end

    pending "doesn't find wrong kind of sibling methods" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, ".bar")
        assert_code_link(obj, "#baz")
      end
    end

    pending "doesn't find wrong kind of methods" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "Base.bar")
        assert_code_link(obj, "Base#baz")
      end
    end

    it "finds multiple methods with brackets" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "#foo2(a, a) and Base#foo3(a,b,  c)",
          %(<a href="Base.html#foo2%28a%2Cb%29-instance-method">#foo2(a, a)</a> and <a href="Base.html#foo3%28a%2Cb%2Cc%29-instance-method">Base#foo3(a,b,  c)</a>))
      end
    end

    it "finds types from base" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "Base and Sub and Nested",
          %(<a href="Base.html">Base</a> and <a href="Sub.html">Sub</a> and <a href="Base/Nested.html">Nested</a>))
      end
    end

    it "finds types from nested" do
      {nested, nested_foo}.each do |obj|
        assert_code_link(obj, "Base and Sub and Nested",
          %(<a href="../Base.html">Base</a> and <a href="../Sub.html">Sub</a> and <a href="../Base/Nested.html">Nested</a>))
      end
    end

    it "finds constant" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "Nested::CONST", %(<a href="Base/Nested.html#CONST">Nested::CONST</a>))
      end
    end

    it "finds nested type" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "Base::Nested", %(<a href="Base/Nested.html">Base::Nested</a>))
      end
    end

    it "finds absolute type" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "::Base::Nested",
          %(<a href="Base/Nested.html">::Base::Nested</a>))
      end
    end

    it "doesn't find wrong absolute type" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "::Nested")
      end
    end

    it "doesn't find type not at word boundary" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "aBase")
      end
    end

    it "finds multiple kinds of things" do
      {base, base_foo}.each do |obj|
        assert_code_link(obj, "Base#foo2(a, a) and #foo3 and Base",
          %(<a href="Base.html#foo2%28a%2Cb%29-instance-method">Base#foo2(a, a)</a> and <a href="Base.html#foo3%28a%2Cb%2Cc%29-instance-method">#foo3</a> and <a href="Base.html">Base</a>))
      end
    end

    it "does not break when referencing lib type (#9928)" do
      program = semantic("lib LibFoo; BAR = 0; end", wants_doc: true).program
      generator = Doc::Generator.new(program, [""])

      # TODO: There should not be a link to LibFoo::Bar in the first place
      # because LibFoo is undocumented
      assert_code_link(generator.type(program), "LibFoo::BAR", %(<a href="LibFoo.html#BAR">LibFoo::BAR</a>))
    end
  end

  describe "renders code blocks" do
    it_renders nil, "```crystal\nHello\nWorld\n```", %(<pre><code class="language-crystal"><span class="t">Hello</span>\n<span class="t">World</span></code></pre>)
    it_renders nil, "```cr\nHello\nWorld\n```", %(<pre><code class="language-crystal"><span class="t">Hello</span>\n<span class="t">World</span></code></pre>)
    it_renders nil, "```\nHello\nWorld\n```", %(<pre><code class="language-crystal"><span class="t">Hello</span>\n<span class="t">World</span></code></pre>)
  end

  describe "renders code spans" do
    it_renders nil, "`<style>`", %(<p><code>&lt;style&gt;</code></p>)
  end

  describe "renders links" do
    it_renders nil, "[foo](http://example.com/foo)", %(<p><a href="http://example.com/foo">foo</a></p>)

    program = semantic("class Foo; end", wants_doc: true).program
    it_renders Doc::Generator.new(program, [""]).type(program), "[`Foo`](http://example.com/foo)", %(<p><a href="http://example.com/foo"><code>Foo</code></a></p>)

    it_renders nil, %([filter](https://docs.celestine.dev/Celestine/Meta/Context.html#filter(&block:Celestine::Filter-%3ECelestine::Filter)-instance-method)),
      %(<p><a href="https://docs.celestine.dev/Celestine/Meta/Context.html#filter(&amp;block:Celestine::Filter-%3ECelestine::Filter)-instance-method">filter</a></p>)
  end

  describe "renders headline" do
    it_renders nil, "## Foo Bar", <<-HTML
    <h2><a id="foo-bar" class="anchor" href="#foo-bar">  <svg class="octicon-link" aria-hidden="true">
        <use href="#octicon-link"/>
      </svg>
    </a>Foo Bar</h2>
    HTML

    it_renders nil, "## Foo Bar\n### Sub\n## Bar Baz\n### Sub", <<-HTML
    <h2><a id="foo-bar" class="anchor" href="#foo-bar">  <svg class="octicon-link" aria-hidden="true">
        <use href="#octicon-link"/>
      </svg>
    </a>Foo Bar</h2>
    <h3><a id="sub" class="anchor" href="#sub">\n  <svg class="octicon-link" aria-hidden="true">
        <use href="#octicon-link"/>
      </svg>
    </a>Sub</h3>
    <h2><a id="bar-baz" class="anchor" href="#bar-baz">\n  <svg class="octicon-link" aria-hidden="true">
        <use href="#octicon-link"/>
      </svg>
    </a>Bar Baz</h2>
    <h3><a id="sub-1" class="anchor" href="#sub-1">\n  <svg class="octicon-link" aria-hidden="true">
        <use href="#octicon-link"/>
      </svg>
    </a>Sub</h3>
    HTML
  end

  {% if !flag?(:without_libxml2) %}
    describe "renders html with sanitization" do
      it_renders nil, %(<h1 align="center">Foo</h1>), %(<h1>Foo</h1>)
      it_renders nil, %(<script>alert("hello world")</script>), %()
      it_renders nil, %(<p style="font-size: 100px">example text</p></div>), %(<p>example text</p>)

      it_renders nil, %(```crystal\n# <script>alert("hello world")</script>\n```),
        %(<pre><code class="language-crystal"><span class="c"># &lt;script&gt;alert(&quot;hello world&quot;)&lt;/script&gt;</span></code></pre>)
    end

    describe "still renders tables despite sanitization" do
      table_mkdn = <<-HTML
        <table>
          <tr>
            <th>column 1</th>
            <th>column 2</th>
          </tr>
          <tr>
            <td>data 1</td>
            <td>data 2</td>
          </tr>
          <tr>
            <td>data 3</td>
            <td>data 4</td>
          </tr>
        </table>
      HTML

      it_renders nil, table_mkdn, table_mkdn
    end
  {% end %}
end
