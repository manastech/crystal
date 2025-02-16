require "./spec_helper"

# Ported from https://github.com/llvm/llvm-project/blob/ce59ccd04023cab3a837da14079ca2dcbfebb70c/compiler-rt/test/builtins/Unit/mulosi4_test.c

private def test__mulosi4(a : Int32, b : Int32, expected : Int32, expected_overflow : Int32, file = __FILE__, line = __LINE__)
  it "passes compiler-rt builtins unit tests" do
    actual_overflow = 0_i32
    actual = __mulosi4(a, b, pointerof(actual_overflow))
    actual_overflow.should eq(expected_overflow), file: file, line: line
    if !expected_overflow
      actual.should eq(expected), file: file, line: line
    end
  end
end

describe "__mulosi4" do
  test__mulosi4(0, 0, 0, 0)
  test__mulosi4(0, 1, 0, 0)
  test__mulosi4(1, 0, 0, 0)
  test__mulosi4(0, 10, 0, 0)
  test__mulosi4(10, 0, 0, 0)
  test__mulosi4(0, 0x1234567, 0, 0)
  test__mulosi4(0x1234567, 0, 0, 0)

  test__mulosi4(0, -1, 0, 0)
  test__mulosi4(-1, 0, 0, 0)
  test__mulosi4(0, -10, 0, 0)
  test__mulosi4(-10, 0, 0, 0)
  test__mulosi4(0, 0x1234567, 0, 0)
  test__mulosi4(0x1234567, 0, 0, 0)

  test__mulosi4(1, 1, 1, 0)
  test__mulosi4(1, 10, 10, 0)
  test__mulosi4(10, 1, 10, 0)
  test__mulosi4(1, 0x1234567, 0x1234567, 0)
  test__mulosi4(0x1234567, 1, 0x1234567, 0)

  test__mulosi4(1, -1, -1, 0)
  test__mulosi4(1, -10, -10, 0)
  test__mulosi4(-10, 1, -10, 0)
  test__mulosi4(1, -0x1234567, -0x1234567, 0)
  test__mulosi4(-0x1234567, 1, -0x1234567, 0)

  test__mulosi4(0x7FFFFFFF, -2, -0x7fffffff, 1)
  test__mulosi4(-2, 0x7FFFFFFF, -0x7fffffff, 1)
  test__mulosi4(0x7FFFFFFF, -1, -0x7fffffff, 0)
  test__mulosi4(-1, 0x7FFFFFFF, -0x7fffffff, 0)
  test__mulosi4(0x7FFFFFFF, 0, 0, 0)
  test__mulosi4(0, 0x7FFFFFFF, 0, 0)
  test__mulosi4(0x7FFFFFFF, 1, 0x7FFFFFFF, 0)
  test__mulosi4(1, 0x7FFFFFFF, 0x7FFFFFFF, 0)
  test__mulosi4(0x7FFFFFFF, 2, -0x7fffffff, 1)
  test__mulosi4(2, 0x7FFFFFFF, -0x7fffffff, 1)

  test__mulosi4(-0x80000000, -2, -0x80000000, 1)
  test__mulosi4(-2, -0x80000000, -0x80000000, 1)
  test__mulosi4(-0x80000000, -1, -0x80000000, 1)
  test__mulosi4(-1, -0x80000000, -0x80000000, 1)
  test__mulosi4(-0x80000000, 0, 0, 0)
  test__mulosi4(0, -0x80000000, 0, 0)
  test__mulosi4(-0x80000000, 1, -0x80000000, 0)
  test__mulosi4(1, -0x80000000, -0x80000000, 0)
  test__mulosi4(-0x80000000, 2, -0x80000000, 1)
  test__mulosi4(2, -0x80000000, -0x80000000, 1)

  test__mulosi4(-0x7fffffff, -2, -0x7fffffff, 1)
  test__mulosi4(-2, -0x7fffffff, -0x7fffffff, 1)
  test__mulosi4(-0x7fffffff, -1, 0x7FFFFFFF, 0)
  test__mulosi4(-1, -0x7fffffff, 0x7FFFFFFF, 0)
  test__mulosi4(-0x7fffffff, 0, 0, 0)
  test__mulosi4(0, -0x7fffffff, 0, 0)
  test__mulosi4(-0x7fffffff, 1, -0x7fffffff, 0)
  test__mulosi4(1, -0x7fffffff, -0x7fffffff, 0)
  test__mulosi4(-0x7fffffff, 2, -0x80000000, 1)
  test__mulosi4(2, -0x7fffffff, -0x80000000, 1)
end
