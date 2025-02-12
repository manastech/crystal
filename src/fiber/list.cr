# The list is modeled after Go's `gQueue`, distributed under a BSD-like
# license: <https://cs.opensource.google/go/go/+/release-branch.go1.23:LICENSE>

class Fiber
  # :nodoc:
  #
  # Singly-linked list of `Fiber`.
  # Last-in, first-out (LIFO) semantic.
  # A fiber can only exist within a single `List` at any time.
  #
  # This list if simpler than `Crystal::PointerLinkedList` which is a doubly
  # linked list. It's meant to maintain a queue of runnable fibers, or to
  # quickly collect an arbitrary number of fibers; situations where we don't
  # need arbitrary deletions from anywhere in the list.
  #
  # Thread unsafe! An external lock is required for concurrent accesses.
  struct List
    getter size : Int32

    def initialize(@head : Fiber? = nil, @tail : Fiber? = nil, @size = 0)
    end

    # Appends *fiber* to the head of the list.
    def push(fiber : Fiber) : Nil
      fiber.list_next = @head
      @head = fiber
      @tail = fiber if @tail.nil?
      @size += 1
    end

    # Appends all the fibers from *other* to the tail of the list.
    def bulk_unshift(other : List*) : Nil
      return unless last = other.value.@tail
      last.list_next = nil

      if tail = @tail
        tail.list_next = other.value.@head
      else
        @head = other.value.@head
      end
      @tail = last

      @size += other.value.size
    end

    # Removes a fiber from the head of the list. Raises `IndexError` when
    # empty.
    @[AlwaysInline]
    def pop : Fiber
      pop { raise IndexError.new }
    end

    # Removes a fiber from the head of the list. Returns `nil` when empty.
    @[AlwaysInline]
    def pop? : Fiber?
      pop { nil }
    end

    private def pop(&)
      if fiber = @head
        @head = fiber.list_next
        @tail = nil if @head.nil?
        @size -= 1
        fiber.list_next = nil
        fiber
      else
        yield
      end
    end

    @[AlwaysInline]
    def empty? : Bool
      @head == nil
    end

    def clear : Nil
      @size = 0
      @head = @tail = nil
    end

    def each(&) : Nil
      cursor = @head
      while cursor
        yield cursor
        cursor = cursor.list_next
      end
    end
  end
end
