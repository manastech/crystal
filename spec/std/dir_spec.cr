require "./spec_helper"
require "../support/env"

private def unset_tempdir(&)
  {% if flag?(:windows) %}
    with_env("TMP": nil, "TEMP": nil, "USERPROFILE": nil) { yield }
  {% else %}
    with_env("TMPDIR": nil) { yield }
  {% end %}
end

{% if flag?(:win32) %}
  private def make_hidden(path)
    wstr = Crystal::System.to_wstr(path)
    attributes = LibC.GetFileAttributesW(wstr)
    LibC.SetFileAttributesW(wstr, attributes | LibC::FILE_ATTRIBUTE_HIDDEN)
  end

  private def make_system(path)
    wstr = Crystal::System.to_wstr(path)
    attributes = LibC.GetFileAttributesW(wstr)
    LibC.SetFileAttributesW(wstr, attributes | LibC::FILE_ATTRIBUTE_SYSTEM)
  end
{% end %}

private def it_raises_on_null_byte(operation, &block)
  it "errors on #{operation}" do
    expect_raises(ArgumentError, "String contains null byte") do
      block.call
    end
  end
end

describe "Dir" do
  it "tests exists? on existing directory" do
    Dir.exists?(datapath).should be_true
  end

  it "tests exists? on existing file" do
    Dir.exists?(datapath("dir", "f1.txt")).should be_false
  end

  it "tests exists? on nonexistent directory" do
    Dir.exists?(datapath("foo", "bar")).should be_false
  end

  it "tests exists? on a directory path to a file" do
    Dir.exists?(datapath("dir", "f1.txt", "/")).should be_false
  end

  describe "empty?" do
    it "tests empty? on a full directory" do
      Dir.empty?(datapath).should be_false
    end

    it "tests empty? on an empty directory" do
      with_tempfile "empty_directory" do |path|
        Dir.mkdir(path, 0o700)
        Dir.empty?(path).should be_true
      end
    end

    it "tests empty? on nonexistent directory" do
      expect_raises(File::NotFoundError, "Error opening directory: '#{datapath("foo", "bar").inspect_unquoted}'") do
        Dir.empty?(datapath("foo", "bar"))
      end
    end

    it "tests empty? on a directory path to a file" do
      expect_raises(File::Error, "Error opening directory: '#{datapath("dir", "f1.txt", "/").inspect_unquoted}'") do
        Dir.empty?(datapath("dir", "f1.txt", "/"))
      end
    end
  end

  it "tests info on existing directory" do
    Dir.open(datapath) do |dir|
      info = dir.info
      info.directory?.should be_true
    end
  end

  it "tests mkdir and delete with a new path" do
    with_tempfile("mkdir") do |path|
      Dir.mkdir(path, 0o700)
      Dir.exists?(path).should be_true
      Dir.delete(path)
      Dir.exists?(path).should be_false
    end
  end

  it "tests mkdir and delete? with a new path" do
    with_tempfile("mkdir") do |path|
      Dir.mkdir(path, 0o700)
      Dir.exists?(path).should be_true
      Dir.delete?(path).should be_true
      Dir.exists?(path).should be_false
      Dir.delete?(path).should be_false
    end
  end

  it "tests mkdir and rmdir with a new path" do
    with_tempfile("mkdir") do |path|
      Dir.mkdir(path, 0o700)
      Dir.exists?(path).should be_true
      Dir.delete(path)
      Dir.exists?(path).should be_false
    end
  end

  it "tests mkdir with an existing path" do
    expect_raises(File::AlreadyExistsError, "Unable to create directory: '#{datapath.inspect_unquoted}'") do
      Dir.mkdir(datapath, 0o700)
    end
  end

  describe ".mkdir_p" do
    it "with a new path" do
      with_tempfile("mkdir_p-new") do |path|
        Dir.mkdir_p(path)
        Dir.exists?(path).should be_true
        path = File.join(path, "a", "b", "c")
        Dir.mkdir_p(path)
        Dir.exists?(path).should be_true
      end
    end

    context "path exists" do
      it "fails when path is a file" do
        expect_raises(File::AlreadyExistsError, "Unable to create directory: '#{datapath("test_file.txt").inspect_unquoted}'") do
          Dir.mkdir_p(datapath("test_file.txt"))
        end
      end

      it "noop when path is a directory" do
        Dir.exists?(datapath("dir")).should be_true
        Dir.mkdir_p(datapath("dir"))
        Dir.exists?(datapath("dir")).should be_true
      end
    end
  end

  describe ".delete" do
    it "raises with an nonexistent path" do
      with_tempfile("nonexistent") do |path|
        expect_raises(File::NotFoundError, "Unable to remove directory: '#{path.inspect_unquoted}'") do
          Dir.delete(path)
        end
      end
    end

    it "raises with a path that cannot be removed" do
      expect_raises(File::Error, "Unable to remove directory: '#{datapath.inspect_unquoted}'") do
        Dir.delete(datapath)
      end
    end

    it "raises with symlink directory" do
      with_tempfile("delete-target-directory", "delete-symlink-directory") do |target_path, symlink_path|
        Dir.mkdir(target_path)
        File.symlink(target_path, symlink_path)
        expect_raises(File::Error) do
          Dir.delete(symlink_path)
        end
      end
    end

    it "deletes a read-only directory" do
      with_tempfile("delete-readonly-dir") do |path|
        Dir.mkdir(path)
        File.chmod(path, 0o000)
        Dir.delete(path)
        Dir.exists?(path).should be_false
      end
    end
  end

  describe "glob" do
    it "tests glob with a single pattern" do
      Dir["#{Path[datapath].to_posix}/dir/*.txt"].sort.should eq [
        datapath("dir", "f1.txt"),
        datapath("dir", "f2.txt"),
        datapath("dir", "g2.txt"),
      ].sort
    end

    it "tests glob with multiple patterns" do
      Dir["#{Path[datapath].to_posix}/dir/*.txt", "#{Path[datapath].to_posix}/dir/subdir/*.txt"].sort.should eq [
        datapath("dir", "f1.txt"),
        datapath("dir", "f2.txt"),
        datapath("dir", "g2.txt"),
        datapath("dir", "subdir", "f1.txt"),
      ].sort
    end

    it "tests glob with a single pattern with block" do
      result = [] of String
      Dir.glob("#{Path[datapath].to_posix}/dir/*.txt") do |filename|
        result << filename
      end
      result.sort.should eq([
        datapath("dir", "f1.txt"),
        datapath("dir", "f2.txt"),
        datapath("dir", "g2.txt"),
      ].sort)
    end

    it "tests a recursive glob" do
      Dir["#{Path[datapath].to_posix}/dir/**/*.txt"].sort.should eq [
        datapath("dir", "f1.txt"),
        datapath("dir", "f2.txt"),
        datapath("dir", "g2.txt"),
        datapath("dir", "subdir", "f1.txt"),
        datapath("dir", "subdir", "subdir2", "f2.txt"),
      ].sort

      Dir["#{Path[datapath].to_posix}/dir/**/subdir2/f2.txt"].sort.should eq [
        datapath("dir", "subdir", "subdir2", "f2.txt"),
      ].sort

      Dir["#{Path[datapath].to_posix}/dir/**/subdir2/*.txt"].sort.should eq [
        datapath("dir", "subdir", "subdir2", "f2.txt"),
      ].sort
    end

    it "tests double recursive matcher (#10807)" do
      with_tempfile "glob-double-recurse" do |path|
        Dir.mkdir_p path
        Dir.cd(path) do
          path1 = Path["x", "b", "x"]
          Dir.mkdir_p path1
          File.touch path1.join("file")

          Dir["**/b/**/*"].sort.should eq [
            path1.to_s,
            path1.join("file").to_s,
          ].sort
        end
      end
    end

    it "tests double recursive matcher, multiple paths" do
      with_tempfile "glob-double-recurse2" do |path|
        Dir.mkdir_p path
        Dir.cd(path) do
          p1 = Path["x", "a", "x", "c"]
          p2 = Path["x", "a", "x", "a", "x", "c"]

          Dir.mkdir_p p1
          Dir.mkdir_p p2

          Dir["**/a/**/c"].sort.should eq [
            p1.to_s,
            p2.to_s,
          ].sort
        end
      end
    end

    it "tests a recursive glob with '?'" do
      Dir["#{Path[datapath].to_posix}/dir/f?.tx?"].sort.should eq [
        datapath("dir", "f1.txt"),
        datapath("dir", "f2.txt"),
        datapath("dir", "f3.txx"),
      ].sort
    end

    it "tests a recursive glob with alternation" do
      Dir["#{Path[datapath].to_posix}/{dir,dir/subdir}/*.txt"].sort.should eq [
        datapath("dir", "f1.txt"),
        datapath("dir", "f2.txt"),
        datapath("dir", "g2.txt"),
        datapath("dir", "subdir", "f1.txt"),
      ].sort
    end

    it "tests a glob with recursion inside alternation" do
      Dir["#{Path[datapath].to_posix}/dir/{**/*.txt,**/*.txx}"].sort.should eq [
        datapath("dir", "f1.txt"),
        datapath("dir", "f2.txt"),
        datapath("dir", "f3.txx"),
        datapath("dir", "g2.txt"),
        datapath("dir", "subdir", "f1.txt"),
        datapath("dir", "subdir", "subdir2", "f2.txt"),
      ].sort
    end

    it "tests a recursive glob with nested alternations" do
      Dir["#{Path[datapath].to_posix}/dir/{?1.*,{f,g}2.txt}"].sort.should eq [
        datapath("dir", "f1.txt"),
        datapath("dir", "f2.txt"),
        datapath("dir", "g2.txt"),
      ].sort
    end

    it "tests with []" do
      Dir["#{Path[datapath].to_posix}/dir/[a-z][0-9].txt"].sort.should eq [
        datapath("dir", "f1.txt"),
        datapath("dir", "f2.txt"),
        datapath("dir", "g2.txt"),
      ].sort
    end

    it "tests with {}" do
      Dir["#{Path[datapath].to_posix}/dir/{f,g}{1,2,3}.tx{t,x}"].sort.should eq [
        datapath("dir", "f1.txt"),
        datapath("dir", "f2.txt"),
        datapath("dir", "f3.txx"),
        datapath("dir", "g2.txt"),
      ].sort
    end

    {% if flag?(:windows) %}
      pending "tests with \\"
    {% else %}
      it "tests with \\" do
        with_tempfile "glob-escape-pattern" do |path|
          Dir.mkdir_p path
          Dir.cd(path) do
            File.touch "g1.txt"
            File.touch %q(\g3)
            File.touch %q(\g4*)

            Dir[%q(\\g*)].sort.should eq [
              "\\g3",
              "\\g4*",
            ].sort

            Dir[%q(*g?\*)].sort.should eq [
              "\\g4*",
            ].sort
          end
        end
      end
    {% end %}

    it "tests with *" do
      Dir["#{Path[datapath].to_posix}/dir/*"].sort.should eq [
        datapath("dir", "dots"),
        datapath("dir", "f1.txt"),
        datapath("dir", "f2.txt"),
        datapath("dir", "f3.txx"),
        datapath("dir", "g2.txt"),
        datapath("dir", "subdir"),
        datapath("dir", "subdir2"),
      ].sort
    end

    it "tests with ** (same as *)" do
      Dir["#{Path[datapath].to_posix}/dir/**"].sort.should eq [
        datapath("dir", "dots"),
        datapath("dir", "f1.txt"),
        datapath("dir", "f2.txt"),
        datapath("dir", "f3.txx"),
        datapath("dir", "g2.txt"),
        datapath("dir", "subdir"),
        datapath("dir", "subdir2"),
      ].sort
    end

    it "tests with */" do
      Dir["#{Path[datapath].to_posix}/dir/*/"].sort.should eq [
        datapath("dir", "dots", ""),
        datapath("dir", "subdir", ""),
        datapath("dir", "subdir2", ""),
      ].sort
    end

    it "tests glob with a single pattern with extra slashes" do
      Dir["spec/std////data////dir////*.txt"].sort.should eq [
        datapath("dir", "f1.txt"),
        datapath("dir", "f2.txt"),
        datapath("dir", "g2.txt"),
      ].sort
    end

    it "tests with relative path" do
      Dir["#{Path[datapath].to_posix}/dir/*/"].sort.should eq [
        datapath("dir", "dots", ""),
        datapath("dir", "subdir", ""),
        datapath("dir", "subdir2", ""),
      ].sort
    end

    it "tests with relative path (starts with .)" do
      Dir["./#{Path[datapath].to_posix}/dir/*/"].sort.should eq [
        File.join(".", "spec", "std", "data", "dir", "dots", ""),
        File.join(".", "spec", "std", "data", "dir", "subdir", ""),
        File.join(".", "spec", "std", "data", "dir", "subdir2", ""),
      ].sort
    end

    it "tests with relative path (starts with ..)" do
      Dir.cd(datapath) do
        base_path = Path["..", "data", "dir"]
        Dir["#{base_path.to_posix}/*/"].sort.should eq [
          base_path.join("dots", "").to_s,
          base_path.join("subdir", "").to_s,
          base_path.join("subdir2", "").to_s,
        ].sort
      end
    end

    it "tests with relative path starting recursive" do
      Dir["**/dir/*/"].sort.should eq [
        datapath("dir", "dots", ""),
        datapath("dir", "subdir", ""),
        datapath("dir", "subdir2", ""),
      ].sort
    end

    it "matches symlinks" do
      with_tempfile "symlinks" do |path|
        Dir.mkdir_p(path)

        link = Path[path, "f1_link.txt"]
        non_link = Path[path, "non_link.txt"]

        File.symlink(datapath("dir", "f1.txt"), link)
        File.symlink(datapath("dir", "nonexisting"), non_link)

        Dir["#{Path[path].to_posix}/*_link.txt"].sort.should eq [
          link.to_s,
          non_link.to_s,
        ].sort
        Dir["#{Path[path].to_posix}/non_link.txt"].should eq [non_link.to_s]
      end
    end

    it "matches symlink dir" do
      with_tempfile "symlink_dir" do |path|
        target = Path[path, "target"]
        non_link = target / "a.txt"
        link_dir = Path[path, "glob", "dir"]

        Dir.mkdir_p(Path[path, "glob"])
        Dir.mkdir_p(target)

        File.write(non_link, "")
        File.symlink(target, link_dir)

        Dir.glob("#{Path[path].to_posix}/glob/*/a.txt").sort.should eq [] of String
        Dir.glob("#{Path[path].to_posix}/glob/*/a.txt", follow_symlinks: true).sort.should eq [
          File.join(path, "glob", "dir", "a.txt"),
        ]
      end
    end

    it "empty pattern" do
      Dir[""].should eq [] of String
    end

    it "root pattern" do
      {% if flag?(:windows) %}
        Dir["C:/"].should eq ["C:\\"]
        Dir["/"].should eq [Path[Dir.current].anchor.not_nil!.to_s]
      {% else %}
        Dir["/"].should eq ["/"]
      {% end %}
    end

    it "pattern ending with .." do
      Dir["#{Path[datapath].to_posix}/dir/.."].sort.should eq [
        datapath("dir", ".."),
      ].sort
    end

    it "pattern ending with */.." do
      Dir["#{Path[datapath].to_posix}/dir/*/.."].sort.should eq [
        datapath("dir", "dots", ".."),
        datapath("dir", "subdir", ".."),
        datapath("dir", "subdir2", ".."),
      ].sort
    end

    it "pattern ending with ." do
      Dir["#{Path[datapath].to_posix}/dir/."].sort.should eq [
        datapath("dir", "."),
      ].sort
    end

    it "pattern ending with */." do
      Dir["#{Path[datapath].to_posix}/dir/*/."].sort.should eq [
        datapath("dir", "dots", "."),
        datapath("dir", "subdir", "."),
        datapath("dir", "subdir2", "."),
      ].sort
    end

    context "match: :dot_files / match_hidden" do
      it "matches dot files" do
        Dir.glob("#{Path[datapath].to_posix}/dir/dots/**/*", match: :dot_files).sort.should eq [
          datapath("dir", "dots", ".dot.hidden"),
          datapath("dir", "dots", ".hidden"),
          datapath("dir", "dots", ".hidden", "f1.txt"),
        ].sort
        Dir.glob("#{Path[datapath].to_posix}/dir/dots/**/*", match_hidden: true).sort.should eq [
          datapath("dir", "dots", ".dot.hidden"),
          datapath("dir", "dots", ".hidden"),
          datapath("dir", "dots", ".hidden", "f1.txt"),
        ].sort
      end

      it "ignores hidden files" do
        Dir.glob("#{Path[datapath].to_posix}/dir/dots/*", match: :none).should be_empty
        Dir.glob("#{Path[datapath].to_posix}/dir/dots/*", match_hidden: false).should be_empty
      end

      it "ignores hidden files recursively" do
        Dir.glob("#{Path[datapath].to_posix}/dir/dots/**/*", match: :none).should be_empty
        Dir.glob("#{Path[datapath].to_posix}/dir/dots/**/*", match_hidden: false).should be_empty
      end
    end

    it "respects `CaseInsensitive`" do
      with_tempfile("glob-case-insensitive") do |path|
        FileUtils.mkdir_p(path)

        a_txt = File.join(path, "a.txt")
        b_txt = File.join(path, "B.TXT")

        File.write(a_txt, "")
        File.write(b_txt, "")

        Dir.glob("#{Path[path].to_posix}/*.txt", match: :case_insensitive).should eq [a_txt, b_txt]
        Dir.glob("#{Path[path].to_posix}/*.TXT", match: :case_insensitive).should eq [a_txt, b_txt]
        Dir.glob("#{Path[path].parent.to_posix}/GlOb-cAsE-INSENSITIVE/*", match: :case_insensitive).should eq [a_txt, b_txt]
      end
    end

    {% if flag?(:win32) %}
      it "respects `NativeHidden` and `OSHidden`" do
        with_tempfile("glob-system-hidden") do |path|
          FileUtils.mkdir_p(path)

          visible_txt = File.join(path, "visible.txt")
          hidden_txt = File.join(path, "hidden.txt")
          system_txt = File.join(path, "system.txt")
          system_hidden_txt = File.join(path, "system_hidden.txt")

          File.write(visible_txt, "")
          File.write(hidden_txt, "")
          File.write(system_txt, "")
          File.write(system_hidden_txt, "")
          make_hidden(hidden_txt)
          make_hidden(system_hidden_txt)
          make_system(system_txt)
          make_system(system_hidden_txt)

          visible_dir = File.join(path, "visible_dir")
          hidden_dir = File.join(path, "hidden_dir")
          system_dir = File.join(path, "system_dir")
          system_hidden_dir = File.join(path, "system_hidden_dir")

          Dir.mkdir(visible_dir)
          Dir.mkdir(hidden_dir)
          Dir.mkdir(system_dir)
          Dir.mkdir(system_hidden_dir)
          make_hidden(hidden_dir)
          make_hidden(system_hidden_dir)
          make_system(system_dir)
          make_system(system_hidden_dir)

          inside_visible = File.join(visible_dir, "inside.txt")
          inside_hidden = File.join(hidden_dir, "inside.txt")
          inside_system = File.join(system_dir, "inside.txt")
          inside_system_hidden = File.join(system_hidden_dir, "inside.txt")

          File.write(inside_visible, "")
          File.write(inside_hidden, "")
          File.write(inside_system, "")
          File.write(inside_system_hidden, "")

          expected = [visible_txt, visible_dir, inside_visible, system_txt, system_dir, inside_system].sort!
          expected_hidden = (expected + [hidden_txt, hidden_dir, inside_hidden]).sort!
          expected_system_hidden = (expected_hidden + [system_hidden_txt, system_hidden_dir, inside_system_hidden]).sort!

          Dir.glob("#{Path[path].to_posix}/**/*", match: :none).sort.should eq(expected)
          Dir.glob("#{Path[path].to_posix}/**/*", match: :native_hidden).sort.should eq(expected_hidden)
          Dir.glob("#{Path[path].to_posix}/**/*", match: :os_hidden).sort.should eq(expected)
          Dir.glob("#{Path[path].to_posix}/**/*", match: File::MatchOptions[NativeHidden, OSHidden]).sort.should eq(expected_system_hidden)
        end
      end
    {% end %}

    context "with path" do
      expected = [
        datapath("dir", "f1.txt"),
        datapath("dir", "f2.txt"),
        datapath("dir", "g2.txt"),
      ]

      it "posix path" do
        Dir[Path.posix(Path[datapath].to_posix, "dir", "*.txt")].sort.should eq expected
        Dir[[Path.posix(Path[datapath].to_posix, "dir", "*.txt")]].sort.should eq expected
      end

      it "windows path" do
        Dir[Path.windows(datapath, "dir", "*.txt")].sort.should eq expected
        Dir[[Path.windows(datapath, "dir", "*.txt")]].sort.should eq expected
      end
    end
  end

  describe "cd" do
    it "accepts string" do
      cwd = Dir.current
      Dir.cd("..")
      Dir.current.should_not eq(cwd)
      Dir.cd(cwd)
      Dir.current.should eq(cwd)
    end

    it "accepts path" do
      cwd = Dir.current
      Dir.cd(Path.new(".."))
      Dir.current.should_not eq(cwd)
      Dir.cd(cwd)
      Dir.current.should eq(cwd)
    end

    it "raises" do
      expect_raises(File::NotFoundError, "Error while changing directory: '/nope'") do
        Dir.cd("/nope")
      end
    end

    it "accepts a block with path" do
      cwd = Dir.current

      Dir.cd(Path.new("..")) do
        Dir.current.should_not eq(cwd)
      end

      Dir.current.should eq(cwd)
    end

    it "accepts a block with string" do
      cwd = Dir.current

      Dir.cd("..") do
        Dir.current.should_not eq(cwd)
      end

      Dir.current.should eq(cwd)
    end
  end

  describe ".current" do
    # can't use backtick in interpreted code (#12241)
    pending_interpreted "matches shell" do
      Dir.current.should eq(`#{{{ flag?(:win32) ? "cmd /c cd" : "pwd" }}}`.chomp)
    end

    # Skip spec on Windows due to weak support for symlinks and $PWD.
    {% unless flag?(:win32) %}
      it "follows $PWD" do
        with_tempfile "current-pwd" do |path|
          Dir.mkdir_p path
          # Resolve any symbolic links in path caused by tmpdir being a link.
          # For example on macOS, /tmp is a symlink to /private/tmp.
          path = File.realpath(path)

          target_path = File.join(path, "target")
          link_path = File.join(path, "link")
          Dir.mkdir_p target_path
          File.symlink(target_path, link_path)

          Dir.cd(link_path) do
            with_env({"PWD" => nil}) do
              Dir.current.should eq target_path
            end

            with_env({"PWD" => link_path}) do
              Dir.current.should eq link_path
            end

            with_env({"PWD" => "/some/other/path"}) do
              Dir.current.should eq target_path
            end
          end
        end
      end
    {% end %}
  end

  describe ".tempdir" do
    it "returns default directory for tempfiles" do
      unset_tempdir do
        {% if flag?(:windows) %}
          # GetTempPathW defaults to the Windows directory when %TMP%, %TEMP%
          # and %USERPROFILE% are not set.
          # Without going further into the implementation details, simply
          # verifying that the directory exits is sufficient.
          Dir.exists?(Dir.tempdir).should be_true
        {% else %}
          # POSIX implementation is in Crystal::System::Dir and defaults to
          # `/tmp` when $TMPDIR is not set.
          Dir.tempdir.should eq "/tmp"
        {% end %}
      end
    end

    it "returns configure directory for tempfiles" do
      unset_tempdir do
        tmp_path = Path["my_temporary_path"].expand.to_s
        ENV[{{ flag?(:windows) ? "TMP" : "TMPDIR" }}] = tmp_path
        Dir.tempdir.should eq tmp_path
      end
    end
  end

  it "opens with new" do
    filenames = [] of String

    dir = Dir.new(datapath("dir"))
    dir.each do |filename|
      filenames << filename
    end.should be_nil
    dir.close

    filenames.should contain("f1.txt")
  end

  it "opens with open" do
    filenames = [] of String

    Dir.open(datapath("dir")) do |dir|
      dir.each do |filename|
        filenames << filename
      end.should be_nil
    end

    filenames.should contain("f1.txt")
  end

  describe "#path" do
    it "returns init value" do
      path = datapath("dir")
      dir = Dir.new(path)
      dir.path.should eq path
    end
  end

  it "lists entries" do
    filenames = Dir.entries(datapath("dir"))
    filenames.should contain(".")
    filenames.should contain("..")
    filenames.should contain("f1.txt")
  end

  it "lists children" do
    Dir.children(datapath("dir")).should eq(Dir.entries(datapath("dir")) - %w(. ..))
  end

  it "does to_s" do
    Dir.new(datapath("dir")).to_s.should eq("#<Dir:#{datapath("dir")}>")
  end

  it "gets dir iterator" do
    filenames = [] of String

    iter = Dir.new(datapath("dir")).each
    iter.each do |filename|
      filenames << filename
    end

    filenames.should contain(".")
    filenames.should contain("..")
    filenames.should contain("f1.txt")
  end

  it "gets child iterator" do
    filenames = [] of String

    iter = Dir.new(datapath("dir")).each_child
    iter.each do |filename|
      filenames << filename
    end

    filenames.should_not contain(".")
    filenames.should_not contain("..")
    filenames.should contain("f1.txt")
  end

  it "double close doesn't error" do
    dir = Dir.open(datapath("dir")) do |dir|
      dir.close
      dir.close
    end
  end

  describe "raises on null byte" do
    it_raises_on_null_byte "new" do
      Dir.new("foo\0bar")
    end

    it_raises_on_null_byte "cd" do
      Dir.cd("foo\0bar")
    end

    it_raises_on_null_byte "exists?" do
      Dir.exists?("foo\0bar")
    end

    it_raises_on_null_byte "mkdir" do
      Dir.mkdir("foo\0bar")
    end

    it_raises_on_null_byte "mkdir_p" do
      Dir.mkdir_p("foo\0bar")
    end

    it_raises_on_null_byte "delete" do
      Dir.delete("foo\0bar")
    end
  end
end
