defmodule ErrowNumericTest do
  use ExUnit.Case, async: true

  describe "Standard integer types" do
    test ":s32 signed 32-bit int" do
      num = Errow.numeric([10, -20, 30], :s32)
      assert Errow.Numeric.size(num) == 3
      assert num[0] == 10
      assert num[1] == -20
      assert num[2] == 30
      assert Enum.sum(num) == 20
    end

    test ":u8 unsigned 8-bit int" do
      num = Errow.numeric([0, 128, 255], :u8)
      assert num[0] == 0
      assert num[1] == 128
      assert num[2] == 255

      assert_raise ArgumentError, fn ->
        Errow.Numeric.append(num, 256)
      end

      assert_raise ArgumentError, fn ->
        Errow.Numeric.append(num, -1)
      end
    end

    test ":s64 signed 64-bit int" do
      big = 8_000_000_000_000_000_000
      num = Errow.numeric([big, -big], :s64)
      assert num[0] == big
      assert num[1] == -big
    end
  end

  describe "128-bit and 256-bit BigInts" do
    test ":s128 128-bit signed BigInt" do
      big_128 = 300_000_000_000_000_000_000_000_000_000_000_000
      num = Errow.numeric([big_128, -big_128], :s128)

      assert Errow.Numeric.size(num) == 2
      # 2 * 16 bytes
      assert Errow.Numeric.buffer_byte_size(num) == 32
      assert num[0] == big_128
      assert num[1] == -big_128
    end

    test ":u256 256-bit unsigned BigInt (Ethereum / crypto scale)" do
      big_256 =
        115_792_089_237_316_195_423_570_985_008_687_907_853_269_984_665_640_564_039_457_584_007_913_129_639_935

      num = Errow.numeric([0, big_256], :u256)

      assert Errow.Numeric.size(num) == 2
      # 2 * 32 bytes
      assert Errow.Numeric.buffer_byte_size(num) == 64
      assert num[0] == 0
      assert num[1] == big_256
    end
  end

  describe "Floating point numbers" do
    test ":f64 double precision float" do
      num = Errow.numeric([1.5, 2.75, -3.125], :f64)
      assert num[0] == 1.5
      assert num[1] == 2.75
      assert num[2] == -3.125
    end

    test ":f32 single precision float" do
      num = Errow.numeric([1.25, 2.5], :f32)
      assert num[0] == 1.25
      assert num[1] == 2.5
    end
  end

  describe "Null handling in numerics" do
    test "appends and fetches nil" do
      num = Errow.numeric([1, nil, 3], :s32)
      assert Errow.Numeric.size(num) == 3
      assert Errow.Numeric.null_count(num) == 1
      assert num[0] == 1
      assert num[1] == nil
      assert num[2] == 3

      assert Errow.Numeric.null?(num, 1)
      refute Errow.Numeric.null?(num, 0)
    end
  end

  describe "Protocols: Enumerable, Collectable, Access, Inspect" do
    test "Collectable: for ... into: Errow.numeric(:s32)" do
      num =
        for i <- 1..5, into: Errow.numeric(:s32) do
          i * 10
        end

      assert Errow.Numeric.to_list(num) == [10, 20, 30, 40, 50]
    end

    test "Access: put_in and pop_in" do
      num = Errow.numeric([10, 20, 30], :s32)
      num2 = put_in(num[1], 99)
      assert num2[1] == 99

      {popped, remaining} = pop_in(num2[0])
      assert popped == 10
      assert Errow.Numeric.to_list(remaining) == [99, 30]
    end

    test "Inspect formatting" do
      num = Errow.numeric([1, 2, 3], :s32)
      assert inspect(num) =~ "#Errow.Numeric<s32, ["
    end
  end

  describe "Native Aggregations" do
    test "sum/2 with ints and floats" do
      ints = Errow.numeric([10, 20, 30, 40], :s32)
      assert Errow.sum(ints) == 100

      floats = Errow.numeric([1.5, 2.5, 3.5], :f64)
      assert Errow.sum(floats) == 7.5

      # with nulls
      with_nulls = Errow.numeric([10, nil, 30], :s32)
      assert Errow.sum(with_nulls) == 40
      assert Errow.sum(with_nulls, skip_nulls: false) == nil
    end

    test "product/2" do
      ints = Errow.numeric([2, 3, 4], :s32)
      assert Errow.product(ints) == 24

      with_nulls = Errow.numeric([2, nil, 5], :s32)
      assert Errow.product(with_nulls) == 10
    end

    test "min/2, max/2, min_max/2" do
      num = Errow.numeric([15, 3, 99, -5, 42], :s32)
      assert Errow.min(num) == -5
      assert Errow.max(num) == 99
      assert Errow.min_max(num) == {-5, 99}

      # with nulls
      with_nulls = Errow.numeric([nil, 15, -2, nil, 50], :s32)
      assert Errow.min(with_nulls) == -2
      assert Errow.max(with_nulls) == 50
      assert Errow.min_max(with_nulls) == {-2, 50}
    end

    test "mean/2" do
      num = Errow.numeric([10, 20, 30], :s32)
      assert Errow.mean(num) == 20.0

      with_nulls = Errow.numeric([10, nil, 20], :s32)
      assert Errow.mean(with_nulls) == 15.0
    end
  end
end
