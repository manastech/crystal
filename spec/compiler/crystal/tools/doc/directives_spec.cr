require "../../../spec_helper"

describe Crystal::Doc::Generator do
  context ":nodoc:" do
    it "hides documentation from being generated for methods" do
      program = top_level_semantic(<<-CRYSTAL, wants_doc: true).program
        class Foo
          # :nodoc:
          #
          # Some docs
          def foo
          end
        end
        CRYSTAL

      generator = Doc::Generator.new program, [""]
      generator.type(program.types["Foo"]).lookup_method("foo").should be_nil
    end

    it "hides documentation from being generated for classes" do
      program = top_level_semantic(<<-CRYSTAL, wants_doc: true).program
        # :nodoc:
        class Foo
        end
        CRYSTAL

      generator = Doc::Generator.new program, [""]
      generator.must_include?(program.types["Foo"]).should be_false
    end
  end

  context ":showdoc:" do
    it "shows documentation for private methods" do
      program = top_level_semantic(<<-CRYSTAL, wants_doc: true).program
        class Foo
          # :showdoc:
          #
          # Some docs
          private def foo
          end
        end
        CRYSTAL

      generator = Doc::Generator.new program, [""]
      a_def = generator.type(program.types["Foo"]).lookup_method("foo").not_nil!
      a_def.doc.should eq("Some docs")
      a_def.visibility.should eq("private")
    end

    it "shows documentation for nested objects if a lib is marked with :showdoc:" do
      program = top_level_semantic(<<-CRYSTAL, wants_doc: true).program
        # :showdoc:
        lib Foo
          # docs for `foo`
          fun foo
        end
        CRYSTAL

      generator = Doc::Generator.new program, [""]

      generator.must_include?(program.types["Foo"]).should be_true
      generator.type(program.types["Foo"]).lookup_method("foo").should_not be_nil
    end

    it "does not include documentation for methods within a :nodoc: namespace" do
      program = top_level_semantic(<<-CRYSTAL, wants_doc: true).program
        # :nodoc:
        class Foo
          # :showdoc:
          #
          # Some docs
          private def foo
          end
        end
        CRYSTAL

      generator = Doc::Generator.new program, [""]

      # If namespace isn't included, don't need to check if the method is included
      generator.must_include?(program.types["Foo"]).should be_false
    end

    it "does not include documentation for private and protected methods and objects in a :showdoc: namespace" do
      program = top_level_semantic(<<-CRYSTAL, wants_doc: true).program
        # :showdoc:
        class Foo
          # Some docs for `foo`
          private def foo
          end

          # Some docs for `bar`
          protected def bar
          end

          # Some docs for `Baz`
          private class Baz
          end
        end
        CRYSTAL

      generator = Doc::Generator.new program, [""]

      generator.type(program.types["Foo"]).lookup_method("foo").should be_nil
      generator.type(program.types["Foo"]).lookup_method("bar").should be_nil

      generator.must_include?(generator.type(program.types["Foo"]).lookup_path("Baz")).should be_false
    end

    it "does not include documentation for a :showdoc: fun inside a lib not marked with :showdoc:" do
      program = top_level_semantic(<<-CRYSTAL, wants_doc: true).program
        lib Foo
          # :showdoc:
          fun foo
        end
        CRYSTAL

      generator = Doc::Generator.new program, [""]

      generator.must_include?(program.types["Foo"]).should be_false
    end

    it "doesn't show a method marked :nodoc: within a :showdoc: namespace" do
      program = top_level_semantic(<<-CRYSTAL, wants_doc: true).program
        # :showdoc:
        class Foo
          # :nodoc:
          # Some docs for `foo`
          def foo
          end
        end
        CRYSTAL

      generator = Doc::Generator.new program, [""]
      generator.type(program.types["Foo"]).lookup_method("foo").should be_nil
    end

    it "doesn't show a fun marked :nodoc: within a :showdoc: lib" do
      program = top_level_semantic(<<-CRYSTAL, wants_doc: true).program
        # :showdoc:
        lib Foo
          # :nodoc:
          # Some docs for `foo`
          fun foo

          fun bar
        end
        CRYSTAL

      generator = Doc::Generator.new program, [""]
      generator.type(program.types["Foo"]).lookup_method("foo").should be_nil
      generator.type(program.types["Foo"]).lookup_method("bar").should_not be_nil
    end
  end
end
