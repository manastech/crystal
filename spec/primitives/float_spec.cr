require "spec"
require "../support/number"

describe "Primitives: Float" do
  describe "#to_i" do
    {% for float in BUILTIN_FLOAT_TYPES %}
      {% for method, int in BUILTIN_INT_CONVERSIONS %}
        it {{ "raises on overflow for #{float}##{method}" }} do
          if {{ float }}::MAX > {{ int }}::MAX
            expect_raises(OverflowError) do
              {{ float }}.new!({{ int }}::MAX).next_float.{{ method }}
            end
          end

          expect_raises(OverflowError) do
            {{ float }}::INFINITY.{{ method }}
          end

          if {{ int }}::MIN.zero? # unsigned
            expect_raises(OverflowError) do
              {{ float }}.zero.prev_float.{{ method }}
            end
          end

          expect_raises(OverflowError) do
            (-{{ float }}::INFINITY).{{ method }}
          end
        end

        it "raises overflow if not a number (#10421)" do
          expect_raises(OverflowError) do
            {{ float }}::NAN.{{ method }}
          end
        end
      {% end %}
    {% end %}

    it "raises overflow if equal to Int::MAX (#11105)" do
      # these examples hold because the integer would be rounded _up_ to the
      # nearest representable float

      expect_raises(OverflowError) { Float32.new!(Int32::MAX).to_i32 }
      expect_raises(OverflowError) { Float32.new!(UInt32::MAX).to_u32 }
      expect_raises(OverflowError) { Float32.new!(Int64::MAX).to_i64 }
      expect_raises(OverflowError) { Float32.new!(UInt64::MAX).to_u64 }
      {% unless flag?(:win32) %}
        expect_raises(OverflowError) { Float32.new!(Int128::MAX).to_i128 }
      {% end %}

      expect_raises(OverflowError) { Float64.new!(Int64::MAX).to_i64 }
      expect_raises(OverflowError) { Float64.new!(UInt64::MAX).to_u64 }
      {% unless flag?(:win32) %}
        expect_raises(OverflowError) { Float64.new!(Int128::MAX).to_i128 }
        expect_raises(OverflowError) { Float64.new!(UInt128::MAX).to_u128 }
      {% end %}
    end
  end

  describe "#to_f" do
    it "raises on overflow for Float64#to_f32" do
      expect_raises(OverflowError) { Float64::MAX.to_f32 }
      expect_raises(OverflowError) { Float32::MAX.to_f64!.next_float.to_f32 }
      expect_raises(OverflowError) { Float32::MIN.to_f64!.prev_float.to_f32 }
      expect_raises(OverflowError) { Float64::MIN.to_f32 }
    end

    it "doesn't raise for infinity" do
      x = Float64::INFINITY.to_f32
      x.should be_a(Float32)
      x.should eq(Float32::INFINITY)

      x = (-Float64::INFINITY).to_f32
      x.should be_a(Float32)
      x.should eq(-Float32::INFINITY)
    end

    it "doesn't raise for NaN" do
      x = Float64::NAN.to_f32
      x.should be_a(Float32)
      x.nan?.should be_true
    end
  end
end
