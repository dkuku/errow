defmodule ErrowBinaryTest do
  use ExUnit.Case, async: true

  test "stores opaque byte blobs" do
    blob1 = <<0, 1, 2, 255>>
    blob2 = <<10, 20, 30>>

    arr = Errow.binary([blob1, blob2, nil])
    assert Errow.Binary.size(arr) == 3
    assert Errow.Binary.null_count(arr) == 1

    assert arr[0] == blob1
    assert arr[1] == blob2
    assert arr[2] == nil
  end

  test "Collectable and Enumerable for binary blobs" do
    blobs =
      for i <- 1..4, into: Errow.binary() do
        <<i::16, 255>>
      end

    assert Errow.Binary.size(blobs) == 4
    assert Enum.map(blobs, &byte_size/1) == [3, 3, 3, 3]
  end
end
