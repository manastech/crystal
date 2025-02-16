# `Time::Span` represents one period of time.
#
# A `Time::Span` initializes with the specified period.
# Different numbers of arguments generate a `Time::Span` in different length.
# Check all `#new` methods for details.
#
# ```
# Time::Span.new(nanoseconds: 10_000)                           # => 00:00:00.000010000
# Time::Span.new(hours: 10, minutes: 10, seconds: 10)           # => 10:10:10
# Time::Span.new(days: 10, hours: 10, minutes: 10, seconds: 10) # => 10.10:10:10
# ```
#
# Calculation between `Time` also returns a `Time::Span`.
#
# ```
# span = Time.utc(2015, 10, 10) - Time.utc(2015, 9, 10)
# span       # => 30.00:00:00
# span.class # => Time::Span
# ```
#
# Inspection:
#
# ```
# span = Time::Span.new(hours: 20, minutes: 10, seconds: 10)
# span.hours   # => 20
# span.minutes # => 10
# span.seconds # => 10
# ```
#
# Calculation:
#
# ```
# a = Time::Span.new(hours: 20, minutes: 10, seconds: 10)
# b = Time::Span.new(hours: 10, minutes: 10, seconds: 10)
# c = a - b # => 10:00:00
# c.hours   # => 10
# ```
#
struct Time::Span
  # *Heavily* inspired by Mono's Time::Span class:
  # https://github.com/mono/mono/blob/master/mcs/class/corlib/System/Time::Span.cs

  include Comparable(self)
  include Steppable

  MAX  = new seconds: Int64::MAX, nanoseconds: 999_999_999
  MIN  = new seconds: Int64::MIN, nanoseconds: -999_999_999
  ZERO = new nanoseconds: 0

  @seconds : Int64

  # Nanoseconds are always in the range (-999_999_999..999_999_999)
  # and always have the same sign as @seconds (if seconds is zero,
  # @nanoseconds can either be negative or positive).
  @nanoseconds : Int32

  # Creates a new `Time::Span` from *seconds* and *nanoseconds*.
  #
  # Nanoseconds get normalized in the range of `0...1_000_000_000`,
  # the nanosecond overflow gets added as seconds.
  #
  # ```
  # Time::Span.new(seconds: 30)                 # => 00:00:30
  # Time::Span.new(seconds: 5, nanoseconds: 12) # => 00:00:05.000000012
  # ```
  def initialize(*, seconds : Int, nanoseconds : Int)
    # Normalize nanoseconds in the range 0...1_000_000_000
    @seconds = seconds.to_i64 + nanoseconds.tdiv(NANOSECONDS_PER_SECOND).to_i64
    @nanoseconds = nanoseconds.remainder(NANOSECONDS_PER_SECOND).to_i32

    # Make sure that if seconds is positive, nanoseconds is
    # positive too. Likewise, if seconds is negative, make
    # sure that nanoseconds is negative too.
    if @seconds > 0 && @nanoseconds < 0
      @seconds -= 1
      @nanoseconds += NANOSECONDS_PER_SECOND
    elsif @seconds < 0 && @nanoseconds > 0
      @seconds += 1
      @nanoseconds -= NANOSECONDS_PER_SECOND
    end
  end

  # Creates a new `Time::Span` from the *nanoseconds* given
  #
  # Nanoseconds get normalized in the range of `0...1_000_000_000`,
  # the nanosecond overflow gets added as seconds.
  #
  # ```
  # Time::Span.new(nanoseconds: 500_000_000)   # => 00:00:00.500000000
  # Time::Span.new(nanoseconds: 5_500_000_000) # => 00:00:05.500000000
  # ```
  def self.new(*, nanoseconds : Int)
    new(seconds: 0, nanoseconds: nanoseconds)
  end

  # Creates a new `Time::Span` from the *days*, *hours*, *minutes*, *seconds* and *nanoseconds* given
  #
  # Any time unit can be omitted.
  #
  # ```
  # Time::Span.new(days: 1)                                                   # => 1.00:00:00
  # Time::Span.new(days: 1, hours: 2, minutes: 3)                             # => 1.02:03:00
  # Time::Span.new(days: 1, hours: 2, minutes: 3, seconds: 4, nanoseconds: 5) # => 1.02:03:04.000000005
  # ```
  def self.new(*, days : Int = 0, hours : Int = 0, minutes : Int = 0, seconds : Int = 0, nanoseconds : Int = 0)
    new(
      seconds: compute_seconds(days, hours, minutes, seconds),
      nanoseconds: nanoseconds,
    )
  end

  private def self.compute_seconds(days, hours, minutes, seconds)
    days_to_seconds = SECONDS_PER_DAY.to_i64 * days
    hours_to_seconds = SECONDS_PER_HOUR.to_i64 * hours
    minutes_to_seconds = SECONDS_PER_MINUTE.to_i64 * minutes

    days_to_seconds + hours_to_seconds + minutes_to_seconds + seconds
  rescue OverflowError
    raise ArgumentError.new "Time::Span too big or too small"
  end

  # Returns the number of full days in this time span.
  #
  # ```
  # (5.days + 25.hours).days # => 6_i64
  # ```
  def days : Int64
    to_i.tdiv(SECONDS_PER_DAY)
  end

  # Returns the number of full hours of the day (`0..23`) in this time span.
  def hours : Int32
    to_i.remainder(SECONDS_PER_DAY)
      .tdiv(SECONDS_PER_HOUR)
      .to_i
  end

  # Returns the number of full minutes of the hour (`0..59`) in this time span.
  def minutes : Int32
    to_i.remainder(SECONDS_PER_HOUR)
      .tdiv(SECONDS_PER_MINUTE)
      .to_i
  end

  # Returns the number of full seconds of the minute (`0..59`) in this time span.
  def seconds : Int32
    to_i.remainder(SECONDS_PER_MINUTE)
      .to_i
  end

  # Returns the number of milliseconds of the second (`0..999`) in this time span.
  def milliseconds : Int32
    nanoseconds // NANOSECONDS_PER_MILLISECOND
  end

  # Returns the number of microseconds of the second (`0..999999`) in this time span.
  def microseconds : Int32
    nanoseconds // NANOSECONDS_PER_MICROSECOND
  end

  # Returns the number of nanoseconds of the second (`0..999_999_999`)
  # in this time span.
  def nanoseconds : Int32
    @nanoseconds
  end

  # Converts to a (possibly fractional) number of weeks.
  #
  # ```
  # (4.weeks + 5.days + 6.hours).total_weeks # => 4.75
  # ```
  def total_weeks : Float64
    total_days / 7
  end

  # Converts to a (possibly fractional) number of days.
  #
  # ```
  # (36.hours).total_days # => 1.5
  # ```
  def total_days : Float64
    total_hours / 24
  end

  # Converts to a (possibly fractional) number of hours.
  def total_hours : Float64
    total_minutes / 60
  end

  # Converts to a (possibly fractional) number of minutes.
  def total_minutes : Float64
    total_seconds / 60
  end

  # Converts to a (possibly fractional) number of seconds.
  def total_seconds : Float64
    to_i.to_f + (nanoseconds.to_f / NANOSECONDS_PER_SECOND)
  end

  # Converts to a number of milliseconds.
  def total_milliseconds : Float64
    total_nanoseconds / NANOSECONDS_PER_MILLISECOND
  end

  # Converts to a number of microseconds.
  def total_microseconds : Float64
    total_nanoseconds / NANOSECONDS_PER_MICROSECOND
  end

  # Converts to a number of nanoseconds.
  def total_nanoseconds : Float64
    (to_i.to_f * NANOSECONDS_PER_SECOND) + nanoseconds
  end

  # Alias of `total_seconds`.
  def to_f : Float64
    total_seconds
  end

  # Returns the number of full seconds.
  def to_i : Int64
    @seconds
  end

  # Returns the absolute (non-negative) amount of time this `Time::Span`
  # represents by removing the sign.
  def abs : Time::Span
    Span.new(seconds: to_i.abs, nanoseconds: nanoseconds.abs)
  end

  # Returns the sign of this time span.
  #
  # Values are `-1`, `0`, `1` if `self` is smaller, equal, bigger compared to `ZERO`.
  def sign : Int32
    if @seconds == 0
      @nanoseconds.sign
    else
      @seconds.sign
    end
  end

  # Returns a `Time` that happens later by `self` than the current time.
  def from_now : Time
    Time.local + self
  end

  # Returns a `Time` that happens earlier by `self` than the current time.
  def ago : Time
    Time.local - self
  end

  def -(other : self) : Time::Span
    # TODO check overflow
    Span.new(
      seconds: to_i - other.to_i,
      nanoseconds: nanoseconds - other.nanoseconds,
    )
  end

  def - : Time::Span
    # TODO check overflow
    Span.new(
      seconds: -to_i,
      nanoseconds: -nanoseconds,
    )
  end

  def +(other : self) : Time::Span
    # TODO check overflow
    Span.new(
      seconds: to_i + other.to_i,
      nanoseconds: nanoseconds + other.nanoseconds,
    )
  end

  # Returns the additive identity of this type.
  #
  # This is `zero`.
  def self.additive_identity : self
    zero
  end

  def + : self
    self
  end

  # Returns a `Time::Span` that is *number* times longer.
  def *(number : Int) : Time::Span
    # TODO check overflow
    Span.new(
      seconds: to_i * number,
      nanoseconds: nanoseconds.to_i64 * number,
    )
  end

  # Returns a `Time::Span` that is *number* times longer.
  def *(number : Float) : Time::Span
    (total_nanoseconds * number).nanoseconds
  end

  # Returns a `Time::Span` that is divided by *number*.
  def /(number : Int) : Time::Span
    seconds = to_i.tdiv(number)
    nanoseconds = self.nanoseconds.tdiv(number)

    remainder = to_i.remainder(number)
    nanoseconds += (remainder * NANOSECONDS_PER_SECOND) // number

    # TODO check overflow
    Span.new(
      seconds: seconds,
      nanoseconds: nanoseconds,
    )
  end

  # Returns a `Time::Span` that is divided by *number*.
  def /(number : Float) : Time::Span
    (total_nanoseconds / number).nanoseconds
  end

  def /(other : self) : Float64
    total_nanoseconds.to_f64 / other.total_nanoseconds.to_f64
  end

  def <=>(other : self)
    cmp = to_i <=> other.to_i
    cmp = nanoseconds <=> other.nanoseconds if cmp == 0
    cmp
  end

  def sign : Int32
    (self <=> ZERO).sign
  end

  def inspect(io : IO) : Nil
    if to_i < 0 || nanoseconds < 0
      io << '-'
    end

    # We need to take absolute values of all components.
    # Can't handle negative timespans by negating the Time::Span
    # as a whole. This would lead to an overflow for the
    # degenerate case `Time::Span.MinValue`.
    if days != 0
      io << days.abs
      io << '.'
    end

    hours = self.hours.abs
    io << '0' if hours < 10
    io << hours

    io << ':'

    minutes = self.minutes.abs
    io << '0' if minutes < 10
    io << minutes

    io << ':'

    seconds = self.seconds.abs
    io << '0' if seconds < 10
    io << seconds

    nanoseconds = self.nanoseconds.abs
    if nanoseconds != 0
      io << '.'
      io << '0' if nanoseconds < 100000000
      io << '0' if nanoseconds < 10000000
      io << '0' if nanoseconds < 1000000
      io << '0' if nanoseconds < 100000
      io << '0' if nanoseconds < 10000
      io << '0' if nanoseconds < 1000
      io << '0' if nanoseconds < 100
      io << '0' if nanoseconds < 10
      io << nanoseconds
    end
  end

  # Creates a new `Time::Span` representing a span of zero time.
  def self.zero : Time::Span
    ZERO
  end

  # Returns `true` if `self` represents a span of zero time.
  #
  # ```
  # 2.hours.zero?  # => false
  # 0.days.zero?   # => true
  # 1.second.zero? # => false
  # ```
  def zero? : Bool
    self == ZERO
  end

  # Returns `true` if `self` represents a positive time span.
  #
  # ```
  # 2.hours.positive? # => true
  # 0.days.positive?  # => false
  # -3.days.positive? # => false
  # ```
  def positive? : Bool
    self > ZERO
  end

  # Returns `true` if `self` represents a negative time span.
  #
  # ```
  # 2.hours.negative? # => false
  # 0.days.negative?  # => false
  # -3.days.negative? # => true
  # ```
  def negative? : Bool
    self < ZERO
  end
