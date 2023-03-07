require "./spec_helper"
require "file_utils"

private def test_with_string_and_path(*paths, &)
  yield *paths
  yield *paths.map { |path| Path[path] }
end

describe "FileUtils" do
  describe ".cd" do
    it "should work" do
      cwd = Dir.current
      test_with_string_and_path(cwd) do |arg|
        FileUtils.cd("..")
        Dir.current.should_not eq(cwd)
        FileUtils.cd(arg)
        Dir.current.should eq(cwd)
      end
    end

    it "raises" do
      test_with_string_and_path "/nope" do |arg|
        expect_raises(File::NotFoundError, "Error while changing directory: '/nope'") do
          FileUtils.cd(arg)
        end
      end
    end

    it "accepts a block" do
      cwd = Dir.current
      test_with_string_and_path("..") do |arg|
        FileUtils.cd(arg) do
          Dir.current.should_not eq(cwd)
        end

        Dir.current.should eq(cwd)
      end
    end
  end

  describe ".pwd" do
    it "returns the current working directory" do
      FileUtils.pwd.should eq(Dir.current)
    end
  end

  describe ".cmp" do
    it "compares two equal files" do
      test_with_string_and_path(datapath("test_file.txt")) do |arg|
        FileUtils.cmp(arg, arg).should be_true
      end
    end

    it "compares two different files" do
      test_with_string_and_path(datapath("test_file.txt"), datapath("test_file.ini")) do |*args|
        FileUtils.cmp(*args).should be_false
      end
    end
  end

  describe ".touch" do
    it "creates file if it doesn't exist" do
      with_tempfile("touch.txt") do |path|
        test_with_string_and_path(path) do |arg|
          File.exists?(path).should be_false
          FileUtils.touch(arg)
          File.exists?(path).should be_true

          FileUtils.rm_rf path
        end
      end
    end

    it "creates multiple files if they don't exists" do
      with_tempfile("touch1", "touch2", "touch3") do |path1, path2, path3|
        paths = {path1, path2, path3}
        test_with_string_and_path(*paths) do |*args|
          paths.each { |path| File.exists?(path).should be_false }
          FileUtils.touch(args.to_a)
          paths.each { |path| File.exists?(path).should be_true }

          FileUtils.rm_rf paths
        end
      end
    end
  end

  describe ".cp" do
    it "copies a file" do
      src_path = datapath("test_file.txt")
      with_tempfile("cp.txt") do |out_path|
        test_with_string_and_path(src_path, out_path) do |*args|
          File.exists?(out_path).should be_false
          FileUtils.cp(*args)
          File.exists?(out_path).should be_true
          FileUtils.cmp(src_path, out_path).should be_true

          FileUtils.rm_rf(out_path)
        end
      end
    end

    pending_win32 "copies permissions" do
      with_tempfile("cp-permissions-src.txt", "cp-permissions-out.txt") do |src_path, out_path|
        test_with_string_and_path(src_path, out_path) do |*args|
          File.write(src_path, "foo")
          File.chmod(src_path, 0o700)

          FileUtils.cp(*args)

          File.info(out_path).permissions.should eq(File::Permissions.new(0o700))
          FileUtils.cmp(src_path, out_path).should be_true

          FileUtils.rm_rf(out_path)
        end
      end
    end

    it "raises an error if the directory doesn't exist" do
      expect_raises(ArgumentError, "No such directory : not_existing_dir") do
        test_with_string_and_path(datapath("test_file.txt"), "not_existing_dir") do |src_path, dest_path|
          FileUtils.cp({src_path}, dest_path)
        end
      end
    end

    it "copies multiple files" do
      name1 = "test_file.txt"
      name2 = "test_file.ini"
      src_path = datapath
      src_name1 = File.join(src_path, name1)
      src_name2 = File.join(src_path, name2)
      with_tempfile("cp-multiple") do |out_path|
        out_name1 = File.join(out_path, name1)
        out_name2 = File.join(out_path, name2)
        test_with_string_and_path(src_name1, src_name2, out_path) do |arg1, arg2, dest_arg|
          Dir.mkdir_p(out_path)

          File.exists?(out_name1).should be_false
          File.exists?(out_name2).should be_false

          FileUtils.cp({arg1, arg2}, dest_arg)

          File.exists?(out_name1).should be_true
          File.exists?(out_name2).should be_true
          FileUtils.cmp(src_name1, out_name1).should be_true
          FileUtils.cmp(src_name2, out_name2).should be_true

          FileUtils.rm_rf(out_path)
        end
      end
    end
  end

  describe ".cp_r" do
    it "copies a directory recursively" do
      with_tempfile("cp_r-test", "cp_r-test-copied") do |src_path, dest_path|
        test_with_string_and_path(src_path, dest_path) do |*args|
          File.exists?(File.join(dest_path, "a")).should be_false
          File.exists?(File.join(dest_path, "b/c")).should be_false
          Dir.mkdir_p(src_path)
          File.write(File.join(src_path, "a"), "")
          Dir.mkdir(File.join(src_path, "b"))
          File.write(File.join(src_path, "b/c"), "")

          FileUtils.cp_r(*args)
          File.exists?(File.join(dest_path, "a")).should be_true
          File.exists?(File.join(dest_path, "b/c")).should be_true

          FileUtils.rm_rf(src_path)
          FileUtils.rm_rf(dest_path)
        end
      end
    end

    it "copies a directory recursively if destination exists and is empty" do
      with_tempfile("cp_r-test", "cp_r-test-copied") do |src_path, dest_path|
        test_with_string_and_path(src_path, dest_path) do |*args|
          Dir.mkdir_p(dest_path)

          Dir.mkdir_p(src_path)
          File.exists?(File.join(dest_path, "cp_r-test", "a")).should be_false
          File.exists?(File.join(dest_path, "cp_r-test", "b/c")).should be_false
          File.write(File.join(src_path, "a"), "")
          Dir.mkdir(File.join(src_path, "b"))
          File.write(File.join(src_path, "b/c"), "")

          FileUtils.cp_r(*args)
          File.exists?(File.join(dest_path, "cp_r-test", "a")).should be_true
          File.exists?(File.join(dest_path, "cp_r-test", "b/c")).should be_true

          FileUtils.rm_rf(src_path)
          FileUtils.rm_rf(dest_path)
        end
      end
    end

    it "copies a directory recursively if destination exists leaving existing files" do
      with_tempfile("cp_r-test", "cp_r-test-copied") do |src_path, dest_path|
        test_with_string_and_path(src_path, dest_path) do |*args|
          Dir.mkdir_p(dest_path)
          File.write(File.join(dest_path, "d"), "")
          Dir.mkdir(File.join(dest_path, "cp_r-test"))
          Dir.mkdir(File.join(dest_path, "cp_r-test", "b"))

          File.exists?(File.join(dest_path, "cp_r-test", "a")).should be_false
          File.exists?(File.join(dest_path, "cp_r-test", "b/c")).should be_false
          File.exists?(File.join(dest_path, "d")).should be_true

          Dir.mkdir_p(src_path)
          File.write(File.join(src_path, "a"), "")
          Dir.mkdir(File.join(src_path, "b"))
          File.write(File.join(src_path, "b/c"), "")

          FileUtils.cp_r(*args)
          File.exists?(File.join(dest_path, "cp_r-test", "a")).should be_true
          File.exists?(File.join(dest_path, "cp_r-test", "b/c")).should be_true
          File.exists?(File.join(dest_path, "d")).should be_true

          FileUtils.rm_rf(src_path)
          FileUtils.rm_rf(dest_path)
        end
      end
    end
  end

  describe ".rm" do
    it "tests rm with an existing path" do
      with_tempfile("rm") do |path|
        test_with_string_and_path(path) do |arg|
          File.write(path, "")
          FileUtils.rm(arg).should be_nil
          File.exists?(path).should be_false
        end
      end
    end

    it "tests rm with nonexistent path" do
      with_tempfile("rm-nonexistent") do |path|
        test_with_string_and_path(path) do |arg|
          expect_raises(File::NotFoundError, "Error deleting file: '#{path.inspect_unquoted}'") do
            FileUtils.rm(arg)
          end
        end
      end
    end

    it "tests rm with directory" do
      with_tempfile("rm-directory") do |path|
        test_with_string_and_path(path) do |arg|
          Dir.mkdir_p(path)

          expect_raises(File::Error, "Error deleting file: '#{path.inspect_unquoted}': Is a directory") do
            FileUtils.rm(arg)
          end
          Dir.exists?(path).should be_true
        end
      end
    end

    it "tests rm with file and directory" do
      with_tempfile("rm-multi1", "rm-multi2", "rm-dir3") do |path1, path2, path3|
        test_with_string_and_path(path1, path2, path3) do |*args|
          File.write(path1, "")
          File.write(path2, "")
          Dir.mkdir_p(path3)

          expect_raises(File::Error, "Error deleting file: '#{path3.inspect_unquoted}': Is a directory") do
            FileUtils.rm(args.to_a)
          end
          File.exists?(path1).should be_false
          File.exists?(path2).should be_false
          Dir.exists?(path3).should be_true
        end
      end
    end

    it "tests rm with multiple existing paths" do
      with_tempfile("rm-multi1", "rm-multi2") do |path1, path2|
        test_with_string_and_path(path1, path2) do |*args|
          File.write(path1, "")
          File.write(path2, "")
          FileUtils.rm(args.to_a).should be_nil
          File.exists?(path1).should be_false
          File.exists?(path2).should be_false
        end
      end
    end

    it "tests rm with some nonexistent paths" do
      with_tempfile("rm-nonexistent1", "rm-nonexistent2") do |path1, path2|
        test_with_string_and_path(path1, path2) do |arg1, arg2|
          File.write(path1, "")
          File.write(path2, "")

          expect_raises(File::NotFoundError, "Error deleting file: '#{path2.inspect_unquoted}'") do
            FileUtils.rm([arg1, arg2, arg2])
          end
        end
      end
    end
  end

  describe ".rm_f" do
    it "tests rm_f with an existing path" do
      with_tempfile("rm_f") do |path|
        test_with_string_and_path(path) do |arg|
          File.write(path, "")
          FileUtils.rm_f(arg).should be_nil
          File.exists?(path).should be_false
        end
      end
    end

    it "tests rm_f with nonexistent path" do
      with_tempfile("rm_f-nonexistent") do |path|
        test_with_string_and_path(path) do |arg|
          FileUtils.rm_f(arg)
        end
      end
    end

    it "tests rm_f with directory" do
      with_tempfile("rm_f-directory") do |path|
        test_with_string_and_path(path) do |arg|
          Dir.mkdir_p(path)
          expect_raises(File::Error, "Error deleting file: '#{path.inspect_unquoted}': Is a directory") do
            FileUtils.rm_f(arg)
          end
          Dir.exists?(path).should be_true
        end
      end
    end

    it "tests rm_f with file and directory" do
      with_tempfile("rm_f-multi1", "rm_f-multi2", "rm_f-dir3") do |path1, path2, path3|
        test_with_string_and_path(path1, path2, path3) do |*args|
          File.write(path1, "")
          File.write(path2, "")
          Dir.mkdir_p(path3)

          expect_raises(File::Error, "Error deleting file: '#{path3.inspect_unquoted}': Is a directory") do
            FileUtils.rm_f(args.to_a)
          end

          File.exists?(path1).should be_false
          File.exists?(path2).should be_false
          Dir.exists?(path3).should be_true
        end
      end
    end

    it "tests rm_f with multiple existing paths" do
      with_tempfile("rm_f-multi1", "rm_f-multi2") do |path1, path2|
        test_with_string_and_path(path1, path2) do |*args|
          File.write(path1, "")
          File.write(path2, "")
          FileUtils.rm_f(args.to_a).should be_nil
          File.exists?(path1).should be_false
          File.exists?(path2).should be_false
        end
      end
    end

    it "tests rm with some nonexistent paths" do
      with_tempfile("rm-nonexistent1", "rm-nonexistent2") do |path1, path2|
        test_with_string_and_path(path1, path2) do |arg1, arg2|
          File.write(path1, "")
          File.write(path2, "")
          FileUtils.rm_f([arg1, arg2, arg2])
          File.exists?(path1).should be_false
          File.exists?(path2).should be_false
        end
      end
    end
  end

  describe ".rm_r" do
    it "deletes a directory recursively" do
      with_tempfile("rm_r") do |path|
        test_with_string_and_path(path) do |arg|
          Dir.mkdir(path)
          File.write(File.join(path, "a"), "")
          Dir.mkdir(File.join(path, "b"))
          File.write(File.join(path, "b/c"), "")

          FileUtils.rm_r(arg)
          Dir.exists?(path).should be_false
        end
      end
    end

    pending_win32 "doesn't follow symlinks" do
      with_tempfile("rm_r-removed", "rm_r-linked") do |removed_path, linked_path|
        link_path = File.join(removed_path, "link")
        file_path = File.join(linked_path, "file")

        test_with_string_and_path(removed_path) do |arg|
          Dir.mkdir(removed_path)
          Dir.mkdir(linked_path)
          File.symlink(linked_path, link_path)
          File.write(file_path, "")

          Dir.exists?(removed_path).should be_true
          Dir.exists?(linked_path).should be_true
          File.exists?(file_path).should be_true

          FileUtils.rm_r(arg)
          Dir.exists?(removed_path).should be_false
          Dir.exists?(linked_path).should be_true
          File.exists?(file_path).should be_true

          FileUtils.rm_rf(linked_path)
        end
      end
    end
  end

  describe ".rm_rf" do
    it "delete recursively a directory" do
      with_tempfile("rm_rf") do |path|
        test_with_string_and_path(path) do |arg|
          FileUtils.mkdir(path)
          File.write(File.join(path, "a"), "")
          FileUtils.mkdir(File.join(path, "b"))
          FileUtils.rm_rf(arg).should be_nil
          Dir.exists?(path).should be_false
        end
      end
    end

    it "delete recursively multiple directory" do
      with_tempfile("rm_rf-multi1", "rm_rf-multi2") do |path1, path2|
        test_with_string_and_path(path1, path2) do |*args|
          FileUtils.mkdir(path1)
          FileUtils.mkdir(path2)
          File.write(File.join(path1, "a"), "")
          File.write(File.join(path2, "a"), "")
          FileUtils.mkdir(File.join(path1, "b"))
          FileUtils.mkdir(File.join(path2, "b"))
          FileUtils.rm_rf(args.to_a).should be_nil
          Dir.exists?(path1).should be_false
          Dir.exists?(path2).should be_false
        end
      end
    end

    it "doesn't return error on nonexistent file" do
      with_tempfile("rm_rf-nonexistent") do |path|
        test_with_string_and_path(path) do |arg|
          FileUtils.rm_rf(arg).should be_nil
        end
      end
    end

    it "doesn't return error on nonexistent files" do
      with_tempfile("rm_rf-nonexistent") do |path1|
        path2 = File.join(path1, "a")
        test_with_string_and_path(path1, path2) do |*args|
          FileUtils.mkdir(path1)
          FileUtils.rm_rf(args.to_a).should be_nil
        end
      end
    end
  end

  describe ".mv" do
    it "moves a file from one place to another" do
      with_tempfile("mv1", "mv2") do |path1, path2|
        a = File.join(path1, "a")
        b = File.join(path2, "b")
        test_with_string_and_path(a, b) do |*args|
          FileUtils.mkdir([path1, path2])
          File.write(a, "")
          FileUtils.mv(*args).should be_nil
          File.exists?(a).should be_false
          File.exists?(b).should be_true
          FileUtils.rm_rf(path1)
          FileUtils.rm_rf(path2)
        end
      end
    end

    it "raises an error if non correct arguments" do
      with_tempfile("mv-nonexistent") do |path|
        test_with_string_and_path(File.join(path, "a"), File.join(path, "b")) do |*args|
          expect_raises(File::NotFoundError, "Error renaming file: '#{File.join(path, "a").inspect_unquoted}' -> '#{File.join(path, "b").inspect_unquoted}'") do
            FileUtils.mv(*args)
          end
        end
      end
    end

    it "moves multiple files to one place" do
      with_tempfile("mv-multi1", "mv-multi2", "mv-multi3") do |path1, path2, path3|
        source1 = File.join(path1, "a")
        source2 = File.join(path2, "b")
        test_with_string_and_path(source1, source2, path3) do |arg1, arg2, arg3|
          FileUtils.mkdir([path1, path2, path3])
          File.write(source1, "")
          File.write(source2, "")
          FileUtils.mv([arg1, arg2], arg3).should be_nil
          File.exists?(source1).should be_false
          File.exists?(source2).should be_false
          File.exists?(File.join(path3, "a")).should be_true
          File.exists?(File.join(path3, "b")).should be_true
          FileUtils.rm_rf([path1, path2, path3])
        end
      end
    end

    it "raises an error if dest is non correct" do
      expect_raises ArgumentError do
        with_tempfile("mv-nonexistent") do |path|
          test_with_string_and_path(File.join(path, "a"), File.join(path, "b"), File.join(path, "c")) do |arg1, arg2, arg3|
            FileUtils.mv([arg1, arg2], arg3)
          end
        end
      end
    end

    it "moves all existing files to destination" do
      with_tempfile("mv-source", "mv-target") do |source_path, target_path|
        path1 = File.join(source_path, "a")
        path2 = File.join(source_path, "b")
        path3 = File.join(source_path, "c", "sub")

        test_with_string_and_path(path1, path2, path3, target_path) do |arg1, arg2, arg3, arg4|
          FileUtils.mkdir_p([path1, path2, target_path])
          path1 = File.join(path1, "a")
          path2 = File.join(path2, "b")
          File.write(path1, "")
          File.write(path2, "")
          FileUtils.mv([arg1, arg2, arg3], arg4).should be_nil
          File.exists?(path1).should be_false
          File.exists?(path2).should be_false
          File.exists?(File.join(target_path, "a")).should be_true
          File.exists?(File.join(target_path, "b")).should be_true
          FileUtils.rm_rf([path1, path2, target_path])
        end
      end
    end
  end

  it "tests mkdir and rmdir with a new path" do
    with_tempfile("mkdir-new") do |path|
      test_with_string_and_path(path) do |arg|
        FileUtils.mkdir(arg, 0o700).should be_nil
        Dir.exists?(path).should be_true
        FileUtils.rmdir(arg).should be_nil
        Dir.exists?(path).should be_false
      end
    end
  end

  it "tests mkdir and rmdir with multiple new paths" do
    with_tempfile("mkdir-new1", "mkdir-new2") do |path1, path2|
      test_with_string_and_path(path1, path2) do |*args|
        FileUtils.mkdir(args.to_a, 0o700).should be_nil
        Dir.exists?(path1).should be_true
        Dir.exists?(path2).should be_true
        FileUtils.rmdir(args.to_a).should be_nil
        Dir.exists?(path1).should be_false
        Dir.exists?(path2).should be_false
        FileUtils.rm_rf([path1, path2])
      end
    end
  end

  it "tests mkdir with an existing path" do
    test_with_string_and_path(datapath) do |arg|
      expect_raises(File::AlreadyExistsError, "Unable to create directory: '#{datapath.inspect_unquoted}'") do
        Dir.mkdir(arg, 0o700)
      end
    end
  end

  it "tests mkdir with multiples existing paths" do
    test_with_string_and_path(datapath) do |arg|
      expect_raises(File::AlreadyExistsError, "Unable to create directory: '#{datapath.inspect_unquoted}'") do
        FileUtils.mkdir([arg, arg], 0o700)
      end
    end

    with_tempfile("mkdir-nonexistent") do |path|
      test_with_string_and_path(path, datapath) do |*args|
        expect_raises(File::AlreadyExistsError, "Unable to create directory: '#{datapath.inspect_unquoted}'") do
          FileUtils.mkdir(args.to_a, 0o700)
        end
        FileUtils.rm_rf(path)
      end
    end
  end

  it "tests mkdir_p with multiples new path" do
    with_tempfile("mkdir_p-multi1", "mkdir_p-multi2") do |path1, path2|
      path3 = File.join({path1, "a", "b", "c"})
      path4 = File.join({path2, "a", "b", "c"})
      test_with_string_and_path(path3, path4) do |*args|
        FileUtils.mkdir_p([path1, path2]).should be_nil
        Dir.exists?(path1).should be_true
        Dir.exists?(path2).should be_true
        FileUtils.mkdir_p(args.to_a).should be_nil
        Dir.exists?(path3).should be_true
        Dir.exists?(path4).should be_true
        FileUtils.rm_rf([path1, path2])
      end
    end
  end

  it "tests mkdir_p with multiple existing path" do
    FileUtils.mkdir_p([datapath, datapath]).should be_nil
    with_tempfile("mkdir_p-existing") do |path|
      test_with_string_and_path(datapath("test_file.txt"), path) do |*args|
        expect_raises(File::AlreadyExistsError, "Unable to create directory: '#{datapath("test_file.txt").inspect_unquoted}'") do
          FileUtils.mkdir_p(args.to_a)
        end
      end
    end
  end

  it "tests rmdir with an nonexistent path" do
    with_tempfile("rmdir-nonexistent") do |path|
      test_with_string_and_path(path) do |arg|
        expect_raises(File::NotFoundError, "Unable to remove directory: '#{path.inspect_unquoted}'") do
          FileUtils.rmdir(arg)
        end
      end
    end
  end

  it "tests rmdir with multiple nonexistent path" do
    with_tempfile("rmdir-nonexistent") do |path|
      test_with_string_and_path("#{path}1", "#{path}2") do |*args|
        expect_raises(File::NotFoundError, "Unable to remove directory: '#{path.inspect_unquoted}1'") do
          FileUtils.rmdir(args.to_a)
        end
      end
    end
  end

  it "tests rmdir with a path that cannot be removed" do
    test_with_string_and_path(datapath) do |arg|
      expect_raises(File::Error, "Unable to remove directory: '#{datapath.inspect_unquoted}'") do
        FileUtils.rmdir(arg)
      end
    end
  end

  it "tests rmdir with multiple path that cannot be removed" do
    test_with_string_and_path(datapath) do |arg|
      expect_raises(File::Error, "Unable to remove directory: '#{datapath.inspect_unquoted}'") do
        FileUtils.rmdir([arg, arg])
      end
    end
  end

  describe ".ln" do
    it "creates a hardlink" do
      with_tempfile("ln_src", "ln_dst") do |path1, path2|
        test_with_string_and_path(path1, path2) do |arg1, arg2|
          FileUtils.touch(path1)
          FileUtils.ln(arg1, arg2)
          File.exists?(path2).should be_true
          File.symlink?(path2).should be_false
          FileUtils.rm_rf([path1, path2])
        end
      end
    end

    it "creates a hardlink inside a destination dir" do
      with_tempfile("ln_src", "ln_dst_dir") do |path1, path2|
        path2 += File::SEPARATOR
        path3 = File.join(path2, File.basename(path1))
        test_with_string_and_path(path1, path2) do |arg1, arg2|
          FileUtils.touch(path1)
          FileUtils.mkdir(path2)
          FileUtils.ln(arg1, arg2)
          File.exists?(path3).should be_true
          File.symlink?(path3).should be_false
          FileUtils.rm_rf([path1, path2])
        end
      end
    end

    it "creates multiple hardlinks inside a destination dir" do
      with_tempfile("ln_src_1", "ln_src_2", "ln_src_3", "ln_dst_dir") do |path1, path2, path3, dir_path|
        paths = [path1, path2, path3]
        dir_path += File::SEPARATOR
        test_with_string_and_path(path1, path2, path3, dir_path) do |arg1, arg2, arg3, arg4|
          paths.each { |path| FileUtils.touch(path) }
          FileUtils.mkdir(dir_path)
          FileUtils.ln([arg1, arg2, arg3], arg4)

          paths.each do |path|
            link_path = File.join(dir_path, File.basename(path))
            File.exists?(link_path).should be_true
            File.symlink?(link_path).should be_false
          end
          FileUtils.rm_rf(dir_path)
        end
      end
    end

    it "fails with a nonexistent source" do
      with_tempfile("ln_src_missing", "ln_dst_missing") do |path1, path2|
        test_with_string_and_path(path1, path2) do |arg1, arg2|
          expect_raises(File::NotFoundError, "Error creating link: '#{path1.inspect_unquoted}' -> '#{path2.inspect_unquoted}'") do
            FileUtils.ln(arg1, arg2)
          end
        end
      end
    end

    it "fails with an extant destination" do
      with_tempfile("ln_src", "ln_dst_exists") do |path1, path2|
        FileUtils.touch([path1, path2])

        test_with_string_and_path(path1, path2) do |arg1, arg2|
          expect_raises(File::AlreadyExistsError, "Error creating link: '#{path1.inspect_unquoted}' -> '#{path2.inspect_unquoted}'") do
            FileUtils.ln(arg1, arg2)
          end
        end
      end
    end
  end

  describe ".ln_s" do
    it "creates a symlink" do
      with_tempfile("ln_s_src", "ln_s_dst") do |path1, path2|
        test_with_string_and_path(path1, path2) do |arg1, arg2|
          FileUtils.touch(path1)
          FileUtils.ln_s(arg1, arg2)
          File.exists?(path2).should be_true
          File.symlink?(path2).should be_true
          FileUtils.rm_rf([path1, path2])
        end
      end
    end

    it "creates a symlink inside a destination dir" do
      with_tempfile("ln_s_src", "ln_s_dst_dir") do |path1, path2|
        path3 = File.join(path2, File.basename(path1))

        test_with_string_and_path(path1, path2) do |arg1, arg2|
          FileUtils.touch(path1)
          FileUtils.mkdir(path2)
          FileUtils.ln_s(arg1, arg2)
          File.exists?(path3).should be_true
          File.symlink?(path3).should be_true
          FileUtils.rm_rf([path1, path2])
        end
      end
    end

    it "creates multiple symlinks inside a destination dir" do
      with_tempfile("ln_s_src_1", "ln_s_src_2", "ln_s_src_3", "ln_s_dst_dir") do |path1, path2, path3, dir_path|
        dir_path += File::SEPARATOR
        test_with_string_and_path(path1, path2, path3, dir_path) do |arg1, arg2, arg3, dir_arg|
          paths = [arg1, arg2, arg3]
          paths.each { |path| FileUtils.touch(path) }
          FileUtils.mkdir(dir_path)
          FileUtils.ln_s(paths, dir_arg)

          paths.each do |path|
            link_path = File.join(dir_path, File.basename(path))
            File.exists?(link_path).should be_true
            File.symlink?(link_path).should be_true
          end
          FileUtils.rm_rf(paths)
          FileUtils.rm_rf(dir_path)
        end
      end
    end

    pending_win32 "works with a nonexistent source" do
      with_tempfile("ln_s_src_missing", "ln_s_dst_missing") do |path1, path2|
        test_with_string_and_path(path1, path2) do |arg1, arg2|
          FileUtils.ln_s(arg1, arg2)
          File.exists?(path2).should be_false
          File.symlink?(path2).should be_true

          expect_raises(File::NotFoundError, "Error resolving real path: '#{path2.inspect_unquoted}'") do
            File.realpath(path2)
          end
          FileUtils.rm_rf(path2)
        end
      end
    end

    it "fails with an existing destination" do
      with_tempfile("ln_s_src", "ln_s_dst_exists") do |path1, path2|
        test_with_string_and_path(path1, path2) do |arg1, arg2|
          FileUtils.touch([path1, path2])

          expect_raises(File::AlreadyExistsError, "Error creating symlink: '#{path1.inspect_unquoted}' -> '#{path2.inspect_unquoted}'") do
            FileUtils.ln_s(arg1, arg2)
          end
          FileUtils.rm_rf([path1, path2])
        end
      end
    end
  end

  describe ".ln_sf" do
    it "overwrites a destination file" do
      with_tempfile("ln_sf_src", "ln_sf_dst_exists") do |path1, path2|
        test_with_string_and_path(path1, path2) do |arg1, arg2|
          FileUtils.touch([path1, path2])
          File.symlink?(path1).should be_false
          File.symlink?(path2).should be_false

          FileUtils.ln_sf(arg1, arg2)
          File.symlink?(path1).should be_false
          File.symlink?(path2).should be_true
          FileUtils.rm_rf([path1, path2])
        end
      end
    end

    it "overwrites a destination file inside a dir" do
      with_tempfile("ln_sf_dst_dir", "ln_sf_dst") do |dir, path2|
        dir += File::SEPARATOR
        path1 = File.join(dir, File.basename(path2))

        test_with_string_and_path(dir, path2) do |dir_arg, arg2|
          FileUtils.mkdir(dir)
          FileUtils.touch([path1, path2])
          File.symlink?(path1).should be_false
          File.symlink?(path2).should be_false

          FileUtils.ln_sf(arg2, dir_arg)
          File.symlink?(path1).should be_true
          File.symlink?(path2).should be_false

          FileUtils.rm_rf([dir, path1, path2])
        end
      end
    end

    it "creates multiple symlinks in a destination dir, with overwrites" do
      with_tempfile("ln_sf_src_dir", "ln_sf_dst_dir") do |src_dir, dir|
        test_with_string_and_path(src_dir, dir) do |src_arg, dir_arg|
          paths1 = Array.new(3) { |i| "exists_#{i}" }
          paths2 = paths1.map { |p| File.join(src_arg, p) }
          paths3 = paths1.map { |p| File.join(dir, p) }

          FileUtils.mkdir(src_dir)
          FileUtils.mkdir(dir)
          FileUtils.touch(paths2 + paths3)
          (paths2 + paths3).each { |p| File.symlink?(p).should be_false }

          FileUtils.ln_sf(paths2, dir_arg)
          paths2.each { |p| File.symlink?(p).should be_false }
          paths3.each { |p| File.symlink?(p).should be_true }

          FileUtils.rm_rf([src_dir, dir])
        end
      end
    end

    it "creates a symlink even if there's nothing to overwrite" do
      with_tempfile("ln_sf_src", "ln_sf_dst") do |path1, path2|
        test_with_string_and_path(path1, path2) do |arg1, arg2|
          FileUtils.touch(path1)
          File.exists?(path2).should be_false

          FileUtils.ln_sf(arg1, arg2)
          File.symlink?(path2).should be_true
          FileUtils.rm_rf([path1, path2])
        end
      end
    end
  end
end
