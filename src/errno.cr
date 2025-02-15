require "c/errno"
require "c/string"

lib LibC
  {% if flag?(:netbsd) || flag?(:openbsd) || flag?(:android) %}
    fun __errno : Int*
  {% elsif flag?(:solaris) %}
    fun ___errno : Int*
  {% elsif flag?(:linux) || flag?(:dragonfly) %}
    fun __errno_location : Int*
  {% elsif flag?(:wasi) %}
    $errno : Int
  {% elsif flag?(:darwin) || flag?(:freebsd) %}
    fun __error : Int*
  {% elsif flag?(:win32) %}
    fun _get_errno(value : Int*) : ErrnoT
    fun _set_errno(value : Int) : ErrnoT
  {% end %}
end

# Errno wraps and gives access to libc's errno. This is mostly useful when
# dealing with C libraries.
#
# The integer values of these errors are platform-specific and should not be directly relied on.
# If an error code is not applicable on the current platform, its value will be `INVALID`.
#
# Intended usages are of the form `if exc.os_error == Errno::ENOATTR`: with this we are checking
# whether the OS-specific error is of the `ENOATTR` kind, even if the actual value of
# `Errno::ENOATTR` might vary across platforms or be equal to `Errno::INVALID` if that platform has
# no such error (so the equality can never be true on that platform, but the code still compiles).
enum Errno
  NONE    =  0
  INVALID = -1

  # grep -hE '^ *\w+ *=' src/lib_c/*/c/errno.cr | awk '{print $1}' | sort -u | xargs | fold -s -w81

  {% for value in %w(
                    E2BIG EACCES EADDRINUSE EADDRNOTAVAIL EAFNOSUPPORT EAGAIN EALREADY EBADF EBADMSG
                    EBUSY ECANCELED ECHILD ECONNABORTED ECONNREFUSED ECONNRESET EDEADLK EDESTADDRREQ
                    EDOM EDQUOT EEXIST EFAULT EFBIG EHOSTUNREACH EIDRM EILSEQ EINPROGRESS EINTR
                    EINVAL EIO EISCONN EISDIR ELOOP EMFILE EMLINK EMSGSIZE EMULTIHOP ENAMETOOLONG
                    ENETDOWN ENETRESET ENETUNREACH ENFILE ENOBUFS ENODATA ENODEV ENOENT ENOEXEC
                    ENOLCK ENOLINK ENOMEM ENOMSG ENOPROTOOPT ENOSPC ENOSR ENOSTR ENOSYS ENOTCONN
                    ENOTDIR ENOTEMPTY ENOTRECOVERABLE ENOTSOCK ENOTSUP ENOTTY ENXIO EOPNOTSUPP
                    EOVERFLOW EOWNERDEAD EPERM EPIPE EPROTO EPROTONOSUPPORT EPROTOTYPE ERANGE EROFS
                    ESPIPE ESRCH ESTALE ETIME ETIMEDOUT ETXTBSY EWOULDBLOCK EXDEV STRUNCATE
                  ) %}
    {% if LibC.has_constant?(value) %}
      {{value.id}} = LibC::{{value.id}}
    {% else %}
      {{value.id}} = INVALID
    {% end %}
  {% end %}

  # Returns the system error message associated with this errno.
  #
  # NOTE: The result may depend on the current system locale. Specs and
  # comparisons should use `#value` instead of this method.
  def message : String
    unsafe_message { |slice| String.new(slice) }
  end

  # :nodoc:
  def unsafe_message(&)
    {% if LibC.has_method?(:strerror_r) %}
      buffer = uninitialized UInt8[256]
      if LibC.strerror_r(value, buffer, buffer.size) == 0
        yield Bytes.new(buffer.to_unsafe, LibC.strlen(buffer))
      else
        yield "(???)".to_slice
      end
    {% else %}
      pointer = LibC.strerror(value)
      yield Bytes.new(pointer, LibC.strlen(pointer))
    {% end %}
  end

  # returns the value of libc's errno.
  def self.value : self
    {% if flag?(:netbsd) || flag?(:openbsd) || flag?(:android) %}
      Errno.new LibC.__errno.value
    {% elsif flag?(:solaris) %}
      Errno.new LibC.___errno.value
    {% elsif flag?(:linux) || flag?(:dragonfly) %}
      Errno.new LibC.__errno_location.value
    {% elsif flag?(:wasi) %}
      Errno.new LibC.errno
    {% elsif flag?(:darwin) || flag?(:freebsd) %}
      Errno.new LibC.__error.value
    {% elsif flag?(:win32) %}
      ret = LibC._get_errno(out errno)
      raise RuntimeError.from_os_error("_get_errno", Errno.new(ret)) unless ret == 0
      Errno.new errno
    {% end %}
  end

  # Sets the value of libc's errno.
  def self.value=(errno : Errno)
    {% if flag?(:netbsd) || flag?(:openbsd) || flag?(:android) %}
      LibC.__errno.value = errno.value
    {% elsif flag?(:solaris) %}
      LibC.___errno.value = errno.value
    {% elsif flag?(:linux) || flag?(:dragonfly) %}
      LibC.__errno_location.value = errno.value
    {% elsif flag?(:darwin) || flag?(:freebsd) %}
      LibC.__error.value = errno.value
    {% elsif flag?(:win32) %}
      ret = LibC._set_errno(errno.value)
      raise RuntimeError.from_os_error("_set_errno", Errno.new(ret)) unless ret == 0
    {% end %}
    errno
  end
end
