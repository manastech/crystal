require "./spec/dsl"
require "./spec/cli"

# Crystal's built-in testing library. It provides a structure for writing executable examples
# of how your code should behave. A domain specific language allows you to write them in a way similar to natural language.
#
# The Crystal compiler has a `spec` command with tools to constrain which examples get run and tailor the output.
#
# A basic spec looks something like this:
#
# ```
# require "spec"
#
# describe Array do
#   describe "#size" do
#     it "correctly reports the number of elements in the Array" do
#       [1, 2, 3].size.should eq 3
#     end
#   end
#
#   describe "#empty?" do
#     it "is empty when no elements are in the array" do
#       ([] of Int32).empty?.should be_true
#     end
#
#     it "is not empty if there are elements in the array" do
#       [1].empty?.should be_false
#     end
#   end
#
#   # lots more specs
# end
# ```
#
# Test files are structured by use of the `describe` or `context` methods.
# Typically a top level `describe` defines the `outer` unit (such as a class)
# that is to be tested by the spec. Further `describe` calls can be nested within
# the outer unit to specify smaller units under test (such as individual methods).
# `describe` can also be used to set up a certain context - think empty `Array` versus
# `Array` with elements. The `context` method behaves just like the `describe` method
# and may be used instead, to emphasize context to the reader.
#
# Within a `describe` block, concrete test cases are defined with `it` . A
# descriptive string is supplied to `it` describing what the test case
# tests specifically.
#
# Specs then use the `should` method to verify that the expected value is
# returned. See the example above for details.
#
# By convention, specs live in the `spec` directory of a project. You can compile
# and run the specs of a project by running `crystal spec`.
#
# ```console
# # Run all specs in files matching spec/**/*_spec.cr
# crystal spec
#
# # Run all specs in files matching spec/my/test/**/*_spec.cr
# crystal spec spec/my/test/
#
# # Run all specs in spec/my/test/file_spec.cr
# crystal spec spec/my/test/file_spec.cr
#
# # Run the spec or group defined in line 14 of spec/my/test/file_spec.cr
# crystal spec spec/my/test/file_spec.cr:14
#
# # Run all specs tagged with "fast"
# crystal spec --tag 'fast'
#
# # Run all specs not tagged with "slow"
# crystal spec --tag '~slow'
# ```
#
# ## Focusing on a group of specs
#
# A `describe`, `context` or `it` can be marked with `focus: true`, like this:
#
# ```
# it "adds", focus: true do
#   (2 + 2).should_not eq(5)
# end
# ```
#
# If any such thing is marked with `focus: true` then only those examples will run.
#
# ## Randomizing order of specs
#
# Specs, by default, run in the order defined, but can be run in a random order
# by passing `--order random` to `crystal spec`.
#
# Specs run in random order will display a seed value upon completion. This seed
# value can be used to rerun the specs in that same order by passing the seed
# value to `--order`.
module Spec
  # :nodoc:
  class CLI
    # :nodoc:
    #
    # Implement formatter configuration.
    def configure_formatter(formatter, output_path = nil)
      case formatter
      when "junit"
        junit_formatter = Spec::JUnitFormatter.file(Path.new(output_path.not_nil!))
        add_formatter(junit_formatter)
      when "verbose"
        override_default_formatter(Spec::VerboseFormatter.new)
      when "tap"
        override_default_formatter(Spec::TAPFormatter.new)
      end
    end

    def main(args)
      Colorize.on_tty_only!

      begin
        option_parser.parse(args)
      rescue e : OptionParser::InvalidOption
        abort("Error: #{e.message}")
      end

      unless args.empty?
        STDERR.puts "Error: unknown argument '#{args.first}'"
        exit 1
      end

      if ENV["SPEC_VERBOSE"]? == "1"
        override_default_formatter(Spec::VerboseFormatter.new)
      end

      add_split_filter ENV["SPEC_SPLIT"]?

      {% unless flag?(:wasm32) %}
        # TODO(wasm): Enable this once `Process.on_terminate` is implemented
        Process.on_terminate { abort! }
      {% end %}
    end
  end
end

Spec.cli.main(ARGV)

# The spec suite should run as last thing in the program. This enables other
# top-level code (for example library configuration) to run before the spec
# suite starts.
macro finished
  Spec.cli.run
end
