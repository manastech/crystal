require "json"

module Markd
  module Utils
    def self.timer(label : String, measure_time? : Bool, &)
      return yield unless measure_time?

      start_time = Time.utc
      yield

      puts "#{label}: #{(Time.utc - start_time).total_milliseconds}ms"
    end

    DECODE_ENTITIES_REGEX = Regex.new("\\\\" + Rule::ESCAPABLE_STRING, Regex::Options::IGNORE_CASE)

    def self.decode_entities_string(text : String) : String
      HTML.decode_entities(text).gsub(DECODE_ENTITIES_REGEX) { |text| text[1].to_s }
    end
  end
end
