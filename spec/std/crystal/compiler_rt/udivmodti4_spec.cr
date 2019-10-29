{% skip_file unless flag?(:compile_rt) %}

require "spec"
require "../../../../src/crystal/compiler_rt/udivmodti4.cr"

# Ported from compiler-rt:test/builtins/Unit/udivmodti4_test.c

private def test__udivmodti4(a : (UInt128 | UInt128RT), b : (UInt128 | UInt128RT), expected : (UInt128 | UInt128RT), expected_overflow : (UInt128 | UInt128RT), file = __FILE__, line = __LINE__)
  it "passes compiler-rt builtins unit tests" do
    actual_overflow = 0_u128
    actual = __udivmodti4(a.to_u128, b.to_u128, pointerof(actual_overflow))
    actual_overflow.should eq(expected_overflow.to_u128), file, line
    if !expected_overflow.to_u128
      actual.should eq(expected.to_u128), file, line
    end
  end
end

private UDIVMODTI4_TESTS = StaticArray[
  StaticArray[UInt128RT[1_i128], UInt128RT[1_i128], UInt128RT[1_i128], UInt128RT[0_i128]],
# # TODO: this is a placeholder, remove when ready
]

describe "__udivmodti4" do
  UDIVMODTI4_TESTS.each do |tests|
    test__udivmodti4(tests[0], tests[1], tests[2], tests[3])
  end
end