end

struct Int
  # Returns a `Time::Span` of `self` weeks.
  def weeks : Time::Span
    Time::Span.new(days: (7 * self))
  end

  # :ditto:
  def week : Time::Span
    weeks
  end

  # Returns a `Time::Span` of `self` days.
  def days : Time::Span
    Time::Span.new(days: self)
  end

  # :ditto:
  def day : Time::Span
    days
  end

  # Returns a `Time::Span` of `self` hours.
  def hours : Time::Span
    Time::Span.new(hours: self)
  end

  # :ditto:
  def hour : Time::Span
    hours
  end

  # Returns a `Time::Span` of `self` minutes.
  def minutes : Time::Span
    Time::Span.new(minutes: self)
  end

  # :ditto:
  def minute : Time::Span
    minutes
  end

  # Returns a `Time::Span` of `self` seconds.
  def seconds : Time::Span
    Time::Span.new(seconds: self)
  end

  # :ditto:
  def second : Time::Span
    seconds
  end

  # Returns a `Time::Span` of `self` milliseconds.
  def milliseconds : Time::Span
    sec, m = self.to_i64.divmod(1_000)
    Time::Span.new(seconds: sec, nanoseconds: m * 1_000_000)
  end

  # :ditto:
  def millisecond : Time::Span
    milliseconds
  end

  # Returns a `Time::Span` of `self` microseconds.
  def microseconds : Time::Span
    sec, m = self.to_i64.divmod(1_000_000)
    Time::Span.new(seconds: sec, nanoseconds: m * 1_000)
  end

  # :ditto:
  def microsecond : Time::Span
    microseconds
  end

  # Returns a `Time::Span` of `self` nanoseconds.
  def nanoseconds : Time::Span
    Time::Span.new(nanoseconds: self.to_i64)
  end

  # :ditto:
  def nanosecond : Time::Span
    nanoseconds
  end
