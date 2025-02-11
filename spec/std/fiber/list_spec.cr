require "../spec_helper"
require "../../support/fibers"
require "fiber/list"

describe Fiber::List do
  describe "#initialize" do
    it "creates an empty queue" do
      list = Fiber::List.new
      list.@head.should be_nil
      list.@tail.should be_nil
      list.size.should eq(0)
      list.empty?.should be_true
    end

    it "creates a filled queue" do
      f1 = new_fake_fiber("f1")
      f2 = new_fake_fiber("f2")
      f1.list_next = f2
      f2.list_next = nil

      list = Fiber::List.new(f2, f1, size: 2)
      list.@head.should be(f2)
      list.@tail.should be(f1)
      list.size.should eq(2)
      list.empty?.should be_false
    end
  end

  describe "#push" do
    it "to head" do
      list = Fiber::List.new
      f1 = new_fake_fiber("f1")
      f2 = new_fake_fiber("f2")
      f3 = new_fake_fiber("f3")

      # simulate fibers previously added to other queues
      f1.list_next = f3
      f2.list_next = f1

      # push first fiber
      list.push(f1)
      list.@head.should be(f1)
      list.@tail.should be(f1)
      f1.list_next.should be_nil
      list.size.should eq(1)

      # push second fiber
      list.push(f2)
      list.@head.should be(f2)
      list.@tail.should be(f1)
      f2.list_next.should be(f1)
      f1.list_next.should be_nil
      list.size.should eq(2)

      # push third fiber
      list.push(f3)
      list.@head.should be(f3)
      list.@tail.should be(f1)
      f3.list_next.should be(f2)
      f2.list_next.should be(f1)
      f1.list_next.should be_nil
      list.size.should eq(3)
    end
  end

  describe "#bulk_unshift" do
    it "to empty queue" do
      # manually create a queue
      f1 = new_fake_fiber("f1")
      f2 = new_fake_fiber("f2")
      f3 = new_fake_fiber("f3")
      f3.list_next = f2
      f2.list_next = f1
      f1.list_next = nil
      q1 = Fiber::List.new(f3, f1, size: 3)

      # push in bulk
      q2 = Fiber::List.new(nil, nil, size: 0)
      q2.bulk_unshift(pointerof(q1))
      q2.@head.should be(f3)
      q2.@tail.should be(f1)
      q2.size.should eq(3)
    end

    it "to filled queue" do
      f1 = new_fake_fiber("f1")
      f2 = new_fake_fiber("f2")
      f3 = new_fake_fiber("f3")
      f4 = new_fake_fiber("f4")
      f5 = new_fake_fiber("f5")

      # source queue
      f3.list_next = f2
      f2.list_next = f1
      f1.list_next = nil
      q1 = Fiber::List.new(f3, f1, size: 3)

      # destination queue
      f5.list_next = f4
      f4.list_next = nil
      q2 = Fiber::List.new(f5, f4, size: 2)

      # push in bulk
      q2.bulk_unshift(pointerof(q1))
      q2.@head.should be(f5)
      q2.@tail.should be(f1)
      q2.size.should eq(5)

      f5.list_next.should be(f4)
      f4.list_next.should be(f3)
      f3.list_next.should be(f2)
      f2.list_next.should be(f1)
      f1.list_next.should be(nil)
    end
  end

  describe "#pop" do
    it "from head" do
      f1 = new_fake_fiber("f1")
      f2 = new_fake_fiber("f2")
      f3 = new_fake_fiber("f3")
      f3.list_next = f2
      f2.list_next = f1
      f1.list_next = nil
      list = Fiber::List.new(f3, f1, size: 3)

      # removes third element
      list.pop.should be(f3)
      list.@head.should be(f2)
      list.@tail.should be(f1)
      list.size.should eq(2)

      # removes second element
      list.pop.should be(f2)
      list.@head.should be(f1)
      list.@tail.should be(f1)
      list.size.should eq(1)

      # removes first element
      list.pop.should be(f1)
      list.@head.should be_nil
      list.@tail.should be_nil
      list.size.should eq(0)

      # empty queue
      expect_raises(IndexError) { list.pop }
      list.size.should eq(0)
    end
  end

  describe "#pop?" do
    it "from head" do
      f1 = new_fake_fiber("f1")
      f2 = new_fake_fiber("f2")
      f3 = new_fake_fiber("f3")
      f3.list_next = f2
      f2.list_next = f1
      f1.list_next = nil
      list = Fiber::List.new(f3, f1, size: 3)

      # removes third element
      list.pop?.should be(f3)
      list.@head.should be(f2)
      list.@tail.should be(f1)
      list.size.should eq(2)

      # removes second element
      list.pop?.should be(f2)
      list.@head.should be(f1)
      list.@tail.should be(f1)
      list.size.should eq(1)

      # removes first element
      list.pop?.should be(f1)
      list.@head.should be_nil
      list.@tail.should be_nil
      list.size.should eq(0)

      # empty queue
      list.pop?.should be_nil
      list.size.should eq(0)
    end
  end
end
