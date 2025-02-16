require "./spec_helper"

# Ported from https://github.com/llvm/llvm-project/blob/ce59ccd04023cab3a837da14079ca2dcbfebb70c/compiler-rt/test/builtins/Unit/muloti4_test.c

private def test__muloti4(a : Int128, b : Int128, expected : Int128, expected_overflow : Int32, file = __FILE__, line = __LINE__)
  it "passes compiler-rt builtins unit tests" do
    actual_overflow = 0_i32
    actual = __muloti4(a, b, pointerof(actual_overflow))
    actual_overflow.should eq(expected_overflow), file: file, line: line
    if !expected_overflow
      actual.should eq(expected), file: file, line: line
    end
  end
end

describe "__muloti4" do
  test__muloti4(0, 0, 0, 0)
  test__muloti4(0, 1, 0, 0)
  test__muloti4(1, 0, 0, 0)
  test__muloti4(0, 10, 0, 0)
  test__muloti4(10, 0, 0, 0)
  test__muloti4(0, 81985529216486895, 0, 0)
  test__muloti4(81985529216486895, 0, 0, 0)
  test__muloti4(0, -1, 0, 0)
  test__muloti4(-1, 0, 0, 0)
  test__muloti4(0, -10, 0, 0)
  test__muloti4(-10, 0, 0, 0)
  test__muloti4(0, -81985529216486895, 0, 0)
  test__muloti4(-81985529216486895, 0, 0, 0)
  test__muloti4(1, 1, 1, 0)
  test__muloti4(1, 10, 10, 0)
  test__muloti4(10, 1, 10, 0)
  test__muloti4(1, 81985529216486895, 81985529216486895, 0)
  test__muloti4(81985529216486895, 1, 81985529216486895, 0)
  test__muloti4(1, -1, -1, 0)
  test__muloti4(1, -10, -10, 0)
  test__muloti4(-10, 1, -10, 0)
  test__muloti4(1, -81985529216486895, -81985529216486895, 0)
  test__muloti4(-81985529216486895, 1, -81985529216486895, 0)
  test__muloti4(3037000499, 3037000499, 9223372030926249001, 0)
  test__muloti4(-3037000499, 3037000499, -9223372030926249001, 0)
  test__muloti4(3037000499, -3037000499, -9223372030926249001, 0)
  test__muloti4(-3037000499, -3037000499, 9223372030926249001, 0)
  test__muloti4(4398046511103, 2097152, 9223372036852678656, 0)
  test__muloti4(-4398046511103, 2097152, -9223372036852678656, 0)
  test__muloti4(4398046511103, -2097152, -9223372036852678656, 0)
  test__muloti4(-4398046511103, -2097152, 9223372036852678656, 0)
  test__muloti4(2097152, 4398046511103, 9223372036852678656, 0)
  test__muloti4(-2097152, 4398046511103, -9223372036852678656, 0)
  test__muloti4(2097152, -4398046511103, -9223372036852678656, 0)
  test__muloti4(-2097152, -4398046511103, 9223372036852678656, 0)
  test__muloti4(make_ti(0x00000000000000B5, 0x04F333F9DE5BE000),
    make_ti(0x0000000000000000u64, 0x00B504F333F9DE5Bu64),
    make_ti(0x7FFFFFFFFFFFF328u64, 0xDF915DA296E8A000u64), 0)
  test__muloti4(make_ti(0x7FFFFFFFFFFFFFFFu64, 0xFFFFFFFFFFFFFFFFu64),
    -2,
    make_ti(0x8000000000000000u64, 0x0000000000000001u64), 1)
  test__muloti4(-2,
    make_ti(0x7FFFFFFFFFFFFFFFu64, 0xFFFFFFFFFFFFFFFFu64),
    make_ti(0x8000000000000000u64, 0x0000000000000001u64), 1)
  test__muloti4(make_ti(0x7FFFFFFFFFFFFFFFu64, 0xFFFFFFFFFFFFFFFFu64),
    -1,
    make_ti(0x8000000000000000u64, 0x0000000000000001u64), 0)
  test__muloti4(-1,
    make_ti(0x7FFFFFFFFFFFFFFFu64, 0xFFFFFFFFFFFFFFFFu64),
    make_ti(0x8000000000000000u64, 0x0000000000000001u64), 0)
  test__muloti4(make_ti(0x7FFFFFFFFFFFFFFFu64, 0xFFFFFFFFFFFFFFFFu64),
    0,
    0, 0)
  test__muloti4(0,
    make_ti(0x7FFFFFFFFFFFFFFFu64, 0xFFFFFFFFFFFFFFFFu64),
    0, 0)
  test__muloti4(make_ti(0x7FFFFFFFFFFFFFFFu64, 0xFFFFFFFFFFFFFFFFu64),
    1,
    make_ti(0x7FFFFFFFFFFFFFFFu64, 0xFFFFFFFFFFFFFFFFu64), 0)
  test__muloti4(1,
    make_ti(0x7FFFFFFFFFFFFFFFu64, 0xFFFFFFFFFFFFFFFFu64),
    make_ti(0x7FFFFFFFFFFFFFFFu64, 0xFFFFFFFFFFFFFFFFu64), 0)
  test__muloti4(make_ti(0x7FFFFFFFFFFFFFFFu64, 0xFFFFFFFFFFFFFFFFu64),
    2,
    make_ti(0x8000000000000000u64, 0x0000000000000001u64), 1)
  test__muloti4(2,
    make_ti(0x7FFFFFFFFFFFFFFFu64, 0xFFFFFFFFFFFFFFFFu64),
    make_ti(0x8000000000000000u64, 0x0000000000000001u64), 1)
  test__muloti4(make_ti(0x8000000000000000u64, 0x0000000000000000u64),
    -2,
    make_ti(0x8000000000000000u64, 0x0000000000000000u64), 1)
  test__muloti4(-2,
    make_ti(0x8000000000000000u64, 0x0000000000000000u64),
    make_ti(0x8000000000000000u64, 0x0000000000000000u64), 1)
  test__muloti4(make_ti(0x8000000000000000u64, 0x0000000000000000u64),
    -1,
    make_ti(0x8000000000000000u64, 0x0000000000000000u64), 1)
  test__muloti4(-1,
    make_ti(0x8000000000000000u64, 0x0000000000000000u64),
    make_ti(0x8000000000000000u64, 0x0000000000000000u64), 1)
  test__muloti4(make_ti(0x8000000000000000u64, 0x0000000000000000u64),
    0,
    0, 0)
  test__muloti4(0,
    make_ti(0x8000000000000000u64, 0x0000000000000000u64),
    0, 0)
  test__muloti4(make_ti(0x8000000000000000u64, 0x0000000000000000u64),
    1,
    make_ti(0x8000000000000000u64, 0x0000000000000000u64), 0)
  test__muloti4(1,
    make_ti(0x8000000000000000u64, 0x0000000000000000u64),
    make_ti(0x8000000000000000u64, 0x0000000000000000u64), 0)
  test__muloti4(make_ti(0x8000000000000000u64, 0x0000000000000000u64),
    2,
    make_ti(0x8000000000000000u64, 0x0000000000000000u64), 1)
  test__muloti4(2,
    make_ti(0x8000000000000000u64, 0x0000000000000000u64),
    make_ti(0x8000000000000000u64, 0x0000000000000000u64), 1)
  test__muloti4(make_ti(0x8000000000000000u64, 0x0000000000000001u64),
    -2,
    make_ti(0x8000000000000000u64, 0x0000000000000001u64), 1)
  test__muloti4(-2,
    make_ti(0x8000000000000000u64, 0x0000000000000001u64),
    make_ti(0x8000000000000000u64, 0x0000000000000001u64), 1)
  test__muloti4(make_ti(0x8000000000000000u64, 0x0000000000000001u64),
    -1,
    make_ti(0x7FFFFFFFFFFFFFFFu64, 0xFFFFFFFFFFFFFFFFu64), 0)
  test__muloti4(-1,
    make_ti(0x8000000000000000u64, 0x0000000000000001u64),
    make_ti(0x7FFFFFFFFFFFFFFFu64, 0xFFFFFFFFFFFFFFFFu64), 0)
  test__muloti4(make_ti(0x8000000000000000u64, 0x0000000000000001u64),
    0,
    0, 0)
  test__muloti4(0,
    make_ti(0x8000000000000000u64, 0x0000000000000001u64),
    0, 0)
  test__muloti4(make_ti(0x8000000000000000u64, 0x0000000000000001u64),
    1,
    make_ti(0x8000000000000000u64, 0x0000000000000001u64), 0)
  test__muloti4(1,
    make_ti(0x8000000000000000u64, 0x0000000000000001u64),
    make_ti(0x8000000000000000u64, 0x0000000000000001u64), 0)
  test__muloti4(make_ti(0x8000000000000000u64, 0x0000000000000001u64),
    2,
    make_ti(0x8000000000000000u64, 0x0000000000000000u64), 1)
  test__muloti4(2,
    make_ti(0x8000000000000000u64, 0x0000000000000001u64),
    make_ti(0x8000000000000000u64, 0x0000000000000000u64), 1)
end
