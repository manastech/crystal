require "../spec_helper"
require "../../support/time"
require "spec/helpers/string"

def parse_time(format, string)
  Time.parse_utc(format, string)
end

def parse_time(string)
  Time.parse_utc(string, "%F %T.%N")
end

describe Time::Format do
  it "formats" do
    with_zoneinfo do
      t = Time.utc 2014, 1, 2, 3, 4, 5, nanosecond: 6_000_000
      t2 = Time.utc 2014, 1, 2, 15, 4, 5, nanosecond: 6_000_000
      t3 = Time.utc 2014, 1, 2, 12, 4, 5, nanosecond: 6_000_000

      assert_prints t.to_s("%Y"), "2014"
      assert_prints Time.utc(1, 1, 2, 3, 4, 5, nanosecond: 6).to_s("%Y"), "0001"

      assert_prints t.to_s("%C"), "20"
      assert_prints t.to_s("%y"), "14"
      assert_prints t.to_s("%m"), "01"
      assert_prints t.to_s("%_m"), " 1"
      assert_prints t.to_s("%_%_m2"), "%_ 12"
      assert_prints t.to_s("%-m"), "1"
      assert_prints t.to_s("%-%-m2"), "%-12"
      assert_prints t.to_s("%B"), "January"
      assert_prints t.to_s("%^B"), "JANUARY"
      assert_prints t.to_s("%^%^B2"), "%^JANUARY2"
      assert_prints t.to_s("%b"), "Jan"
      assert_prints t.to_s("%^b"), "JAN"
      assert_prints t.to_s("%h"), "Jan"
      assert_prints t.to_s("%^h"), "JAN"
      assert_prints t.to_s("%d"), "02"
      assert_prints t.to_s("%-d"), "2"
      assert_prints t.to_s("%e"), " 2"
      assert_prints t.to_s("%j"), "002"
      assert_prints t.to_s("%H"), "03"

      assert_prints t.to_s("%k"), " 3"
      assert_prints t2.to_s("%k"), "15"

      assert_prints t.to_s("%I"), "03"
      assert_prints t2.to_s("%I"), "03"
      assert_prints t3.to_s("%I"), "12"

      assert_prints t.to_s("%l"), " 3"
      assert_prints t2.to_s("%l"), " 3"
      assert_prints t3.to_s("%l"), "12"

      # Note: we purposely match %p to am/pm and %P to AM/PM (makes more sense)
      assert_prints t.to_s("%p"), "am"
      assert_prints t2.to_s("%p"), "pm"

      assert_prints t.to_s("%P"), "AM"
      assert_prints t2.to_s("%P"), "PM"

      assert_prints t.to_s("%M"), "04"
      assert_prints t.to_s("%S"), "05"
      assert_prints t.to_s("%L"), "006"
      assert_prints t.to_s("%N"), "006000000"
      assert_prints t.to_s("%3N"), "006"
      assert_prints t.to_s("%6N"), "006000"
      assert_prints t.to_s("%9N"), "006000000"

      assert_prints t.to_s("%z"), "+0000"
      assert_prints t.to_s("%:z"), "+00:00"
      assert_prints t.to_s("%::z"), "+00:00:00"
      assert_prints t.to_s("%^Z"), "UTC"
      assert_prints t.to_s("%Z"), "UTC"

      with_zoneinfo do
        zoned = Time.local(2017, 11, 24, 13, 5, 6, location: Time::Location.load("Europe/Berlin"))
        assert_prints zoned.to_s("%z"), "+0100"
        assert_prints zoned.to_s("%:z"), "+01:00"
        assert_prints zoned.to_s("%::z"), "+01:00:00"
        assert_prints zoned.to_s("%^Z"), "CET"
        assert_prints zoned.to_s("%Z"), "Europe/Berlin"

        zoned = Time.local(2017, 11, 24, 13, 5, 6, location: Time::Location.load("America/Buenos_Aires"))
        assert_prints zoned.to_s("%z"), "-0300"
        assert_prints zoned.to_s("%:z"), "-03:00"
        assert_prints zoned.to_s("%::z"), "-03:00:00"
        assert_prints zoned.to_s("%^Z"), "-03"
        assert_prints zoned.to_s("%Z"), "America/Buenos_Aires"
      end

      offset = Time.local(2017, 11, 24, 13, 5, 6, location: Time::Location.fixed(9000))
      assert_prints offset.to_s("%z"), "+0230"
      assert_prints offset.to_s("%:z"), "+02:30"
      assert_prints offset.to_s("%::z"), "+02:30:00"
      assert_prints offset.to_s("%^Z"), "+02:30"
      assert_prints offset.to_s("%Z"), "+02:30"

      offset = Time.local(2017, 11, 24, 13, 5, 6, location: Time::Location.fixed(9001))
      assert_prints offset.to_s("%z"), "+0230"
      assert_prints offset.to_s("%:z"), "+02:30"
      assert_prints offset.to_s("%::z"), "+02:30:01"
      assert_prints offset.to_s("%^Z"), "+02:30:01"
      assert_prints offset.to_s("%Z"), "+02:30:01"

      assert_prints t.to_s("%A"), "Thursday"
      assert_prints t.to_s("%^A"), "THURSDAY"
      assert_prints t.to_s("%a"), "Thu"
      assert_prints t.to_s("%^a"), "THU"
      assert_prints t.to_s("%u"), "4"
      assert_prints t.to_s("%w"), "4"

      t4 = Time.utc 2014, 1, 5 # A Sunday
      assert_prints t4.to_s("%u"), "7"
      assert_prints t4.to_s("%w"), "0"

      assert_prints Time.utc(1985, 4, 12).to_s("%G-W%V-%u"), "1985-W15-5"
      assert_prints Time.utc(2005, 1, 1).to_s("%G-W%V-%u"), "2004-W53-6"
      assert_prints Time.utc(2005, 1, 2).to_s("%G-W%V-%u"), "2004-W53-7"
      assert_prints Time.utc(2005, 12, 31).to_s("%G-W%V-%u"), "2005-W52-6"
      assert_prints Time.utc(2006, 1, 1).to_s("%G-W%V-%u"), "2005-W52-7"
      assert_prints Time.utc(2006, 1, 2).to_s("%G-W%V-%u"), "2006-W01-1"
      assert_prints Time.utc(2006, 12, 31).to_s("%G-W%V-%u"), "2006-W52-7"
      assert_prints Time.utc(2007, 1, 1).to_s("%G-W%V-%u"), "2007-W01-1"
      assert_prints Time.utc(2007, 12, 30).to_s("%G-W%V-%u"), "2007-W52-7"
      assert_prints Time.utc(2007, 12, 31).to_s("%G-W%V-%u"), "2008-W01-1"
      assert_prints Time.utc(2008, 1, 1).to_s("%G-W%V-%u"), "2008-W01-2"
      assert_prints Time.utc(2008, 12, 28).to_s("%G-W%V-%u"), "2008-W52-7"
      assert_prints Time.utc(2008, 12, 29).to_s("%G-W%V-%u"), "2009-W01-1"
      assert_prints Time.utc(2008, 12, 30).to_s("%G-W%V-%u"), "2009-W01-2"
      assert_prints Time.utc(2008, 12, 31).to_s("%G-W%V-%u"), "2009-W01-3"
      assert_prints Time.utc(2009, 1, 1).to_s("%G-W%V-%u"), "2009-W01-4"
      assert_prints Time.utc(2009, 12, 31).to_s("%G-W%V-%u"), "2009-W53-4"
      assert_prints Time.utc(2010, 1, 1).to_s("%G-W%V-%u"), "2009-W53-5"
      assert_prints Time.utc(2010, 1, 2).to_s("%G-W%V-%u"), "2009-W53-6"
      assert_prints Time.utc(2010, 1, 3).to_s("%G-W%V-%u"), "2009-W53-7"
      assert_prints Time.utc(1985, 4, 12).to_s("%g-W%V-%u"), "85-W15-5"
      # TODO %U
      # TODO %W
      # TODO %s
      # TODO %n
      # TODO %t
      # TODO %%

      assert_prints t.to_s("%%"), "%"
      assert_prints t.to_s("%c"), t.to_s("%a %b %e %T %Y")
      assert_prints t.to_s("%D"), t.to_s("%m/%d/%y")
      assert_prints t.to_s("%F"), t.to_s("%Y-%m-%d")
      # TODO %v
      assert_prints t.to_s("%x"), t.to_s("%D")
      assert_prints t.to_s("%X"), t.to_s("%T")
      assert_prints t.to_s("%r"), t.to_s("%I:%M:%S %P")
      assert_prints t.to_s("%R"), t.to_s("%H:%M")
      assert_prints t.to_s("%T"), t.to_s("%H:%M:%S")

      assert_prints t.to_s("%Y-%m-hello"), "2014-01-hello"

      t5 = Time.utc 2014, 1, 2, 3, 4, 5, nanosecond: 6
      assert_prints t5.to_s("%s"), "1388631845"
    end
  end

  it "formats standard formats" do
    time = Time.utc(2016, 2, 15)
    assert_prints time.to_rfc3339, "2016-02-15T00:00:00Z"
    Time.parse_rfc3339(time.to_rfc3339).should eq time
    assert_prints time.to_rfc2822, "Mon, 15 Feb 2016 00:00:00 +0000"
    Time.parse_rfc2822(time.to_rfc2822).should eq time
  end

  it "formats rfc3339 with different fraction digits" do
    time = Time.utc(2016, 2, 15, 8, 23, 45, nanosecond: 123456789)
    assert_prints time.to_rfc3339, "2016-02-15T08:23:45Z"
    assert_prints time.to_rfc3339(fraction_digits: 0), "2016-02-15T08:23:45Z"
    assert_prints time.to_rfc3339(fraction_digits: 3), "2016-02-15T08:23:45.123Z"
    assert_prints time.to_rfc3339(fraction_digits: 6), "2016-02-15T08:23:45.123456Z"
    assert_prints time.to_rfc3339(fraction_digits: 9), "2016-02-15T08:23:45.123456789Z"
    expect_raises(ArgumentError, "Invalid fraction digits: 5") { time.to_rfc3339(fraction_digits: 5) }
    expect_raises(ArgumentError, "Invalid fraction digits: -1") { time.to_rfc3339(fraction_digits: -1) }

    time = Time.utc(2016, 2, 15, 8, 23, 45)
    assert_prints time.to_rfc3339, "2016-02-15T08:23:45Z"
    assert_prints time.to_rfc3339(fraction_digits: 0), "2016-02-15T08:23:45Z"
    assert_prints time.to_rfc3339(fraction_digits: 3), "2016-02-15T08:23:45.000Z"
    assert_prints time.to_rfc3339(fraction_digits: 6), "2016-02-15T08:23:45.000000Z"
    assert_prints time.to_rfc3339(fraction_digits: 9), "2016-02-15T08:23:45.000000000Z"
  end

  it "parses empty" do
    t = Time.parse("", "", Time::Location.local)
    t.year.should eq(1)
    t.month.should eq(1)
    t.day.should eq(1)
    t.hour.should eq(0)
    t.minute.should eq(0)
    t.second.should eq(0)
    t.millisecond.should eq(0)
    t.local?.should be_true
  end

  it "parse fails without time zone" do
    expect_raises(Time::Format::Error, "no default location provided") do
      Time.parse!("2017-12-01 20:15:13", "%F %T")
    end
    Time.parse("2017-12-01 20:15:13", "%F %T", Time::Location.local).to_s("%F %T").should eq "2017-12-01 20:15:13"
    Time.parse!("2017-12-01 20:15:13 +01:00", "%F %T %:z").to_s("%F %T %:z").should eq "2017-12-01 20:15:13 +01:00"
  end

  it "gives nice error message when end of input is reached (#12047)" do
    expect_raises(Time::Format::Error, "Expected '-' but the end of the input was reached") do
      Time.parse!("2021-01", "%F")
    end
  end

  it "parses" do
    parse_time("2014", "%Y").year.should eq(2014)
    parse_time("19", "%C").year.should eq(1900)
    parse_time("14", "%y").year.should eq(2014)
    parse_time("09", "%m").month.should eq(9)
    parse_time(" 9", "%_m").month.should eq(9)
    parse_time("9", "%-m").month.should eq(9)
    parse_time("February", "%B").month.should eq(2)
    parse_time("March", "%B").month.should eq(3)
    parse_time("MaRcH", "%B").month.should eq(3)
    parse_time("MaR", "%B").month.should eq(3)
    parse_time("MARCH", "%^B").month.should eq(3)
    parse_time("Mar", "%b").month.should eq(3)
    parse_time("Mar", "%^b").month.should eq(3)
    parse_time("MAR", "%^b").month.should eq(3)
    parse_time("MAR", "%h").month.should eq(3)
    parse_time("MAR", "%^h").month.should eq(3)
    parse_time("2", "%d").day.should eq(2)
    parse_time("02", "%d").day.should eq(2)
    parse_time("02", "%-d").day.should eq(2)
    parse_time(" 2", "%e").day.should eq(2)
    parse_time("9", "%H").hour.should eq(9)
    parse_time(" 9", "%k").hour.should eq(9)
    parse_time("09", "%I").hour.should eq(9)
    parse_time(" 9", "%l").hour.should eq(9)
    parse_time("9pm", "%l%p").hour.should eq(21)
    parse_time("9PM", "%l%P").hour.should eq(21)
    parse_time("12PM", "%l%P").hour.should eq(12)
    parse_time("9am", "%l%p").hour.should eq(9)
    parse_time("9AM", "%l%P").hour.should eq(9)
    parse_time("12AM", "%l%P").hour.should eq(0)
    parse_time("09", "%M").minute.should eq(9)
    parse_time("09", "%S").second.should eq(9)
    parse_time("123", "%L").millisecond.should eq(123)
    parse_time("1", "%L").millisecond.should eq(100)
    parse_time("000000321", "%N").nanosecond.should eq(321)
    parse_time("321", "%N").nanosecond.should eq(321000000)
    parse_time("321999", "%3N").nanosecond.should eq(321000000)
    parse_time("321", "%6N").nanosecond.should eq(321000000)
    parse_time("000321999", "%6N").nanosecond.should eq(321000)
    parse_time("000000321999", "%9N").nanosecond.should eq(321)
    parse_time("321", "%9N").nanosecond.should eq(321000000)
    parse_time("3214569879999", "%N").nanosecond.should eq(321456987)
    parse_time("Fri Oct 31 23:00:24 2014", "%c").to_s.should eq("2014-10-31 23:00:24 UTC")
    parse_time("10/31/14", "%D").to_s.should eq("2014-10-31 00:00:00 UTC")
    parse_time("10/31/69", "%D").to_s.should eq("1969-10-31 00:00:00 UTC")
    parse_time("2014-10-31", "%F").to_s.should eq("2014-10-31 00:00:00 UTC")
    parse_time("2014-10-31", "%F").to_s.should eq("2014-10-31 00:00:00 UTC")
    parse_time("10/31/14", "%x").to_s.should eq("2014-10-31 00:00:00 UTC")
    parse_time("10:11:12", "%X").to_s.should eq("0001-01-01 10:11:12 UTC")
    parse_time("11:14:01 PM", "%r").to_s.should eq("0001-01-01 23:14:01 UTC")
    parse_time("11:14", "%R").to_s.should eq("0001-01-01 11:14:00 UTC")
    parse_time("11:12:13", "%T").to_s.should eq("0001-01-01 11:12:13 UTC")
    parse_time("This was done on Friday, October 31, 2014", "This was done on %A, %B %d, %Y").to_s.should eq("2014-10-31 00:00:00 UTC")
    parse_time("今は Friday, October 31, 2014", "今は %A, %B %d, %Y").to_s.should eq("2014-10-31 00:00:00 UTC")
    parse_time("epoch: 1459864667", "epoch: %s").to_unix.should eq(1459864667)
    parse_time("epoch: -1459864667", "epoch: %s").to_unix.should eq(-1459864667)

    parse_time("1985-W15-5", "%G-W%V-%u").should eq(Time.utc(1985, 4, 12))
    parse_time("2004-W53-6", "%G-W%V-%u").should eq(Time.utc(2005, 1, 1))
    parse_time("2004-W53-7", "%G-W%V-%u").should eq(Time.utc(2005, 1, 2))
    parse_time("2005-W52-6", "%G-W%V-%u").should eq(Time.utc(2005, 12, 31))
    parse_time("2005-W52-7", "%G-W%V-%u").should eq(Time.utc(2006, 1, 1))
    parse_time("2006-W01-1", "%G-W%V-%u").should eq(Time.utc(2006, 1, 2))
    parse_time("2006-W52-7", "%G-W%V-%u").should eq(Time.utc(2006, 12, 31))
    parse_time("2007-W01-1", "%G-W%V-%u").should eq(Time.utc(2007, 1, 1))
    parse_time("2007-W52-7", "%G-W%V-%u").should eq(Time.utc(2007, 12, 30))
    parse_time("2008-W01-1", "%G-W%V-%u").should eq(Time.utc(2007, 12, 31))
    parse_time("2008-W01-2", "%G-W%V-%u").should eq(Time.utc(2008, 1, 1))
    parse_time("2008-W52-7", "%G-W%V-%u").should eq(Time.utc(2008, 12, 28))
    parse_time("2009-W01-1", "%G-W%V-%u").should eq(Time.utc(2008, 12, 29))
    parse_time("2009-W01-2", "%G-W%V-%u").should eq(Time.utc(2008, 12, 30))
    parse_time("2009-W01-3", "%G-W%V-%u").should eq(Time.utc(2008, 12, 31))
    parse_time("2009-W01-4", "%G-W%V-%u").should eq(Time.utc(2009, 1, 1))
    parse_time("2009-W53-4", "%G-W%V-%u").should eq(Time.utc(2009, 12, 31))
    parse_time("2009-W53-5", "%G-W%V-%u").should eq(Time.utc(2010, 1, 1))
    parse_time("2009-W53-6", "%G-W%V-%u").should eq(Time.utc(2010, 1, 2))
    parse_time("2009-W53-7", "%G-W%V-%u").should eq(Time.utc(2010, 1, 3))
  end

  it "parses am/pm" do
    parse_time("12:00 am", "%I:%M %P").to_s("%H:%M").should eq("00:00")
    parse_time("12:01 am", "%I:%M %P").to_s("%H:%M").should eq("00:01")
    parse_time("01:00 am", "%I:%M %P").to_s("%H:%M").should eq("01:00")
    parse_time("11:00 am", "%I:%M %P").to_s("%H:%M").should eq("11:00")
    parse_time("00:00 pm", "%I:%M %P").to_s("%H:%M").should eq("12:00")
    parse_time("00:01 pm", "%I:%M %P").to_s("%H:%M").should eq("12:01")
    parse_time("12:00 pm", "%I:%M %P").to_s("%H:%M").should eq("12:00")
    parse_time("12:01 pm", "%I:%M %P").to_s("%H:%M").should eq("12:01")
    parse_time("01:00 pm", "%I:%M %P").to_s("%H:%M").should eq("13:00")
    parse_time("11:00 pm", "%I:%M %P").to_s("%H:%M").should eq("23:00")
    expect_raises Time::Format::Error, "Invalid hour for 12-hour clock" do
      parse_time("00:00 am", "%I:%M %P")
    end
    expect_raises Time::Format::Error, "Invalid hour for 12-hour clock" do
      parse_time("00:01 am", "%I:%M %P")
    end
    expect_raises Time::Format::Error, "Invalid hour for 12-hour clock" do
      parse_time("13:00 am", "%I:%M %P")
    end
    expect_raises Time::Format::Error, "Invalid hour for 12-hour clock" do
      parse_time("13:00 pm", "%I:%M %P")
    end

    parse_time("12:00", "%I:%M").to_s("%H:%M").should eq("00:00")
    parse_time("12:01", "%I:%M").to_s("%H:%M").should eq("00:01")
    parse_time("01:00", "%I:%M").to_s("%H:%M").should eq("01:00")
    parse_time("11:00", "%I:%M").to_s("%H:%M").should eq("11:00")
    expect_raises Time::Format::Error, "Invalid hour for 12-hour clock" do
      parse_time("00:00", "%I:%M")
    end
    expect_raises Time::Format::Error, "Invalid hour for 12-hour clock" do
      parse_time("00:01", "%I:%M")
    end
    expect_raises Time::Format::Error, "Invalid hour for 12-hour clock" do
      parse_time("13:00", "%I:%M")
    end

    parse_time("12:00 am", "%l:%M %P").to_s("%H:%M").should eq("00:00")
    parse_time("12:01 am", "%l:%M %P").to_s("%H:%M").should eq("00:01")
    parse_time(" 1:00 am", "%l:%M %P").to_s("%H:%M").should eq("01:00")
    parse_time("11:00 am", "%l:%M %P").to_s("%H:%M").should eq("11:00")
    parse_time(" 0:00 pm", "%l:%M %P").to_s("%H:%M").should eq("12:00")
    parse_time(" 0:01 pm", "%l:%M %P").to_s("%H:%M").should eq("12:01")
    parse_time("12:00 pm", "%l:%M %P").to_s("%H:%M").should eq("12:00")
    parse_time("12:01 pm", "%l:%M %P").to_s("%H:%M").should eq("12:01")
    parse_time(" 1:00 pm", "%l:%M %P").to_s("%H:%M").should eq("13:00")
    parse_time("11:00 pm", "%l:%M %P").to_s("%H:%M").should eq("23:00")
    expect_raises Time::Format::Error, "Invalid hour for 12-hour clock" do
      parse_time(" 0:00 am", "%l:%M %P")
    end
    expect_raises Time::Format::Error, "Invalid hour for 12-hour clock" do
      parse_time(" 0:01 am", "%l:%M %P")
    end
    expect_raises Time::Format::Error, "Invalid hour for 12-hour clock" do
      parse_time("13:00 am", "%l:%M %P")
    end
    expect_raises Time::Format::Error, "Invalid hour for 12-hour clock" do
      parse_time("13:00 pm", "%l:%M %P")
    end

    parse_time("12:00", "%l:%M").to_s("%H:%M").should eq("00:00")
    parse_time("12:01", "%l:%M").to_s("%H:%M").should eq("00:01")
    parse_time("01:00", "%l:%M").to_s("%H:%M").should eq("01:00")
    parse_time("11:00", "%l:%M").to_s("%H:%M").should eq("11:00")
    expect_raises Time::Format::Error, "Invalid hour for 12-hour clock" do
      parse_time(" 0:00", "%l:%M")
    end
    expect_raises Time::Format::Error, "Invalid hour for 12-hour clock" do
      parse_time(" 0:01", "%l:%M")
    end
    expect_raises Time::Format::Error, "Invalid hour for 12-hour clock" do
      parse_time("13:00", "%l:%M")
    end
  end

  it "parses 24h clock" do
    parse_time("00:00", "%H:%M").to_s("%H:%M").should eq("00:00")
    parse_time("00:01", "%H:%M").to_s("%H:%M").should eq("00:01")
    parse_time("01:00", "%H:%M").to_s("%H:%M").should eq("01:00")
    parse_time("11:00", "%H:%M").to_s("%H:%M").should eq("11:00")
    parse_time("12:00", "%H:%M").to_s("%H:%M").should eq("12:00")
    parse_time("12:01", "%H:%M").to_s("%H:%M").should eq("12:01")
    parse_time("13:00", "%H:%M").to_s("%H:%M").should eq("13:00")
    parse_time("23:00", "%H:%M").to_s("%H:%M").should eq("23:00")
    parse_time("24:00", "%H:%M").to_s("%H:%M").should eq("00:00")
    parse_time("2020-05-21 24:00", "%F %H:%M").should eq(Time.utc(2020, 5, 22, 0, 0))

    parse_time(" 0:00", "%k:%M").to_s("%H:%M").should eq("00:00")
    parse_time(" 0:01", "%k:%M").to_s("%H:%M").should eq("00:01")
    parse_time(" 1:00", "%k:%M").to_s("%H:%M").should eq("01:00")
    parse_time("11:00", "%k:%M").to_s("%H:%M").should eq("11:00")
    parse_time("12:00", "%k:%M").to_s("%H:%M").should eq("12:00")
    parse_time("12:01", "%k:%M").to_s("%H:%M").should eq("12:01")
    parse_time("13:00", "%k:%M").to_s("%H:%M").should eq("13:00")
    parse_time("23:00", "%k:%M").to_s("%H:%M").should eq("23:00")
    parse_time("24:00", "%k:%M").to_s("%H:%M").should eq("00:00")
    parse_time("2020-05-21 24:00", "%F %k:%M").should eq(Time.utc(2020, 5, 22, 0, 0))
  end

  it "parses 24h clock with am/pm" do
    parse_time("00:00 AM", "%H:%M %P").to_s("%H:%M").should eq("00:00")
    parse_time("00:01 AM", "%H:%M %P").to_s("%H:%M").should eq("00:01")
    parse_time("01:00 AM", "%H:%M %P").to_s("%H:%M").should eq("01:00")
    parse_time("11:00 AM", "%H:%M %P").to_s("%H:%M").should eq("11:00")
    parse_time("12:00 AM", "%H:%M %P").to_s("%H:%M").should eq("12:00")
    parse_time("12:01 AM", "%H:%M %P").to_s("%H:%M").should eq("12:01")
    parse_time("13:00 AM", "%H:%M %P").to_s("%H:%M").should eq("13:00")
    parse_time("23:00 AM", "%H:%M %P").to_s("%H:%M").should eq("23:00")
    parse_time("24:00 AM", "%H:%M %P").to_s("%H:%M").should eq("00:00")

    parse_time(" 0:00 AM", "%k:%M %P").to_s("%H:%M").should eq("00:00")
    parse_time(" 0:01 AM", "%k:%M %P").to_s("%H:%M").should eq("00:01")
    parse_time(" 1:00 AM", "%k:%M %P").to_s("%H:%M").should eq("01:00")
    parse_time("11:00 AM", "%k:%M %P").to_s("%H:%M").should eq("11:00")
    parse_time("12:00 AM", "%k:%M %P").to_s("%H:%M").should eq("12:00")
    parse_time("12:01 AM", "%k:%M %P").to_s("%H:%M").should eq("12:01")
    parse_time("13:00 AM", "%k:%M %P").to_s("%H:%M").should eq("13:00")
    parse_time("23:00 AM", "%k:%M %P").to_s("%H:%M").should eq("23:00")
    parse_time("24:00 AM", "%k:%M %P").to_s("%H:%M").should eq("00:00")

    parse_time("00:00 PM", "%H:%M %P").to_s("%H:%M").should eq("00:00")
    parse_time("00:01 PM", "%H:%M %P").to_s("%H:%M").should eq("00:01")
    parse_time("01:00 PM", "%H:%M %P").to_s("%H:%M").should eq("01:00")
    parse_time("11:00 PM", "%H:%M %P").to_s("%H:%M").should eq("11:00")
    parse_time("12:00 PM", "%H:%M %P").to_s("%H:%M").should eq("12:00")
    parse_time("12:01 PM", "%H:%M %P").to_s("%H:%M").should eq("12:01")
    parse_time("13:00 PM", "%H:%M %P").to_s("%H:%M").should eq("13:00")
    parse_time("23:00 PM", "%H:%M %P").to_s("%H:%M").should eq("23:00")
    parse_time("24:00 PM", "%H:%M %P").to_s("%H:%M").should eq("00:00")

    parse_time(" 0:00 PM", "%k:%M %P").to_s("%H:%M").should eq("00:00")
    parse_time(" 0:01 PM", "%k:%M %P").to_s("%H:%M").should eq("00:01")
    parse_time(" 1:00 PM", "%k:%M %P").to_s("%H:%M").should eq("01:00")
    parse_time("11:00 PM", "%k:%M %P").to_s("%H:%M").should eq("11:00")
    parse_time("12:00 PM", "%k:%M %P").to_s("%H:%M").should eq("12:00")
    parse_time("12:01 PM", "%k:%M %P").to_s("%H:%M").should eq("12:01")
    parse_time("13:00 PM", "%k:%M %P").to_s("%H:%M").should eq("13:00")
    parse_time("23:00 PM", "%k:%M %P").to_s("%H:%M").should eq("23:00")
    parse_time("24:00 PM", "%k:%M %P").to_s("%H:%M").should eq("00:00")
  end

  it "parses timezone" do
    patterns = {"%z", "%:z", "%::z"}

    {"+0000", "+00:00", "+00:00:00"}.zip(patterns) do |string, pattern|
      time = Time.parse!(string, pattern)
      time.offset.should eq 0
      time.utc?.should be_false
      time.location.fixed?.should be_true
    end

    {"-0000", "-00:00", "-00:00:00"}.zip(patterns) do |string, pattern|
      time = Time.parse!(string, pattern)
      time.offset.should eq 0
      time.utc?.should be_false
      time.location.fixed?.should be_true
    end

    {"-0200", "-02:00", "-02:00:00"}.zip(patterns) do |string, pattern|
      time = Time.parse!(string, pattern)
      time.offset.should eq -2 * 3600
      time.utc?.should be_false
      time.location.fixed?.should be_true
    end

    {"Z", "Z", "Z"}.zip(patterns) do |string, pattern|
      time = Time.parse!(string, pattern)
      time.offset.should eq 0
      time.utc?.should be_true
      time.location.fixed?.should be_true
    end

    {"UTC", "UTC", "UTC"}.zip(patterns) do |string, pattern|
      time = Time.parse!(string, pattern)
      time.offset.should eq 0
      time.utc?.should be_true
      time.location.fixed?.should be_true
    end

    time = Time.parse!("+04:12:39", "%::z")
    time.offset.should eq 4 * 3600 + 12 * 60 + 39
    time.utc?.should be_false
    time.location.fixed?.should be_true

    time = Time.parse!("-04:12:39", "%::z")
    time.offset.should eq -1 * (4 * 3600 + 12 * 60 + 39)
    time.utc?.should be_false
    time.location.fixed?.should be_true
  end

  it "parses zone name" do
    ["%^Z", "%Z"].each do |pattern|
      time = Time.parse!("UTC", pattern)
      time.offset.should eq 0
      time.utc?.should be_true
      time.location.fixed?.should be_true

      time = Time.parse!("-00:00", pattern)
      time.offset.should eq 0
      time.utc?.should be_false
      time.location.fixed?.should be_true

      time = Time.parse!("+00:00", pattern)
      time.offset.should eq 0
      time.utc?.should be_false
      time.location.fixed?.should be_true

      time = Time.parse!("+00:00:00", pattern)
      time.offset.should eq 0
      time.utc?.should be_false
      time.location.fixed?.should be_true

      with_zoneinfo do
        time = Time.parse!("CET", pattern)
        time.offset.should eq 3600
        time.utc?.should be_false
        time.location.fixed?.should be_false

        time = Time.parse!("Europe/Berlin", pattern)
        time.location.should eq Time::Location.load("Europe/Berlin")

        expect_raises(Time::Location::InvalidLocationNameError) do
          Time.parse!("INVALID", pattern)
        end
      end
    end
  end

  it "raises when time zone missing" do
    expect_raises(Time::Format::Error, "Invalid timezone") do
      Time.parse!("", "%z")
    end
    expect_raises(Time::Format::Error, "Invalid timezone") do
      Time.parse!("123456+01:00", "%3N%z")
    end
  end

  it "parses day of year" do
    parse_time("2006-001", "%Y-%j").should eq(Time.utc(2006, 1, 1))
    parse_time("2006-032", "%Y-%j").should eq(Time.utc(2006, 2, 1))
    parse_time("2006-059", "%Y-%j").should eq(Time.utc(2006, 2, 28))
    parse_time("2006-060", "%Y-%j").should eq(Time.utc(2006, 3, 1))
    parse_time("2006-200", "%Y-%j").should eq(Time.utc(2006, 7, 19))
    parse_time("2006-365", "%Y-%j").should eq(Time.utc(2006, 12, 31))

    parse_time("2004-001", "%Y-%j").should eq(Time.utc(2004, 1, 1))
    parse_time("2004-032", "%Y-%j").should eq(Time.utc(2004, 2, 1))
    parse_time("2004-059", "%Y-%j").should eq(Time.utc(2004, 2, 28))
    parse_time("2004-060", "%Y-%j").should eq(Time.utc(2004, 2, 29))
    parse_time("2004-061", "%Y-%j").should eq(Time.utc(2004, 3, 1))
    parse_time("2004-200", "%Y-%j").should eq(Time.utc(2004, 7, 18))
    parse_time("2004-365", "%Y-%j").should eq(Time.utc(2004, 12, 30))
    parse_time("2004-366", "%Y-%j").should eq(Time.utc(2004, 12, 31))

    expect_raises(Time::Format::Error, "Invalid day of year") do
      parse_time("2006-000", "%Y-%j")
    end
    expect_raises(Time::Format::Error, "Invalid day of year") do
      parse_time("2004-000", "%Y-%j")
    end
    expect_raises(Time::Format::Error, "Invalid day of year") do
      parse_time("2006-366", "%Y-%j")
    end
    expect_raises(Time::Format::Error, "Invalid day of year") do
      parse_time("2004-367", "%Y-%j")
    end
  end

  # TODO %Z
  # TODO %G
  # TODO %g
  # TODO %V
  # TODO %U
  # TODO %W
  # TODO %s
  # TODO %n
  # TODO %t
  # TODO %%
  # TODO %v

  it do
    time = Time.parse!("2014-10-31 10:11:12 Z hi", "%F %T %z hi")
    time.utc?.should be_true
    time.to_utc.to_s.should eq("2014-10-31 10:11:12 UTC")
  end

  it do
    time = Time.parse!("2014-10-31 10:11:12 UTC hi", "%F %T %z hi")
    time.utc?.should be_true
    time.to_utc.to_s.should eq("2014-10-31 10:11:12 UTC")
  end

  it do
    time = Time.parse!("2014-10-31 10:11:12 -06:00 hi", "%F %T %z hi")
    time.utc?.should be_false
    time.location.fixed?.should be_true
    time.offset.should eq -6 * 3600
    time.to_utc.to_s.should eq("2014-10-31 16:11:12 UTC")
  end

  it do
    time = Time.parse!("2014-10-31 10:11:12 +05:00 hi", "%F %T %z hi")
    time.utc?.should be_false
    time.location.fixed?.should be_true
    time.offset.should eq 5 * 3600
    time.to_utc.to_s.should eq("2014-10-31 05:11:12 UTC")
  end

  it do
    time = Time.parse!("2014-10-31 10:11:12 -06:00:00 hi", "%F %T %z hi")
    time.utc?.should be_false
    time.location.fixed?.should be_true
    time.offset.should eq -6 * 3600
    time.to_utc.to_s.should eq("2014-10-31 16:11:12 UTC")
  end

  it do
    time = Time.parse!("2014-10-31 10:11:12 -060000 hi", "%F %T %z hi")
    time.utc?.should be_false
    time.location.fixed?.should be_true
    time.offset.should eq -6 * 3600
    time.to_utc.to_s.should eq("2014-10-31 16:11:12 UTC")
  end

  it "parses centiseconds" do
    time = Time.parse!("2016-09-09T17:03:28.45+01:00", "%FT%T.%L%z").to_utc
    time.to_s.should eq("2016-09-09 16:03:28 UTC")
    time.millisecond.should eq(450)
    time.nanosecond.should eq(450000000)
  end

  it "parses milliseconds with %L" do
    time = Time.parse!("2016-09-09T17:03:28.456+01:00", "%FT%T.%L%z").to_utc
    time.to_s.should eq("2016-09-09 16:03:28 UTC")
    time.millisecond.should eq(456)
    time.nanosecond.should eq(456000000)
  end

  it "parses milliseconds with %3N" do
    time = Time.parse!("2016-09-09T17:03:28.456+01:00", "%FT%T.%3N%z").to_utc
    time.to_s.should eq("2016-09-09 16:03:28 UTC")
    time.millisecond.should eq(456)
    time.nanosecond.should eq(456000000)
  end

  it "parses microseconds with %6N" do
    time = Time.parse!("2016-09-09T17:03:28.456789+01:00", "%FT%T.%6N%z").to_utc
    time.to_s.should eq("2016-09-09 16:03:28 UTC")
    time.millisecond.should eq(456)
    time.nanosecond.should eq(456789000)
  end

  it "parses nanoseconds" do
    time = Time.parse!("2016-09-09T17:03:28.456789123+01:00", "%FT%T.%N%z").to_utc
    time.to_s.should eq("2016-09-09 16:03:28 UTC")
    time.nanosecond.should eq(456789123)
  end

  it "parses nanoseconds with %9N" do
    time = Time.parse!("2016-09-09T17:03:28.456789123+01:00", "%FT%T.%9N%z").to_utc
    time.to_s.should eq("2016-09-09 16:03:28 UTC")
    time.nanosecond.should eq(456789123)
  end

  it "parses discarding additional decimals" do
    time = Time.parse("2016-09-09T17:03:28.456789123999", "%FT%T.%3N", Time::Location::UTC)
    time.nanosecond.should eq(456000000)

    time = Time.parse("2016-09-09T17:03:28.456789123999", "%FT%T.%6N", Time::Location::UTC)
    time.nanosecond.should eq(456789000)

    time = Time.parse("2016-09-09T17:03:28.456789123990", "%FT%T.%9N", Time::Location::UTC)
    time.nanosecond.should eq(456789123)

    time = Time.parse!("2016-09-09T17:03:28.456789123999999+01:00", "%FT%T.%N%z")
    time.to_s.should eq("2016-09-09 17:03:28 +01:00")
    time.nanosecond.should eq(456789123)

    time = Time.parse("4567892016-09-09T17:03:28", "%6N%FT%T", Time::Location::UTC)
    time.year.should eq(2016)
    time.nanosecond.should eq(456789000)
  end

  it "parses if some decimals are missing" do
    time = Time.parse!("2016-09-09T17:03:28.45+01:00", "%FT%T.%3N%z").to_utc
    time.nanosecond.should eq(450000000)

    time = Time.parse!("2016-09-09T17:03:28.45678+01:00", "%FT%T.%6N%z").to_utc
    time.nanosecond.should eq(456780000)

    time = Time.parse!("2016-09-09T17:03:28.4567891+01:00", "%FT%T.%9N%z").to_utc
    time.nanosecond.should eq(456789100)
  end

  it "parses the correct amount of digits (#853)" do
    time = Time.parse("20150624", "%Y%m%d", Time::Location::UTC)
    time.year.should eq(2015)
    time.month.should eq(6)
    time.day.should eq(24)
  end

  it "parses month blank padded" do
    time = Time.parse("2015 624", "%Y%_m%d", Time::Location::UTC)
    time.year.should eq(2015)
    time.month.should eq(6)
    time.day.should eq(24)
  end

  it "parses day of month blank padded" do
    time = Time.parse("201506 4", "%Y%m%e", Time::Location::UTC)
    time.year.should eq(2015)
    time.month.should eq(6)
    time.day.should eq(4)
  end

  it "parses hour 24 blank padded" do
    time = Time.parse(" 31112", "%k%M%S", Time::Location::UTC)
    time.hour.should eq(3)
    time.minute.should eq(11)
    time.second.should eq(12)
  end

  it "parses hour 12 blank padded" do
    time = Time.parse(" 31112", "%l%M%S", Time::Location::UTC)
    time.hour.should eq(3)
    time.minute.should eq(11)
    time.second.should eq(12)
  end

  it "can parse in location" do
    with_zoneinfo do
      time = Time.parse("2014-10-31 11:12:13", "%F %T", Time::Location::UTC)
      time.utc?.should be_true

      location = Time::Location.load("Europe/Berlin")
      time = Time.parse("2016-11-24 14:32:02", "%F %T", location)
      time.location.should eq location

      time = Time.parse("2016-11-24 14:32:02 +01:00", "%F %T %:z", location)
      time.location.should eq Time::Location.fixed(3600)
    end
  end
end
