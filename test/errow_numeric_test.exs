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

    test ":s8 and :u8 8-bit ints" do
      s8 = Errow.s8([-128, 0, 127])
      assert Enum.to_list(s8) == [-128, 0, 127]

      u8 = Errow.u8([0, 128, 255])
      assert u8[0] == 0
      assert u8[1] == 128
      assert u8[2] == 255

      assert_raise ArgumentError, fn -> Errow.Numeric.append(u8, 256) end
      assert_raise ArgumentError, fn -> Errow.Numeric.append(u8, -1) end
      assert_raise ArgumentError, fn -> Errow.Numeric.append(s8, 128) end
      assert_raise ArgumentError, fn -> Errow.Numeric.append(s8, -129) end
    end

    test ":s16 and :u16 16-bit ints" do
      s16 = Errow.s16([-32768, 0, 32767])
      assert Enum.to_list(s16) == [-32768, 0, 32767]

      u16 = Errow.u16([0, 65535])
      assert Enum.to_list(u16) == [0, 65535]

      assert_raise ArgumentError, fn -> Errow.Numeric.append(s16, 32768) end
      assert_raise ArgumentError, fn -> Errow.Numeric.append(u16, 65536) end
    end

    test ":s64 and :u64 64-bit ints" do
      big_s64 = 8_000_000_000_000_000_000
      s64 = Errow.numeric([big_s64, -big_s64], :s64)
      assert s64[0] == big_s64
      assert s64[1] == -big_s64

      big_u64 = 18_000_000_000_000_000_000
      u64 = Errow.numeric([0, big_u64], :u64)
      assert u64[0] == 0
      assert u64[1] == big_u64

      assert_raise ArgumentError, fn ->
        Errow.Numeric.append(s64, 9_223_372_036_854_775_808)
      end

      assert_raise ArgumentError, fn ->
        Errow.Numeric.append(u64, 18_446_744_073_709_551_616)
      end
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

      assert_raise ArgumentError, fn ->
        Errow.Numeric.append(num, 0x80000000000000000000000000000000)
      end
    end

    test ":u128 128-bit unsigned BigInt" do
      big_u128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      num = Errow.u128([0, big_u128])
      assert num[0] == 0
      assert num[1] == big_u128

      assert_raise ArgumentError, fn ->
        Errow.Numeric.append(num, big_u128 + 1)
      end
    end

    test ":s256 256-bit signed BigInt" do
      big_s256 = 100_000_000_000_000_000_000_000_000_000_000_000_000_000_000
      num = Errow.s256([big_s256, -big_s256])
      assert num[0] == big_s256
      assert num[1] == -big_s256
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
      assert Errow.Numeric.null?(num, -2)
      refute Errow.Numeric.null?(num, 99)
    end
  end

  describe "Access behaviour and Slicing" do
    test "slicing with ranges and negative indices" do
      num = Errow.s32([10, 20, 30, 40, 50])
      assert num[-1] == 50
      assert num[-2] == 40
      assert num[10] == nil

      assert num[0..2] == [10, 20, 30]
      assert num[1..-1//1] == [20, 30, 40, 50]
      assert num[3..1//-1] == [40, 30, 20]

      assert Errow.Numeric.get(num, 0) == 10
      assert Errow.Numeric.get(num, 99, :default) == :default
    end

    test "Access: put_in, update_in, pop_in" do
      num = Errow.numeric([10, 20, 30], :s32)
      num2 = put_in(num[1], 99)
      assert num2[1] == 99

      num3 = update_in(num[0], &(&1 * 2))
      assert num3[0] == 20

      {popped, remaining} = pop_in(num2[0])
      assert popped == 10
      assert Errow.Numeric.to_list(remaining) == [99, 30]

      assert Access.pop(num, 99) == {nil, num}

      assert_raise ArgumentError, fn ->
        Access.get_and_update(num, 99, fn x -> {x, x} end)
      end
    end

    test "replace_at and delete_at" do
      num = Errow.s32([10, 20, 30])
      num2 = Errow.Numeric.replace_at(num, 1, nil)
      assert num2[1] == nil
      assert num2.null_count == 1

      num3 = Errow.Numeric.delete_at(num, 0)
      assert num3.length == 2
      assert Enum.to_list(num3) == [20, 30]

      assert_raise ArgumentError, fn -> Errow.Numeric.delete_at(num, 99) end
    end
  end

  describe "Protocols: Enumerable, Collectable, Inspect" do
    test "Collectable: for ... into: Errow.numeric(:s32)" do
      num =
        for i <- 1..5, into: Errow.numeric(:s32) do
          i * 10
        end

      assert Errow.Numeric.to_list(num) == [10, 20, 30, 40, 50]
    end

    test "Enumerable implementation" do
      num = Errow.s32([10, 20, 30, 40])
      assert Enum.count(num) == 4
      assert Enum.member?(num, 20) == true
      assert Enum.member?(num, 99) == false
      assert Enum.slice(num, 1, 2) == [20, 30]
      assert Enum.take(num, 2) == [10, 20]
    end

    test "Inspect formatting" do
      num = Errow.numeric([1, 2, 3], :s32)
      assert inspect(num) =~ "#Errow.Numeric<s32, ["

      big = Errow.s32(for(i <- 1..10, do: i))
      assert inspect(big) =~ "total 10 items"

      with_nulls = Errow.s32([1, nil, 3])
      assert inspect(with_nulls) =~ "nil"
    end
  end

  describe "Native Aggregations across all types" do
    test "sum/2 across multiple types" do
      assert Errow.sum(Errow.s8([10, 20])) == 30
      assert Errow.sum(Errow.u8([10, 20])) == 30
      assert Errow.sum(Errow.s16([100, 200])) == 300
      assert Errow.sum(Errow.u16([100, 200])) == 300
      assert Errow.sum(Errow.u32([1000, 2000])) == 3000
      assert Errow.sum(Errow.s64([10_000, 20_000])) == 30_000
      assert Errow.sum(Errow.u64([10_000, 20_000])) == 30_000
      assert Errow.sum(Errow.s128([10, 20])) == 30
      assert Errow.sum(Errow.u128([10, 20])) == 30
      assert Errow.sum(Errow.s256([10, 20])) == 30
      assert Errow.sum(Errow.u256([10, 20])) == 30
      assert Errow.sum(Errow.f32([1.5, 2.5])) == 4.0
      assert Errow.sum(Errow.f64([1.5, 2.5])) == 4.0
    end

    test "product/2 across types" do
      assert Errow.product(Errow.s8([2, 3])) == 6
      assert Errow.product(Errow.u8([2, 3])) == 6
      assert Errow.product(Errow.s16([2, 3])) == 6
      assert Errow.product(Errow.u16([2, 3])) == 6
      assert Errow.product(Errow.s32([2, 3, 4])) == 24
      assert Errow.product(Errow.u32([2, 3])) == 6
      assert Errow.product(Errow.s64([2, 3])) == 6
      assert Errow.product(Errow.u64([2, 3])) == 6
      assert Errow.product(Errow.s128([2, 3])) == 6
      assert Errow.product(Errow.u128([2, 3])) == 6
      assert Errow.product(Errow.s256([2, 3])) == 6
      assert Errow.product(Errow.u256([2, 3])) == 6
      assert Errow.product(Errow.f32([1.5, 2.0])) == 3.0
      assert Errow.product(Errow.f64([1.5, 2.0])) == 3.0

      with_nulls = Errow.s32([2, nil, 5])
      assert Errow.product(with_nulls) == 10
      assert Errow.product(with_nulls, skip_nulls: false) == nil
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

      all_nulls = Errow.s32([nil, nil])
      assert Errow.min(all_nulls) == nil
      assert Errow.max(all_nulls) == nil
      assert Errow.min_max(all_nulls) == nil

      assert Errow.min(with_nulls, skip_nulls: false) == nil
      assert Errow.max(with_nulls, skip_nulls: false) == nil
      assert Errow.min_max(with_nulls, skip_nulls: false) == nil
    end

    test "mean/2 edge cases and empty aggregations" do
      empty = Errow.s32([])
      assert Errow.sum(empty) == 0
      assert Errow.product(empty) == 1
      assert Errow.min(empty) == nil
      assert Errow.max(empty) == nil
      assert Errow.min_max(empty) == nil
      assert Errow.mean(empty) == nil

      assert Enum.member?(empty, 42) == false
      assert Enum.slice(empty, 0, 0) == []

      {_, collector} = Collectable.into(empty)
      assert collector.({<<>>, <<>>, 0, 0}, :halt) == :ok

      # Invalid fetch key
      assert empty["invalid"] == nil

      # replace_at nil transitions
      with_nil = Errow.s32([10, nil])
      restored = Errow.Numeric.replace_at(with_nil, 1, 20)
      assert restored[1] == 20
      assert restored.null_count == 0

      assert_raise RuntimeError, fn ->
        Access.get_and_update(restored, 0, fn _ -> :invalid end)
      end

      assert Errow.mean(Errow.s32([nil, nil])) == nil
      assert Errow.mean(Errow.s32([10, 20, 30])) == 20.0
      assert Errow.mean(Errow.s32([10, nil, 20])) == 15.0
      assert Errow.mean(Errow.s32([10, nil, 20]), skip_nulls: false) == nil
    end
  end
end
