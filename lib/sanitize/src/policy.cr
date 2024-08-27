# A policy defines the rules for transforming an HTML/XML tree.
#
# * `HTMLSanitizer` is a policy for HTML sanitization.
# * `Whitelist` is a whitelist-based transformer that's useful either for
#    simple stripping applications or as a building block for more advanced
#    sanitization policies.
# * `Text` is a policy that turns HTML into plain text.
abstract class Sanitize::Policy
  # :nodoc:
  alias CONTINUE = Processor::CONTINUE
  # :nodoc:
  alias STOP = Processor::STOP

  # Defines the string that is added when whitespace is needed when a block tag
  # is stripped.
  property block_whitespace = " "

  # Receives the content of a text node and returns the transformed content.
  #
  # If the return value is `nil`, the content is skipped.
  abstract def transform_text(text : String) : String?

  # Receives the element name and attributes of an opening tag and returns the
  # transformed element name (usually the same as the input name).
  #
  # *attributes* are transformed directly in place.
  #
  # Special return values:
  # * `Processor::CONTINUE`: Tells the processor to strip the current tag but
  #   continue traversing its children.
  # * `Processor::CONTINUE`: Tells the processor to skip the current tag and its
  #   children completely and move to the next sibling.
  abstract def transform_tag(name : String, attributes : Hash(String, String)) : String | Processor::CONTINUE | Processor::STOP

  HTML_BLOCK_ELEMENTS = Set{
    "address", "article", "aside", "audio", "video", "blockquote", "br",
    "canvas", "dd", "div", "dl", "fieldset", "figcaption", "figure", "footer",
    "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr",
    "noscript", "ol", "output", "p", "pre", "section", "table", "tfoot", "ul",
  }

  def block_tag?(name)
    HTML_BLOCK_ELEMENTS.includes?(name)
  end
end
