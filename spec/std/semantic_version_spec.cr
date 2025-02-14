require "spec"
require "semantic_version"

describe SemanticVersion do
  it "compares <" do
    sversions = %w(
      1.2.3-2
      1.2.3-10
      1.2.3-alpha
      1.2.3-alpha.2
      1.2.3-alpha.10
      1.2.3-beta
      1.2.3
      1.2.4-alpha
      1.2.4-beta
      1.2.4
    )
    versions = sversions.map { |s| SemanticVersion.parse(s) }.to_a

    versions.each_with_index do |v, i|
      v.to_s.should eq(sversions[i])
    end

    versions.each_cons(2) do |pair|
      pair[0].should be < pair[1]
    end
  end

  it "compares build equivalence" do
    sversions = %w(
      1.2.3+1
      1.2.3+999
      1.2.3+a
      1.2.3+a.b
      1.2.3+a.b.c
    )
    versions = sversions.map { |s| SemanticVersion.parse(s) }.to_a

    versions.each_with_index do |v, i|
      v.to_s.should eq(sversions[i])
    end

    versions.each_cons(2) do |pair|
      (pair[0] <=> pair[1]).should eq 0
    end
  end

  it "accepts valid versions" do
    %w[
      1.2.3
      1.2.3-2
      1.2.3-10
      1.2.3-alpha
      1.2.3-alpha.2
      1.2.3-alpha.10
    ].each do |version|
      SemanticVersion.valid?(version).should be_true
      SemanticVersion.parse?(version).should_not be_nil
    end
  end

  it "does not accept bad versions" do
    sversions = %w(
      1
      1.2
      1.2.3-0123
      1.2.3-0123.0123
      0.0.4--.
      1.1.2+.123
      +invalid
      -invalid
      -invalid+invalid
      -invalid.01
      alpha
      alpha.beta
      alpha.beta.1
      alpha.1
      alpha+beta
      alpha_beta
      alpha.
      alpha..
      1.0.0-alpha_beta
      -alpha.
      1.0.0-alpha..
      1.0.0-alpha..1
      1.0.0-alpha...1
      01.1.1
      1.01.1
      1.1.01
      1.2.3.DEV
      1.2-SNAPSHOT
      1.2.31.2.3----RC-SNAPSHOT.12.09.1--..12+788
      1.2-RC-SNAPSHOT
      -1.0.3-gamma+b7718
      +justmeta
      9.8.7+meta+meta
      9.8.7-whatever+meta+meta
      99999999999999999999999.999999999999999999.99999999999999999----RC-SNAPSHOT.12.09.1--------------------------------..12
    )
    sversions.each do |s|
      SemanticVersion.valid?(s).should be_false
      SemanticVersion.parse?(s).should be_nil
      expect_raises(ArgumentError) { SemanticVersion.parse(s) }
    end
  end

  it "copies with specified modifications" do
    base_version = SemanticVersion.new(1, 2, 3, "rc", "0000")
    base_version.copy_with(major: 0).should eq SemanticVersion.new(0, 2, 3, "rc", "0000")
    base_version.copy_with(minor: 0).should eq SemanticVersion.new(1, 0, 3, "rc", "0000")
    base_version.copy_with(patch: 0).should eq SemanticVersion.new(1, 2, 0, "rc", "0000")
    base_version.copy_with(prerelease: "alpha").should eq SemanticVersion.new(1, 2, 3, "alpha", "0000")
    base_version.copy_with(build: "0001").should eq SemanticVersion.new(1, 2, 3, "rc", "0001")
    base_version.copy_with(prerelease: nil, build: nil).should eq SemanticVersion.new(1, 2, 3)
  end

  it "bumps to the correct version" do
    SemanticVersion.new(1, 1, 1).bump_minor.should eq SemanticVersion.new(1, 2, 0)
    SemanticVersion.new(1, 2, 0).bump_patch.should eq SemanticVersion.new(1, 2, 1)
    SemanticVersion.new(1, 2, 1).bump_major.should eq SemanticVersion.new(2, 0, 0)
    SemanticVersion.new(2, 0, 0).bump_patch.should eq SemanticVersion.new(2, 0, 1)
    SemanticVersion.new(2, 0, 1).bump_minor.should eq SemanticVersion.new(2, 1, 0)
    SemanticVersion.new(2, 1, 0).bump_major.should eq SemanticVersion.new(3, 0, 0)

    version_with_prerelease = SemanticVersion.new(1, 2, 3, "rc", "0001")
    version_with_prerelease.bump_major.should eq SemanticVersion.new(2, 0, 0)
    version_with_prerelease.bump_minor.should eq SemanticVersion.new(1, 3, 0)
    version_with_prerelease.bump_patch.should eq SemanticVersion.new(1, 2, 3)
  end

  describe SemanticVersion::Prerelease do
    it "compares <" do
      sprereleases = %w(
        alpha.1
        beta.1
        beta.2
      )
      prereleases = sprereleases.map { |s|
        SemanticVersion::Prerelease.parse(s)
      }

      prereleases.each_cons(2) do |pair|
        pair[0].should be < pair[1]
      end
    end
  end
end
