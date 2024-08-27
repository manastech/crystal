require "./support/hrx"
require "../src/policy/text"
require "../src/processor"

describe Sanitize::Policy::Text do
  it "continues on tag" do
    Sanitize::Policy::Text.new.transform_tag("foo", {} of String => String).should eq Sanitize::Policy::CONTINUE
  end

  it "adds whitespace" do
    Sanitize::Policy::Text.new.process("foo<br/>bar").should eq "foo bar"
  end

  run_hrx_samples Path["./text_policy.hrx"], {
    "text" => Sanitize::Policy::Text.new,
  }
end
