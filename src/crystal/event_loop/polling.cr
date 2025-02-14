# forward declaration for the require below to not create a module
abstract class Crystal::EventLoop::Polling < Crystal::EventLoop; end

require "./polling/*"
require "./timers"

module Crystal::System::FileDescriptor
  # user data (generation index for the arena)
  property __evloop_data : EventLoop::Polling::Arena::Index = EventLoop::Polling::Arena::INVALID_INDEX
end

module Crystal::System::Socket
  # user data (generation index for the arena)
  property __evloop_data : EventLoop::Polling::Arena::Index = EventLoop::Polling::Arena::INVALID_INDEX
end

# Polling EventLoop.
#
# This is the abstract interface that implements `Crystal::EventLoop` for
# polling based UNIX targets, such as epoll (linux), kqueue (bsd), or poll
# (posix) syscalls. This class only implements the generic parts for the
# external world to interact with the loop. A specific implementation is
# required to handle the actual syscalls. See `Crystal::Epoll::EventLoop` and
# `Crystal::Kqueue::EventLoop`.
#
# The event loop registers the fd into the kernel data structures when an IO
# operation would block, then keeps it there until the fd is closed.
#
# NOTE: the fds must have `O_NONBLOCK` set.
#
# It is possible to have multiple event loop instances, but an fd can only be in
# one instance at a time. When trying to block from another loop, the fd will be
# removed from its associated loop and added to the current one (this is
# automatic). Trying to move a fd to another loop with pending waiters is
# unsupported and will raise an exception. See `PollDescriptor#remove`.
#
# A timed event such as sleep or select timeout follows the following logic:
#
# 1. create an `Event` (actually reuses it, see `FiberChannel`);
# 2. register the event in `@timers`;
# 3. supend the current fiber.
#
# The timer will eventually trigger and resume the fiber.
# When an IO operation on fd would block, the loop follows the following logic:
#
# 1. register the fd (once);
# 2. create an `Event`;
# 3. suspend the current fiber;
#
# When the IO operation is ready, the fiber will eventually be resumed (one
# fiber at a time). If it's an IO operation, the operation is tried again which
# may block again, until the operation succeeds or an error occured (e.g.
# closed, broken pipe).
#
# If the IO operation has a timeout, the event is also registered into `@timers`
# before suspending the fiber, then after resume it will raise
# `IO::TimeoutError` if the event timed out, and continue otherwise.
abstract class Crystal::EventLoop::Polling < Crystal::EventLoop
  # The generational arena:
  #
  # 1. decorrelates the fd from the IO since the evloop only really cares about
  #    the fd state and to resume pending fibers (it could monitor a fd without
  #    an IO object);
  #
  # 2. permits to avoid pushing raw pointers to IO objects into kernel data
  #    structures that are unknown to the GC, and to safely check whether the
  #    allocation is still valid before trying to dereference the pointer. Since
  #    `PollDescriptor` also doesn't have pointers to the actual IO object, it
  #    won't prevent the GC from collecting lost IO objects (and spares us from
  #    using weak references).
  #
  # 3. to a lesser extent, it also allows to keep the `PollDescriptor` allocated
  #    together in the same region, and polluting the IO object itself with
  #    specific evloop data (except for the generation index).
  #
  # The implementation takes advantage of the fd being unique per process and
  # that the operating system will always reuse the lowest fd (POSIX compliance)
  # and will only grow when the process needs that many file descriptors, so the
  # allocated memory region won't grow larger than necessary. This assumption
  # allows the arena to skip maintaining a list of free indexes. Some systems
  # may deviate from the POSIX default, but all systems seem to follow it, as it
  # allows optimizations to the OS (it can reuse already allocated resources),
  # and either the man page explicitly says so (Linux), or they don't (BSD) and
  # they must follow the POSIX definition.
  #
  # The block size is set to 64KB because it's a multiple of:
  # - 4KB (usual page size)
  # - 1024 (common soft limit for open files)
  # - sizeof(Arena::Entry(PollDescriptor))
  protected class_getter arena = Arena(PollDescriptor, 65536).new(max_fds)

  private def self.max_fds : Int32
    if LibC.getrlimit(LibC::RLIMIT_NOFILE, out rlimit) == -1
      raise RuntimeError.from_errno("getrlimit(RLIMIT_NOFILE)")
    end
    rlimit.rlim_max.clamp(..Int32::MAX).to_i32!
  end

  @lock = SpinLock.new # protects parallel accesses to @timers
  @timers = Timers(Event).new

  # reset the mutexes since another thread may have acquired the lock of one
  # event loop, which would prevent closing file descriptors for example.
  def after_fork_before_exec : Nil
    @lock = SpinLock.new
  end

  {% unless flag?(:preview_mt) %}
    # no parallelism issues, but let's clean-up anyway
    def after_fork : Nil
      @lock = SpinLock.new
    end
  {% end %}

  # NOTE: thread unsafe
  def run(blocking : Bool) : Bool
    system_run(blocking) do |fiber|
      Crystal::Scheduler.enqueue(fiber)
    end
    true
  end

  # fiber interface, see Crystal::EventLoop

  def create_resume_event(fiber : Fiber) : FiberEvent
    FiberEvent.new(:sleep, fiber)
  end

  def create_timeout_event(fiber : Fiber) : FiberEvent
    FiberEvent.new(:select_timeout, fiber)
  end

  # file descriptor interface, see Crystal::EventLoop::FileDescriptor

  def read(file_descriptor : System::FileDescriptor, slice : Bytes) : Int32
    size = evented_read(file_descriptor, slice, file_descriptor.@read_timeout)

    if size == -1
      if Errno.value == Errno::EBADF
        raise IO::Error.new("File not open for reading", target: file_descriptor)
      else
        raise IO::Error.from_errno("read", target: file_descriptor)
      end
    else
      size.to_i32
    end
  end

  def wait_readable(file_descriptor : System::FileDescriptor) : Nil
    wait_readable(file_descriptor, file_descriptor.@read_timeout) do
      raise IO::TimeoutError.new
    end
  end

  def write(file_descriptor : System::FileDescriptor, slice : Bytes) : Int32
    size = evented_write(file_descriptor, slice, file_descriptor.@write_timeout)

    if size == -1
      if Errno.value == Errno::EBADF
        raise IO::Error.new("File not open for writing", target: file_descriptor)
      else
        raise IO::Error.from_errno("write", target: file_descriptor)
      end
    else
      size.to_i32
    end
  end

  def wait_writable(file_descriptor : System::FileDescriptor) : Nil
    wait_writable(file_descriptor, file_descriptor.@write_timeout) do
      raise IO::TimeoutError.new
    end
  end

  def close(file_descriptor : System::FileDescriptor) : Nil
    evented_close(file_descriptor)
  end

  protected def self.remove_impl(file_descriptor : System::FileDescriptor) : Nil
    internal_remove(file_descriptor)
  end

  # socket interface, see Crystal::EventLoop::Socket

  def read(socket : ::Socket, slice : Bytes) : Int32
    size = evented_read(socket, slice, socket.@read_timeout)
    raise IO::Error.from_errno("read", target: socket) if size == -1
    size
  end

  def wait_readable(socket : ::Socket) : Nil
    wait_readable(socket, socket.@read_timeout) do
      raise IO::TimeoutError.new
    end
  end

  def write(socket : ::Socket, slice : Bytes) : Int32
    size = evented_write(socket, slice, socket.@write_timeout)
    raise IO::Error.from_errno("write", target: socket) if size == -1
    size
  end

  def wait_writable(socket : ::Socket) : Nil
    wait_writable(socket, socket.@write_timeout) do
      raise IO::TimeoutError.new
    end
  end

  def accept(socket : ::Socket) : ::Socket::Handle?
    loop do
      client_fd =
        {% if LibC.has_method?(:accept4) %}
          LibC.accept4(socket.fd, nil, nil, LibC::SOCK_CLOEXEC)
        {% else %}
          # we may fail to set FD_CLOEXEC between `accept` and `fcntl` but we
          # can't call `Crystal::System::Socket.lock_read` because the socket
          # might be in blocking mode and accept would block until the socket
          # receives a connection.
          #
          # we could lock when `socket.blocking?` is false, but another thread
          # could change the socket back to blocking mode between the condition
          # check and the `accept` call.
          LibC.accept(socket.fd, nil, nil).tap do |fd|
            System::Socket.fcntl(fd, LibC::F_SETFD, LibC::FD_CLOEXEC) unless fd == -1
          end
        {% end %}

      return client_fd unless client_fd == -1
      return if socket.closed?

      if Errno.value == Errno::EAGAIN
        wait_readable(socket, socket.@read_timeout) do
          raise IO::TimeoutError.new("Accept timed out")
        end
        return if socket.closed?
      else
        raise ::Socket::Error.from_errno("accept")
      end
    end
  end

  def connect(socket : ::Socket, address : ::Socket::Addrinfo | ::Socket::Address, timeout : Time::Span?) : IO::Error?
    loop do
      ret = LibC.connect(socket.fd, address, address.size)
      return unless ret == -1

      case Errno.value
      when Errno::EISCONN
        return
      when Errno::EINPROGRESS, Errno::EALREADY
        wait_writable(socket, timeout) do
          return IO::TimeoutError.new("Connect timed out")
        end
      else
        return ::Socket::ConnectError.from_errno("connect")
      end
    end
  end

  def send_to(socket : ::Socket, slice : Bytes, address : ::Socket::Address) : Int32
    bytes_sent = LibC.sendto(socket.fd, slice.to_unsafe.as(Void*), slice.size, 0, address, address.size)
    raise ::Socket::Error.from_errno("Error sending datagram to #{address}") if bytes_sent == -1
    bytes_sent.to_i32
  end

  def receive_from(socket : ::Socket, slice : Bytes) : {Int32, ::Socket::Address}
    sockaddr = Pointer(LibC::SockaddrStorage).malloc.as(LibC::Sockaddr*)

    # initialize sockaddr with the initialized family of the socket
    copy = sockaddr.value
    copy.sa_family = socket.family
    sockaddr.value = copy
    addrlen = LibC::SocklenT.new(sizeof(LibC::SockaddrStorage))

    loop do
      size = LibC.recvfrom(socket.fd, slice, slice.size, 0, sockaddr, pointerof(addrlen))
      if size == -1
        if Errno.value == Errno::EAGAIN
          wait_readable(socket, socket.@read_timeout)
          check_open(socket)
        else
          raise IO::Error.from_errno("recvfrom", target: socket)
        end
      else
        return {size.to_i32, ::Socket::Address.from(sockaddr, addrlen)}
      end
    end
  end

  def close(socket : ::Socket) : Nil
    evented_close(socket)
  end

  protected def self.remove_impl(socket : ::Socket) : Nil
    internal_remove(socket)
  end

  # internals: IO

  private def evented_read(io, slice : Bytes, timeout : Time::Span?) : Int32
    loop do
      ret = LibC.read(io.fd, slice, slice.size)
      if ret == -1 && Errno.value == Errno::EAGAIN
        wait_readable(io, timeout)
        check_open(io)
      else
        return ret.to_i
      end
    end
  end

  private def evented_write(io, slice : Bytes, timeout : Time::Span?) : Int32
    loop do
      ret = LibC.write(io.fd, slice, slice.size)
      if ret == -1 && Errno.value == Errno::EAGAIN
        wait_writable(io, timeout)
        check_open(io)
      else
        return ret.to_i
      end
    end
  end

  protected def evented_close(io)
    return unless (index = io.__evloop_data).valid?

    Polling.arena.free(index) do |pd|
      pd.value.@readers.ready_all do |event|
        pd.value.@event_loop.try(&.unsafe_resume_io(event) do |fiber|
          Crystal::Scheduler.enqueue(fiber)
        end)
      end

      pd.value.@writers.ready_all do |event|
        pd.value.@event_loop.try(&.unsafe_resume_io(event) do |fiber|
          Crystal::Scheduler.enqueue(fiber)
        end)
      end

      pd.value.remove(io.fd)
    end
  end

  private def self.internal_remove(io)
    return unless (index = io.__evloop_data).valid?

    Polling.arena.free(index) do |pd|
      pd.value.remove(io.fd) { } # ignore system error
    end
  end

  private def wait_readable(io, timeout = nil) : Nil
    wait_readable(io, timeout) do
      raise IO::TimeoutError.new("Read timed out")
    end
  end

  private def wait_writable(io, timeout = nil) : Nil
    wait_writable(io, timeout) do
      raise IO::TimeoutError.new("Write timed out")
    end
  end

  private def wait_readable(io, timeout = nil, &) : Nil
    yield if wait(:io_read, io, timeout) do |pd, event|
               # don't wait if the waiter has already been marked ready (see Waiters#add)
               return unless pd.value.@readers.add(event)
             end
  end

  private def wait_writable(io, timeout = nil, &) : Nil
    yield if wait(:io_write, io, timeout) do |pd, event|
               # don't wait if the waiter has already been marked ready (see Waiters#add)
               return unless pd.value.@writers.add(event)
             end
  end

  private def wait(type : Polling::Event::Type, io, timeout, &)
    # prepare event (on the stack); we can't initialize it properly until we get
    # the arena index below; we also can't use a nilable since `pointerof` would
    # point to the union, not the event
    event = uninitialized Event

    # add the event to the waiting list; in case we can't access or allocate the
    # poll descriptor into the arena, we merely return to let the caller handle
    # the situation (maybe the IO got closed?)
    if (index = io.__evloop_data).valid?
      event = Event.new(type, Fiber.current, index, timeout)

      return false unless Polling.arena.get?(index) do |pd|
                            yield pd, pointerof(event)
                          end
    else
      # OPTIMIZE: failing to allocate may be a simple conflict with 2 fibers
      # starting to read or write on the same fd, we may want to detect any
      # error situation instead of returning and retrying a syscall
      return false unless Polling.arena.allocate_at?(io.fd) do |pd, index|
                            # register the fd with the event loop (once), it should usually merely add
                            # the fd to the current evloop but may "transfer" the ownership from
                            # another event loop:
                            io.__evloop_data = index
                            pd.value.take_ownership(self, io.fd, index)

                            event = Event.new(type, Fiber.current, index, timeout)
                            yield pd, pointerof(event)
                          end
    end

    if event.wake_at?
      add_timer(pointerof(event))

      Fiber.suspend

      # no need to delete the timer: either it triggered which means it was
      # dequeued, or `#unsafe_resume_io` was called to resume the IO and the
      # timer got deleted from the timers before the fiber got reenqueued.
      return event.timed_out?
    end

    Fiber.suspend
    false
  end

  private def check_open(io : IO)
    raise IO::Error.new("Closed stream") if io.closed?
  end

  # internals: timers

  protected def add_timer(event : Event*)
    @lock.sync do
      is_next_ready = @timers.add(event)
      system_set_timer(event.value.wake_at) if is_next_ready
    end
  end

  protected def delete_timer(event : Event*) : Bool
    @lock.sync do
      dequeued, was_next_ready = @timers.delete(event)
      # update system timer if we deleted the next timer
      system_set_timer(@timers.next_ready?) if was_next_ready
      dequeued
    end
  end

  # Helper to resume the fiber associated to an IO event and remove the event
  # from timers if applicable. Returns true if the fiber has been enqueued.
  #
  # Thread unsafe: we must hold the poll descriptor waiter lock for the whole
  # duration of the dequeue/resume_io otherwise we might conflict with timers
  # trying to cancel an IO event.
  protected def unsafe_resume_io(event : Event*, &) : Bool
    # we only partially own the poll descriptor; thanks to the lock we know that
    # another thread won't dequeue it, yet it may still be in the timers queue,
    # which at worst may be waiting on the lock to be released, so event* can be
    # dereferenced safely.

    if !event.value.wake_at? || delete_timer(event)
      # no timeout or we canceled it: we fully own the event
      yield event.value.fiber
      true
    else
      # failed to cancel the timeout so the timer owns the event (by rule)
      false
    end
  end

  # Process ready timers.
  #
  # Shall be called after processing IO events. IO events with a timeout that
  # have succeeded shall already have been removed from `@timers` otherwise the
  # fiber could be resumed twice!
  private def process_timers(timer_triggered : Bool, &) : Nil
    # collect ready timers before processing them —this is safe— to avoids a
    # deadlock situation when another thread tries to process a ready IO event
    # (in poll descriptor waiters) with a timeout (same event* in timers)
    buffer = uninitialized StaticArray(Pointer(Event), 128)
    size = 0

    @lock.sync do
      @timers.dequeue_ready do |event|
        buffer.to_unsafe[size] = event
        break if (size &+= 1) == buffer.size
      end

      if size > 0 || timer_triggered
        system_set_timer(@timers.next_ready?)
      end
    end

    buffer.to_slice[0, size].each do |event|
      process_timer(event) { |fiber| yield fiber }
    end
  end

  private def process_timer(event : Event*, &)
    # we dequeued the event from timers, and by rule we own it, so event* can
    # safely be dereferenced:
    fiber = event.value.fiber

    case event.value.type
    when .io_read?
      # reached read timeout: cancel io event; by rule the timer always wins,
      # even in case of conflict with #unsafe_resume_io we must resume the fiber
      Polling.arena.get?(event.value.index) { |pd| pd.value.@readers.delete(event) }
      event.value.timed_out!
    when .io_write?
      # reached write timeout: cancel io event; by rule the timer always wins,
      # even in case of conflict with #unsafe_resume_io we must resume the fiber
      Polling.arena.get?(event.value.index) { |pd| pd.value.@writers.delete(event) }
      event.value.timed_out!
    when .select_timeout?
      # always dequeue the event but only enqueue the fiber if we win the
      # atomic CAS
      return unless select_action = fiber.timeout_select_action
      fiber.timeout_select_action = nil
      return unless select_action.time_expired?
      fiber.@timeout_event.as(FiberEvent).clear
    when .sleep?
      # cleanup
      fiber.@resume_event.as(FiberEvent).clear
    else
      raise RuntimeError.new("BUG: unexpected event in timers: #{event.value}%s\n")
    end

    yield fiber
  end

  # internals: system

  # Process ready events and timers.
  #
  # The loop must always process ready events and timers before returning. When
  # *blocking* is `true` the loop must wait for events to become ready (possibly
  # indefinitely); when `false` the loop shall return immediately.
  #
  # The `PollDescriptor` of IO events can be retrieved using the *index*
  # from the system event's user data.
  private abstract def system_run(blocking : Bool, & : Fiber ->) : Nil

  # Add *fd* to the polling system, setting *index* as user data.
  protected abstract def system_add(fd : Int32, index : Arena::Index) : Nil

  # Remove *fd* from the polling system. Must raise a `RuntimeError` on error.
  #
  # If *closing* is true, then it preceeds a call to `close(2)`. Some
  # implementations may take advantage of close doing the book keeping.
  #
  # If *closing* is false then the fd must be deleted from the polling system.
  protected abstract def system_del(fd : Int32, closing = true) : Nil

  # Identical to `#system_del` but yields on error.
  protected abstract def system_del(fd : Int32, closing = true, & : -> _) : Nil

  # Arm a timer to interrupt a run at *time*. Set to `nil` to disarm the timer.
  private abstract def system_set_timer(time : Time::Span?) : Nil
end
