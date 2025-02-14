module Spec::Methods
  # Defines an example group that describes a unit to be tested.
  # Inside *&block* examples are defined by `#it` or `#pending`.
  #
  # Several `describe` blocks can be nested.
  #
  # Example:
  # ```
  # require "spec"
  #
  # describe "Int32" do
  #   describe "+" do
  #     it "adds" { (1 + 1).should eq 2 }
  #   end
  # end
  # ```
  #
  # If `focus` is `true`, only this `describe`, and others marked with `focus: true`, will run.
  def describe(description = nil, *, file = __FILE__, line = __LINE__, end_line = __END_LINE__, focus : Bool = false, tags : String | Enumerable(String) | Nil = nil, &block)
    Spec.cli.root_context.describe(description.to_s, file, line, end_line, focus, tags, &block)
  end

  @[Deprecated]
  def describe(description = nil, file = __FILE__, line = __LINE__, end_line = __END_LINE__, focus : Bool = false, tags : String | Enumerable(String) | Nil = nil, &block)
    Spec.cli.root_context.describe(description.to_s, file, line, end_line, focus, tags, &block)
  end

  # Defines an example group that establishes a specific context,
  # like *empty array* versus *array with elements*.
  # Inside *&block* examples are defined by `#it` or `#pending`.
  #
  # It is functionally equivalent to `#describe`.
  #
  # If `focus` is `true`, only this `context`, and others marked with `focus: true`, will run.
  def context(description = nil, *, file = __FILE__, line = __LINE__, end_line = __END_LINE__, focus : Bool = false, tags : String | Enumerable(String) | Nil = nil, &block)
    describe(description.to_s, file, line, end_line, focus, tags, &block)
  end

  @[Deprecated]
  def context(description = nil, file = __FILE__, line = __LINE__, end_line = __END_LINE__, focus : Bool = false, tags : String | Enumerable(String) | Nil = nil, &block)
    describe(description.to_s, file, line, end_line, focus, tags, &block)
  end

  # Defines a concrete test case.
  #
  # The test is performed by the block supplied to *&block*.
  #
  # Example:
  # ```
  # require "spec"
  #
  # it "adds" { (1 + 1).should eq 2 }
  # ```
  #
  # It is usually used inside a `#describe` or `#context` section.
  #
  # If `focus` is `true`, only this test, and others marked with `focus: true`, will run.
  def it(description = "assert", *, file = __FILE__, line = __LINE__, end_line = __END_LINE__, focus : Bool = false, tags : String | Enumerable(String) | Nil = nil, &block)
    Spec.cli.root_context.it(description.to_s, file, line, end_line, focus, tags, &block)
  end

  @[Deprecated]
  def it(description = "assert", file = __FILE__, line = __LINE__, end_line = __END_LINE__, focus : Bool = false, tags : String | Enumerable(String) | Nil = nil, &block)
    Spec.cli.root_context.it(description.to_s, file, line, end_line, focus, tags, &block)
  end

  # Defines a pending test case.
  #
  # *&block* is never evaluated.
  # It can be used to describe behaviour that is not yet implemented.
  #
  # Example:
  # ```
  # require "spec"
  #
  # pending "check cat" { cat.alive? }
  # ```
  #
  # It is usually used inside a `#describe` or `#context` section.
  #
  # If `focus` is `true`, only this test, and others marked with `focus: true`, will run.
  def pending(description = "assert", *, file = __FILE__, line = __LINE__, end_line = __END_LINE__, focus : Bool = false, tags : String | Enumerable(String) | Nil = nil, &block)
    pending(description, file, line, end_line, focus, tags)
  end

  @[Deprecated]
  def pending(description = "assert", file = __FILE__, line = __LINE__, end_line = __END_LINE__, focus : Bool = false, tags : String | Enumerable(String) | Nil = nil, &block)
    pending(description, file, line, end_line, focus, tags)
  end

  # Defines a yet-to-be-implemented pending test case
  #
  # If `focus` is `true`, only this test, and others marked with `focus: true`, will run.
  def pending(description = "assert", *, file = __FILE__, line = __LINE__, end_line = __END_LINE__, focus : Bool = false, tags : String | Enumerable(String) | Nil = nil)
    Spec.cli.root_context.pending(description.to_s, file, line, end_line, focus, tags)
  end

  @[Deprecated]
  def pending(description = "assert", file = __FILE__, line = __LINE__, end_line = __END_LINE__, focus : Bool = false, tags : String | Enumerable(String) | Nil = nil)
    Spec.cli.root_context.pending(description.to_s, file, line, end_line, focus, tags)
  end

  # Fails an example.
  #
  # This method can be used to manually fail an example defined in an `#it` block.
  def fail(msg, *, file = __FILE__, line = __LINE__)
    raise Spec::AssertionFailed.new(msg, file, line)
  end

  @[Deprecated]
  def fail(msg, file = __FILE__, line = __LINE__)
    raise Spec::AssertionFailed.new(msg, file, line)
  end

  # Marks the current example pending
  #
  # In case an example needs to be pending on some condition that requires executing it,
  # this allows to mark it as such  rather than letting it fail or never run.
  #
  # ```
  # require "spec"
  #
  # it "test git" do
  #   cmd = Process.find_executable("git")
  #   pending!("git is not available") unless cmd
  #   cmd.should end_with("git")
  # end
  # ```
  def pending!(msg = "Cannot run example", *, file = __FILE__, line = __LINE__)
    raise Spec::ExamplePending.new(msg, file, line)
  end

  @[Deprecated]
  def pending!(msg = "Cannot run example", file = __FILE__, line = __LINE__)
    raise Spec::ExamplePending.new(msg, file, line)
  end

  # Executes the given block before each spec in the current context runs.
  #
  # A context is defined by `describe` or `context` blocks, or outside of them
  # it's the root context. Nested contexts inherit the `*_each` blocks of
  # their ancestors.
  #
  # If multiple blocks are registered for the same spec, the blocks defined in
  # the outermost context go first. Blocks on the same context are executed in
  # order of definition.
  #
  # ```
  # require "spec"
  #
  # it "sample_a" { }
  #
  # describe "nested_context" do
  #   before_each do
  #     puts "runs before sample_b"
  #   end
  #
  #   it "sample_b" { }
  # end
  # ```
  def before_each(&block)
    if Spec.cli.current_context.is_a?(RootContext)
      raise "Can't call `before_each` outside of a describe/context"
    end
    Spec.cli.current_context.before_each(&block)
  end

  # Executes the given block after each spec in the current context runs.
  #
  # A context is defined by `describe` or `context` blocks, or outside of them
  # it's the root context. Nested contexts inherit the `*_each` blocks of
  # their ancestors.
  #
  # If multiple blocks are registered for the same spec, the blocks defined in
  # the outermost context go first. Blocks on the same context are executed in
  # order of definition.
  #
  # ```
  # require "spec"
  #
  # it "sample_a" { }
  #
  # describe "nested_context" do
  #   after_each do
  #     puts "runs after sample_b"
  #   end
  #
  #   it "sample_b" { }
  # end
  # ```
  def after_each(&block)
    if Spec.cli.current_context.is_a?(RootContext)
      raise "Can't call `after_each` outside of a describe/context"
    end
    Spec.cli.current_context.after_each(&block)
  end

  # Executes the given block before the first spec in the current context runs.
  #
  # A context is defined by `describe` or `context` blocks, or outside of them
  # it's the root context.
  # This is independent of the source location the specs and this hook are
  # defined.
  #
  # If multiple blocks are registered on the same context, they are executed in
  # order of definition.
  #
  # ```
  # require "spec"
  #
  # it "sample_a" { }
  #
  # describe "nested_context" do
  #   before_all do
  #     puts "runs at start of nested_context"
  #   end
  #
  #   it "sample_b" { }
  # end
  # ```
  def before_all(&block)
    if Spec.cli.current_context.is_a?(RootContext)
      raise "Can't call `before_all` outside of a describe/context"
    end
    Spec.cli.current_context.before_all(&block)
  end

  # Executes the given block after the last spec in the current context runs.
  #
  # A context is defined by `describe` or `context` blocks, or outside of them
  # it's the root context.
  # This is independent of the source location the specs and this hook are
  # defined.
  #
  # If multiple blocks are registered on the same context, they are executed in
  # order of definition.
  #
  # ```
  # require "spec"
  #
  # it "sample_a" { }
  #
  # describe "nested_context" do
  #   after_all do
  #     puts "runs at end of nested_context"
  #   end
  #
  #   it "sample_b" { }
  # end
  # ```
  def after_all(&block)
    if Spec.cli.current_context.is_a?(RootContext)
      raise "Can't call `after_all` outside of a describe/context"
    end
    Spec.cli.current_context.after_all(&block)
  end

  # Executes the given block when each spec in the current context runs.
  #
  # The block must call `run` on the given `Example::Procsy`
  # object.
  #
  # This is essentially a `before_each` and `after_each` hook combined into one.
  # It is useful for example when setup and teardown steps need shared state.
  #
  # A context is defined by `describe` or `context` blocks, or outside of them
  # it's the root context. Nested contexts inherit the `*_each` blocks of
  # their ancestors.
  #
  # If multiple blocks are registered for the same spec, the blocks defined in
  # the outermost context go first. Blocks on the same context are executed in
  # order of definition.
  #
  # ```
  # require "spec"
  #
  # it "sample_a" { }
  #
  # describe "nested_context" do
  #   around_each do |example|
  #     puts "runs before sample_b"
  #     example.run
  #     puts "runs after sample_b"
  #   end
  #
  #   it "sample_b" { }
  # end
  # ```
  def around_each(&block : Example::Procsy ->)
    if Spec.cli.current_context.is_a?(RootContext)
      raise "Can't call `around_each` outside of a describe/context"
    end
    Spec.cli.current_context.around_each(&block)
  end

  # Executes the given block when the current context runs.
  #
  # The block must call `run` on the given `Context::Procsy`
  # object.
  #
  # This is essentially a `before_all` and `after_all` hook combined into one.
  # It is useful for example when setup and teardown steps need shared state.
  #
  # A context is defined by `describe` or `context` blocks. This hook does not
  # work outside such a block (i.e. in the root context).
  #
  # If multiple blocks are registered for the same spec, the blocks defined in
  # the outermost context go first. Blocks on the same context are executed in
  # order of definition.
  #
  # ```
  # require "spec"
  #
  # describe "main_context" do
  #   around_each do |example|
  #     puts "runs at beginning of main_context"
  #     example.run
  #     puts "runs at end of main_context"
  #   end
  #
  #   it "sample_a" { }
  #
  #   describe "nested_context" do
  #     around_each do |example|
  #       puts "runs at beginning of nested_context"
  #       example.run
  #       puts "runs at end of nested_context"
  #     end
  #
  #     it "sample_b" { }
  #   end
  # end
  # ```
  def around_all(&block : ExampleGroup::Procsy ->)
    if Spec.cli.current_context.is_a?(RootContext)
      raise "Can't call `around_all` outside of a describe/context"
    end
    Spec.cli.current_context.around_all(&block)
  end
end

include Spec::Methods
