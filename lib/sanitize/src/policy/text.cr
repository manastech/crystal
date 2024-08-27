require "../policy"

# Reduces an HTML tree to the content of its text nodes.
# It renders a plain text result, similar to copying HTML content rendered by
# a browser to a text editor.
# HTML special characters are escaped.
#
# ```
# policy = Sanitize::Policy::Text.new
# policy.process(%(foo <strong><a href="bar">bar</a>!</strong>)) # => "foo bar!"
# policy.process(%(<p>foo</p><p>bar</p>))                        # => "foo bar"
# policy.block_whitespace = "\n"
# policy.process(%(<p>foo</p><p>bar</p>)) # => "foo\nbar"
# ```
class Sanitize::Policy::Text < Sanitize::Policy
  def transform_text(text : String) : String?
    text
  end

  def transform_tag(name : String, attributes : Hash(String, String)) : String | CONTINUE | STOP
    CONTINUE
  end
end
