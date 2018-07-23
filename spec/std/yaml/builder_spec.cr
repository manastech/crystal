require "spec"
require "yaml"

private def assert_built(expected, expect_document_end = false)
  # libyaml 0.2.1 removed the errorneously written document end marker (`...`) after some scalars in root context (see https://github.com/yaml/libyaml/pull/18).
  # Earlier libyaml releases still write the document end marker and this is hard to fix on Crystal's side.
  # So we just ignore it and adopt the specs accordingly to coincide with the used libyaml version.
  if expect_document_end
    major, minor, _ = YAML.libyaml_version
    if major == 0 && minor < 2
      expected += "...\n"
    end
  end

  string = YAML.build do |yaml|
    with yaml yield yaml
  end
  string.should eq(expected)
end

describe YAML::Builder do
  it "writes scalar" do
    assert_built("--- 1\n", expect_document_end: true) do
      scalar(1)
    end
  end

  it "writes scalar with style" do
    assert_built(%(--- "1"\n)) do
      scalar(1, style: YAML::ScalarStyle::DOUBLE_QUOTED)
    end
  end

  it "writes scalar with tag" do
    assert_built(%(--- !foo 1\n), expect_document_end: true) do
      scalar(1, tag: "!foo")
    end
  end

  it "writes scalar with anchor" do
    assert_built(%(--- &foo 1\n), expect_document_end: true) do
      scalar(1, anchor: "foo")
    end
  end

  it "writes sequence" do
    assert_built("---\n- 1\n- 2\n- 3\n") do
      sequence do
        scalar(1)
        scalar(2)
        scalar(3)
      end
    end
  end

  it "writes sequence with tag" do
    assert_built("--- !foo\n- 1\n- 2\n- 3\n") do
      sequence(tag: "!foo") do
        scalar(1)
        scalar(2)
        scalar(3)
      end
    end
  end

  it "writes sequence with anchor" do
    assert_built("--- &foo\n- 1\n- 2\n- 3\n") do
      sequence(anchor: "foo") do
        scalar(1)
        scalar(2)
        scalar(3)
      end
    end
  end

  it "writes sequence with style" do
    assert_built("--- [1, 2, 3]\n") do
      sequence(style: YAML::SequenceStyle::FLOW) do
        scalar(1)
        scalar(2)
        scalar(3)
      end
    end
  end

  it "writes mapping" do
    assert_built("---\nfoo: 1\nbar: 2\n") do
      mapping do
        scalar("foo")
        scalar(1)
        scalar("bar")
        scalar(2)
      end
    end
  end

  it "writes mapping with tag" do
    assert_built("--- !foo\nfoo: 1\nbar: 2\n") do
      mapping(tag: "!foo") do
        scalar("foo")
        scalar(1)
        scalar("bar")
        scalar(2)
      end
    end
  end

  it "writes mapping with anchor" do
    assert_built("--- &foo\nfoo: 1\nbar: 2\n") do
      mapping(anchor: "foo") do
        scalar("foo")
        scalar(1)
        scalar("bar")
        scalar(2)
      end
    end
  end

  it "writes mapping with style" do
    assert_built("--- {foo: 1, bar: 2}\n") do
      mapping(style: YAML::MappingStyle::FLOW) do
        scalar("foo")
        scalar(1)
        scalar("bar")
        scalar(2)
      end
    end
  end
end
