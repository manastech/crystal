require "../spec_helper"
require "../../support/time"
require "spec/helpers/iterate"

CALENDAR_WEEK_TEST_DATA = [
  { {1981, 1, 1}, {1981, 1, 4} },
  { {1982, 1, 1}, {1981, 53, 5} },
  { {1983, 1, 1}, {1982, 52, 6} },
  { {1984, 1, 1}, {1983, 52, 7} },
  { {1985, 1, 1}, {1985, 1, 2} },
  { {1985, 4, 12}, {1985, 15, 5} },
  { {1986, 1, 1}, {1986, 1, 3} },
  { {1987, 1, 1}, {1987, 1, 4} },
  { {1988, 1, 1}, {1987, 53, 5} },
  { {1989, 1, 1}, {1988, 52, 7} },
  { {1990, 1, 1}, {1990, 1, 1} },
  { {1991, 1, 1}, {1991, 1, 2} },
  { {1992, 1, 1}, {1992, 1, 3} },
  { {1993, 1, 1}, {1992, 53, 5} },
  { {1994, 1, 1}, {1993, 52, 6} },
  { {1995, 1, 2}, {1995, 1, 1} },
  { {1996, 1, 1}, {1996, 1, 1} },
  { {1996, 1, 7}, {1996, 1, 7} },
  { {1996, 1, 8}, {1996, 2, 1} },
  { {1997, 1, 1}, {1997, 1, 3} },
  { {1998, 1, 1}, {1998, 1, 4} },
  { {1999, 1, 1}, {1998, 53, 5} },
  { {2000, 1, 1}, {1999, 52, 6} },
  { {2001, 1, 1}, {2001, 1, 1} },
  { {2002, 1, 1}, {2002, 1, 2} },
  { {2003, 1, 1}, {2003, 1, 3} },
  { {2004, 1, 1}, {2004, 1, 4} },
  { {2005, 1, 1}, {2004, 53, 6} },
  { {2006, 1, 1}, {2005, 52, 7} },
  { {2007, 1, 1}, {2007, 1, 1} },
  { {2008, 1, 1}, {2008, 1, 2} },
  { {2009, 1, 1}, {2009, 1, 4} },
  { {2010, 1, 1}, {2009, 53, 5} },
  { {2010, 1, 1}, {2009, 53, 5} },
  { {2011, 1, 1}, {2010, 52, 6} },
  { {2011, 1, 2}, {2010, 52, 7} },
  { {2011, 1, 3}, {2011, 1, 1} },
  { {2011, 1, 4}, {2011, 1, 2} },
  { {2011, 1, 5}, {2011, 1, 3} },
  { {2011, 1, 6}, {2011, 1, 4} },
  { {2011, 1, 7}, {2011, 1, 5} },
  { {2011, 1, 8}, {2011, 1, 6} },
  { {2011, 1, 9}, {2011, 1, 7} },
  { {2011, 1, 10}, {2011, 2, 1} },
  { {2011, 1, 11}, {2011, 2, 2} },
  { {2011, 6, 12}, {2011, 23, 7} },
  { {2011, 6, 13}, {2011, 24, 1} },
  { {2011, 12, 25}, {2011, 51, 7} },
  { {2011, 12, 26}, {2011, 52, 1} },
  { {2011, 12, 27}, {2011, 52, 2} },
  { {2011, 12, 28}, {2011, 52, 3} },
  { {2011, 12, 29}, {2011, 52, 4} },
  { {2011, 12, 30}, {2011, 52, 5} },
  { {2011, 12, 31}, {2011, 52, 6} },
  { {1995, 1, 1}, {1994, 52, 7} },
  { {2012, 1, 1}, {2011, 52, 7} },
  { {2012, 1, 2}, {2012, 1, 1} },
  { {2012, 1, 8}, {2012, 1, 7} },
  { {2012, 1, 9}, {2012, 2, 1} },
  { {2012, 12, 23}, {2012, 51, 7} },
  { {2012, 12, 24}, {2012, 52, 1} },
  { {2012, 12, 30}, {2012, 52, 7} },
  { {2012, 12, 31}, {2013, 1, 1} },
  { {2013, 1, 1}, {2013, 1, 2} },
  { {2013, 1, 6}, {2013, 1, 7} },
  { {2013, 1, 7}, {2013, 2, 1} },
  { {2013, 12, 22}, {2013, 51, 7} },
  { {2013, 12, 23}, {2013, 52, 1} },
  { {2013, 12, 29}, {2013, 52, 7} },
  { {2013, 12, 30}, {2014, 1, 1} },
  { {2014, 1, 1}, {2014, 1, 3} },
  { {2014, 1, 5}, {2014, 1, 7} },
  { {2014, 1, 6}, {2014, 2, 1} },
  { {2015, 1, 1}, {2015, 1, 4} },
  { {2016, 1, 1}, {2015, 53, 5} },
  { {2017, 1, 1}, {2016, 52, 7} },
  { {2018, 1, 1}, {2018, 1, 1} },
  { {2019, 1, 1}, {2019, 1, 2} },
  { {2020, 1, 1}, {2020, 1, 3} },
  { {2021, 1, 1}, {2020, 53, 5} },
  { {2022, 1, 1}, {2021, 52, 6} },
  { {2023, 1, 1}, {2022, 52, 7} },
  { {2024, 1, 1}, {2024, 1, 1} },
  { {2025, 1, 1}, {2025, 1, 3} },
  { {2026, 1, 1}, {2026, 1, 4} },
  { {2027, 1, 1}, {2026, 53, 5} },
  { {2028, 1, 1}, {2027, 52, 6} },
  { {2029, 1, 1}, {2029, 1, 1} },
  { {2030, 1, 1}, {2030, 1, 2} },
  { {2031, 1, 1}, {2031, 1, 3} },
  { {2032, 1, 1}, {2032, 1, 4} },
  { {2033, 1, 1}, {2032, 53, 6} },
  { {2034, 1, 1}, {2033, 52, 7} },
  { {2035, 1, 1}, {2035, 1, 1} },
  { {2036, 1, 1}, {2036, 1, 2} },
  { {2037, 1, 1}, {2037, 1, 4} },
  { {2038, 1, 1}, {2037, 53, 5} },
  { {2039, 1, 1}, {2038, 52, 6} },
  { {2040, 1, 1}, {2039, 52, 7} },
]

