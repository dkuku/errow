defmodule ErrowBinaryTest do
  use ExUnit.Case, async: true

  test "stores opaque byte blobs and metadata" do
    blob1 = <<0, 1, 2, 255>>
    blob2 = <<10, 20, 30>>

    arr = Errow.binary([blob1, blob2, nil])
    assert Errow.Binary.size(arr) == 3
    assert Errow.Binary.null_count(arr) == 1
    assert Errow.Binary.buffer_byte_size(arr) == 7

    assert arr[0] == blob1
    assert arr[1] == blob2
    assert arr[2] == nil
    assert arr[-1] == nil
    assert arr[-2] == blob2
    assert arr[10] == nil
    assert arr["invalid"] == nil

    assert Errow.Binary.null?(arr, 2) == true
    assert Errow.Binary.null?(arr, 0) == false
    assert Errow.Binary.null?(arr, -1) == true
    assert Errow.Binary.null?(arr, 99) == false

    assert Errow.Binary.get(arr, 0) == blob1
    assert Errow.Binary.get(arr, 99, :default) == :default
  end

  test "slicing with ranges" do
    b0 = <<0>>
    b1 = <<1>>
    b2 = <<2>>
    b3 = <<3>>
    arr = Errow.binary([b0, b1, b2, b3])

    assert arr[0..1] == [b0, b1]
    assert arr[1..-1//1] == [b1, b2, b3]
    assert arr[2..0//-1] == [b2, b1, b0]
  end

  test "Access behaviour: put_in, update_in, pop" do
    arr = Errow.binary([<<1>>, <<2>>, <<3>>])

    arr2 = put_in(arr[1], <<99, 100>>)
    assert arr2[1] == <<99, 100>>
    assert Errow.Binary.size(arr2) == 3

    arr3 = update_in(arr[0], fn val -> <<val::binary, 42>> end)
    assert arr3[0] == <<1, 42>>

    {popped, rest} = pop_in(arr[1])
    assert popped == <<2>>
    assert Errow.Binary.size(rest) == 2
    assert Enum.to_list(rest) == [<<1>>, <<3>>]

    # Out of bounds pop returns nil
    assert Access.pop(arr, 99) == {nil, arr}
  end

  test "replace_at and delete_at" do
    arr = Errow.binary([<<1>>, <<2>>, <<3>>])

    arr2 = Errow.Binary.replace_at(arr, 1, nil)
    assert arr2[1] == nil
    assert arr2.null_count == 1

    arr3 = Errow.Binary.delete_at(arr, 0)
    assert arr3.length == 2
    assert Enum.to_list(arr3) == [<<2>>, <<3>>]

    # Out of bounds delete raises ArgumentError
    assert_raise ArgumentError, fn -> Errow.Binary.delete_at(arr, 100) end
  end

  test "Collectable and Enumerable for binary blobs" do
    blobs =
      for i <- 1..4, into: Errow.binary() do
        <<i::16, 255>>
      end

    assert Errow.Binary.size(blobs) == 4
    assert Enum.map(blobs, &byte_size/1) == [3, 3, 3, 3]
    assert Enum.count(blobs) == 4
    assert Enum.member?(blobs, <<1::16, 255>>) == true
    assert Enum.member?(blobs, <<99::16, 255>>) == false

    # Enum.slice
    assert Enum.slice(blobs, 1, 2) == [<<2::16, 255>>, <<3::16, 255>>]

    # Early halt in reduce
    first_two = Enum.take(blobs, 2)
    assert length(first_two) == 2
  end

  test "Inspect representation" do
    small = Errow.binary([<<1>>, <<2>>])
    inspect_small = inspect(small)
    assert inspect_small =~ "#Errow.Binary<"
    assert inspect_small =~ "<<1>>"

    big = Errow.binary(for(i <- 1..10, do: <<i, i>>))
    inspect_big = inspect(big)
    assert inspect_big =~ "total 10 items"

    assert Enum.member?(Errow.binary(), <<1>>) == false

    {_, collector} = Collectable.into(Errow.binary())
    assert collector.({<<>>, <<>>, <<>>, 0, 0, 0}, :halt) == :ok

    # replace_at nil transitions
    with_nil = Errow.binary([<<1>>, nil])
    restored = Errow.Binary.replace_at(with_nil, 1, <<2>>)
    assert restored[1] == <<2>>
    assert restored.null_count == 0

    assert_raise RuntimeError, fn ->
      Access.get_and_update(restored, 0, fn _ -> :invalid end)
    end
  end
end
