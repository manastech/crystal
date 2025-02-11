# This file defines the `__crystal_once` functions expected by the compiler. It
# is called each time a constant or class variable has to be initialized and is
# its responsibility to verify the initializer is executed only once and to fail
# on recursion.
#
# It also defines the `__crystal_once_init` function for backward compatibility
# with older compiler releases. It is executed only once at the beginning of the
# program and, for the legacy implementation, the result is passed on each call
# to `__crystal_once`.

require "crystal/pointer_linked_list"
require "crystal/spin_lock"

module Crystal
  # :nodoc:
  module Once
    struct Operation
      include PointerLinkedList::Node

      getter fiber : Fiber
      getter flag : Bool*

      def initialize(@flag : Bool*, @fiber : Fiber)
        @waiting = PointerLinkedList(Fiber::PointerLinkedListNode).new
      end

      def add_waiter(node) : Nil
        @waiting.push(node)
      end

      def resume_all : Nil
        @waiting.each(&.value.enqueue)
      end
    end

    @@spin = uninitialized SpinLock
    @@operations = uninitialized PointerLinkedList(Operation)

    def self.init : Nil
      @@spin = SpinLock.new
      @@operations = PointerLinkedList(Operation).new
    end

    protected def self.exec(flag : Bool*, &)
      @@spin.lock

      if flag.value
        @@spin.unlock
      elsif operation = processing?(flag)
        check_reentrancy(operation)
        wait_initializer(operation)
      else
        run_initializer(flag) { yield }
      end

      # safety check, and allows to safely call `Intrinsics.unreachable` in
      # `__crystal_once`
      return if flag.value

      System.print_error "BUG: failed to initialize class variable or constant\n"
      LibC._exit(1)
    end

    private def self.processing?(flag)
      @@operations.each do |operation|
        return operation if operation.value.flag == flag
      end
    end

    private def self.check_reentrancy(operation)
      if operation.value.fiber == Fiber.current
        @@spin.unlock
        raise "Recursion while initializing class variables and/or constants"
      end
    end

    private def self.wait_initializer(operation)
      waiting = Fiber::PointerLinkedListNode.new(Fiber.current)
      operation.value.add_waiter(pointerof(waiting))
      @@spin.unlock
      Fiber.suspend
    end

    private def self.run_initializer(flag, &)
      operation = Operation.new(flag, Fiber.current)
      @@operations.push pointerof(operation)
      @@spin.unlock

      yield

      @@spin.lock
      flag.value = true
      @@operations.delete pointerof(operation)
      @@spin.unlock

      operation.resume_all
    end
  end

  # :nodoc:
  #
  # Never inlined to avoid bloating the call site with the slow-path that should
  # usually not be taken.
  @[NoInline]
  def self.once(flag : Bool*, initializer : Void*)
    Once.exec(flag, &Proc(Nil).new(initializer, Pointer(Void).null))
  end

  # :nodoc:
  #
  # NOTE: should also never be inlined, but that would capture the block, which
  # would be a breaking change when we use this method to protect class getter
  # and class property macros with lazy initialization (the block may return or
  # break).
  #
  # TODO: consider a compile time flag to enable/disable the capture? returning
  # from the block is unexpected behavior: the returned value won't be saved in
  # the class variable.
  def self.once(flag : Bool*, &)
    Once.exec(flag) { yield } unless flag.value
  end
end

{% if compare_versions(Crystal::VERSION, "1.16.0-dev") >= 0 %}
  # :nodoc:
  #
  # We always inline this accessor to optimize for the fast-path (already
  # initialized).
  @[AlwaysInline]
  fun __crystal_once(flag : Bool*, initializer : Void*)
    return if flag.value
    Crystal.once(flag, initializer)

    # tells LLVM to assume that the flag is true, this avoids repeated access to
    # the same constant or class variable to check the flag and try to run the
    # initializer (only the first access will)
    Intrinsics.unreachable unless flag.value
  end
{% else %}
  # :nodoc:
  #
  # Unused. Kept for backward compatibility with older compilers.
  fun __crystal_once_init : Void*
    Pointer(Void).null
  end

  # :nodoc:
  @[AlwaysInline]
  fun __crystal_once(state : Void*, flag : Bool*, initializer : Void*)
    return if flag.value
    Crystal.once(flag, initializer)
    Intrinsics.unreachable unless flag.value
  end
{% end %}
