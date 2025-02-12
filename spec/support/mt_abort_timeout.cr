{% skip_file unless flag?(:preview_mt) %}

private SPEC_TIMEOUT = 15.seconds

Spec.around_each do |example|
  done = Channel(Exception?).new

  spawn(same_thread: !{{flag?(:execution_context) && flag?(:mt)}}) do
    begin
      example.run
    rescue e
      done.send(e)
    else
      done.send(nil)
    end
  end

  timeout = SPEC_TIMEOUT
  if example.example.all_tags.includes?("slow")
    timeout *= 4
  end

  select
  when res = done.receive
    raise res if res
  when timeout(timeout)
    _it = example.example
    ex = Spec::AssertionFailed.new("spec timed out after #{timeout}", _it.file, _it.line)
    _it.parent.report(:fail, _it.description, _it.file, _it.line, timeout, ex)
  end
end