end

struct Float
  # Returns a `Time::Span` of `self` weeks.
  def weeks : Time::Span
    (self * 7).days
  end

  # Returns a `Time::Span` of `self` days.
  def days : Time::Span
    (self * 24).hours
  end

  # Returns a `Time::Span` of `self` hours.
  def hours : Time::Span
    (self * 60).minutes
  end

  # Returns a `Time::Span` of `self` minutes.
  def minutes : Time::Span
    (self * 60).seconds
  end

  # Returns a `Time::Span` of `self` seconds.
  def seconds : Time::Span
    seconds = self.to_i64
    nanoseconds = (self - seconds) * Time::NANOSECONDS_PER_SECOND

    # round away from zero
    nanoseconds = (nanoseconds < 0 ? (nanoseconds - 0.5) : (nanoseconds + 0.5)).to_i64

    Time::Span.new(
      seconds: seconds,
      nanoseconds: nanoseconds,
    )
  end

  # Returns a `Time::Span` of `self` milliseconds.
  def milliseconds : Time::Span
    (self / 1_000).seconds
  end

  # Returns a `Time::Span` of `self` microseconds.
  def microseconds : Time::Span
    (self / 1_000_000).seconds
  end

  # Returns a `Time::Span` of `self` nanoseconds.
  def nanoseconds : Time::Span
    seconds = (self / Time::NANOSECONDS_PER_SECOND).to_i64
    nanoseconds = self.remainder(Time::NANOSECONDS_PER_SECOND)

    # round away from zero
    nanoseconds = (nanoseconds < 0 ? (nanoseconds - 0.5) : (nanoseconds + 0.5)).to_i64

    Time::Span.new(
      seconds: seconds,
      nanoseconds: nanoseconds,
    )
  end
