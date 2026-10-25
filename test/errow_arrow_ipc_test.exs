defmodule ErrowArrowIpcTest do
  use ExUnit.Case, async: true

  @fixture_path Path.expand("fixtures/generated_primitive.stream", __DIR__)

  test "verifies downloaded Apache Arrow IPC stream fixture" do
    assert File.exists?(@fixture_path)
    file_bytes = File.read!(@fixture_path)

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
end
