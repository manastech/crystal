require "spec"

private def expect_overflow
  expect_raises OverflowError, "Arithmetic overflow" do
    yield
  end
end

describe Time::MonthSpan do
  it "initializes" do
    t1 = Time::MonthSpan.new 123_456_789_123
    t1.value.should eq(123_456_789_123)

    t1 = Time::MonthSpan.new 0
    t1.value.should eq(0)

    t1 = Time::MonthSpan.new 1
    t1.value.should eq(1)

    t1 = Time::MonthSpan.new Int64::MAX
    t1.value.should eq(Int64::MAX)

    t1 = Time::MonthSpan.new Int64::MIN
    t1.value.should eq(Int64::MIN)
  end

  it "test add" do
    t1 = Time::MonthSpan.new 5
    t2 = Time::MonthSpan.new 10
    t3 = t1 + t2

    t3.value.should eq(15)

    # TODO check overflow
  end

  it "test subtract" do
    t1 = Time::MonthSpan.new 36
    t2 = Time::MonthSpan.new 12
    t3 = t1 - t2
    t3.value.should eq(24)

    t1 = Time::MonthSpan.new 5
    t2 = Time::MonthSpan.new 10
    t3 = t1 - t2
    t3.value.should eq(-5)

    # TODO check overflow
  end

  it "test multiply" do
    t1 = Time::MonthSpan.new 12
    t2 = t1 * 2
    t3 = t1 * 0.5

    t2.should eq(Time::MonthSpan.new 24)
    t3.should eq(Time::MonthSpan.new 6)

    # TODO check overflow
  end

  it "test divide" do
    t1 = Time::MonthSpan.new 24
    t2 = t1 / 2
    t3 = t1 / 1.5

    t2.should eq(Time::MonthSpan.new 12)
    t3.should eq(Time::MonthSpan.new 16)

    # TODO check overflow
  end

  it "test compare" do
    t1 = Time::MonthSpan.new -1
    t2 = Time::MonthSpan.new 1

    (t1 <=> t2).should eq(-1)
    (t2 <=> t1).should eq(1)
    (t2 <=> t2).should eq(0)

    (t1 == t2).should be_false
    (t1 > t2).should be_false
    (t1 >= t2).should be_false
    (t1 != t2).should be_true
    (t1 < t2).should be_true
    (t1 <= t2).should be_true
  end

  it "test equals" do
    t1 = Time::MonthSpan.new 1
    t2 = Time::MonthSpan.new 2

    (t1 == t1).should be_true
    (t1 == t2).should be_false
    (t1 == "hello").should be_false
  end

  it "> Int64::MAX overflows" do
    expect_overflow do
      month = Int64::MAX.to_i128 + 1
      Time::MonthSpan.new month
    end
  end

  it "< Int64::MIN overflows" do
    expect_overflow do
      month = Int64::MIN.to_i128 - 1
      Time::MonthSpan.new month
    end
  end

  it "negate overflow" do
    expect_overflow do
      month = Int64::MIN
      t1 = Time::MonthSpan.new month
      -t1
    end
  end
end
