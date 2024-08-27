require "./whitelist"
require "../uri_sanitizer"

# This policy serves as a good default configuration that should fit most
# typical use cases for HTML sanitization.
#
# ## Configurations
# It comes in three different configurations with different sets of supported
# HTML tags.
#
# They only differ in the default configuration of allowed tags and attributes.
# The transformation behaviour is otherwise the same.
#
# ### Common Configuration
# `.common`: Accepts most standard tags and thus allows using a good
# amount of HTML features (see `COMMON_SAFELIST`).
#
# This is the recommended default configuration and should work for typical use
# cases unless strong restrictions on allowed content is required.
#
# ```
# sanitizer = Sanitize::Policy::HTMLSanitizer.common
# sanitizer.process(%(<a href="javascript:alert('foo')">foo</a>))        # => %(foo)
# sanitizer.process(%(<p><a href="foo">foo</a></p>))                     # => %(<p><a href="foo" rel="nofollow">foo</a></p>)
# sanitizer.process(%(<img src="foo.jpg">))                              # => %(<img src="foo.jpg">)
# sanitizer.process(%(<table><tr><td>foo</td><td>bar</td></tr></table>)) # => %(<table><tr><td>foo</td><td>bar</td></tr></table>)
# ```
#
# NOTE: This configuration (nor any other) does not accept `&lt;html&gt;`,
# `&lt;head&gt;`, or # `&lt;body&gt;` tags by default. In order to use
# `#sanitized_document` they need to be added explicitly to `accepted_arguments`.
#
# ### Basic Configuration
#
# `.basic`: This set accepts some basic tags including paragraphs, headlines,
# lists, and images (see `BASIC_SAFELIST`).
#
# ```
# sanitizer = Sanitize::Policy::HTMLSanitizer.basic
# sanitizer.process(%(<a href="javascript:alert('foo')">foo</a>))        # => %(foo)
# sanitizer.process(%(<p><a href="foo">foo</a></p>))                     # => %(<p><a href="foo" rel="nofollow">foo</a></p>)
# sanitizer.process(%(<img src="foo.jpg">))                              # => %(<img src="foo.jpg">)
# sanitizer.process(%(<table><tr><td>foo</td><td>bar</td></tr></table>)) # => %(foo bar)
# ```
#
# ### Inline Configuration
#
# `.inline`: Accepts only a limited set of inline tags (see `INLINE_SAFELIST`).
#
# ```
# sanitizer = Sanitize::Policy::HTMLSanitizer.inline
# sanitizer.process(%(<a href="javascript:alert('foo')">foo</a>))        # => %(foo)
# sanitizer.process(%(<p><a href="foo">foo</a></p>))                     # => %(<a href="foo" rel="nofollow">foo</a>)
# sanitizer.process(%(<img src="foo.jpg">))                              # => %()
# sanitizer.process(%(<table><tr><td>foo</td><td>bar</td></tr></table>)) # => %(foo bar)
# ```
#
# ## Attribute Transformations
#
# Attribute transformations are identical in all three configurations. But more
# advanced transforms won't apply if the respective attribute is not allowed in
# `accepted_tags`.
# So you can easily add additional elements and attributes to lower-tier sets
# and get the same attribute validation. For example: `.inline` doesn't include
# `&lt;img&gt;` tags, but when `img` is added to `accepted_attributes`,
# the policy validates img tags the same way as in `.common`.
#
# ### URL Sanitization
#
# This transformation applies to attributes that contain a URL (configurable
# through (`url_attributes`).
#
# * Makes sure the value is a valid URI (via `URI.parse`). If it does not parse,
#   the attribute value is set to empty string.
# * Sanitizes the URI via `URISanitizer (configurable trough `uri_sanitizer`).
#   If the sanitizer returns `nil`, the attribute value is set to empty string.
#
# The same `URISanitizer` is used for any URL attributes.
#
# ### Anchor Tags
#
# For `&lt;a&gt;` tags with a `href` attribute, there are two transforms:
#
# * `rel="nofollow"` is added (can be disabled with `add_rel_nofollow`).
# * `rel="noopener"` is added to links with `target` attribute (can be disabled
#   with `add_rel_noopener`).
#
# Anchor tags the have neither a `href`, `name` or `id` attribute are stripped.
#
# NOTE: `name` and `id` attributes are not in any of the default sets of
# accepted attributes, so they can only be used when explicitly enabled.
#
# ### Image Tags
#
# `&lt;img&gt;` tags are stripped if they don't have a `src` attribute.
#
# ### Size Attributes
#
# If a tag has `width` or `height` attributes, the values are validated to be
# numerical or percent values.
# By default, these attributes are only accepted for &lt;img&gt; tags.
#
# ### Alignment Attribute
#
# The `align` attribute is validated against allowed values for this attribute:
# `center, left, right, justify, char`.
# If the value is invalid, the attribute is stripped.
#
# ### Classes
#
# `class` attributes are filtered to accept only classes described by
# `valid_classes`. String values need to match the class name exactly, regex
# values need to match the entire class name.
#
# `class` is accepted as a global attribute in the default configuration, but no
# values are allowed in `valid_classes`.
#
# All classes can be accepted by adding the match-all regular expression `/.*/`
# to `valid_classes`.
class Sanitize::Policy::HTMLSanitizer < Sanitize::Policy::Whitelist
  # Add `rel="nofollow"` to every `&lt;a&gt;` tag with `href` attribute.
  property add_rel_nofollow = true

  # Add `rel="noopener"` to every `&lt;a&gt;` tag with `href` and `target` attribute.
  property add_rel_noopener = true

  # Configures the `URISanitizer` to use for sanitizing URL attributes.
  property uri_sanitizer = URISanitizer.new

  # Configures which attributes are considered to contain URLs. If empty, URL
  # sanitization is disabled.
  #
  # Default value: `Set{"src", "href", "action", "cite", "longdesc"}`.
  property url_attributes : Set(String) = Set{"src", "href", "action", "cite", "longdesc"}

  # Configures which classes are valid for `class` attributes.
  #
  # String values need to match the class name exactly, regex
  # values need to match the entire class name.
  #
  # Default value: empty
  property valid_classes : Set(String | Regex) = Set(String | Regex).new

  def valid_classes=(classes)
    valid_classes = classes.map(&.as(String | Regex)).to_set
  end

  # Creates an instance which accepts a limited set of inline tags (see
  # `INLINE_SAFELIST`).
  def self.inline : HTMLSanitizer
    new(
      accepted_attributes: INLINE_SAFELIST.clone
    )
  end

  # Creates an instance which accepts more basic tags including paragraphs,
  # headlines, lists, and images (see `BASIC_SAFELIST`).
  def self.basic : HTMLSanitizer
    new(
      accepted_attributes: BASIC_SAFELIST.clone
    )
  end

  # Creates an instance which accepts even more standard tags and thus allows
  # using a good amount of HTML features (see `COMMON_SAFELIST`).
  #
  # Unless you need tight restrictions on allowed content, this is the
  # recommended default.
  def self.common : HTMLSanitizer
    new(
      accepted_attributes: COMMON_SAFELIST.clone
    )
  end

  # Removes anchor tag (`&lt;a&gt;` from the list of accepted tags).
  #
  # NOTE: This doesn't reject attributes with URL values for other tags.
  def no_links
    accepted_attributes.delete("a")

    self
  end

  def accept_tag(tag : String, attributes : Set(String) = Set(String).new)
    accepted_attributes[tag] = attributes
  end

  def transform_attributes(tag : String, attributes : Hash(String, String)) : String | CONTINUE | STOP
    transform_url_attributes(tag, attributes)

    tag_result = case tag
                 when "a"
                   transform_tag_a(attributes)
                 when "img"
                   transform_tag_img(attributes)
                 end

    if tag_result
      return tag_result
    end

    limit_numeric_or_percent(attributes, "width")
    limit_numeric_or_percent(attributes, "height")
    limit_enum(attributes, "align", ["center", "left", "right", "justify", "char"])

    transform_classes(tag, attributes)

    tag
  end

  def transform_tag_img(attributes)
    unless attributes.has_key?("src")
      return CONTINUE
    end
  end

  def transform_tag_a(attributes)
    if href = attributes["href"]?
      if add_rel_nofollow
        append_attribute(attributes, "rel", "nofollow")
      end
      if add_rel_noopener && attributes.has_key?("target")
        append_attribute(attributes, "rel", "noopener")
      end
    end
    if !(((href = attributes["href"]?) && !href.empty?) || attributes.has_key?("id") || attributes.has_key?("tag"))
      return CONTINUE
    end
  end

  def transform_url_attributes(tag, attributes)
    all_ok = true
    url_attributes.each do |key|
      if value = attributes[key]?
        all_ok &&= transform_url_attribute(tag, attributes, key, value)
      end
    end
    all_ok
  end

  def transform_url_attribute(tag, attributes, attribute, value)
    begin
      uri = URI.parse(value.strip)
    rescue URI::Error
      attributes[attribute] = ""
      return false
    end

    uri = transform_uri(tag, attributes, attribute, uri)
    if uri.nil? || (uri.blank? || uri == "#")
      attributes[attribute] = ""
      return false
    end

    attributes[attribute] = uri
    true
  end

  def transform_uri(tag, attributes, attribute, uri : URI) : String?
    if uri_sanitizer = self.uri_sanitizer
      uri = uri_sanitizer.sanitize(uri)

      return unless uri
    end

    # Make sure special characters are properly encoded to avoid interpretation
    # of tweaked relative paths as "javascript:" URI (for example)
    if path = uri.path
      uri.path = String.build do |io|
        URI.encode(URI.decode(path), io) { |byte| URI.reserved?(byte) || URI.unreserved?(byte) }
      end
    end

    uri.to_s
  end

  def transform_classes(tag, attributes)
    attribute = attributes["class"]?
    return unless attribute

    classes = attribute.split
    classes = classes.select { |klass| valid_class?(tag, klass, valid_classes) }
    if classes.empty?
      attributes.delete("class")
    else
      attributes["class"] = classes.join(" ")
    end
  end

  private def limit_numeric_or_percent(attributes, attribute)
    if value = attributes[attribute]?
      value = value.strip
      if value.ends_with?("%")
        value = value.byte_slice(0, value.size - 1)
      end
      value.each_char do |char|
        unless char.ascii_number?
          attributes.delete(attribute)
          break
        end
      end
    end
  end

  private def limit_enum(attributes, attribute, list)
    if value = attributes[attribute]?
      value = value.strip
      if valid_with_list?(value, list)
        attributes[attribute] = value
      else
        attributes.delete(attribute)
      end
    end
  end

  def valid_class?(tag, klass, valid_classes)
    valid_with_list?(klass, valid_classes)
  end

  private def valid_with_list?(value, list)
    list.any? { |validator|
      case validator
      when String
        validator == value
      when Regex
        data = validator.match(value)
        next unless data
        data.byte_begin == 0 && data.byte_end == value.bytesize
      end
    }
  end

  def append_attribute(attributes, attribute, value)
    if curr_value = attributes[attribute]?
      values = curr_value.split
      if values.includes?(value)
        return false
      else
        values << value
        attributes[attribute] = values.join(" ")
      end
    else
      attributes[attribute] = value
    end

    true
  end
end

require "./html_sanitizer/safelist"
