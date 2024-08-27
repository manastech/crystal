require "../policy"

# This is a simple policy based on a tag and attribute whitelist.
#
# This policy accepts only `&lt;div&gt;` and `&lt;p&gt;` tags with optional `title` attributes:
# ```
# policy = Sanitize::Policy::Whitelist.new({
#   "div" => Set{"title"},
#   "p"   => Set{"title"},
# })
# ```
#
# The special `*` key applies to *all* tag names and can be used to allow global
# attributes:
#
# This example is equivalent to the above. If more tag names were added, they
# would also accept `title` attributes.
# ```
# policy = Sanitize::Policy::Whitelist.new({
#   "div" => Set(String).new,
#   "p"   => Set(String).new,
#   "*"   => Set{"title"},
# })
# ```
#
# Attributes are always optional, so this policy won't enforce the presence of
# an attribute.
#
# If a tag's attribute list is empty, no attributes are allowed for this tag.
#
# Attribute values are not changed by this policy.
class Sanitize::Policy::Whitelist < Sanitize::Policy
  # Mapping of accepted tag names and attributes.
  property accepted_attributes : Hash(String, Set(String))

  # Short cut to `accepted_attributes["*"]`.
  getter global_attributes : Set(String) { accepted_attributes.fetch("*") { Set(String).new } }

  def initialize(@accepted_attributes : Hash(String, Set(String)))
  end

  def transform_text(text : String) : String?
    text
  end

  def transform_tag(name : String, attributes : Hash(String, String)) : String | CONTINUE | STOP
    acceptable_attributes = accepted_attributes.fetch(name) { return CONTINUE }

    attributes.reject! { |attr, _| !acceptable_attributes.includes?(attr) && !global_attributes.includes?(attr) }

    transform_attributes(name, attributes)
  end

  def transform_attributes(name : String, attributes : Hash(String, String)) : String | CONTINUE | STOP
    name
  end
end
