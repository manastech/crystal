# Conforms to Semantic Versioning 2.0.0
#
# See [https://semver.org/](https://semver.org/) for more information.
struct SemanticVersion
  include Comparable(self)

  VERSION_PATTERN = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)
                      (?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?
                      (?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$/x

  # The major version of this semantic version
  getter major : Int32

  # The minor version of this semantic version
  getter minor : Int32

  # The patch version of this semantic version
  getter patch : Int32

  # The build metadata of this semantic version
  getter build : String?

  # The pre-release version of this semantic version
  getter prerelease : Prerelease

  # Checks if *str* is a valid semantic version.
  #
  # ```
  # require "semantic_version"
  #
  # SemanticVersion.valid?("1.15.0") # => true
  # SemanticVersion.valid?("1.2")    # => false
  def self.valid?(str : String) : Bool
    VERSION_PATTERN.matches?(str)
  end

  # Parses a `SemanticVersion` from the given semantic version string.
  #
  # ```
  # require "semantic_version"
  #
  # semver = SemanticVersion.parse("2.61.4")
  # semver # => #<SemanticVersion:0x55b3667c9e70 @major=2, @minor=61, @patch=4, ... >
  # ```
  #
  # Raises `ArgumentError` if *str* is not a semantic version.
  def self.parse(str : String) : self
    parse?(str) || raise ArgumentError.new("Not a semantic version: #{str.inspect}")
  end

  # Parses a `SemanticVersion` from the given semantic version string.
  #
  # ```
  # require "semantic_version"
  #
  # semver = SemanticVersion.parse?("2.61.4")
  # semver # => #<SemanticVersion:0x55b3667c9e70 @major=2, @minor=61, @patch=4, ... >
  # ```
  #
  # Returns `nil` if *str* is not a semantic version.
  def self.parse?(str : String) : self?
    return unless m = str.match VERSION_PATTERN

    new m[1].to_i, m[2].to_i, m[3].to_i, m[4]?, m[5]?
  end

  # Creates a new `SemanticVersion` instance with the given major, minor, and patch versions
  # and optionally build and pre-release version
  #
  # Raises `ArgumentError` if *prerelease* is invalid pre-release version
  def initialize(@major : Int, @minor : Int, @patch : Int, prerelease : String | Prerelease | Nil = nil, @build : String? = nil)
    @prerelease = case prerelease
                  when Prerelease
                    prerelease
                  when String
                    Prerelease.parse prerelease
                  when nil
                    Prerelease.new
                  else
                    raise ArgumentError.new("Invalid prerelease #{prerelease.inspect}")
                  end
  end

  def_equals_and_hash major, minor, patch, prerelease, build

  # Returns the string representation of this semantic version
  #
  # ```
  # require "semantic_version"
  #
  # semver = SemanticVersion.parse("0.27.1")
  # semver.to_s # => "0.27.1"
  # ```
  def to_s(io : IO) : Nil
    io << major << '.' << minor << '.' << patch
    unless prerelease.identifiers.empty?
      io << '-'
      prerelease.to_s io
    end
    if build
      io << '+' << build
    end
  end

  # Returns a new `SemanticVersion` created with the specified parts. The
  # default for each part is its current value.
  #
  # ```
  # require "semantic_version"
  #
  # current_version = SemanticVersion.new 1, 1, 1, "rc"
  # current_version.copy_with(patch: 2)        # => SemanticVersion(@build=nil, @major=1, @minor=1, @patch=2, @prerelease=SemanticVersion::Prerelease(@identifiers=["rc"]))
  # current_version.copy_with(prerelease: nil) # => SemanticVersion(@build=nil, @major=1, @minor=1, @patch=1, @prerelease=SemanticVersion::Prerelease(@identifiers=[]))
  # ```
  def copy_with(major : Int32 = @major, minor : Int32 = @minor, patch : Int32 = @patch, prerelease : String | Prerelease | Nil = @prerelease, build : String? = @build)
    SemanticVersion.new major, minor, patch, prerelease, build
  end

  # Returns a copy of the current version with a major bump.
  #
  # ```
  # require "semantic_version"
  #
  # current_version = SemanticVersion.new 1, 1, 1, "rc"
  # current_version.bump_major # => SemanticVersion(@build=nil, @major=2, @minor=0, @patch=0, @prerelease=SemanticVersion::Prerelease(@identifiers=[]))
  # ```
  def bump_major
    copy_with(major: major + 1, minor: 0, patch: 0, prerelease: nil, build: nil)
  end

  # Returns a copy of the current version with a minor bump.
  #
  # ```
  # require "semantic_version"
  #
  # current_version = SemanticVersion.new 1, 1, 1, "rc"
  # current_version.bump_minor # => SemanticVersion(@build=nil, @major=1, @minor=2, @patch=0, @prerelease=SemanticVersion::Prerelease(@identifiers=[]))
  # ```
  def bump_minor
    copy_with(minor: minor + 1, patch: 0, prerelease: nil, build: nil)
  end

  # Returns a copy of the current version with a patch bump. Bumping a patch of
  # a prerelease just erase the prerelease data.
  #
  # ```
  # require "semantic_version"
  #
  # current_version = SemanticVersion.new 1, 1, 1, "rc"
  # next_patch = current_version.bump_patch # => SemanticVersion(@build=nil, @major=1, @minor=1, @patch=1, @prerelease=SemanticVersion::Prerelease(@identifiers=[]))
  # next_patch.bump_patch                   # => SemanticVersion(@build=nil, @major=1, @minor=1, @patch=2, @prerelease=SemanticVersion::Prerelease(@identifiers=[]))
  # ```
  def bump_patch
    if prerelease.identifiers.empty?
      copy_with(patch: patch + 1, prerelease: nil, build: nil)
    else
      copy_with(prerelease: nil, build: nil)
    end
  end

  # The comparison operator.
  #
  # Returns `-1`, `0` or `1` depending on whether `self`'s version is lower than *other*'s,
  # equal to *other*'s version or greater than *other*'s version.
  #
  # ```
  # require "semantic_version"
  #
  # semver1 = SemanticVersion.new(1, 0, 0)
  # semver2 = SemanticVersion.new(2, 0, 0)
  #
  # semver1 <=> semver2 # => -1
  # semver2 <=> semver2 # => 0
  # semver2 <=> semver1 # => 1
  # ```
  def <=>(other : self) : Int32
    r = major <=> other.major
    return r unless r.zero?
    r = minor <=> other.minor
    return r unless r.zero?
    r = patch <=> other.patch
    return r unless r.zero?

    prerelease <=> other.prerelease
  end

  # Contains the pre-release version related to this semantic version
  struct Prerelease
    include Comparable(self)

    # Parses a `Prerelease` from the given pre-release version string
    #
    # ```
    # require "semantic_version"
    #
    # prerelease = SemanticVersion::Prerelease.parse("rc.1.3")
    # prerelease # => SemanticVersion::Prerelease(@identifiers=["rc", 1, 3])
    # ```
    def self.parse(str : String) : self
      identifiers = [] of String | Int32
      str.split('.') do |val|
        if number = val.to_i32?
          identifiers << number
        else
          identifiers << val
        end
      end
      Prerelease.new identifiers
    end

    # Array of identifiers that make up the pre-release metadata
    getter identifiers : Array(String | Int32)

    # Creates a new `Prerelease` instance with supplied array of identifiers
    def initialize(@identifiers : Array(String | Int32) = [] of String | Int32)
    end

    # Returns the string representation of this semantic version's pre-release metadata
    #
    # ```
    # require "semantic_version"
    #
    # semver = SemanticVersion.parse("0.27.1-rc.1")
    # semver.prerelease.to_s # => "rc.1"
    # ```
    def to_s(io : IO) : Nil
      identifiers.join(io, '.')
    end

    # The comparison operator.
    #
    # Returns `-1`, `0` or `1` depending on whether `self`'s pre-release is lower than *other*'s,
    # equal to *other*'s pre-release or greater than *other*'s pre-release.
    #
    # ```
    # require "semantic_version"
    #
    # prerelease1 = SemanticVersion::Prerelease.new(["rc", 1])
    # prerelease2 = SemanticVersion::Prerelease.new(["rc", 1, 2])
    #
    # prerelease1 <=> prerelease2 # => -1
    # prerelease1 <=> prerelease1 # => 0
    # prerelease2 <=> prerelease1 # => 1
    # ```
    def <=>(other : self) : Int32
      if identifiers.empty?
        if other.identifiers.empty?
          return 0
        else
          return 1
        end
      elsif other.identifiers.empty?
        return -1
      end

      identifiers.each_with_index do |item, i|
        return 1 if i >= other.identifiers.size # larger = higher precedence

        oitem = other.identifiers[i]
        r = compare item, oitem
        return r if r != 0
      end

      return -1 if identifiers.size != other.identifiers.size # larger = higher precedence
      0
    end

    private def compare(x : Int32, y : String)
      -1
    end

    private def compare(x : String, y : Int32)
      1
    end

    private def compare(x : Int32, y : Int32)
      x <=> y
    end

    private def compare(x : String, y : String)
      x <=> y
    end
  end
end
