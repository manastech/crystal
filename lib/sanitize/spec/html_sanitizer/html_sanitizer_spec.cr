require "../support/hrx"
require "../../src/policy/html_sanitizer"

describe Sanitize::Policy::HTMLSanitizer do
  it "removes invalid element" do
    Sanitize::Policy::HTMLSanitizer.common.process("<p>foo<invalid>bar</p>").should eq "<p>foobar</p>"
  end

  it "inserts whitespace for removed block tag" do
    Sanitize::Policy::HTMLSanitizer.common.process("<p>foo<article>bar</article>baz</p>").should eq "<p>foo bar baz</p>"
  end

  it "strips tag with invalid URL attribute" do
    Sanitize::Policy::HTMLSanitizer.common.process(%(<img src="foo:bar">)).should eq %(<img src=""/>)
    Sanitize::Policy::HTMLSanitizer.common.process(%(<a href="foo:bar">foo</a>)).should eq "foo"
  end

  it "escapes URL attribute" do
    Sanitize::Policy::HTMLSanitizer.common.process(%(<img src="jav&#13;ascript:alert('%20');"/>)).should eq %(<img src="jav%0Dascript:alert('%20');"/>)
  end

  it %(adds rel="noopener" on target="_blank") do
    policy = Sanitize::Policy::HTMLSanitizer.common
    policy.process(%(<a href="foo" target="_blank">foo</a>)).should eq(%(<a href="foo" rel="nofollow">foo</a>))
    policy.accepted_attributes["a"] << "target"
    policy.process(%(<a href="foo" target="_blank">foo</a>)).should eq(%(<a href="foo" target="_blank" rel="nofollow noopener">foo</a>))
  end

  it "doesn't leak configuration" do
    policy = Sanitize::Policy::HTMLSanitizer.common
    policy.accepted_attributes["p"] << "invalid"
    policy.process(%(<p invalid="foo">bar</p>)).should eq(%(<p invalid="foo">bar</p>))
    Sanitize::Policy::HTMLSanitizer.common.process(%(<p invalid="foo">bar</p>)).should eq(%(<p>bar</p>))
  end

  describe "html scaffold" do
    it "fragment" do
      Sanitize::Policy::HTMLSanitizer.common.process("<html><head><title>FOO</title></head><body><p>BAR</p></body>").should eq "FOO<p>BAR</p>"
    end

    it "document" do
      sanitizer = Sanitize::Policy::HTMLSanitizer.common
      sanitizer.accept_tag("html")
      sanitizer.accept_tag("head")
      sanitizer.accept_tag("body")
      sanitizer.process_document("<html><head><title>FOO</title></head><body><p>BAR</p></body>").should eq "<html><head>FOO</head><body><p>BAR</p></body></html>\n"
    end
  end

  describe "#transform_classes" do
    it "strips classes by default" do
      policy = Sanitize::Policy::HTMLSanitizer.inline
      orig_attributes = {"class" => "foo bar baz"}
      attributes = orig_attributes.clone
      policy.transform_classes("div", attributes)
      attributes.should eq Hash(String, String).new
    end

    it "accepts classes" do
      policy = Sanitize::Policy::HTMLSanitizer.inline
      orig_attributes = {"class" => "foo bar baz"}
      attributes = orig_attributes.clone

      policy.valid_classes << /fo*/
      policy.valid_classes << "bar"
      policy.transform_classes("div", attributes)
      attributes.should eq({"class" => "foo bar"})
    end

    it "only matches full class name" do
      policy = Sanitize::Policy::HTMLSanitizer.inline
      orig_attributes = {"class" => "foobar barfoo barfoobaz foo fom"}
      attributes = orig_attributes.clone

      policy.valid_classes << /fo./
      policy.transform_classes("div", attributes)
      attributes.should eq({"class" => "foo fom"})
    end
  end

  run_hrx_samples Path["basic.hrx"], {
    "common" => Sanitize::Policy::HTMLSanitizer.common,
  }
  run_hrx_samples Path["protocol_javascript.hrx"], {
    "common" => Sanitize::Policy::HTMLSanitizer.common,
  }
  run_hrx_samples Path["links.hrx"], {
    "common" => Sanitize::Policy::HTMLSanitizer.common,
  }
  run_hrx_samples Path["xss.hrx"], {
    "common" => Sanitize::Policy::HTMLSanitizer.common,
  }
  run_hrx_samples Path["img.hrx"], {
    "common" => Sanitize::Policy::HTMLSanitizer.common,
  }
  run_hrx_samples Path["class.hrx"], {
    "common"       => Sanitize::Policy::HTMLSanitizer.common,
    "allow-prefix" => Sanitize::Policy::HTMLSanitizer.common.tap { |sanitizer|
      sanitizer.valid_classes = Set{/allowed-.+/, "explicitly-allowed"}
    },
  }
end
