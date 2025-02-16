require "./libxml2"
require "./parser_options"

# `XML::Reader` is a parser for XML that iterates a XML document.
#
# ```
# require "xml"
#
# reader = XML::Reader.new(<<-XML)
#   <message>Hello XML!</message>
#   XML
# reader.read
# reader.name # => "message"
# reader.read
# reader.value # => "Hello XML!"
# ```
#
# This is an alternative approach to `XML.parse` which parses an entire document
# into an XML data structure.
# `XML::Reader` offers more control and does not need to store the XML document
# in memory entirely. The latter is especially useful for large documents with
# the `IO`-based constructor.
#
# WARNING: This type is not concurrency-safe.
class XML::Reader
  # Returns the errors reported while parsing.
  getter errors = [] of XML::Error

  # Creates a new reader from a string.
  #
  # See `XML::ParserOptions.default` for default options.
  def initialize(str : String, options : XML::ParserOptions = XML::ParserOptions.default)
    @reader = LibXML.xmlReaderForMemory(str, str.bytesize, nil, nil, options)
    LibXML.xmlTextReaderSetErrorHandler @reader, ->(arg, msg, severity, locator) do
      msg_str = String.new(msg).chomp
      line_number = LibXML.xmlTextReaderLocatorLineNumber(locator)
      raise Error.new(msg_str, line_number)
    end
  end

  # Creates a new reader from an IO.
  #
  # See `XML::ParserOptions.default` for default options.
  def initialize(io : IO, options : XML::ParserOptions = XML::ParserOptions.default)
    @reader = LibXML.xmlReaderForIO(
      ->(context, buffer, length) { Box(IO).unbox(context).read(Slice.new(buffer, length)).to_i },
      ->(context) { Box(IO).unbox(context).close; 0 },
      Box(IO).box(io),
      nil,
      nil,
      options
    )
  end

  # Moves the reader to the next node.
  def read : Bool
    collect_errors { LibXML.xmlTextReaderRead(@reader) == 1 }
  end

  # Moves the reader to the next node while skipping subtrees.
  def next : Bool
    LibXML.xmlTextReaderNext(@reader) == 1
  end

  # Moves the reader to the next sibling node while skipping subtrees.
  def next_sibling : Bool
    result = LibXML.xmlTextReaderNextSibling(@reader)
    # Work around libxml2 with incomplete xmlTextReaderNextSibling()
    # see: https://gitlab.gnome.org/GNOME/libxml2/issues/7
    if result == -1
      node = LibXML.xmlTextReaderCurrentNode(@reader)
      if node.null?
        collect_errors { LibXML.xmlTextReaderRead(@reader) == 1 }
      elsif !node.value.next.null?
        LibXML.xmlTextReaderNext(@reader) == 1
      else
        false
      end
    else
      result == 1
    end
  end

  # Returns the `XML::Reader::Type` of the node.
  def node_type : XML::Reader::Type
    LibXML.xmlTextReaderNodeType(@reader)
  end

  # Returns the name of the node.
  def name : String
    value = LibXML.xmlTextReaderConstName(@reader)
    value ? String.new(value) : ""
  end

  # Checks if the node is an empty element.
  def empty_element? : Bool
    LibXML.xmlTextReaderIsEmptyElement(@reader) == 1
  end

  # Checks if the node has any attributes.
  def has_attributes? : Bool
    LibXML.xmlTextReaderHasAttributes(@reader) == 1
  end

  # Returns attribute count of the node.
  def attributes_count : Int32
    LibXML.xmlTextReaderAttributeCount(@reader)
  end

  # Moves to the first `XML::Reader::Type::ATTRIBUTE` of the node.
  def move_to_first_attribute : Bool
    LibXML.xmlTextReaderMoveToFirstAttribute(@reader) == 1
  end

  # Moves to the next `XML::Reader::Type::ATTRIBUTE` of the node.
  def move_to_next_attribute : Bool
    LibXML.xmlTextReaderMoveToNextAttribute(@reader) == 1
  end

  # Moves to the `XML::Reader::Type::ATTRIBUTE` with the specified name.
  def move_to_attribute(name : String) : Bool
    check_no_null_byte(name)
    LibXML.xmlTextReaderMoveToAttribute(@reader, name) == 1
  end

  # Gets the attribute content for the *attribute* given by name.
  # Raises `KeyError` if attribute is not found.
  def [](attribute : String) : String
    self[attribute]? || raise(KeyError.new("Missing attribute: #{attribute}"))
  end

  # Gets the attribute content for the *attribute* given by name.
  # Returns `nil` if attribute is not found.
  def []?(attribute : String) : String?
    check_no_null_byte(attribute)
    value = LibXML.xmlTextReaderGetAttribute(@reader, attribute)
    String.new(value) if value
  end

  # Moves from the `XML::Reader::Type::ATTRIBUTE` to its containing `XML::Reader::Type::ELEMENT`.
  def move_to_element : Bool
    LibXML.xmlTextReaderMoveToElement(@reader) == 1
  end

  # Returns the current nesting depth of the reader.
  def depth : Int32
    LibXML.xmlTextReaderDepth(@reader)
  end

  # Returns the node's XML content including subtrees.
  def read_inner_xml : String
    xml = collect_errors { LibXML.xmlTextReaderReadInnerXml(@reader) }
    xml ? String.new(xml) : ""
  end

  # Returns the XML for the node and its content including subtrees.
  def read_outer_xml : String
    # On a NONE type libxml2 2.9.9 is giving a segfault:
    #
    #   https://gitlab.gnome.org/GNOME/libxml2/issues/43
    #
    # so we avoid the issue by returning early here.
    #
    # FIXME: if that issue is fixed we should revert this line
    # to avoid doing an extra C call each time.
    return "" if node_type.none?

    xml = collect_errors { LibXML.xmlTextReaderReadOuterXml(@reader) }
    xml ? String.new(xml) : ""
  end

  # Expands the node to a `XML::Node` that can be searched with XPath etc.
  # The returned `XML::Node` is only valid until the next call to `#read`.
  #
  # Raises a `XML::Error` if the node could not be expanded.
  def expand : XML::Node
    expand? || raise XML::Error.new LibXML.xmlGetLastError
  end

  # Expands the node to a `XML::Node` that can be searched with XPath etc.
  # The returned `XML::Node` is only valid until the next call to `#read`.
  #
  # Returns `nil` if the node could not be expanded.
  def expand? : XML::Node?
    xml = LibXML.xmlTextReaderExpand(@reader)
    XML::Node.new(xml) if xml
  end

  # Returns the text content of the node.
  def value : String
    value = LibXML.xmlTextReaderConstValue(@reader)
    value ? String.new(value) : ""
  end

  def column_number : Int32
    LibXML.xmlTextReaderGetParserColumnNumber(@reader)
  end

  def line_number : Int32
    LibXML.xmlTextReaderGetParserLineNumber(@reader)
  end

  # Returns a reference to the underlying `LibXML::XMLTextReader`.
  def to_unsafe
    @reader
  end

  private def collect_errors(&)
    Error.collect(@errors) { yield }
  end

  private def check_no_null_byte(attribute)
    if attribute.byte_index(0)
      raise XML::Error.new("Invalid attribute name: #{attribute.inspect} (contains null character)", 0)
    end
  end
end
