require "spec"
require "hrx"

def run_hrx_samples_dir(dir)
  Dir.each_child(dir) do |child|
    path = dir.join(child)
    if path.extension == ".hrx"
      describe path.basename do
        run_hrx_samples(path)
      end
    end
  end
end

def run_hrx_samples(archive_file, policies, *, relative_to = __DIR__)
  File.open(Path[archive_file].expand(relative_to), "r") do |io|
    describe archive_file.to_s do
      source = nil
      source_was_used = true
      HRX.parse(io) do |file|
        if file.path.starts_with?("pending:")
          name = File.dirname(file.path).lchop("pending:")
          pending(name) { }
          next
        end

        extension = File.extname(file.path)
        basename = File.basename(file.path, extension)
        case basename
        when "document", "fragment"
          if source && !source_was_used
            it_hrx_sample(policies, source, archive_file.to_s)
          end
          source = file
          source_was_used = false
        else
          next unless source
          source_was_used = true

          it_hrx_sample(policies, source, file, archive_file.to_s)
        end
      end
    end
  end
end

def it_hrx_sample(policies, source, expected, archive_file)
  extension = File.extname(expected.path)
  basename = File.basename(expected.path, extension)
  found_policy = true
  policy = policies.fetch(basename) { found_policy = false; nil }
  if !policy && found_policy
    pending "#{File.dirname(source.path)} #{basename}"
    return
  end

  it "#{File.dirname(source.path)} (#{basename})" do
    if p = policy
      assert_sanitize(p, source, expected, file: archive_file)
    else
      raise "Unregistered policy #{basename}"
    end
  end
end

def it_hrx_sample(policies, source, archive_file)
  describe File.dirname(source.path) do
    policies.each do |name, policy|
      next unless policy
      it name do
        assert_sanitize(policy, source, source, file: archive_file)
      end
    end
  end
end

def assert_sanitize(policy, source, expected, *, file = __FILE__)
  if File.basename(source.path, File.extname(source.path)) == "fragment"
    policy.process(source.content).should eq(expected.content), file: file, line: expected.line
  else
    policy.process_document(source.content).should eq(expected.content), file: file, line: expected.line
  end
end
