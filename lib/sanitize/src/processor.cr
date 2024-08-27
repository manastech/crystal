require "xml"
require "log"
require "./adapter/libxml2"

module Sanitize
  abstract class Policy
    # Processes the HTML fragment *html* with this policy using the default
    # adapter (`Adapter::LibXML2`).
    def process(html : String | XML::Node) : String
      Adapter::LibXML2.process(self, html, fragment: true)
    end

    # Processes the HTML document *html* with this policy using the default
    # adapter (`Adapter::LibXML2`).
    def process_document(html : String | XML::Node) : String
      Adapter::LibXML2.process(self, html, fragment: false)
    end
  end

  module Adapter
    abstract def write_text(text : String) : Nil
    abstract def start_tag(name : String, attributes : Hash(String, String)) : Nil
    abstract def end_tag(name : String, attributes : Hash(String, String)) : Nil
  end

  # A processor traverses the HTML/XML tree, applies transformations through the
  # policy and passes the result to the adapter which then builds the result.
  class Processor
    Log = ::Log.for(self)

    # This module serves as a singleton constant that signals the processor to
    # skip the current tag but continue to traverse its children.
    module CONTINUE
      extend self
    end

    # This module serves as a singleton constant that signals the processor to
    # skip the current tag and its children.
    module STOP
      extend self
    end

    @last_text_ended_with_whitespace = true
    @stripped_block_tag = false

    def initialize(@policy : Policy, @adapter : Adapter)
    end

    def process_text(text : String)
      text = @policy.transform_text(text)

      if @stripped_block_tag && !@last_text_ended_with_whitespace && !text.try(&.[0].whitespace?)
        @adapter.write_text(@policy.block_whitespace)
      end

      @stripped_block_tag = false

      if text
        @adapter.write_text(text)
        @last_text_ended_with_whitespace = text.[-1].whitespace?
      else
        @last_text_ended_with_whitespace = false
      end
    end

    def process_element(name : String, attributes : Hash(String, String), &)
      process_element(name, attributes, @policy.transform_tag(name, attributes)) do
        yield
      end
    end

    def process_element(orig_name : String, attributes : Hash(String, String), name, &)
      case name
      when STOP
        Log.debug { "#{@policy.class} stopping at tag #{orig_name} #{attributes}" }
        if @policy.block_tag?(orig_name)
          @stripped_block_tag = true
        end
        return
      when CONTINUE
        Log.debug { "#{@policy.class} stripping tag #{orig_name} #{attributes}" }
        if @policy.block_tag?(orig_name)
          @stripped_block_tag = true
        end
      when String
        @stripped_block_tag = false
        @adapter.start_tag(name, attributes)
      end

      yield

      case name
      when CONTINUE
        if @policy.block_tag?(orig_name)
          @stripped_block_tag = true
        end
      when String
        @stripped_block_tag = false
        @adapter.end_tag(name, attributes)
      end
    end

    def reset
      @last_text_ended_with_whitespace = true
      @stripped_block_tag = false
    end
  end
end

require "./adapter/libxml2"
