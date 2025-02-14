require "spec"
require "spec/helpers/string"

private def exit_status(status)
  {% if flag?(:unix) %}
    status << 8
  {% else %}
    status.to_u32!
  {% end %}
end

private def status_for(exit_reason : Process::ExitReason)
  exit_code = case exit_reason
              when .interrupted?
                {% if flag?(:unix) %}Signal::INT.value{% else %}LibC::STATUS_CONTROL_C_EXIT{% end %}
              else
                raise NotImplementedError.new("status_for")
              end
  Process::Status.new(exit_code)
end

describe Process::Status do
  it "#exit_code" do
    Process::Status.new(exit_status(0)).exit_code.should eq 0
    Process::Status.new(exit_status(1)).exit_code.should eq 1
    Process::Status.new(exit_status(127)).exit_code.should eq 127
    Process::Status.new(exit_status(128)).exit_code.should eq 128
    Process::Status.new(exit_status(255)).exit_code.should eq 255

    expect_raises(RuntimeError, "Abnormal exit has no exit code") do
      status_for(:interrupted).exit_code
    end
  end

  it "#exit_code?" do
    Process::Status.new(exit_status(0)).exit_code?.should eq 0
    Process::Status.new(exit_status(1)).exit_code?.should eq 1
    Process::Status.new(exit_status(127)).exit_code?.should eq 127
    Process::Status.new(exit_status(128)).exit_code?.should eq 128
    Process::Status.new(exit_status(255)).exit_code?.should eq 255

    status_for(:interrupted).exit_code?.should be_nil
  end

  it "#system_exit_status" do
    Process::Status.new(exit_status(0)).system_exit_status.should eq 0_u32
    Process::Status.new(exit_status(1)).system_exit_status.should eq({{ flag?(:unix) ? 0x0100_u32 : 1_u32 }})
    Process::Status.new(exit_status(127)).system_exit_status.should eq({{ flag?(:unix) ? 0x7f00_u32 : 127_u32 }})
    Process::Status.new(exit_status(128)).system_exit_status.should eq({{ flag?(:unix) ? 0x8000_u32 : 128_u32 }})
    Process::Status.new(exit_status(255)).system_exit_status.should eq({{ flag?(:unix) ? 0xFF00_u32 : 255_u32 }})

    status_for(:interrupted).system_exit_status.should eq({% if flag?(:unix) %}Signal::INT.value{% else %}LibC::STATUS_CONTROL_C_EXIT{% end %})
  end

  it "#success?" do
    Process::Status.new(exit_status(0)).success?.should be_true
    Process::Status.new(exit_status(1)).success?.should be_false
    Process::Status.new(exit_status(127)).success?.should be_false
    Process::Status.new(exit_status(128)).success?.should be_false
    Process::Status.new(exit_status(255)).success?.should be_false

    status_for(:interrupted).success?.should be_false
  end

  it "#normal_exit?" do
    Process::Status.new(exit_status(0)).normal_exit?.should be_true
    Process::Status.new(exit_status(1)).normal_exit?.should be_true
    Process::Status.new(exit_status(127)).normal_exit?.should be_true
    Process::Status.new(exit_status(128)).normal_exit?.should be_true
    Process::Status.new(exit_status(255)).normal_exit?.should be_true

    status_for(:interrupted).normal_exit?.should be_false
  end

  it "#abnormal_exit?" do
    Process::Status.new(exit_status(0)).abnormal_exit?.should be_false
    Process::Status.new(exit_status(1)).abnormal_exit?.should be_false
    Process::Status.new(exit_status(127)).abnormal_exit?.should be_false
    Process::Status.new(exit_status(128)).abnormal_exit?.should be_false
    Process::Status.new(exit_status(255)).abnormal_exit?.should be_false

    status_for(:interrupted).abnormal_exit?.should be_true
  end

  it "#signal_exit?" do
    Process::Status.new(exit_status(0)).signal_exit?.should be_false
    Process::Status.new(exit_status(1)).signal_exit?.should be_false
    Process::Status.new(exit_status(127)).signal_exit?.should be_false
    Process::Status.new(exit_status(128)).signal_exit?.should be_false
    Process::Status.new(exit_status(255)).signal_exit?.should be_false

    status_for(:interrupted).signal_exit?.should eq {{ !flag?(:win32) }}
  end

  it "equality" do
    ok1 = Process::Status.new(exit_status(0))
    ok2 = Process::Status.new(exit_status(0))
    err1 = Process::Status.new(exit_status(1))
    err2 = Process::Status.new(exit_status(1))

    ok1.should eq(ok2)
    ok1.should_not eq(err2)
    err1.should_not eq(ok2)
    err1.should eq(err2)

    ok1.hash.should eq(ok2.hash)
    ok1.hash.should_not eq(err2.hash)
    err1.hash.should_not eq(ok2.hash)
    err1.hash.should eq(err2.hash)
  end

  it "#exit_signal?" do
    Process::Status.new(exit_status(0)).exit_signal?.should be_nil
    Process::Status.new(exit_status(1)).exit_signal?.should be_nil

    status_for(:interrupted).exit_signal?.should eq({% if flag?(:unix) %}Signal::INT{% else %}nil{% end %})
  end

  {% if flag?(:unix) && !flag?(:wasi) %}
    it "#exit_signal" do
      Process::Status.new(Signal::HUP.value).exit_signal.should eq Signal::HUP
      Process::Status.new(Signal::INT.value).exit_signal.should eq Signal::INT
      last_signal = Signal.values[-1]
      Process::Status.new(last_signal.value).exit_signal.should eq last_signal

      unknown_signal = Signal.new(126)
      Process::Status.new(unknown_signal.value).exit_signal.should eq unknown_signal
    end

    it "#exit_signal?" do
      Process::Status.new(Signal::HUP.value).exit_signal?.should eq Signal::HUP
      Process::Status.new(Signal::INT.value).exit_signal?.should eq Signal::INT
      last_signal = Signal.values[-1]
      Process::Status.new(last_signal.value).exit_signal?.should eq last_signal

      unknown_signal = Signal.new(126)
      Process::Status.new(unknown_signal.value).exit_signal?.should eq unknown_signal
    end

    it "#normal_exit? with signal code" do
      Process::Status.new(0x00).normal_exit?.should be_true
      Process::Status.new(0x01).normal_exit?.should be_false
      Process::Status.new(0x7e).normal_exit?.should be_false
      Process::Status.new(0x7f).normal_exit?.should be_false
    end

    it "#signal_exit? with signal code" do
      Process::Status.new(0x00).signal_exit?.should be_false
      Process::Status.new(0x01).signal_exit?.should be_true
      Process::Status.new(0x7e).signal_exit?.should be_true
      Process::Status.new(0x7f).signal_exit?.should be_true
    end
  {% end %}

  {% if flag?(:win32) %}
    describe "#exit_reason" do
      it "returns Normal" do
        Process::Status.new(exit_status(0)).exit_reason.normal?.should be_true
        Process::Status.new(exit_status(1)).exit_reason.normal?.should be_true
        Process::Status.new(exit_status(127)).exit_reason.normal?.should be_true
        Process::Status.new(exit_status(128)).exit_reason.normal?.should be_true
        Process::Status.new(exit_status(255)).exit_reason.normal?.should be_true

        Process::Status.new(0x3FFFFFFF_u32).exit_reason.normal?.should be_true
        Process::Status.new(0x40001234_u32).exit_reason.normal?.should be_false
        Process::Status.new(0x80001234_u32).exit_reason.normal?.should be_false
        Process::Status.new(0xC0001234_u32).exit_reason.normal?.should be_false
      end

      it "returns Aborted" do
        Process::Status.new(LibC::STATUS_FATAL_APP_EXIT).exit_reason.aborted?.should be_true
      end

      it "returns Interrupted" do
        Process::Status.new(LibC::STATUS_CONTROL_C_EXIT).exit_reason.interrupted?.should be_true
      end

      it "returns Breakpoint" do
        Process::Status.new(LibC::STATUS_BREAKPOINT).exit_reason.breakpoint?.should be_true
      end

      it "returns AccessViolation" do
        Process::Status.new(LibC::STATUS_ACCESS_VIOLATION).exit_reason.access_violation?.should be_true
        Process::Status.new(LibC::STATUS_STACK_OVERFLOW).exit_reason.access_violation?.should be_true
      end

      it "returns BadMemoryAccess" do
        Process::Status.new(LibC::STATUS_DATATYPE_MISALIGNMENT).exit_reason.bad_memory_access?.should be_true
      end

      it "returns BadInstruction" do
        Process::Status.new(LibC::STATUS_ILLEGAL_INSTRUCTION).exit_reason.bad_instruction?.should be_true
        Process::Status.new(LibC::STATUS_PRIVILEGED_INSTRUCTION).exit_reason.bad_instruction?.should be_true
      end

      it "returns FloatException" do
        Process::Status.new(LibC::STATUS_FLOAT_DIVIDE_BY_ZERO).exit_reason.float_exception?.should be_true
        Process::Status.new(LibC::STATUS_FLOAT_INEXACT_RESULT).exit_reason.float_exception?.should be_true
        Process::Status.new(LibC::STATUS_FLOAT_INVALID_OPERATION).exit_reason.float_exception?.should be_true
        Process::Status.new(LibC::STATUS_FLOAT_OVERFLOW).exit_reason.float_exception?.should be_true
        Process::Status.new(LibC::STATUS_FLOAT_UNDERFLOW).exit_reason.float_exception?.should be_true
      end
    end
  {% elsif flag?(:unix) && !flag?(:wasi) %}
    describe "#exit_reason" do
      it "returns Normal" do
        Process::Status.new(exit_status(0)).exit_reason.normal?.should be_true
        Process::Status.new(exit_status(1)).exit_reason.normal?.should be_true
        Process::Status.new(exit_status(127)).exit_reason.normal?.should be_true
        Process::Status.new(exit_status(128)).exit_reason.normal?.should be_true
        Process::Status.new(exit_status(255)).exit_reason.normal?.should be_true

        Process::Status.new(0x01).exit_reason.normal?.should be_false
        Process::Status.new(0x7e).exit_reason.normal?.should be_false

        Process::Status.new(0x017f).exit_reason.normal?.should be_false
        Process::Status.new(0xffff).exit_reason.normal?.should be_false
      end

      it "returns Aborted" do
        Process::Status.new(Signal::ABRT.value).exit_reason.aborted?.should be_true
        Process::Status.new(Signal::KILL.value).exit_reason.aborted?.should be_true
        Process::Status.new(Signal::QUIT.value).exit_reason.aborted?.should be_true
      end

      it "returns TerminalDisconnected" do
        Process::Status.new(Signal::HUP.value).exit_reason.terminal_disconnected?.should be_true
      end

      it "returns SessionEnded" do
        Process::Status.new(Signal::TERM.value).exit_reason.session_ended?.should be_true
      end

      it "returns Interrupted" do
        Process::Status.new(Signal::INT.value).exit_reason.interrupted?.should be_true
      end

      it "returns Breakpoint" do
        Process::Status.new(Signal::TRAP.value).exit_reason.breakpoint?.should be_true
      end

      it "returns AccessViolation" do
        Process::Status.new(Signal::SEGV.value).exit_reason.access_violation?.should be_true
      end

      it "returns BadMemoryAccess" do
        Process::Status.new(Signal::BUS.value).exit_reason.bad_memory_access?.should be_true
      end

      it "returns BadInstruction" do
        Process::Status.new(Signal::ILL.value).exit_reason.bad_instruction?.should be_true
      end

      it "returns FloatException" do
        Process::Status.new(Signal::FPE.value).exit_reason.float_exception?.should be_true
      end
    end
  {% end %}

  describe "#to_s" do
    it "with exit status" do
      assert_prints Process::Status.new(exit_status(0)).to_s, "0"
      assert_prints Process::Status.new(exit_status(1)).to_s, "1"
      assert_prints Process::Status.new(exit_status(127)).to_s, "127"
      assert_prints Process::Status.new(exit_status(128)).to_s, "128"
      assert_prints Process::Status.new(exit_status(255)).to_s, "255"
    end

    it "on abnormal exit" do
      {% if flag?(:win32) %}
        assert_prints status_for(:interrupted).to_s, "STATUS_CONTROL_C_EXIT"
      {% else %}
        assert_prints status_for(:interrupted).to_s, "INT"
      {% end %}
    end

    {% if flag?(:unix) && !flag?(:wasi) %}
      it "with exit signal" do
        assert_prints Process::Status.new(Signal::HUP.value).to_s, "HUP"
        last_signal = Signal.values[-1]
        assert_prints Process::Status.new(last_signal.value).to_s, last_signal.to_s

        assert_prints Process::Status.new(Signal.new(126).value).to_s, "Signal[126]"
      end
    {% end %}

    {% if flag?(:win32) %}
      it "hex format" do
        assert_prints Process::Status.new(UInt16::MAX).to_s, "0x0000FFFF"
        assert_prints Process::Status.new(0x01234567).to_s, "0x01234567"
        assert_prints Process::Status.new(UInt32::MAX).to_s, "0xFFFFFFFF"
      end
    {% end %}
  end

  describe "#inspect" do
    it "with exit status" do
      assert_prints Process::Status.new(exit_status(0)).inspect, "Process::Status[0]"
      assert_prints Process::Status.new(exit_status(1)).inspect, "Process::Status[1]"
      assert_prints Process::Status.new(exit_status(127)).inspect, "Process::Status[127]"
      assert_prints Process::Status.new(exit_status(128)).inspect, "Process::Status[128]"
      assert_prints Process::Status.new(exit_status(255)).inspect, "Process::Status[255]"
    end

    it "on abnormal exit" do
      {% if flag?(:win32) %}
        assert_prints status_for(:interrupted).inspect, "Process::Status[LibC::STATUS_CONTROL_C_EXIT]"
      {% else %}
        assert_prints status_for(:interrupted).inspect, "Process::Status[Signal::INT]"
      {% end %}
    end

    {% if flag?(:unix) && !flag?(:wasi) %}
      it "with exit signal" do
        assert_prints Process::Status.new(Signal::HUP.value).inspect, "Process::Status[Signal::HUP]"
        last_signal = Signal.values[-1]
        assert_prints Process::Status.new(last_signal.value).inspect, "Process::Status[#{last_signal.inspect}]"

        unknown_signal = Signal.new(126)
        assert_prints Process::Status.new(unknown_signal.value).inspect, "Process::Status[Signal[126]]"
      end
    {% end %}

    {% if flag?(:win32) %}
      it "hex format" do
        assert_prints Process::Status.new(UInt16::MAX).inspect, "Process::Status[0x0000FFFF]"
        assert_prints Process::Status.new(0x01234567).inspect, "Process::Status[0x01234567]"
        assert_prints Process::Status.new(UInt32::MAX).inspect, "Process::Status[0xFFFFFFFF]"
      end
    {% end %}
  end

  describe "#description" do
    it "with exit status" do
      Process::Status.new(exit_status(0)).description.should eq "Process exited normally"
      Process::Status.new(exit_status(255)).description.should eq "Process exited normally"
    end

    it "on interrupt" do
      status_for(:interrupted).description.should eq "Process was interrupted"
    end

    {% if flag?(:unix) && !flag?(:wasi) %}
      it "with exit signal" do
        Process::Status.new(Signal::HUP.value).description.should eq "Process terminated abnormally"
        Process::Status.new(Signal::STOP.value).description.should eq "Process received and didn't handle signal STOP"
        last_signal = Signal.values[-1]
        Process::Status.new(last_signal.value).description.should eq "Process received and didn't handle signal #{last_signal}"

        unknown_signal = Signal.new(126)
        Process::Status.new(unknown_signal.value).description.should eq "Process received and didn't handle signal 126"
      end
    {% end %}
  end
end
