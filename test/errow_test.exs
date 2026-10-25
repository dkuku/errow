defmodule ErrowTest do
  use ExUnit.Case, async: true
  doctest Errow

  test "Errow facade delegations" do
    s = Errow.string(["A", "B"])
    assert Errow.String.size(s) == 2

    b = Errow.binary([<<1>>, <<2>>])
    assert Errow.Binary.size(b) == 2

    n = Errow.numeric([10, 20], :s32)
    assert Errow.Numeric.size(n) == 2
  end

  test "comprehension into: Errow.numeric_8 without parens" do
    arr = for x <- 1..5, into: Errow.numeric_8(), do: x * 2

    assert arr.type == :s8
    assert arr.length == 5
    assert Enum.to_list(arr) == [2, 4, 6, 8, 10]
    assert Errow.sum(arr) == 30
  end

  test "comprehension into: Errow.numeric_8() with parens" do
    arr = for x <- [10, -20, 30], into: Errow.numeric_8(), do: x

    assert arr.type == :s8
    assert Enum.to_list(arr) == [10, -20, 30]
  end

  test "comprehension into typed shorthands Errow.s8 and Errow.u8" do
    s8 = for x <- [-128, 0, 127], into: Errow.s8(), do: x
    assert s8.type == :s8
    assert Enum.to_list(s8) == [-128, 0, 127]

    u8 = for x <- [0, 128, 255], into: Errow.u8(), do: x
    assert u8.type == :u8
    assert Enum.to_list(u8) == [0, 128, 255]
  end

  test "comprehensions into Errow.s32, Errow.f32, Errow.s256" do
    s32 = for x <- 1..3, into: Errow.s32(), do: x * 1000
    assert s32.type == :s32
    assert Enum.to_list(s32) == [1000, 2000, 3000]

    f32 = for x <- [1.5, 2.5], into: Errow.f32(), do: x
    assert f32.type == :f32
    assert Enum.to_list(f32) == [1.5, 2.5]

    big = for x <- [1, 2], into: Errow.s256(), do: x * 100_000_000_000_000_000_000
    assert big.type == :s256
    assert Enum.to_list(big) == [100_000_000_000_000_000_000, 200_000_000_000_000_000_000]
  end

  test "comprehensions with nil values into Errow.numeric_8" do
    arr = for x <- [1, nil, 3], into: Errow.numeric_8(), do: x
    assert arr.length == 3
    assert arr.null_count == 1
    assert Enum.to_list(arr) == [1, nil, 3]
  end

  test "comprehension into Errow.string and Errow.binary without parens" do
    s = for word <- ["hello", "arrow"], into: Errow.string(), do: String.upcase(word)
    assert s[0] == "HELLO"
    assert s[1] == "ARROW"

    b = for byte <- [1, 2], into: Errow.binary(), do: <<byte, byte + 1>>
    assert b[0] == <<1, 2>>
    assert b[1] == <<2, 3>>
  end

  test "direct constructor functions" do
    arr8 = Errow.numeric_8([-1, 0, 1])
    assert arr8.type == :s8
    assert arr8.length == 3

    arr_u8 = Errow.numeric_u8([0, 255])
    assert arr_u8.type == :u8

    arr32 = Errow.s32([10, 20])
    assert arr32.type == :s32
  end
end