end

# Represents a number of months passed. Used for shifting `Time`s by a
# specified number of months.
#
# ```
# Time.local(2016, 2, 1) + 13.months # => 2017-03-01 00:00:00
# Time.local(2016, 2, 29) + 2.years  # => 2018-02-28 00:00:00
# ```
struct Time::MonthSpan
  include Comparable(self)

  # The number of months.
  getter value : Int64

  def initialize(value : Int)
    @value = value.to_i64
  end

  # Returns a `Time` that happens N months after now.
  def from_now : Time
    Time.local + self
  end

  # Returns a `Time` that happens N months before now.
  def ago : Time
    Time.local - self
  end

  def -(other : self) : Time::MonthSpan
    # TODO check overflow
    MonthSpan.new(@value - other.value)
  end

  def - : Time::MonthSpan
    # TODO check overflow
    MonthSpan.new(-@value)
  end

  def +(other : self) : Time::MonthSpan
    # TODO check overflow
    MonthSpan.new(@value + other.value)
  end

  def + : self
    self
  end

  # Returns a `Time::MonthSpan` that is *number* times longer.
  def *(number : Int) : Time::MonthSpan
    # TODO check overflow
    MonthSpan.new((@value * number).to_i64)
  end

  # Returns a `Time::MonthSpan` that is *number* times longer.
  def *(number : Float) : Time::MonthSpan
    # TODO check overflow
    MonthSpan.new((@value * number).to_i64)
  end

  # Returns a `Time::MonthSpan` that is divided by *number*.
  def /(number : Int) : Time::MonthSpan
    # TODO check overflow
    MonthSpan.new((@value / number).to_i64)
  end

  # Returns a `Time::MonthSpan` that is divided by *number*.
  def /(other : self) : Float64
    # TODO check overflow
    @value / other.value
  end

  def /(number : Float) : Time::MonthSpan
    # TODO check overflow
    MonthSpan.new((@value / number).to_i64)
  end

  def <=>(other : self)
    @value <=> other.value
  end
end

struct Int
  # Returns a `Time::MonthSpan` of `self` months.
  def months : Time::MonthSpan
    Time::MonthSpan.new(self)
  end

  # :ditto:
  def month : Time::MonthSpan
    months
  end

  # Returns a `Time::MonthSpan` of `self` years.
  def years : Time::MonthSpan
    Time::MonthSpan.new(self * 12)
  end

  # :ditto:
  def year : Time::MonthSpan
    years
  end
end
