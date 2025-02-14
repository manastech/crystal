require "spec"

describe Process::ExitReason do
  describe "#description" do
    it "with exit status" do
      Process::ExitReason::Normal.description.should eq "Process exited normally"
      Process::ExitReason::Unknown.description.should eq "Process terminated abnormally, the cause is unknown"
    end
  end
end
