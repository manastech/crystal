require "spec"
require "option_parser"

private def expect_capture_option(args, option, value)
  flag = nil
  OptionParser.parse(args) do |opts|
    opts.on(option, "some flag") do |flag_value|
      flag = flag_value
    end
  end
  flag.should eq(value)
  args.size.should eq(0)
end

private def expect_doesnt_capture_option(args, option)
  flag = false
  OptionParser.parse(args) do |opts|
    opts.on(option, "some flag") do
      flag = true
    end
  end
  flag.should be_false
end

private def expect_missing_option(option)
  expect_raises OptionParser::MissingOption do
    OptionParser.parse([] of String) do |opts|
      opts.on(option, "some flag") do |flag_value|
      end
    end
  end
end

private def expect_missing_option(args, option, flag)
  expect_raises OptionParser::MissingOption, "Missing option: #{flag}" do
    OptionParser.parse(args) do |opts|
      opts.on(option, "some flag") do |flag_value|
      end
    end
  end
end

describe "OptionParser" do
  it "has flag" do
    expect_capture_option ["-f"], "-f", ""
  end

  it "has flag with many letters" do
    expect_capture_option ["-ll"], "-ll", "l"
  end

  it "doesn't have flag" do
    expect_doesnt_capture_option [] of String, "-f"
  end

  it "has flag with double dash" do
    expect_capture_option ["--flag"], "--flag", ""
  end

  it "doesn't have flag with double dash" do
    expect_doesnt_capture_option [] of String, "--flag"
  end

  it "has required option next to flag" do
    expect_capture_option ["-f123"], "-fFLAG", "123"
  end

  it "has required option next to flag but given separated" do
    expect_capture_option ["-f", "123"], "-fFLAG", "123"
  end

  it "raises if missing option next to flag" do
    expect_missing_option ["-f"], "-fFLAG", "-f"
  end

  it "has required option separated from flag" do
    expect_capture_option ["-f", "123"], "-f FLAG", "123"
  end

  it "has required option separated from flag but given together" do
    expect_capture_option ["-f123"], "-f FLAG", "123"
  end

  it "gets short option with value that looks like flag" do
    expect_capture_option ["-f", "-g -h"], "-f FLAG", "-g -h"
  end

  describe "Consumption of flags following an ungiven optional argument" do
    context "Given a short option with an optional value" do
      it "doesn't eat a following short option" do
        flag = nil
        not_eaten = [] of String
        args = ["-f", "-g", "-i"]
        OptionParser.parse(args) do |opts|
          opts.on("-f [FLAG]", "some flag") do |flag_value|
            flag = flag_value
          end
          opts.on("-g", "shouldn't be eaten") do
            not_eaten << "-g"
          end
          opts.on("-i", "shouldn't be eaten") do
            not_eaten << "-i"
          end
        end
        flag.should eq("")
        not_eaten.should eq(["-g", "-i"])
        args.size.should eq(0)
      end

      it "doesn't eat a following long option" do
        flag = nil
        not_eaten = [] of String
        args = ["-f", "--g-long", "-i"]
        OptionParser.parse(args) do |opts|
          opts.on("-f [FLAG]", "some flag") do |flag_value|
            flag = flag_value
          end
          opts.on("-g", "--g-long", "shouldn't be eaten") do
            not_eaten << "--g-long"
          end
          opts.on("-i", "shouldn't be eaten") do
            not_eaten << "-i"
          end
        end
        flag.should eq("")
        not_eaten.should eq(["--g-long", "-i"])
        args.size.should eq(0)
      end

      it "does eat a value that looks like an option" do
        flag = nil
        not_eaten = [] of String
        args = ["-f", "--not-an-option--", "-i"]
        OptionParser.parse(args) do |opts|
          opts.on("-f [FLAG]", "some flag") do |flag_value|
            flag = flag_value
          end
          opts.on("-i", "shouldn't be eaten") do
            not_eaten << "-i"
          end
        end
        flag.should eq("--not-an-option--")
        not_eaten.should eq(["-i"])
        args.size.should eq(0)
      end
    end

    context "Given a long option with an optional value" do
      it "doesn't eat further short options" do
        flag = nil
        not_eaten = [] of String
        args = ["--long-flag", "-g", "-i"]
        OptionParser.parse(args) do |opts|
          opts.on("--long-flag [FLAG]", "some flag") do |flag_value|
            flag = flag_value
          end
          opts.on("-g", "shouldn't be eaten") do
            not_eaten << "-g"
          end
          opts.on("-i", "shouldn't be eaten") do
            not_eaten << "-i"
          end
        end
        flag.should eq("")
        not_eaten.should eq(["-g", "-i"])
        args.size.should eq(0)
      end

      it "doesn't eat further long options" do
        flag = nil
        not_eaten = [] of String
        args = ["--long-flag", "--g-long", "-i"]
        OptionParser.parse(args) do |opts|
          opts.on("--long-flag [FLAG]", "some flag") do |flag_value|
            flag = flag_value
          end
          opts.on("--g-long", "shouldn't be eaten") do
            not_eaten << "--g-long"
          end
          opts.on("-i", "shouldn't be eaten") do
            not_eaten << "-i"
          end
        end
        flag.should eq("")
        not_eaten.should eq(["--g-long", "-i"])
        args.size.should eq(0)
      end
    end
  end

  it "raises if missing required option with space" do
    expect_missing_option ["-f"], "-f FLAG", "-f"
  end

  it "has required option separated from long flag" do
    expect_capture_option ["--flag", "123"], "--flag FLAG", "123"
  end

  it "has required option with =" do
    expect_capture_option ["--flag=123"], "--flag FLAG", "123"
  end

  it "has required option with = (2)" do
    expect_capture_option ["--flag=123"], "--flag=FLAG", "123"
  end

  it "has required option with = (3) handles empty" do
    expect_capture_option ["--flag="], "--flag=FLAG", ""
  end

  it "raises if missing required argument separated from long flag" do
    expect_missing_option ["--flag"], "--flag FLAG", "--flag"
  end

  it "has required option with space" do
    expect_capture_option ["-f", "123"], "-f ", "123"
  end

  it "has required option with long flag space" do
    expect_capture_option ["--flag", "123"], "--flag ", "123"
  end

  it "gets short option with value -- (#8937)" do
    expect_capture_option ["-f", "--"], "-f ARG", "--"
  end

  it "gets long option with value -- (#8937)" do
    expect_capture_option ["--flag", "--"], "--flag [ARG]", "--"
  end

  it "doesn't raise if required option is not specified" do
    expect_doesnt_capture_option [] of String, "-f "
  end

  it "doesn't raise if optional option is not specified with short flag" do
    expect_doesnt_capture_option [] of String, "-f[FLAG]"
  end

  it "doesn't raise if optional option is not specified with long flag" do
    expect_doesnt_capture_option [] of String, "--flag [FLAG]"
  end

  it "doesn't raise if optional option is not specified with separated short flag" do
    expect_doesnt_capture_option [] of String, "-f [FLAG]"
  end

  it "doesn't raise if required option is not specified with separated short flag" do
    expect_doesnt_capture_option [] of String, "-f FLAG"
  end

  describe "gnu_optional_args" do
    it "doesn't get optional argument for short flag after space" do
      flag = nil
      args = %w(-f 123)
      OptionParser.parse(args, gnu_optional_args: true) do |opts|
        opts.on("-f [FLAG]", "some flag") do |flag_value|
          flag = flag_value
        end
      end
      flag.should eq("")
      args.should eq(%w(123))
    end

    it "doesn't get optional argument for long flag after space" do
      flag = nil
      args = %w(--f 123)
      OptionParser.parse(args, gnu_optional_args: true) do |opts|
        opts.on("--f [FLAG]", "some flag") do |flag_value|
          flag = flag_value
        end
      end
      flag.should eq("")
      args.should eq(%w(123))
    end
  end

  it "parses argument when only referenced in long flag" do
    captured = ""
    parser = OptionParser.parse([] of String) do |opts|
      opts.on("-f", "--flag X", "some flag") { |x| captured = x }
    end
    parser.parse(["-f", "12"])
    captured.should eq "12"
    parser.to_s.should contain "   -f, --flag X"
  end

  it "parses argument when referenced in long and short flag" do
    captured = ""
    parser = OptionParser.parse([] of String) do |opts|
      opts.on("-f X", "--flag X", "some flag") { |x| captured = x }
    end
    parser.parse(["-f", "12"])
    captured.should eq "12"
    parser.to_s.should contain "   -f X, --flag X"
  end

  it "does to_s with banner" do
    parser = OptionParser.parse([] of String) do |opts|
      opts.banner = "Usage: foo"
      opts.on("-f", "--flag", "some flag") do
      end
      opts.on("-g[FLAG]", "some other flag") do
      end
    end
    parser.to_s.should eq <<-USAGE
      Usage: foo
          -f, --flag                       some flag
          -g[FLAG]                         some other flag
      USAGE
  end

  it "does to_s with separators" do
    parser = OptionParser.parse([] of String) do |opts|
      opts.banner = "Usage: foo"
      opts.separator
      opts.separator "Type F flags:"
      opts.on("-f", "--flag", "some flag") do
      end
      opts.separator
      opts.separator "Type G flags:"
      opts.on("-g[FLAG]", "some other flag") do
      end
    end
    parser.to_s.should eq <<-USAGE
      Usage: foo

      Type F flags:
          -f, --flag                       some flag

      Type G flags:
          -g[FLAG]                         some other flag
      USAGE
  end

  it "does to_s with very long flag (#3305)" do
    parser = OptionParser.parse([] of String) do |opts|
      opts.banner = "Usage: foo"
      opts.on("--very_long_option_kills=formatter", "long") do
      end
      opts.on("-f", "--flag", "some flag") do
      end
      opts.on("-g[FLAG]", "some other flag") do
      end
    end
    parser.to_s.should eq <<-USAGE
      Usage: foo
          --very_long_option_kills=formatter
                                           long
          -f, --flag                       some flag
          -g[FLAG]                         some other flag
      USAGE
  end

  it "does to_s with multi line description (#5832)" do
    parser = OptionParser.parse([] of String) do |opts|
      opts.banner = "Usage: foo"
      opts.on("--very_long_option_kills=formatter", "long flag with\nmultiline description") do
      end
      opts.on("-f", "--flag", "some flag with\nmultiline description") do
      end
      opts.on("-g[FLAG]", "some other flag") do
      end
    end
    parser.to_s.should eq <<-USAGE
      Usage: foo
          --very_long_option_kills=formatter
                                           long flag with
                                           multiline description
          -f, --flag                       some flag with
                                           multiline description
          -g[FLAG]                         some other flag
      USAGE
  end

  it "raises on invalid option" do
    expect_raises OptionParser::InvalidOption, "Invalid option: -j" do
      OptionParser.parse(["-f", "-j"]) do |opts|
        opts.on("-f", "some flag") { }
      end
    end
  end

  it "raises on invalid option if value is given to none value handler (short flag, #9553) " do
    expect_raises OptionParser::InvalidOption, "Invalid option: -foo" do
      OptionParser.parse(["-foo"]) do |opts|
        opts.on("-f", "some flag") { }
      end
    end
  end

  it "raises on invalid option if value is given to none value handler (long flag, #9553)" do
    expect_raises OptionParser::InvalidOption, "Invalid option: --foo=bar" do
      OptionParser.parse(["--foo=bar"]) do |opts|
        opts.on("-foo", "some flag") { }
      end
    end
  end

  it "calls the handler for invalid options" do
    called = false
    OptionParser.parse(["-f", "-j"]) do |opts|
      opts.on("-f", "some flag") { }
      opts.invalid_option do |flag|
        flag.should eq("-j")
        called = true
      end
    end

    called.should be_true
  end

  it "calls the handler for missing options" do
    called = false
    OptionParser.parse(["-f"]) do |opts|
      opts.on("-f FOO", "some flag") { }
      opts.missing_option do |flag|
        flag.should eq("-f")
        called = true
      end
    end

    called.should be_true
  end

  describe "multiple times" do
    it "gets an existence flag multiple times" do
      args = %w(-f -f -f)
      count = 0
      OptionParser.parse(args) do |opts|
        opts.on("-f", "some flag") do
          count += 1
        end
      end
      count.should eq(3)
    end

    it "gets a single flag option multiple times" do
      args = %w(-f 1 -f 2)
      values = [] of String
      OptionParser.parse(args) do |opts|
        opts.on("-f VALUE", "some flag") do |value|
          values << value
        end
      end
      values.should eq(%w(1 2))
    end

    it "gets a double flag option multiple times" do
      args = %w(--f 1 --f 2)
      values = [] of String
      OptionParser.parse(args) do |opts|
        opts.on("--f VALUE", "some flag") do |value|
          values << value
        end
      end
      values.should eq(%w(1 2))
    end
  end

  describe "--" do
    it "ignores everything after -- with bool flag" do
      args = ["-f", "bar", "--", "baz", "qux", "-g"]
      f = false
      g = false
      OptionParser.parse(args) do |opts|
        opts.on("-f", "some flag") do
          f = true
        end
        opts.on("-g", "some flag") do
          g = true
        end
      end
      f.should be_true
      g.should be_false
      args.should eq(["bar", "baz", "qux", "-g"])
    end

    it "ignores everything after -- with single flag)" do
      args = ["-f", "bar", "x", "--", "baz", "qux", "-g", "lala"]
      f = nil
      g = nil
      OptionParser.parse(args) do |opts|
        opts.on("-f FLAG", "some flag") do |v|
          f = v
        end
        opts.on("-g FLAG", "some flag") do |v|
          g = v
        end
      end
      f.should eq("bar")
      g.should be_nil
      args.should eq(["x", "baz", "qux", "-g", "lala"])
    end

    it "ignores everything after -- with double flag" do
      args = ["--f", "bar", "x", "--", "baz", "qux", "--g", "lala"]
      f = nil
      g = nil
      OptionParser.parse(args) do |opts|
        opts.on("--f FLAG", "some flag") do |v|
          f = v
        end
        opts.on("--g FLAG", "some flag") do |v|
          g = v
        end
      end
      f.should eq("bar")
      g.should be_nil
      args.should eq(["x", "baz", "qux", "--g", "lala"])
    end

    it "returns a pair with things coming before and after --" do
      args = %w(--f bar baz -- qux)
      f = nil
      unknown_args = nil
      OptionParser.parse(args) do |opts|
        opts.on("--f FLAG", "some flag") do |v|
          f = v
        end
        opts.unknown_args do |before_dash, after_dash|
          unknown_args = {before_dash, after_dash}
        end
      end
      f.should eq("bar")
      args.should eq(["baz", "qux"])
      unknown_args.should eq({["baz"], ["qux"]})
    end

    it "returns a pair with things coming before and after --, without --" do
      args = %w(--f bar baz)
      f = nil
      unknown_args = nil
      OptionParser.parse(args) do |opts|
        opts.on("--f FLAG", "some flag") do |v|
          f = v
        end
        opts.unknown_args do |before_dash, after_dash|
          unknown_args = {before_dash, after_dash}
        end
      end
      f.should eq("bar")
      args.should eq(["baz"])
      unknown_args.should eq({["baz"], [] of String})
    end

    it "initializes without block and does parse!" do
      old_argv = ARGV.dup
      begin
        ARGV.clear
        ARGV.concat %w(--f hi)
        f = nil
        OptionParser.new do |opts|
          opts.on("--f FLAG", "some flag") do |v|
            f = v
          end
        end.parse
        f.should eq("hi")
      ensure
        ARGV.clear
        ARGV.concat old_argv
      end
    end

    it "gets `-` as argument" do
      args = %w(-)
      OptionParser.parse(args) do |opts|
      end
      args.should eq(%w(-))
    end
  end

  describe "forward-match" do
    it "distinguishes between '--lamb VALUE' and '--lambda VALUE'" do
      args = %w(--lamb value1 --lambda value2)
      value1 = nil
      value2 = nil
      OptionParser.parse(args) do |opts|
        opts.on("--lamb VALUE", "") { |v| value1 = v }
        opts.on("--lambda VALUE", "") { |v| value2 = v }
      end
      value1.should eq("value1")
      value2.should eq("value2")
    end

    it "distinguishes between '--lamb=VALUE' and '--lambda=VALUE'" do
      args = %w(--lamb=value1 --lambda=value2)
      value1 = nil
      value2 = nil
      OptionParser.parse(args) do |opts|
        opts.on("--lamb=VALUE", "") { |v| value1 = v }
        opts.on("--lambda=VALUE", "") { |v| value2 = v }
      end
      value1.should eq("value1")
      value2.should eq("value2")
    end
  end

  it "raises if flag pair doesn't start with dash (#4001)" do
    OptionParser.parse([] of String) do |opts|
      expect_raises ArgumentError, %(Argument 'short_flag' ("foo") must start with a dash) do
        opts.on("foo", "bar", "baz") { }
      end

      expect_raises ArgumentError, %(Argument 'long_flag' ("bar") must start with a dash) do
        opts.on("-foo", "bar", "baz") { }
      end

      opts.on("", "-bar", "baz") { }
    end
  end

  it "handles subcommands" do
    args = %w(--verbose subcommand --foo 1 --bar sub2 -z)
    verbose = false
    subcommand = false
    foo = nil
    bar = false
    sub2 = false
    z = false
    OptionParser.parse(args) do |opts|
      opts.on("subcommand", "") do
        subcommand = true
        opts.on("--foo arg", "") { |v| foo = v }
        opts.on("--bar", "") { bar = true }
        opts.on("sub2", "") { sub2 = true }
      end
      opts.on("--verbose", "") { verbose = true }
      opts.on("-z", "--baz", "") { z = true }
    end

    verbose.should be_true
    subcommand.should be_true
    foo.should be("1")
    bar.should be_true
    sub2.should be_true
    z.should be_true
  end

  it "parses with subcommands twice" do
    args = %w(--verbose subcommand --foo 1 --bar sub2 -z)
    verbose = false
    subcommand = false
    foo = nil
    bar = false
    sub2 = false
    z = false

    parser = OptionParser.new do |opts|
      opts.on("subcommand", "") do
        subcommand = true
        opts.on("--foo arg", "") { |v| foo = v }
        opts.on("--bar", "") { bar = true }
        opts.on("sub2", "") { sub2 = true }
      end
      opts.on("--verbose", "") { verbose = true }
      opts.on("-z", "--baz", "") { z = true }
    end

    parser.parse args

    verbose.should be_true
    subcommand.should be_true
    foo.should be("1")
    bar.should be_true
    sub2.should be_true
    z.should be_true

    args = %w(--verbose subcommand --foo 1 --bar sub2 -z)
    verbose = false
    subcommand = false
    foo = nil
    bar = false
    sub2 = false
    z = false

    parser.parse args

    verbose.should be_true
    subcommand.should be_true
    foo.should be("1")
    bar.should be_true
    sub2.should be_true
    z.should be_true
  end

  it "unregisters subcommands on call" do
    foo = false
    bar = false
    baz = false
    OptionParser.parse(%w(foo baz)) do |opts|
      opts.on("foo", "") do
        foo = true
        opts.on("bar", "") { bar = true }
      end
      opts.on("baz", "") { baz = true }
    end
    foo.should be_true
    bar.should be_false
    baz.should be_false
  end

  it "handles subcommand --help well (top level)" do
    help = nil
    OptionParser.parse(%w(--help)) do |opts|
      opts.banner = "Usage: foo"
      opts.on("subcommand", "Subcommand Description") do
        opts.on("-f", "--foo", "Foo") { }
      end
      opts.on("--verbose", "Verbose mode") { }
      opts.on("--help", "Help") { help = opts.to_s }
    end

    help.should eq <<-USAGE
      Usage: foo
          subcommand                       Subcommand Description
          --verbose                        Verbose mode
          --help                           Help
      USAGE
  end

  it "handles subcommand --help well (subcommand)" do
    help = nil
    OptionParser.parse(%w(subcommand --help)) do |opts|
      opts.banner = "Usage: foo"
      opts.on("subcommand", "Subcommand Description") do
        opts.banner = "Usage: foo subcommand"
        opts.on("-f", "--foo", "Foo") { }
      end
      opts.on("--verbose", "Verbose mode") { }
      opts.on("--help", "Help") { help = opts.to_s }
    end

    help.should eq <<-USAGE
      Usage: foo subcommand
          --verbose                        Verbose mode
          --help                           Help
          -f, --foo                        Foo
      USAGE
  end

  it "handles subcommands with hyphen" do
    subcommand = false
    OptionParser.parse(%w(sub-command)) do |opts|
      opts.banner = "Usage: foo"
      opts.on("sub-command", "Subcommand description") { subcommand = true }
    end

    subcommand.should be_true
  end

  it "stops when asked" do
    args = %w(--foo --stop --bar)
    foo = false
    bar = false
    OptionParser.parse(args) do |opts|
      opts.on("--foo", "") { foo = true }
      opts.on("--bar", "") { bar = true }
      opts.on("--stop", "") { opts.stop }
      opts.unknown_args do |before, after|
        before.should eq(%w())
        after.should eq(%w(--bar))
      end
    end
    foo.should be_true
    bar.should be_false
    args.should eq(%w(--bar))
  end

  it "can run a callback on every argument" do
    args = %w(--foo file --bar)
    foo = false
    bar = false
    OptionParser.parse(args) do |opts|
      opts.on("--foo", "") { foo = true }
      opts.on("--bar", "") { bar = true }
      opts.before_each do |arg|
        if arg == "file"
          opts.stop
        end
      end
      opts.unknown_args do |before, after|
        before.should eq(%w(file))
        after.should eq(%w(--bar))
      end
    end

    foo.should be_true
    bar.should be_false
    args.should eq(%w(file --bar))
  end

  describe "boolean args" do
    describe "only-negative options" do
      context "when chosen" do
        it "should accept a negative option as a value of 'false'" do
          flag = true
          args = %w(--no-verbose)
          OptionParser.parse(args) do |opts|
            opts.on("--no-verbose", "Turn off verbose") do
              flag = false
            end
          end
          flag.should eq(false)
        end
      end
      context "when not chosen" do
        it "should produce a value of 'true' (the default)" do
          flag = true
          args = [] of String
          OptionParser.parse(args) do |opts|
            opts.on("--no-verbose", "Turn off verbose") do
              flag = false
            end
          end
          flag.should eq(true)
        end
      end
    end
    describe "both-forms boolean" do
      it "should be true when chosen" do
        flag = nil
        args = %w(--verbose)
        OptionParser.parse(args) do |opts|
          opts.bool("--[no-]verbose", "Run verbosely") do |v|
            flag = v
          end
        end
        flag.should eq(true)
      end
      it "should be true when chosen" do
        flag = nil
        args = %w(--no-verbose)
        OptionParser.parse(args) do |opts|
          opts.bool("--[no-]verbose", "Run verbosely") do |v|
            flag = v
          end
        end
        flag.should eq(false)
      end
    end
  end
end
