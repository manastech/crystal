require "../spec_helper"
require "../../support/finalize"

class IO::FileDescriptor
  include FinalizeCounter
end

private CLOSE_ON_EXEC_AVAILABLE = {{ !flag?(:win32) }}

private def shell_command(command)
  {% if flag?(:win32) %}
    "cmd.exe /c #{Process.quote(command)}"
  {% else %}
    "/bin/sh -c #{Process.quote(command)}"
  {% end %}
end

describe IO::FileDescriptor do
  describe "#initialize" do
    it "handles closed file descriptor gracefully" do
      a, b = IO.pipe
      a.close
      b.close

      fd = IO::FileDescriptor.new(a.fd)
      fd.closed?.should be_true
    end
  end

  it "reopen STDIN with the right mode", tags: %w[slow] do
    code = %q(puts "#{STDIN.blocking} #{STDIN.info.type}")
    compile_source(code) do |binpath|
      `#{shell_command %(#{Process.quote(binpath)} < #{Process.quote(binpath)})}`.chomp.should eq("true File")
      `#{shell_command %(echo "" | #{Process.quote(binpath)})}`.chomp.should eq("#{{{ flag?(:win32) }}} Pipe")
    end
  end

  describe "#tty?" do
    it "returns false for null device" do
      File.open(File::NULL) do |f|
        f.tty?.should be_false
      end
    end

    it "returns false for standard streams redirected to null device", tags: %w[slow] do
      code = %q(print STDIN.tty?, ' ', STDERR.tty?)
      compile_source(code) do |binpath|
        `#{shell_command %(#{Process.quote(binpath)} < #{File::NULL} 2> #{File::NULL})}`.should eq("false false")
      end
    end
  end

  describe "#finalize" do
    it "closes" do
      pipes = [] of IO::FileDescriptor
      assert_finalizes("fd") do
        a, b = IO.pipe
        pipes << b
        a
      end

      expect_raises(IO::Error) do
        pipes.each do |p|
          p.puts "123"
        end
      end
    end

    it "does not flush" do
      with_tempfile "fd-finalize-flush" do |path|
        file = File.new(path, "w")
        file << "foo"
        file.flush
        file << "bar"
        file.finalize

        File.read(path).should eq "foo"
      ensure
        file.try(&.close) rescue nil
      end
    end
  end

  it "opens STDIN in binary mode", tags: %w[slow] do
    code = %q(print STDIN.gets_to_end.includes?('\r'))
    compile_source(code) do |binpath|
      io_in = IO::Memory.new("foo\r\n")
      io_out = IO::Memory.new
      Process.run(binpath, input: io_in, output: io_out)
      io_out.to_s.should eq("true")
    end
  end

  it "opens STDOUT in binary mode", tags: %w[slow] do
    code = %q(puts "foo")
    compile_source(code) do |binpath|
      io = IO::Memory.new
      Process.run(binpath, output: io)
      io.to_s.should eq("foo\n")
    end
  end

  it "opens STDERR in binary mode", tags: %w[slow] do
    code = %q(STDERR.puts "foo")
    compile_source(code) do |binpath|
      io = IO::Memory.new
      Process.run(binpath, error: io)
      io.to_s.should eq("foo\n")
    end
  end

  it "does not close if close_on_finalize is false" do
    pipes = [] of IO::FileDescriptor
    assert_finalizes("fd") do
      a, b = IO.pipe
      a.close_on_finalize = false
      pipes << b
      a
    end

    pipes.each do |p|
      p.puts "123"
    end
  end

  it "reopens" do
    File.open(datapath("test_file.txt")) do |file1|
      File.open(datapath("test_file.ini")) do |file2|
        file2.reopen(file1)
        file2.gets.should eq("Hello World")
      end
    end
  end

  describe "close_on_exec" do
    it "sets close on exec on the reopened standard descriptors" do
      unless STDIN.fd == Crystal::System::FileDescriptor::STDIN_HANDLE
        STDIN.close_on_exec?.should be_true
      end

      unless STDOUT.fd == Crystal::System::FileDescriptor::STDOUT_HANDLE
        STDOUT.close_on_exec?.should be_true
      end

      unless STDERR.fd == Crystal::System::FileDescriptor::STDERR_HANDLE
        STDERR.close_on_exec?.should be_true
      end
    end

    it "is enabled by default (open)" do
      File.open(datapath("test_file.txt")) do |file|
        file.close_on_exec?.should eq CLOSE_ON_EXEC_AVAILABLE
      end
    end

    it "is enabled by default (pipe)" do
      IO::FileDescriptor.pipe.each do |fd|
        fd.close_on_exec?.should eq CLOSE_ON_EXEC_AVAILABLE
        fd.close_on_exec?.should eq CLOSE_ON_EXEC_AVAILABLE
      end
    end

    it "can be disabled and reenabled" do
      File.open(datapath("test_file.txt")) do |file|
        file.close_on_exec = false
        file.close_on_exec?.should be_false

        if CLOSE_ON_EXEC_AVAILABLE
          file.close_on_exec = true
          file.close_on_exec?.should be_true
        else
          expect_raises(NotImplementedError) do
            file.close_on_exec = true
          end
        end
      end
    end

    if CLOSE_ON_EXEC_AVAILABLE
      it "is copied on reopen" do
        File.open(datapath("test_file.txt")) do |file1|
          file1.close_on_exec = true

          File.open(datapath("test_file.ini")) do |file2|
            file2.reopen(file1)
            file2.close_on_exec?.should be_true
          end

          file1.close_on_exec = false

          File.open(datapath("test_file.ini")) do |file3|
            file3.reopen(file1)
            file3.close_on_exec?.should be_false
          end
        end
      end
    end
  end

  typeof(STDIN.noecho { })
  typeof(STDIN.noecho!)
  typeof(STDIN.echo { })
  typeof(STDIN.echo!)
  typeof(STDIN.cooked { })
  typeof(STDIN.cooked!)
  typeof(STDIN.raw { })
  typeof(STDIN.raw!)
end
