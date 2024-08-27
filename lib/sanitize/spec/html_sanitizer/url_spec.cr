require "../support/hrx"
require "../../src/policy/html_sanitizer"

describe "Sanitize::Policy::HTMLSanitizer" do
  it "escapes URL attribute" do
    Sanitize::Policy::HTMLSanitizer.common.process(%(<img src="jav&#13;ascript:alert('%20');"/>)).should eq %(<img src="jav%0Dascript:alert('%20');"/>)
  end
end