describe Time do
  describe ".local" do
    it "initializes" do
      t1 = Time.local 2002, 2, 25
      t1.date.should eq({2002, 2, 25})
      t1.year.should eq(2002)
      t1.month.should eq(2)
      t1.day.should eq(25)
      t1.hour.should eq(0)
      t1.minute.should eq(0)
      t1.second.should eq(0)
      t1.local?.should be_true

      t2 = Time.local 2002, 2, 25, 15, 25, 13, nanosecond: 8
      t2.date.should eq({2002, 2, 25})
      t2.year.should eq(2002)
      t2.month.should eq(2)
      t2.day.should eq(25)
      t2.hour.should eq(15)
      t2.minute.should eq(25)
      t2.second.should eq(13)
      t2.nanosecond.should eq(8)
      t2.local?.should be_true
    end

    it "initializes max value" do
      time = Time.local(9999, 12, 31, 23, 59, 59, nanosecond: 999_999_999)
      time.year.should eq(9999)
      time.month.should eq(12)
      time.day.should eq(31)
      time.hour.should eq(23)
      time.minute.should eq(59)
      time.second.should eq(59)
      time.nanosecond.should eq(999_999_999)
    end

    it "fails with negative nanosecond" do
      expect_raises ArgumentError, "Invalid time" do
        Time.local(9999, 12, 31, 23, 59, 59, nanosecond: -1)
      end
    end

    it "fails with too big nanoseconds" do
      expect_raises ArgumentError, "Invalid time" do
        Time.local(9999, 12, 31, 23, 59, 59, nanosecond: 1_000_000_000)
      end
    end

    it "checks boundary at time min" do
      {-5 * 3600, -1, 0, 1, 5 * 3600}.each do |offset|
        seconds = -offset.to_i64
        location = Time::Location.fixed(offset)
        Time.new(seconds: seconds + 1, nanoseconds: 0, location: location)
        Time.new(seconds: seconds, nanoseconds: 0, location: location)
        expect_raises ArgumentError, "Invalid time" do
          Time.new(seconds: seconds - 1, nanoseconds: 0, location: location)
        end
      end
    end

    it "checks boundary at time max" do
      {-5 * 3600, -1, 0, 1, 5 * 3600}.each do |offset|
        seconds = Time::MAX_SECONDS - offset.to_i64
        location = Time::Location.fixed(offset)
        Time.new(seconds: seconds - 1, nanoseconds: 0, location: location)
        Time.new(seconds: seconds, nanoseconds: 0, location: location)
        expect_raises ArgumentError, "Invalid time" do
          Time.new(seconds: seconds + 1, nanoseconds: 0, location: location)
        end
      end
    end

    it "accepts midnight 24:00" do
      Time.utc(2020, 5, 21, 24, 0, 0).should eq Time.utc(2020, 5, 22, 0, 0, 0)

      expect_raises ArgumentError, "Invalid time" do
        Time.utc(2020, 5, 21, 24, 0, 0, nanosecond: 1)
      end

      expect_raises ArgumentError, "Invalid time" do
        Time.utc(2020, 5, 21, 24, 0, 1)
      end

      expect_raises ArgumentError, "Invalid time" do
        Time.utc(2020, 5, 21, 24, 1, 0)
      end
    end
  end

  it "UNIX_EPOCH" do
    Time::UNIX_EPOCH.should eq(Time.utc(1970, 1, 1))
  end

  it ".unix" do
    seconds = 1439404155
    time = Time.unix(seconds)
    time.should eq(Time.utc(2015, 8, 12, 18, 29, 15))
    time.to_unix.should eq(seconds)
    time.utc?.should be_true
  end

  it ".unix_ms" do
    milliseconds = 1439404155000
    time = Time.unix_ms(milliseconds)
    time.should eq(Time.utc(2015, 8, 12, 18, 29, 15))
    time.to_unix_ms.should eq(milliseconds)
    time.utc?.should be_true
  end

  describe ".unix_ns" do
    it "supports Int64 values" do
      nanoseconds = 1439404155001457425i64
      time = Time.unix_ns(nanoseconds)
      time.should eq(Time.utc(2015, 8, 12, 18, 29, 15, nanosecond: 1457425))
      time.to_unix_ns.should eq(nanoseconds)
      time.utc?.should be_true
    end

    it "supports maximum valid time" do
      nanoseconds = Int128.new("253402300799999999999")
      time = Time.unix_ns(nanoseconds)
      time.should eq(Time.utc(9999, 12, 31, 23, 59, 59, nanosecond: 999999999))
      time.to_unix_ns.should eq(nanoseconds)
      time.utc?.should be_true
    end

    it "supports minimum valid time" do
      nanoseconds = Int128.new("-62135596800000000000")
      time = Time.unix_ns(nanoseconds)
      time.should eq(Time.utc(1, 1, 1, 0, 0, 0, nanosecond: 0))
      time.to_unix_ns.should eq(nanoseconds)
      time.utc?.should be_true
    end
  end

  describe ".local without arguments" do
    it "current time is similar in different locations" do
      (Time.local - Time.utc).should be_close(0.seconds, 1.second)
      (Time.local - Time.local(Time::Location.fixed(1234))).should be_close(0.seconds, 1.second)
    end
  end

  describe ".monotonic" do
    it "returns always increasing monotonic clock" do
      clock = Time.monotonic
      Time.monotonic.should be >= clock
    end
  end

  describe ".measure" do
    it "measures elapsed time" do
      # NOTE: On some systems, the sleep may not always wait for 1ms and the fiber
      #       be resumed early. We thus merely test that the method returns a
      #       positive time span.
      elapsed = Time.measure { sleep 1.millisecond }
      elapsed.should be >= 0.seconds
    end
  end

  it "#clone" do
    time = Time.local
    time.clone.should eq(time)
  end

  describe "#shift" do
    it "adds hours, minutes, seconds" do
      t1 = Time.utc(2002, 2, 25, 15, 25, 13)
      t2 = t1 + Time::Span.new(hours: 3, minutes: 54, seconds: 1)

      t2.should eq Time.utc(2002, 2, 25, 19, 19, 14)
    end

    it "raises out of range min" do
      t1 = Time.utc(9980, 2, 25, 15, 25, 13)

      expect_raises ArgumentError do
        t1 + Time::Span.new(nanoseconds: Int64::MAX)
      end
    end

    it "raises out of range max" do
      t1 = Time.utc(1, 2, 25, 15, 25, 13)

      expect_raises ArgumentError do
        t1 + Time::Span.new(nanoseconds: Int64::MIN)
      end
    end

    it "checks boundary at time min" do
      {5 * 3600, 1, 0, -1, -5 * 3600}.each do |offset|
        location = Time::Location.fixed(offset)

        time = Time.local(1, 1, 1, location: location)
        time.shift(0, 1).should eq Time.local(1, 1, 1, nanosecond: 1, location: location)
        time.shift(0, 0).should eq time
        expect_raises(ArgumentError) do
          time.shift(0, -1)
        end
      end
    end

    it "checks boundary at time max" do
      {5 * 3600, 1, 0, -1, -5 * 3600}.each do |offset|
        location = Time::Location.fixed(offset)

        time = Time.local(9999, 12, 31, 23, 59, 59, nanosecond: 999_999_999, location: location)
        time.shift(0, -1).should eq Time.local(9999, 12, 31, 23, 59, 59, nanosecond: 999_999_998, location: location)
        time.shift(0, 0).should eq time
        expect_raises(ArgumentError) do
          time.shift(0, 1)
        end
      end
    end

    it "adds zero span" do
      time = Time.utc
      time.shift(0, 0).should eq time
    end

    describe "irregular calendaric unit ratios" do
      it "shifts by a week if one day is left out" do
        # The week from 2011-12-25 to 2012-01-01 for example lasted only 6 days in Samoa,
        # because it skipped 2011-12-28 due to changing time zone from -11:00 to +13:00.
        with_zoneinfo do
          samoa = Time::Location.load("Pacific/Apia")
          start = Time.local(2011, 12, 25, 0, 0, 0, location: samoa)

          plus_one_week = start.shift days: 7
          plus_one_week.should eq start + 6.days

          plus_one_year = start.shift years: 1
          plus_one_year.should eq start + 365.days # 2012 is a leap year so it should've been 366 days, but 2011-12-28 was skipped
        end
      end

      it "shifts by conceptual hour even if elapsed time is less" do
        # Venezuela switched from -4:30 to -4:00 on 2016-05-01, the hour between 2:00 and 3:00 lasted only 30 minutes
        with_zoneinfo do
          venezuela = Time::Location.load("America/Caracas")
          start = Time.local(2016, 5, 1, 2, 0, 0, location: venezuela)
          plus_one_hour = start.shift hours: 1
          plus_one_hour.should eq start + 30.minutes
        end
      end
    end

    describe "adds days" do
      it "simple" do
        time = Time.utc(2002, 2, 25, 15, 25, 13)
        time = time + 3.days

        time.should eq Time.utc(2002, 2, 28, 15, 25, 13)

        time = time + 1.9.days
        time.should eq Time.utc(2002, 3, 2, 13, 1, 13)

        time = time + 0.2.days
        time.should eq Time.utc(2002, 3, 2, 17, 49, 13)
      end

      it "over dst" do
        with_zoneinfo do
          location = Time::Location.load("Europe/Berlin")
          reference = Time.local(2017, 10, 28, 13, 37, location: location)
          next_day = reference.shift days: 1

          next_day.should eq reference + 25.hours
        end
      end

      it "out of range max" do
        time = Time.utc(2002, 2, 25, 15, 25, 13)
        expect_raises ArgumentError do
          time + 10000000.days
        end
      end

      it "out of range max (shift days)" do
        time = Time.utc(2002, 2, 25, 15, 25, 13)
        expect_raises OverflowError do
          time.shift days: 10000000
        end
      end

      it "out of range min" do
        time = Time.utc(2002, 2, 25, 15, 25, 13)
        expect_raises ArgumentError do
          time - 10000000.days
        end
      end

      it "out of range min (shift days)" do
        time = Time.utc(2002, 2, 25, 15, 25, 13)
        expect_raises OverflowError do
          time.shift days: -10000000
        end
      end
    end

    it "adds months" do
      t = Time.utc 2014, 10, 30, 21, 18, 13

      t2 = t.shift months: 1
      t2.should eq Time.utc(2014, 11, 30, 21, 18, 13)

      t2 = t.shift months: -1
      t2.should eq Time.utc(2014, 9, 30, 21, 18, 13)

      t = Time.utc 2014, 10, 31, 21, 18, 13
      t2 = t.shift months: 1
      t2.should eq Time.utc(2014, 11, 30, 21, 18, 13)

      t = Time.utc 2014, 10, 31, 21, 18, 13
      t2 = t.shift months: -1
      t2.should eq Time.utc(2014, 9, 30, 21, 18, 13)

      t = Time.utc 2014, 10, 31, 21, 18, 13
      t2 = t.shift months: 6
      t2.should eq Time.utc(2015, 4, 30, 21, 18, 13)
    end

    it "adds years" do
      t = Time.utc 2014, 10, 30, 21, 18, 13
      t2 = t.shift years: 1
      t2.should eq Time.utc(2015, 10, 30, 21, 18, 13)

      t = Time.utc 2014, 10, 30, 21, 18, 13
      t2 = t.shift years: -2
      t2.should eq Time.utc(2012, 10, 30, 21, 18, 13)
    end

    it "adds hours" do
      time = Time.utc(2002, 2, 25, 15, 25, 13)

      time = time + 10.hours
      time.should eq Time.utc(2002, 2, 26, 1, 25, 13)

      time = time - 3.7.hours
      time.should eq Time.utc(2002, 2, 25, 21, 43, 13)

      time = time + 3.732.hours
      time.should eq Time.utc(2002, 2, 26, 1, 27, 8, nanosecond: 200_000_000)
    end

    it "adds nanoseconds" do
      t1 = Time.utc(2002, 2, 25, 15, 25, 13)
      t1 = t1.shift nanoseconds: 10_000_000_000_000_000

      t1.should eq Time.utc(2002, 6, 21, 9, 11, 53)

      t1 = t1.shift nanoseconds: -190_000_000_000_000_000
      t1.should eq Time.utc(1996, 6, 13, 7, 25, 13)

      t1 = t1.shift nanoseconds: 15_623_000
      t1.should eq Time.utc(1996, 6, 13, 7, 25, 13, nanosecond: 15_623_000)
    end

    it "preserves location when adding" do
      time = Time.utc
      time.utc?.should be_true

      (time + 5.minutes).utc?.should be_true

      location = Time::Location.fixed(1234)
      time = Time.local(location)
      (time + 5.minutes).location.should eq location
    end

    it "covers date boundaries with zone offset (#8741)" do
      zone = Time::Location.fixed(7 * 3600)

      Time.local(2020, 2, 5, 0, 13, location: zone).shift(months: 3).should eq Time.local(2020, 5, 5, 0, 13, location: zone)
    end

    it "covers date boundaries with zone offset (#10869)" do
      location = Time::Location.fixed(2 * 3600)
      Time.local(2021, 7, 1, location: location).shift(months: 1).should eq Time.local(2021, 8, 1, location: location)
    end
  end

  it "#time_of_day" do
    t = Time.utc 2014, 10, 30, 21, 18, 13
    t.time_of_day.should eq(Time::Span.new(hours: 21, minutes: 18, seconds: 13))
  end

  describe "#day_of_week" do
    it "gets day of week" do
      t = Time.utc 2014, 10, 30, 21, 18, 13
      t.day_of_week.should eq(Time::DayOfWeek::Thursday)
    end

    CALENDAR_WEEK_TEST_DATA.each do |date, week_date|
      it "#{date.join('-')} is #{week_date[2]}" do
        Time.utc(*date).day_of_week.should eq Time::DayOfWeek.from_value(week_date[2])
      end
    end
  end

  it "answers day name predicates" do
    7.times do |i|
      time = Time.utc(2015, 2, 15 + i)
      time.sunday?.should eq(i == 0)
      time.monday?.should eq(i == 1)
      time.tuesday?.should eq(i == 2)
      time.wednesday?.should eq(i == 3)
      time.thursday?.should eq(i == 4)
      time.friday?.should eq(i == 5)
      time.saturday?.should eq(i == 6)
    end
  end

  describe "#calendar_week" do
    CALENDAR_WEEK_TEST_DATA.each do |date, week_date|
      it "#{date.join('-')} to #{week_date[0]}-#{week_date[1]}" do
        Time.utc(*date).calendar_week.should eq({week_date[0], week_date[1]})
      end
    end
  end

  it "#day_of_year" do
    t = Time.utc 2014, 10, 30, 21, 18, 13
    t.day_of_year.should eq(303)
  end

  describe "#<=>" do
    it "compares" do
      t1 = Time.utc 2014, 10, 30, 21, 18, 13
      t2 = Time.utc 2014, 10, 30, 21, 18, 14

      (t1 <=> t2).should eq(-1)
      (t1 == t2).should be_false
      (t1 < t2).should be_true
    end

    it "compares different locations" do
      time = Time.local(Time::Location.fixed(1234))
      (time.to_utc <=> time).should eq(0)
    end
  end

  describe "#step" do
    days = (1..24).map { |d| Time.utc(2020, 12, d) }.to_a
    it_iterates "advent", days, Time.utc(2020, 12, 1).step(to: Time.utc(2020, 12, 24), by: 1.day)
  end

  describe "#to_unix" do
    it "gets unix seconds" do
      t1 = Time.utc 2014, 10, 30, 21, 18, 13, nanosecond: 0
      t1.to_unix.should eq(1414703893)
      t1.to_unix_f.should be_close(1414703893, 1e-01)
    end

    it "gets unix seconds at GMT" do
      t1 = Time.local(Time::Location.fixed(1234))
      t1.to_unix.should eq(t1.to_utc.to_unix)
      t1.to_unix_f.should be_close(t1.to_utc.to_unix_f, 1e-01)
    end
  end

  it "#year" do
    Time.utc(2008, 12, 31).year.should eq 2008
    Time.utc(2000, 12, 31).year.should eq 2000
    Time.utc(1900, 12, 31).year.should eq 1900
    Time.utc(1800, 12, 31).year.should eq 1800
    Time.utc(1700, 12, 31).year.should eq 1700
    Time.utc(1600, 12, 31).year.should eq 1600
    Time.utc(400, 12, 31).year.should eq 400
    Time.utc(100, 12, 31).year.should eq 100
    Time.utc(4, 12, 31).year.should eq 4
    Time.utc(1, 1, 1).year.should eq 1
  end

  describe "#to_s" do
    it "prints string" do
      with_zoneinfo do
        time = Time.local(2017, 11, 25, 22, 6, 17, location: Time::Location::UTC)
        time.to_s.should eq "2017-11-25 22:06:17 UTC"

        time = Time.local(2017, 11, 25, 22, 6, 17, location: Time::Location.fixed(-7200))
        time.to_s.should eq "2017-11-25 22:06:17 -02:00"

        time = Time.local(2017, 11, 25, 22, 6, 17, location: Time::Location.fixed(-7259))
        time.to_s.should eq "2017-11-25 22:06:17 -02:00:59"

        location = Time::Location.load("Europe/Berlin")
        time = Time.local(2017, 11, 25, 22, 6, 17, location: location)
        time.to_s.should eq "2017-11-25 22:06:17 +01:00"
      end
    end

    it "prints date-time fields" do
      Time.utc(2014, 1, 30, 21, 18, 13).to_s.should eq("2014-01-30 21:18:13 UTC")
      Time.utc(2014, 10, 1, 21, 18, 13).to_s.should eq("2014-10-01 21:18:13 UTC")
      Time.utc(2014, 10, 30, 1, 18, 13).to_s.should eq("2014-10-30 01:18:13 UTC")
      Time.utc(2014, 10, 30, 21, 1, 13).to_s.should eq("2014-10-30 21:01:13 UTC")
      Time.utc(2014, 10, 30, 21, 18, 1).to_s.should eq("2014-10-30 21:18:01 UTC")
    end

    it "omits nanoseconds" do
      Time.utc(2014, 10, 30, 21, 18, 13).to_s.should eq("2014-10-30 21:18:13 UTC")
      Time.utc(2014, 10, 30, 21, 18, 13, nanosecond: 12345).to_s.should eq("2014-10-30 21:18:13 UTC")
    end

    it "prints offset for location" do
      with_zoneinfo do
        location = Time::Location.load("Europe/Berlin")
        Time.local(2014, 10, 30, 21, 18, 13, location: location).to_s.should eq("2014-10-30 21:18:13 +01:00")
        Time.local(2014, 10, 30, 21, 18, 13, nanosecond: 123_456, location: location).to_s.should eq("2014-10-30 21:18:13 +01:00")

        Time.local(2014, 10, 10, 21, 18, 13, location: location).to_s.should eq("2014-10-10 21:18:13 +02:00")
        Time.local(2014, 10, 10, 21, 18, 13, nanosecond: 123_456, location: location).to_s.should eq("2014-10-10 21:18:13 +02:00")
      end
    end

    it "prints offset for fixed location" do
      location = Time::Location.fixed(3601)
      Time.local(2014, 1, 2, 3, 4, 5, location: location).to_s.should eq "2014-01-02 03:04:05 +01:00:01"
      Time.local(2014, 1, 2, 3, 4, 5, nanosecond: 123_456_789, location: location).to_s.should eq "2014-01-02 03:04:05 +01:00:01"

      t = Time.local 2014, 10, 30, 21, 18, 13, location: Time::Location.fixed(-9000)
      t.to_s.should eq("2014-10-30 21:18:13 -02:30")
    end

    it "prints local time" do
      # Simulates loading non-fixed offset local time from /etc/localtime
      old_local = Time::Location.local
      begin
        location = Time::Location.new "Local", [Time::Location::Zone.new("STZ", 3600, false), Time::Location::Zone.new("DTZ", -3600, false)], [] of Time::Location::ZoneTransition
        Time::Location.local = location

        Time.local(2014, 10, 30, 21, 18, 13).to_s.should eq("2014-10-30 21:18:13 +01:00")
      ensure
        Time::Location.local = old_local
      end
    end
  end

  it "#inspect" do
    Time.utc(2014, 1, 2, 3, 4, 5).inspect.should eq "2014-01-02 03:04:05.0 UTC"
    Time.utc(2014, 1, 2, 3, 4, 5, nanosecond: 123_456_789).inspect.should eq "2014-01-02 03:04:05.123456789 UTC"

    with_zoneinfo do
      location = Time::Location.load("Europe/Berlin")
      Time.local(2014, 1, 2, 3, 4, 5, location: location).inspect.should eq "2014-01-02 03:04:05.0 +01:00 Europe/Berlin"
      Time.local(2014, 1, 2, 3, 4, 5, nanosecond: 123_456_789, location: location).inspect.should eq "2014-01-02 03:04:05.123456789 +01:00 Europe/Berlin"
    end

    location = Time::Location.fixed(3601)
    Time.local(2014, 1, 2, 3, 4, 5, location: location).inspect.should eq "2014-01-02 03:04:05.0 +01:00:01"
    Time.local(2014, 1, 2, 3, 4, 5, nanosecond: 123_456_789, location: location).inspect.should eq "2014-01-02 03:04:05.123456789 +01:00:01"
  end

  it "at methods" do
    t1 = Time.utc 2014, 11, 25, 10, 11, 12, nanosecond: 13
    t2 = Time.utc 2014, 6, 25, 10, 11, 12, nanosecond: 13

    t1.at_beginning_of_year.should eq Time.utc(2014, 1, 1)

    1.upto(3) do |i|
      Time.utc(2014, i, 10).at_beginning_of_quarter.should eq Time.utc(2014, 1, 1)
      Time.utc(2014, i, 10).at_end_of_quarter.should eq Time.utc(2014, 3, 31, 23, 59, 59, nanosecond: 999_999_999)
    end
    4.upto(6) do |i|
      Time.utc(2014, i, 10).at_beginning_of_quarter.should eq Time.utc(2014, 4, 1)
      Time.utc(2014, i, 10).at_end_of_quarter.should eq Time.utc(2014, 6, 30, 23, 59, 59, nanosecond: 999_999_999)
    end
    7.upto(9) do |i|
      Time.utc(2014, i, 10).at_beginning_of_quarter.should eq Time.utc(2014, 7, 1)
      Time.utc(2014, i, 10).at_end_of_quarter.should eq Time.utc(2014, 9, 30, 23, 59, 59, nanosecond: 999_999_999)
    end
    10.upto(12) do |i|
      Time.utc(2014, i, 10).at_beginning_of_quarter.should eq Time.utc(2014, 10, 1)
      Time.utc(2014, i, 10).at_end_of_quarter.should eq Time.utc(2014, 12, 31, 23, 59, 59, nanosecond: 999_999_999)
    end

    t1.at_beginning_of_quarter.should eq Time.utc(2014, 10, 1)
    t1.at_beginning_of_month.should eq Time.utc(2014, 11, 1)

    3.upto(9) do |i|
      Time.utc(2014, 11, i).at_beginning_of_week.should eq Time.utc(2014, 11, 3)
    end

    sunday_day_of_week = Time::DayOfWeek::Sunday
    Time.utc(2014, 11, 1).at_beginning_of_week(sunday_day_of_week).should eq Time.utc(2014, 10, 26)
    2.upto(8) do |i|
      Time.utc(2014, 11, i).at_beginning_of_week(sunday_day_of_week).should eq Time.utc(2014, 11, 2)
    end
    Time.utc(2014, 11, 9).at_beginning_of_week(sunday_day_of_week).should eq Time.utc(2014, 11, 9)

    Time.utc(2014, 11, 1).at_beginning_of_week(:sunday).should eq Time.utc(2014, 10, 26)
    2.upto(8) do |i|
      Time.utc(2014, 11, i).at_beginning_of_week(:sunday).should eq Time.utc(2014, 11, 2)
    end
    Time.utc(2014, 11, 9).at_beginning_of_week(:sunday).should eq Time.utc(2014, 11, 9)

    Time.utc(2014, 11, 10).at_beginning_of_week(Time::DayOfWeek::Sunday).should eq Time.utc(2014, 11, 9)
    Time.utc(2014, 11, 10).at_beginning_of_week(Time::DayOfWeek::Monday).should eq Time.utc(2014, 11, 10)
    Time.utc(2014, 11, 10).at_beginning_of_week(Time::DayOfWeek::Tuesday).should eq Time.utc(2014, 11, 4)
    Time.utc(2014, 11, 10).at_beginning_of_week(Time::DayOfWeek::Wednesday).should eq Time.utc(2014, 11, 5)
    Time.utc(2014, 11, 10).at_beginning_of_week(Time::DayOfWeek::Thursday).should eq Time.utc(2014, 11, 6)
    Time.utc(2014, 11, 10).at_beginning_of_week(Time::DayOfWeek::Friday).should eq Time.utc(2014, 11, 7)
    Time.utc(2014, 11, 10).at_beginning_of_week(Time::DayOfWeek::Saturday).should eq Time.utc(2014, 11, 8)

    at_beginning_of_week_default = Time.local.at_beginning_of_week
    at_beginning_of_week_default.hour.should eq 0
    at_beginning_of_week_default.minute.should eq 0
    at_beginning_of_week_default.second.should eq 0

    at_beginning_of_week_sunday = Time.local.at_beginning_of_week(:sunday)
    at_beginning_of_week_sunday.hour.should eq 0
    at_beginning_of_week_sunday.minute.should eq 0
    at_beginning_of_week_sunday.second.should eq 0

    t1.at_beginning_of_day.should eq Time.utc(2014, 11, 25)
    t1.at_beginning_of_hour.should eq Time.utc(2014, 11, 25, 10)
    t1.at_beginning_of_minute.should eq Time.utc(2014, 11, 25, 10, 11)
    t1.at_beginning_of_second.should eq Time.utc(2014, 11, 25, 10, 11, 12)

    t1.at_end_of_year.should eq Time.utc(2014, 12, 31, 23, 59, 59, nanosecond: 999_999_999)

    t1.at_end_of_quarter.should eq Time.utc(2014, 12, 31, 23, 59, 59, nanosecond: 999_999_999)
    t2.at_end_of_quarter.should eq Time.utc(2014, 6, 30, 23, 59, 59, nanosecond: 999_999_999)

    t1.at_end_of_month.should eq Time.utc(2014, 11, 30, 23, 59, 59, nanosecond: 999_999_999)
    t1.at_end_of_week.should eq Time.utc(2014, 11, 30, 23, 59, 59, nanosecond: 999_999_999)

    Time.utc(2014, 11, 2).at_end_of_week.should eq Time.utc(2014, 11, 2, 23, 59, 59, nanosecond: 999_999_999)
    3.upto(9) do |i|
      Time.utc(2014, 11, i).at_end_of_week.should eq Time.utc(2014, 11, 9, 23, 59, 59, nanosecond: 999_999_999)
    end

    t1.at_end_of_day.should eq Time.utc(2014, 11, 25, 23, 59, 59, nanosecond: 999_999_999)
    t1.at_end_of_hour.should eq Time.utc(2014, 11, 25, 10, 59, 59, nanosecond: 999_999_999)
    t1.at_end_of_minute.should eq Time.utc(2014, 11, 25, 10, 11, 59, nanosecond: 999_999_999)
    t1.at_end_of_second.should eq Time.utc(2014, 11, 25, 10, 11, 12, nanosecond: 999_999_999)

    t1.at_midday.should eq Time.utc(2014, 11, 25, 12)

    t1.at_beginning_of_semester.should eq Time.utc(2014, 7, 1)
    t2.at_beginning_of_semester.should eq Time.utc(2014, 1, 1)

    t1.at_end_of_semester.should eq Time.utc(2014, 12, 31, 23, 59, 59, nanosecond: 999_999_999)
    t2.at_end_of_semester.should eq Time.utc(2014, 6, 30, 23, 59, 59, nanosecond: 999_999_999)
  end

  it "does diff of utc vs local time" do
    local = Time.local(Time::Location.fixed(1234))
    utc = local.to_utc
    (utc - local).should eq(0.seconds)
    (local - utc).should eq(0.seconds)
  end

  describe "#in" do
    it "changes location" do
      location = Time::Location.fixed(3600)
      location2 = Time::Location.fixed(12345)
      time1 = Time.local(location)
      time1.location.should eq(location)

      time2 = time1.in(location2)
      time2.should eq(time1)
      time2.location.should eq(location2)
    end
  end

  describe "#to_local_in" do
    it "keeps wall clock" do
      location = Time::Location.fixed(3600)
      location2 = Time::Location.fixed(12345)
      time1 = Time.local(location)
      time1.location.should eq(location)

      time2 = time1.to_local_in(location2)
      time2.location.should eq(location2)
      time2.year.should eq time1.year
      time2.month.should eq time1.month
      time2.day.should eq time1.day
      time2.hour.should eq time1.hour
      time2.minute.should eq time1.minute
      time2.second.should eq time1.second
      time2.nanosecond.should eq time1.nanosecond
    end

    it "is the difference of offsets apart" do
      location = Time::Location.fixed(3600)
      location2 = Time::Location.fixed(12345)
      time1 = Time.local(location)
      time2 = time1.to_local_in(location2)

      (time2 - time1).should eq (time1.offset - time2.offset).seconds
    end
  end

  it "#to_s" do
    with_zoneinfo do
      time = Time.local(2017, 11, 25, 22, 6, 17, location: Time::Location::UTC)
      time.to_s.should eq "2017-11-25 22:06:17 UTC"

      time = Time.local(2017, 11, 25, 22, 6, 17, location: Time::Location.fixed(-7200))
      time.to_s.should eq "2017-11-25 22:06:17 -02:00"

      time = Time.local(2017, 11, 25, 22, 6, 17, location: Time::Location.fixed(-7259))
      time.to_s.should eq "2017-11-25 22:06:17 -02:00:59"

      location = Time::Location.load("Europe/Berlin")
      time = Time.local(2017, 11, 25, 22, 6, 17, location: location)
      time.to_s.should eq "2017-11-25 22:06:17 +01:00"
    end
  end

  describe ".days_in_month" do
    it "returns days for valid month and year" do
      Time.days_in_month(2016, 2).should eq(29)
      Time.days_in_month(1990, 4).should eq(30)
    end

    it "raises exception for invalid month" do
      expect_raises(ArgumentError, "Invalid month") do
        Time.days_in_month(2016, 13)
      end
    end

    it "raises exception for invalid year" do
      expect_raises(ArgumentError, "Invalid year") do
        Time.days_in_month(10000, 11)
      end
    end
  end

  it ".days_in_year" do
    Time.days_in_year(2005).should eq(365)
    Time.days_in_year(2004).should eq(366)
    Time.days_in_year(2000).should eq(366)
    Time.days_in_year(1990).should eq(365)
  end

  describe ".leap_year?" do
    it "knows that 400-year centuries are leap years" do
      {1600, 2000, 2400}.each do |year|
        Time.leap_year?(year).should be_true
      end
    end

    it "knows that 100-year centuries are normal years" do
      {1700, 1800, 1900, 2100, 2200, 2300}.each do |year|
        Time.leap_year?(year).should be_false
      end
    end

    it "knows that typical non-century leap years are divisible by 4" do
      {1968, 1972, 2004, 2020}.each do |year|
        Time.leap_year?(year).should be_true
      end
    end

    it "knows years *not* divisible by 4 are normal" do
      {1965, 1999, 2001, 2018, 2019, 2021, 2099, 2101}.each do |year|
        Time.leap_year?(year).should be_false
      end
    end
  end

  describe Time::DayOfWeek do
    it "#value" do
      Time::DayOfWeek::Monday.value.should eq 1
      Time::DayOfWeek::Tuesday.value.should eq 2
      Time::DayOfWeek::Wednesday.value.should eq 3
      Time::DayOfWeek::Thursday.value.should eq 4
      Time::DayOfWeek::Friday.value.should eq 5
      Time::DayOfWeek::Saturday.value.should eq 6
      Time::DayOfWeek::Sunday.value.should eq 7
    end

    it ".from_value" do
      Time::DayOfWeek.from_value(1).should eq Time::DayOfWeek::Monday
      Time::DayOfWeek.from_value(2).should eq Time::DayOfWeek::Tuesday
      Time::DayOfWeek.from_value(3).should eq Time::DayOfWeek::Wednesday
      Time::DayOfWeek.from_value(4).should eq Time::DayOfWeek::Thursday
      Time::DayOfWeek.from_value(5).should eq Time::DayOfWeek::Friday
      Time::DayOfWeek.from_value(6).should eq Time::DayOfWeek::Saturday
      Time::DayOfWeek.from_value(7).should eq Time::DayOfWeek::Sunday

      # Special case: Identify 0 as Sunday
      Time::DayOfWeek.from_value(0).should eq Time::DayOfWeek::Sunday

      expect_raises(Exception, "Unknown enum Time::DayOfWeek value: 8") do
        Time::DayOfWeek.from_value(8)
      end
    end

    it ".new does not identify 0 as Sunday" do
      Time::DayOfWeek.new(0).should_not eq Time::DayOfWeek::Sunday
    end
  end

  describe ".week_date" do
    describe "verify test data" do
      with_zoneinfo do
        location = Time::Location.load("Europe/Berlin")

        CALENDAR_WEEK_TEST_DATA.each do |date, week_date|
          it "W#{week_date.join('-')} eq #{date.join('-')}" do
            Time.week_date(*week_date, location: Time::Location::UTC).should eq(Time.utc(*date))
            Time.week_date(week_date[0], week_date[1], Time::DayOfWeek.from_value(week_date[2]), location: Time::Location::UTC).should eq(Time.utc(*date))
            Time.week_date(*week_date).should eq(Time.local(*date))
            Time.week_date(*week_date, location: location).should eq(Time.local(*date, location: location))
          end
        end
      end
    end

    it "accepts time arguments" do
      with_zoneinfo do
        location = Time::Location.load("Europe/Berlin")
        Time.week_date(*CALENDAR_WEEK_TEST_DATA[0][1], 11, 57, 32, nanosecond: 123_567, location: location).should eq(
          Time.local(*CALENDAR_WEEK_TEST_DATA[0][0], 11, 57, 32, nanosecond: 123_567, location: location))

        location = Time::Location.load("America/Buenos_Aires")
        Time.week_date(*CALENDAR_WEEK_TEST_DATA[0][1], 11, 57, 32, nanosecond: 123_567, location: location).should eq(
          Time.local(*CALENDAR_WEEK_TEST_DATA[0][0], 11, 57, 32, nanosecond: 123_567, location: location))
      end
    end
  end

  typeof(Time.local.year)
  typeof(1.minute.from_now.year)
  typeof(1.minute.ago.year)
  typeof(1.month.from_now.year)
  typeof(1.month.ago.year)
  typeof(Time.local.to_utc)
  typeof(Time.local.to_local)
end
