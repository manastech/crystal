require "./sys/types"

lib LibC
  CLOCK_MONOTONIC = 1
  CLOCK_REALTIME  = 0

  struct Tm
    tm_sec : Int
    tm_min : Int
    tm_hour : Int
    tm_mday : Int
    tm_mon : Int
    tm_year : Int
    tm_wday : Int
    tm_yday : Int
    tm_isdst : Int
    tm_gmtoff : Long
    tm_zone : Char*
  end

  struct Timespec
    tv_sec : TimeT
    tv_nsec : Long
  end

  struct Itimerspec
    it_interval : Timespec
    it_value : Timespec
  end

  alias Sigevent = Void

  fun clock_gettime(clock_id : ClockidT, tp : Timespec*) : Int
  fun clock_settime(clock_id : ClockidT, tp : Timespec*) : Int
  fun gmtime_r(timer : TimeT*, tp : Tm*) : Tm*
  fun localtime_r(timer : TimeT*, tp : Tm*) : Tm*
  fun mktime(tp : Tm*) : TimeT
  fun tzset : Void
  fun timegm(tp : Tm*) : TimeT
  fun timer_create(ClockidT, Sigevent*, TimerT*) : Int
  fun timer_delete(TimerT) : Int
  fun timer_settime(TimerT, Int, Itimerspec*, Itimerspec*) : Int

  $daylight : Int
  $timezone : Long
  $tzname : StaticArray(Char*, 2)
end
