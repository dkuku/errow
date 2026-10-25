defmodule ErrowCDataTest do
  use ExUnit.Case, async: true

  test "export_schema for strings and binaries" do
    str = Errow.string(["hello", "world"])
    schema_str = Errow.CData.export_schema(str, name: "my_strings", nullable: false)
    assert schema_str.format == "u"
    assert schema_str.name == "my_strings"
    assert schema_str.n_buffers == 3
    # Non-nullable flag = 0
    assert schema_str.flags == 0

    bin = Errow.binary([<<1, 2>>])
    schema_bin = Errow.CData.export_schema(bin)
    assert schema_bin.format == "z"
    assert schema_bin.n_buffers == 3
    assert schema_bin.flags == 2
  end

  test "export_schema for all numeric types" do
    types_and_formats = [
      {:s8, "c"},
      {:u8, "C"},
      {:s16, "s"},
      {:u16, "S"},
      {:s32, "i"},
      {:u32, "I"},
      {:s64, "l"},
      {:u64, "L"},
      {:s128, "d:38,0"},
      {:u128, "w:16"},
      {:s256, "d:76,0"},
      {:u256, "w:32"},
      {:f32, "f"},
      {:f64, "g"}
    ]

    for {type, expected_format} <- types_and_formats do
      arr = Errow.numeric(type)
      schema = Errow.CData.export_schema(arr)
      assert schema.format == expected_format, "Type #{type} format mismatch"
      assert schema.n_buffers == 2
    end
  end

  test "export_buffers generates 8-byte aligned buffers" do
    str = Errow.string(["Daniel", "Kuku", "Elixir"])
    exported = Errow.CData.export_buffers(str, pad_to_8: true)

    assert exported.length == 3
    assert exported.null_count == 0

    [validity, offsets, data] = exported.buffers

    # Null count is 0, so validity buffer can be empty
    assert byte_size(validity) == 0

    # Offsets and data must be multiples of 8 bytes for Arrow alignment
    assert rem(byte_size(offsets), 8) == 0
    assert rem(byte_size(data), 8) == 0

    # Read back first two offsets
    <<off0::32-little, off1::32-little, _rest::binary>> = offsets
    assert off0 == 0
    # byte size of "Daniel"
    assert off1 == 6
  end

  test "export_buffers without 8-byte padding" do
    str = Errow.string(["Daniel", "Kuku"])
    exported = Errow.CData.export_buffers(str, pad_to_8: false)
    [validity, offsets, data] = exported.buffers

    assert validity == <<>>
    # 3 offsets * 4 bytes = 12 bytes (not 8-padded)
    assert byte_size(offsets) == 12
    # 6 + 4 = 10 bytes
    assert byte_size(data) == 10
  end

  test "export_buffers with nulls generates padded validity bitmap" do
    str = Errow.string(["Daniel", nil, "Elixir"])
    exported = Errow.CData.export_buffers(str, pad_to_8: true)

    assert exported.null_count == 1
    [validity, _offsets, _data] = exported.buffers

    # Padded to 8 bytes
    assert byte_size(validity) == 8

    # Arrow LSB-first bitmap: slot 0 is bit 0 (val 1), slot 1 is bit 1 (val 2), slot 2 is bit 2 (val 4)
    # ["Daniel", nil, "Elixir"] -> 1 + 0 + 4 = 5 (0b00000101)
    <<byte0::8, _rest::binary>> = validity
    assert Bitwise.band(byte0, 1) == 1
    assert Bitwise.band(byte0, 2) == 0
    assert Bitwise.band(byte0, 4) == 4
  end

  test "export_buffers with nulls where length is multiple of 8" do
    list = [1, 2, 3, 4, 5, 6, 7, nil]
    num = Errow.s32(list)
    exported = Errow.CData.export_buffers(num, pad_to_8: true)
    [validity, data] = exported.buffers

    assert byte_size(validity) == 8
    assert byte_size(data) == 32
    assert exported.null_count == 1
    # 7 valid items + 1 null at slot 7 (bit 7): 0b01111111 = 127
    <<byte0::8, _rest::binary>> = validity
    assert byte0 == 127
  end

  test "export_buffers for binary array" do
    bin = Errow.binary([<<1, 2>>, nil, <<3>>])
    exported = Errow.CData.export_buffers(bin, pad_to_8: true)
    assert exported.null_count == 1
    assert length(exported.buffers) == 3
  end
end
