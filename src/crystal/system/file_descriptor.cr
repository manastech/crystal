# :nodoc:
module Crystal::System::FileDescriptor
  # Enables input echoing if *enable* is true, disables it otherwise.
  # private def system_echo(enable : Bool)

  # For the duration of the block, enables input echoing if *enable* is true,
  # disables it otherwise.
  # private def system_echo(enable : Bool, & : ->)

  # Enables raw mode if *enable* is true, enables cooked mode otherwise.
  # private def system_raw(enable : Bool)

  # For the duration of the block, enables raw mode if *enable* is true, enables
  # cooked mode otherwise.
  # private def system_raw(enable : Bool, & : ->)

  # Closes the internal file descriptor without notifying the event loop.
  # This is directly used after the fork of a process to close the
  # parent's Crystal::System::Signal.@@pipe reference before re initializing
  # the event loop. In the case of a fork that will exec there is even
  # no need to initialize the event loop at all.
  # Also used in `IO::FileDescriptor#finalize`.
  # def file_descriptor_close

  # Returns `true` or `false` if this file descriptor pretends to block or not
  # to block the caller thread regardless of the underlying internal file
  # descriptor's implementation. Returns `nil` if nothing needs to be done, i.e.
  # `#blocking` is identical to `#system_blocking?`.
  #
  # Currently used by console STDIN on Windows.
  private def emulated_blocking? : Bool?
  end

  private def system_read(slice : Bytes) : Int32
    event_loop.read(self, slice)
  end

  private def system_write(slice : Bytes) : Int32
    event_loop.write(self, slice)
  end

  private def system_wait_readable : Nil
    event_loop.wait_readable(self)
  end

  private def system_wait_writable : Nil
    event_loop.wait_writable(self)
  end

  private def event_loop? : Crystal::EventLoop::FileDescriptor?
    Crystal::EventLoop.current?
  end

  private def event_loop : Crystal::EventLoop::FileDescriptor
    Crystal::EventLoop.current
  end
end

{% if flag?(:wasi) %}
  require "./wasi/file_descriptor"
{% elsif flag?(:unix) %}
  require "./unix/file_descriptor"
{% elsif flag?(:win32) %}
  require "./win32/file_descriptor"
{% else %}
  {% raise "No Crystal::System::FileDescriptor implementation available" %}
{% end %}
