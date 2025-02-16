# Reorders overloads so that more specific overloads come before less specific
# ones, according to `Crystal::DefWithMetadata#restriction_of?`. Also assigns
# the correct `previous_def`s for redefinitions.
#
# This processor is used only if `-Dpreview_overload_order` is specified;
# otherwise, every new def is ordered as soon as it is defined, which could
# cause problems because type definitions may not be complete yet:
#
# ```
# class Foo
# end
#
# module Bar
# end
#
# def foo(a : Bar)
#   1
# end
#
# # requests the definitions of `Foo` and `Bar` to determine the overload order;
# # at this point `Foo < Bar` does not hold, so the `Bar` overload is still
# # considered first
# def foo(a : Foo)
#   2
# end
#
# class Foo
#   include Bar
# end
#
# foo(Foo.new) # => 1
# ```
#
# A consequence of deferring overload ordering is that top-level macros can no
# longer observe intermediate overload orders via `TypeNode#methods`.
#
# Defs added after this processor runs must still be ordered on definition (e.g.
# those from `method_missing`).
class Crystal::OverloadOrderingProcessor
  def initialize(@program : Program)
    @all_checked = Set(Type).new
  end

  def run
    check_type(@program)
    @program.file_modules.each_value do |file_module|
      check_type(file_module)
    end
  end

  def check_type(type)
    return if @all_checked.includes?(type)
    @all_checked << type

    check_single(type)

    type.types?.try &.each_value do |type|
      check_type(type)
    end
  end

  def check_single(type)
    if type.is_a?(ModuleType)
      reorder_overloads(type)
      reorder_overloads(type.metaclass.as(ModuleType))
    end
  end

  def reorder_overloads(type)
    type.defs.try &.each do |method, overloads|
      next unless overloads.size > 1

      # simply re-add all overloads one by one
      # TODO: if the overload order is confirmed to be transitive, we could sort
      # the overloads in-place
      unordered = overloads.dup
      overloads.clear
      unordered.each do |item|
        type.add_def(item.def, ordered: true)
      end
    end
  end
end
