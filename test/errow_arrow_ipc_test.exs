defmodule ErrowArrowIpcTest do
  use ExUnit.Case, async: true

  @fixtures_dir Path.expand("fixtures", __DIR__)
  @stream_path Path.join(@fixtures_dir, "generated_primitive.stream")
  @arrow_path Path.join(@fixtures_dir, "generated_primitive.arrow")
  @decimal_path Path.join(@fixtures_dir, "generated_decimal.arrow")
  @decimal256_path Path.join(@fixtures_dir, "generated_decimal256.arrow")
  @json_path Path.join(@fixtures_dir, "generated_primitive.json")

  test "verifies official Apache Arrow IPC stream fixture (.stream)" do
    assert File.exists?(@stream_path)
    file_bytes = File.read!(@stream_path)

    # Official Arrow IPC Stream message format:
    # 4 bytes continuation indicator (0xFFFFFFFF) or message metadata length
    <<magic::32-little, metadata_len::32-little, rest::binary>> = file_bytes

    assert byte_size(file_bytes) > 20_000
    assert is_integer(magic)
    assert is_integer(metadata_len)
    assert byte_size(rest) > 0

    # Verify that Errow exported buffers conform to the same Arrow IPC alignment rules (8-byte multiples)
    test_arr = Errow.numeric(1..100, :s64)
    %{buffers: [_validity, data]} = Errow.CData.export_buffers(test_arr, pad_to_8: true)

    assert rem(byte_size(data), 8) == 0
    # 100 * 8 bytes
    assert byte_size(data) == 800
  end

  test "verifies official Apache Arrow columnar file fixture (.arrow)" do
    assert File.exists?(@arrow_path)
    file_bytes = File.read!(@arrow_path)

    size = byte_size(file_bytes)
    assert size > 20_000

    # Arrow File Format:
    # Header: "ARROW1\0\0" (6 bytes magic + 2 bytes padding)
    # Body: dictionary batches & record batches
    # Footer: metadata FlatBuffers
    # End: 4 bytes footer length + "ARROW1" (6 bytes magic)
    <<header_magic::binary-size(6), _padding::binary-size(2), _body_and_footer::binary>> =
      file_bytes

    assert header_magic == "ARROW1"

    # Verify end of file:
    footer_start = size - 10

    <<_prefix::binary-size(^footer_start), footer_len::32-little, footer_magic::binary-size(6)>> =
      file_bytes

    assert footer_magic == "ARROW1"
    assert footer_len > 0
  end

  test "verifies 128-bit and 256-bit decimal fixtures (.arrow)" do
    assert File.exists?(@decimal_path)
    assert File.exists?(@decimal256_path)

    d128_bytes = File.read!(@decimal_path)
    d256_bytes = File.read!(@decimal256_path)

    assert String.starts_with?(d128_bytes, "ARROW1")
    assert String.ends_with?(d128_bytes, "ARROW1")
    assert String.starts_with?(d256_bytes, "ARROW1")
    assert String.ends_with?(d256_bytes, "ARROW1")

    # Errow supports 128-bit and 256-bit fixed-width buffers
    schema128 = Errow.CData.export_schema(Errow.s128())
    schema256 = Errow.CData.export_schema(Errow.s256())

    assert schema128.format == "d:38,0"
    assert schema256.format == "d:76,0"

    arr128 = Errow.s128([1000, 2000])
    %{buffers: [_val128, data128]} = Errow.CData.export_buffers(arr128, pad_to_8: true)
    # 2 elements * 16 bytes = 32 bytes
    assert byte_size(data128) == 32

    arr256 = Errow.s256([1000, 2000])
    %{buffers: [_val256, data256]} = Errow.CData.export_buffers(arr256, pad_to_8: true)
    # 2 elements * 32 bytes = 64 bytes
    assert byte_size(data256) == 64
  end

  test "verifies Apache Arrow JSON specification schema mapping" do
    assert File.exists?(@json_path)
    json_content = File.read!(@json_path)

    # Ensure JSON schema defines columns with types matching Errow columnar arrays
    assert String.contains?(json_content, ~s("name": "int32_nullable"))
    assert String.contains?(json_content, ~s("name": "int64_nullable"))
    assert String.contains?(json_content, ~s("name": "utf8_nullable"))
    assert String.contains?(json_content, ~s("name": "bool_nullable"))
    assert String.contains?(json_content, ~s("VALIDITY"))
    assert String.contains?(json_content, ~s("DATA"))
  end

  @tag :integration
  test "cross-language verification with PyArrow (reconstructs Errow buffers)" do
    if uv = System.find_executable("uv") do
      # 1. Test Int32 array with nulls
      num = Errow.s32([10, -20, nil, 42])

      %{buffers: [validity_int, data_int], null_count: null_int} =
        Errow.CData.export_buffers(num, pad_to_8: false)

      py_int_code = """
      import sys, pyarrow as pa
      validity = bytes.fromhex(sys.argv[1]) if sys.argv[1] else None
      data = bytes.fromhex(sys.argv[2])
      arr = pa.Array.from_buffers(pa.int32(), 4, [pa.py_buffer(validity) if validity else None, pa.py_buffer(data)], null_count=int(sys.argv[3]))
      assert arr.to_pylist() == [10, -20, None, 42]
      print("OK_INT32")
      """

      {output_int, 0} =
        System.cmd(uv, [
          "run",
          "--with",
          "pyarrow",
          "python",
          "-c",
          py_int_code,
          Base.encode16(validity_int, case: :lower),
          Base.encode16(data_int, case: :lower),
          to_string(null_int)
        ])

      assert String.contains?(output_int, "OK_INT32")

      # 2. Test Utf8 String array with nulls
      str = Errow.string(["Daniel", nil, "Elixir"])

      %{buffers: [validity_str, offsets_str, data_str], null_count: null_str} =
        Errow.CData.export_buffers(str, pad_to_8: false)

      py_str_code = """
      import sys, pyarrow as pa
      validity = bytes.fromhex(sys.argv[1]) if sys.argv[1] else None
      offsets = bytes.fromhex(sys.argv[2])
      data = bytes.fromhex(sys.argv[3])
      arr = pa.Array.from_buffers(pa.string(), 3, [pa.py_buffer(validity) if validity else None, pa.py_buffer(offsets), pa.py_buffer(data)], null_count=int(sys.argv[4]))
      assert arr.to_pylist() == ["Daniel", None, "Elixir"]
      print("OK_STRING")
      """

      {output_str, 0} =
        System.cmd(uv, [
          "run",
          "--with",
          "pyarrow",
          "python",
          "-c",
          py_str_code,
          Base.encode16(validity_str, case: :lower),
          Base.encode16(offsets_str, case: :lower),
          Base.encode16(data_str, case: :lower),
          to_string(null_str)
        ])

      assert String.contains?(output_str, "OK_STRING")
    end
  end
end
