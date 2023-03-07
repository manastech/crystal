# NOTE: To use `FileUtils`, you must explicitly import it with `require "file_utils"`
module FileUtils
  extend self

  # Changes the current working directory of the process to the given string *path*.
  #
  # ```
  # require "file_utils"
  #
  # FileUtils.cd("/tmp")
  # ```
  #
  # NOTE: Alias of `Dir.cd`
  def cd(path : Path | String) : Nil
    Dir.cd(path)
  end

  # Changes the current working directory of the process to the given string *path*
  # and invoked the block, restoring the original working directory when the block exits.
  #
  # ```
  # require "file_utils"
  #
  # FileUtils.cd("/tmp") { Dir.current } # => "/tmp"
  # ```
  #
  # NOTE: Alias of `Dir.cd` with block
  def cd(path : Path | String, &)
    Dir.cd(path) { yield }
  end

  # Compares two files *filename1* to *filename2* to determine if they are identical.
  # Returns `true` if content are the same, `false` otherwise.
  #
  # ```
  # require "file_utils"
  #
  # File.write("file.cr", "1")
  # File.write("bar.cr", "1")
  # FileUtils.cmp("file.cr", "bar.cr") # => true
  # ```
  #
  # NOTE: Alias of `File.same_content?`
  def cmp(filename1 : Path | String, filename2 : Path | String) : Bool
    File.same_content?(filename1, filename2)
  end

  # Attempts to set the access and modification times of the file named
  # in the *path* parameter to the value given in *time*.
  #
  # If the file does not exist, it will be created.
  #
  # ```
  # require "file_utils"
  #
  # FileUtils.touch("afile.cr")
  # ```
  #
  # NOTE: Alias of `File.touch`
  def touch(path : Path | String, time : Time = Time.utc) : Nil
    File.touch(path, time)
  end

  # Attempts to set the access and modification times of each file given
  # in the *paths* parameter to the value given in *time*.
  #
  # If the file does not exist, it will be created.
  #
  # ```
  # require "file_utils"
  #
  # FileUtils.touch(["foo", "bar"])
  # ```
  def touch(paths : Enumerable(Path | String), time : Time = Time.utc) : Nil
    paths.each do |path|
      touch(path, time)
    end
  end

  # Copies the file *src_path* to the file or directory *dest*.
  # If *dest* is a directory, a file with the same basename as *src_path* is created in *dest*
  # Permission bits are copied too.
  #
  # ```
  # require "file_utils"
  #
  # File.touch("afile")
  # File.chmod("afile", 0o600)
  # FileUtils.cp("afile", "afile_copy")
  # File.info("afile_copy").permissions.value # => 0o600
  # ```
  def cp(src_path : Path | String, dest : Path | String) : Nil
    dest = Path[dest, File.basename(src_path)] if Dir.exists?(dest)
    File.copy(src_path, dest)
  end

  # Copies a list of files *src* to *dest*.
  # *dest* must be an existing directory.
  #
  # ```
  # require "file_utils"
  #
  # Dir.mkdir("files")
  # FileUtils.cp({"bar.cr", "afile"}, "files")
  # ```
  def cp(srcs : Enumerable(Path | String), dest : Path | String) : Nil
    raise ArgumentError.new("No such directory : #{dest}") unless Dir.exists?(dest)
    srcs.each do |src|
      cp(src, dest)
    end
  end

  # Copies a file or directory *src_path* to *dest_path*.
  # If *src_path* is a directory, this method copies all its contents recursively.
  # If *dest* is a directory, copies src to dest/src.
  #
  # ```
  # require "file_utils"
  #
  # FileUtils.cp_r("files", "dir")
  # ```
  def cp_r(src_path : Path | String, dest_path : Path | String) : Nil
    dest_path = File.join(dest_path, File.basename(src_path)) if File.directory?(dest_path)
    cp_recursive(src_path, dest_path)
  end

  private def cp_recursive(src_path : Path | String, dest_path : Path | String)
    if Dir.exists?(src_path)
      Dir.mkdir(dest_path) unless Dir.exists?(dest_path)
      Dir.each_child(src_path) do |entry|
        src = File.join(src_path, entry)
        dest = File.join(dest_path, entry)
        cp_recursive(src, dest)
      end
    else
      cp(src_path, dest_path)
    end
  end

  # Creates a hard link *dest_path* which points to *src_path*.
  # If *dest_path* already exists and is a directory, creates a link *dest_path/src_path*.
  #
  # ```
  # require "file_utils"
  #
  # # Create a hard link, pointing from /usr/bin/emacs to /usr/bin/vim
  # FileUtils.ln("/usr/bin/vim", "/usr/bin/emacs")
  # # Create a hard link, pointing from /tmp/foo.c to foo.c
  # FileUtils.ln("foo.c", "/tmp")
  # ```
  def ln(src_path : Path | String, dest_path : Path | String) : Nil
    if Dir.exists?(dest_path)
      File.link(src_path, File.join(dest_path, File.basename(src_path)))
    else
      File.link(src_path, dest_path)
    end
  end

  # Creates a hard link to each path in *src_paths* inside the *dest_dir* directory.
  # If *dest_dir* is not a directory, raises an `ArgumentError`.
  #
  # ```
  # require "file_utils"
  #
  # # Create /usr/bin/vim, /usr/bin/emacs, and /usr/bin/nano as hard links
  # FileUtils.ln(["vim", "emacs", "nano"], "/usr/bin")
  # ```
  def ln(src_paths : Enumerable(Path | String), dest_dir : Path | String) : Nil
    raise ArgumentError.new("No such directory : #{dest_dir}") unless Dir.exists?(dest_dir)

    src_paths.each do |path|
      ln(path, dest_dir)
    end
  end

  # Creates a symbolic link *dest_path* which points to *src_path*.
  # If *dest_path* already exists and is a directory, creates a link *dest_path/src_path*.
  #
  # ```
  # require "file_utils"
  #
  # # Create a symbolic link pointing from logs to /var/log
  # FileUtils.ln_s("/var/log", "logs")
  # # Create a symbolic link pointing from /tmp/src to src
  # FileUtils.ln_s("src", "/tmp")
  # ```
  def ln_s(src_path : Path | String, dest_path : Path | String) : Nil
    if Dir.exists?(dest_path)
      File.symlink(src_path, File.join(dest_path, File.basename(src_path)))
    else
      File.symlink(src_path, dest_path)
    end
  end

  # Creates a symbolic link to each path in *src_paths* inside the *dest_dir* directory.
  # If *dest_dir* is not a directory, raises an `ArgumentError`.
  #
  # ```
  # require "file_utils"
  #
  # # Create symbolic links in src/ pointing to every .c file in the current directory
  # FileUtils.ln_s(Dir["*.c"], "src")
  # ```
  def ln_s(src_paths : Enumerable(Path | String), dest_dir : Path | String) : Nil
    raise ArgumentError.new("No such directory : #{dest_dir}") unless Dir.exists?(dest_dir)

    src_paths.each do |path|
      ln_s(path, dest_dir)
    end
  end

  # Like `#ln_s(Path | String, Path | String)`, but overwrites `dest_path` if it exists and is not a directory
  # or if `dest_path/src_path` exists.
  #
  # ```
  # require "file_utils"
  #
  # # Create a symbolic link pointing from bar.c to foo.c, even if bar.c already exists
  # FileUtils.ln_sf("foo.c", "bar.c")
  # ```
  def ln_sf(src_path : Path | String, dest_path : Path | String) : Nil
    if File.directory?(dest_path)
      dest_path = File.join(dest_path, File.basename(src_path))
    end

    File.delete(dest_path) if File.file?(dest_path)
    File.symlink(src_path, dest_path)
  end

  # Creates a symbolic link to each path in *src_paths* inside the *dest_dir* directory,
  # ignoring any overwritten paths.
  #
  # If *dest_dir* is not a directory, raises an `ArgumentError`.
  #
  # ```
  # require "file_utils"
  #
  # # Create symbolic links in src/ pointing to every .c file in the current directory,
  # # even if it means overwriting files in src/
  # FileUtils.ln_sf(Dir["*.c"], "src")
  # ```
  def ln_sf(src_paths : Enumerable(Path | String), dest_dir : Path | String) : Nil
    raise ArgumentError.new("No such directory : #{dest_dir}") unless Dir.exists?(dest_dir)

    src_paths.each do |path|
      ln_sf(path, dest_dir)
    end
  end

  # Creates a new directory at the given *path*. The linux-style permission *mode*
  # can be specified, with a default of 777 (0o777).
  #
  # ```
  # require "file_utils"
  #
  # FileUtils.mkdir("src")
  # ```
  #
  # NOTE: Alias of `Dir.mkdir`
  def mkdir(path : Path | String, mode = 0o777) : Nil
    Dir.mkdir(path, mode)
  end

  # Creates a new directory at the given *paths*. The linux-style permission *mode*
  # can be specified, with a default of 777 (0o777).
  #
  # ```
  # require "file_utils"
  #
  # FileUtils.mkdir(["foo", "bar"])
  # ```
  def mkdir(paths : Enumerable(Path | String), mode = 0o777) : Nil
    paths.each do |path|
      Dir.mkdir(path, mode)
    end
  end

  # Creates a new directory at the given *path*, including any non-existing
  # intermediate directories. The linux-style permission *mode* can be specified,
  # with a default of 777 (0o777).
  #
  # ```
  # require "file_utils"
  #
  # FileUtils.mkdir_p("foo")
  # ```
  #
  # NOTE: Alias of `Dir.mkdir_p`
  def mkdir_p(path : Path | String, mode = 0o777) : Nil
    Dir.mkdir_p(path, mode)
  end

  # Creates a new directory at the given *paths*, including any non-existing
  # intermediate directories. The linux-style permission *mode* can be specified,
  # with a default of 777 (0o777).
  #
  # ```
  # require "file_utils"
  #
  # FileUtils.mkdir_p(["foo", "bar", "baz", "dir1", "dir2", "dir3"])
  # ```
  def mkdir_p(paths : Enumerable(Path | String), mode = 0o777) : Nil
    paths.each do |path|
      Dir.mkdir_p(path, mode)
    end
  end

  # Moves *src_path* to *dest_path*.
  #
  # NOTE: If *src_path* and *dest_path* exist on different mounted filesystems,
  # the file at *src_path* is copied to *dest_path* and then removed.
  #
  # ```
  # require "file_utils"
  #
  # FileUtils.mv("afile", "afile.cr")
  # ```
  def mv(src_path : Path | String, dest_path : Path | String) : Nil
    if error = Crystal::System::File.rename(src_path.to_s, dest_path.to_s)
      raise error unless Errno.value.in?(Errno::EXDEV, Errno::EPERM)
      cp_r(src_path, dest_path)
      rm_r(src_path)
    end
  end

  # Moves every *srcs* to *dest*.
  #
  # ```
  # require "file_utils"
  #
  # FileUtils.mv(["foo", "bar"], "src")
  # ```
  def mv(srcs : Enumerable(Path | String), dest : Path | String) : Nil
    raise ArgumentError.new("No such directory : #{dest}") unless Dir.exists?(dest)
    srcs.each do |src|
      begin
        mv(src, File.join(dest, File.basename(src)))
      rescue File::Error
      end
    end
  end

  # Returns the current working directory.
  #
  # ```
  # require "file_utils"
  #
  # FileUtils.pwd
  # ```
  #
  # NOTE: Alias of `Dir.current`
  def pwd : String
    Dir.current
  end

  # Deletes the *path* file given, raised if path is not exists.
  #
  # ```
  # require "file_utils"
  #
  # FileUtils.rm("afile.cr")
  # ```
  #
  # NOTE: Alias of `File.delete`
  def rm(path : Path | String) : Nil
    File.delete(path)
  end

  # Deletes all *paths* file given, raised if one path is not exists.
  #
  # ```
  # require "file_utils"
  #
  # FileUtils.rm(["dir/afile", "afile_copy"])
  # ```
  def rm(paths : Enumerable(Path | String)) : Nil
    paths.each do |path|
      File.delete(path)
    end
  end

  # Deletes the *path* file given, ignored if path is not exists.
  #
  # ```
  # require "file_utils"
  #
  # FileUtils.rm_f("afile.cr")
  # ```
  #
  # NOTE: Alias of `File.delete?`
  def rm_f(path : Path | String) : Nil
    File.delete?(path)
  end

  # Deletes all *paths* file given, ignored if one path is not exists.
  #
  # ```
  # require "file_utils"
  #
  # FileUtils.rm_f(["dir/afile", "afile_copy"])
  # ```
  def rm_f(paths : Enumerable(Path | String)) : Nil
    paths.each do |path|
      File.delete?(path)
    end
  end

  # Deletes a file or directory *path*.
  # If *path* is a directory, this method removes all its contents recursively.
  #
  # ```
  # require "file_utils"
  #
  # FileUtils.rm_r("dir")
  # FileUtils.rm_r("file.cr")
  # ```
  def rm_r(path : Path | String) : Nil
    if Dir.exists?(path) && !File.symlink?(path)
      Dir.each_child(path) do |entry|
        src = File.join(path, entry)
        rm_r(src)
      end
      Dir.delete(path)
    else
      File.delete(path)
    end
  end

  # Deletes a list of files or directories *paths*.
  # If one path is a directory, this method removes all its contents recursively.
  #
  # ```
  # require "file_utils"
  #
  # FileUtils.rm_r(["files", "bar.cr"])
  # ```
  def rm_r(paths : Enumerable(Path | String)) : Nil
    paths.each do |path|
      rm_r(path)
    end
  end

  # Deletes a file or directory *path*.
  # If *path* is a directory, this method removes all its contents recursively.
  # Ignores all errors.
  #
  # ```
  # require "file_utils"
  #
  # FileUtils.rm_rf("dir")
  # FileUtils.rm_rf("file.cr")
  # FileUtils.rm_rf("non_existent_file")
  # ```
  def rm_rf(path : Path | String) : Nil
    rm_r(path)
  rescue File::Error
  end

  # Deletes a list of files or directories *paths*.
  # If one path is a directory, this method removes all its contents recursively.
  # Ignores all errors.
  #
  # ```
  # require "file_utils"
  #
  # FileUtils.rm_rf(["dir", "file.cr", "non_existent_file"])
  # ```
  def rm_rf(paths : Enumerable(Path | String)) : Nil
    paths.each do |path|
      begin
        rm_r(path)
      rescue File::Error
      end
    end
  end

  # Removes the directory at the given *path*.
  #
  # ```
  # require "file_utils"
  #
  # FileUtils.rmdir("baz")
  # ```
  #
  # NOTE: Alias of `Dir.delete`
  def rmdir(path : Path | String) : Nil
    Dir.delete(path)
  end

  # Removes all directories at the given *paths*.
  #
  # ```
  # require "file_utils"
  #
  # FileUtils.rmdir(["dir1", "dir2", "dir3"])
  # ```
  def rmdir(paths : Enumerable(Path | String)) : Nil
    paths.each do |path|
      Dir.delete(path)
    end
  end
end
