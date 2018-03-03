require "spec"
require "spec/cli"

private def prepare_cli(argv, **kargs)
  cli = Spec::CLI.new(argv, **kargs)
  cli.prepare

  {cli, cli.options}
end

# override and capture exit calls
module Spec
  class CLI
    property! exited : Int32
    property? testing = false

    def testing
      @testing = true
      yield
    ensure
      @testing = false
    end

    private def display(message)
      stdout.puts message

      if testing?
        @exited = 0
      else
        exit
      end
    end

    private def terminate(message, status = 1)
      stderr.puts message

      if testing?
        @exited = status
      else
        exit status
      end
    end
  end
end

describe Spec::CLI do
  context "parses options" do
    it "captures provided example pattern" do
      _, options = prepare_cli %w(-e Foo)
      options.pattern?.should be_truthy
      options.pattern.should eq("Foo")

      _, options = prepare_cli %w(--example Bar)
      options.pattern?.should be_truthy
      options.pattern.should eq("Bar")
    end

    it "captures provided line number" do
      _, options = prepare_cli %w(-l 10)
      options.line?.should be_truthy
      options.line.should eq(10)

      _, options = prepare_cli %w(--line 10)
      options.line?.should be_truthy
      options.line.should eq(10)
    end

    it "enables slowest mode" do
      _, options = prepare_cli %w(-p)
      options.slowest?.should be_truthy
      options.slowest.should eq(10)

      _, options = prepare_cli %w(--profile)
      options.slowest?.should be_truthy
      options.slowest.should eq(10)
    end

    it "enables fail-fast mode" do
      _, options = prepare_cli %w(--fail-fast)
      options.fail_fast?.should be_true
    end

    context "locations" do
      it "captures single file:line location" do
        _, options = prepare_cli %w(--location foo.cr:1)

        options.locations.size.should eq(1)
        options.locations.should eq([{"foo.cr", 1}])
      end

      it "captures multiple file:line locations" do
        _, options = prepare_cli %w(--location foo.cr:10 --location bar.cr:50)

        options.locations.size.should eq(2)
        options.locations.should eq([{"foo.cr", 10}, {"bar.cr", 50}])
      end

      it "aborts on incorrect location format" do
        io = IO::Memory.new

        cli = Spec::CLI.new %w(--location missing.cr), stderr: io
        cli.testing do
          cli.prepare
        end

        cli.options.locations.size.should eq(0)
        cli.exited?.should be_truthy
        cli.exited.should eq(1)

        io.to_s.should contain("location missing.cr must be file:line")
      end
    end

    it "adds JUnit format to output" do
      _, options = prepare_cli %w(--junit_output tmp)

      options.formatters.size.should eq(1)
      options.formatters.first.should be_a(Spec::JUnitFormatter)
    end

    it "displays help options" do
      io = IO::Memory.new

      cli = Spec::CLI.new %w(--help), stdout: io
      cli.testing do
        cli.prepare
      end

      cli.exited?.should be_truthy
      cli.exited.should eq(0)

      output = io.to_s
      output.should contain("crystal spec runner")
      output.should contain("show this help")
    end

    it "changes default formatter to verbose" do
      _, options = prepare_cli %w()
      options.default_formatter?.should be_falsey

      _, options = prepare_cli %w(-v)
      options.default_formatter.should be_truthy
      options.default_formatter.should be_a(Spec::VerboseFormatter)

      _, options = prepare_cli %w(--verbose)
      options.default_formatter.should be_truthy
      options.default_formatter.should be_a(Spec::VerboseFormatter)
    end

    it "changes default formatter using SPEC_VERBOSE" do
      old_env = ENV["SPEC_VERBOSE"]?
      ENV["SPEC_VERBOSE"] = "1"

      _, options = prepare_cli %w()
      options.default_formatter.should be_truthy
      options.default_formatter.should be_a(Spec::VerboseFormatter)
    ensure
      ENV["SPEC_VERBOSE"] = old_env
    end

    it "disables color output" do
      _, options = prepare_cli %w(--no-color)
      options.no_color?.should be_true
    end

    it "aborts execution with unknown arguments" do
      io = IO::Memory.new
      cli = Spec::CLI.new %w(unknown), stderr: io

      cli.testing do
        cli.prepare
      end

      cli.exited?.should be_truthy
      cli.exited.should eq(1)

      io.to_s.should contain("Error: unknown argument 'unknown'")
    end
  end
end
