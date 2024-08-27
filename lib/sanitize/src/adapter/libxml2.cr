struct Sanitize::Adapter::LibXML2
  include Adapter

  def self.process(policy : Policy, html : String, fragment : Bool = false)
    return "" if html.empty?

    node = parse(html, fragment)
    process(policy, node, fragment)
  end

  def self.process(policy : Policy, node : XML::Node, fragment : Bool = false)
    build(fragment) do |builder|
      process(policy, node, builder, fragment)
    end
  end

  def self.process(policy : Policy, node : XML::Node, builder : XML::Builder, fragment : Bool = false)
    processor = Processor.new(policy, new(builder))
    visit(processor, node, fragment)
    builder.end_document
    builder.flush
  end

  def self.parse(html : String, fragment : Bool)
    if fragment
      html = "<html><body>#{html}</body></html>"
    end

    node = XML.parse_html(html, XML::HTMLParserOptions.default | XML::HTMLParserOptions::NOIMPLIED | XML::HTMLParserOptions::NODEFDTD)
  end

  def self.build(fragment : Bool)
    result = String.build do |io|
      builder = XML::Builder.new(io)

      if fragment
        builder.start_element("fragment")
      end

      yield(builder)
    end

    if fragment
      result = "" if result == "<fragment/>\n"
      result = result.lchop("<fragment>").rchop("</fragment>\n")
    end
    # strip trailing non-linebreak whitespace
    if result.ends_with?("\n")
      result
    else
      result.rstrip
    end
  end

  def self.visit(processor : Processor, node : XML::Node, fragment : Bool)
    visitor = Visitor.new(processor, fragment)
    visitor.visit(node)
  end

  # :nodoc:
  struct Visitor
    @attributes = Hash(String, String).new

    def initialize(@processor : Processor, @fragment : Bool)
    end

    # :nodoc:
    def visit(node : XML::Node)
      case node.type
      when .html_document_node?
        visit_children(node)
      when .dtd_node?
        # skip DTD
      when .text_node?
        visit_text(node)
      when .element_node?
        visit_element(node)
      when .comment_node?
        # skip comments
      when .cdata_section_node?
        # skip CDATA
      else
        raise "Not implemented for: #{node.type}:#{node.name}:#{node.content}"
      end
    end

    def visit_children(node)
      node.children.each do |child|
        visit(child)
      end
    end

    def visit_text(node)
      @processor.process_text(node.content)
    end

    def visit_element(node)
      if @fragment && node.name.in?({"html", "body"})
        @attributes.clear
        @processor.process_element(node.name, @attributes, Processor::CONTINUE) do
          visit_children(node)
        end
        return
      end

      @attributes.clear
      node.attributes.each do |attribute|
        @attributes[attribute.name] = attribute.content
      end

      name = node.name
      if namespace = node.namespace
        name = "#{namespace}:#{name}"
      end

      @processor.process_element(name, @attributes) do
        visit_children(node)
      end
    end
  end

  def initialize(@builder : XML::Builder)
  end

  def start_tag(name : String, attributes : Hash(String, String)) : Nil
    @builder.start_element(name)
    @builder.attributes(attributes)
  end

  def end_tag(name : String, attributes : Hash(String, String)) : Nil
    @builder.end_element
  end

  def write_text(text : String) : Nil
    @builder.text(text)
  end
end
