defmodule ErrowCDataTest do
  use ExUnit.Case, async: true

  test "export_schema for strings and binaries" do
    str = Errow.string(["hello", "world"])
    schema_str = Errow.CData.export_schema(str, name: "my_strings")
    assert schema_str.format == "u"
    assert schema_str.name == "my_strings"
    assert schema_str.n_buffers == 3
    # Nullable
    assert schema_str.flags == 2

    bin = Errow.binary([<<1, 2>>])
    schema_bin = Errow.CData.export_schema(bin)
    assert schema_bin.format == "z"
    assert schema_bin.n_buffers == 3
  end

  test "export_schema for numeric types" do
    assert Errow.CData.export_schema(Errow.numeric(:s32)).format == "i"
    assert Errow.CData.export_schema(Errow.numeric(:s64)).format == "l"
    assert Errow.CData.export_schema(Errow.numeric(:f64)).format == "g"
    assert Errow.CData.export_schema(Errow.numeric(:s128)).format == "d:38,0"
    assert Errow.CData.export_schema(Errow.numeric(:u256)).format == "w:32"
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

  test "export_buffers with nulls generates padded validity bitmap" do
    str = Errow.string(["Daniel", nil, "Elixir"])
    exported = Errow.CData.export_buffers(str, pad_to_8: true)

    assert exported.null_count == 1
    [validity, _offsets, _data] = exported.buffers

    # Padded to 8 bytes
    assert byte_size(validity) == 8

    # First bit = 1, second bit = 0, third bit = 1
    <<b0::1, b1::1, b2::1, _rest::bitstring>> = validity
    assert b0 == 1
    assert b1 == 0
    assert b2 == 1
  end
end
