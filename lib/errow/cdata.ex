defmodule Errow.CData do
  @moduledoc """
  Utilities for exporting `Errow` arrays to the **Apache Arrow C Data Interface** specification.

  This allows zero-copy consumption by external native libraries such as:
    * **DuckDB** (`duckdb_arrow_scan`)
    * **Polars / arrow-rs** (`arrow::ffi::ArrowArray`)
    * **PyArrow** (`pyarrow.Array._import_from_c`)
    * **Custom NIFs in C, Rust, or Zig**
  """

  @doc """
  Generates the Arrow C Schema metadata map for an array.

  Returns a map containing:
    * `:format` - The Arrow C format string (e.g. `"u"`, `"z"`, `"i"`, `"l"`, `"g"`, `"d:38,0"`, `"w:32"`).
    * `:name` - Column name (defaults to empty string `""`).
    * `:flags` - Integer bitfield (`2` for nullable).
    * `:n_buffers` - Count of buffers expected (`2` for primitives, `3` for variable-length binaries/strings).
  """
  @spec export_schema(struct(), keyword()) :: map()
  def export_schema(arr, opts \\ [])

  def export_schema(%Errow.String{}, opts) do
    name = Keyword.get(opts, :name, "")
    nullable? = Keyword.get(opts, :nullable, true)

    %{
      format: "u",
      name: name,
      flags: if(nullable?, do: 2, else: 0),
      n_buffers: 3,
      data_type: :utf8
    }
  end

  def export_schema(%Errow.Binary{}, opts) do
    name = Keyword.get(opts, :name, "")
    nullable? = Keyword.get(opts, :nullable, true)

    %{
      format: "z",
      name: name,
      flags: if(nullable?, do: 2, else: 0),
      n_buffers: 3,
      data_type: :binary
    }
  end

  def export_schema(%Errow.Numeric{type: type}, opts) do
    name = Keyword.get(opts, :name, "")
    nullable? = Keyword.get(opts, :nullable, true)

    %{
      format: format_for_numeric_type(type),
      name: name,
      flags: if(nullable?, do: 2, else: 0),
      n_buffers: 2,
      data_type: type
    }
  end

  @doc """
  Exports the raw memory buffers ready to be passed to NIFs or Arrow C Data Interface.

  Returns a map with:
    * `:length` - Number of elements.
    * `:null_count` - Number of null values.
    * `:buffers` - List of binaries padded to 8-byte boundaries as per Arrow spec:
        - For `Errow.String` / `Errow.Binary`: `[validity, offsets, data]`
        - For `Errow.Numeric`: `[validity, data]`
  """
  @spec export_buffers(struct(), keyword()) :: map()
  def export_buffers(arr, opts \\ [])

  def export_buffers(%Errow.String{} = arr, opts) do
    do_export_variable_buffers(arr, opts)
  end

  def export_buffers(%Errow.Binary{} = arr, opts) do
    do_export_variable_buffers(arr, opts)
  end

  def export_buffers(%Errow.Numeric{} = arr, opts) do
    pad_to_8? = Keyword.get(opts, :pad_to_8, true)

    validity_bin = export_validity_bitmap(arr.validity, arr.length, arr.null_count, pad_to_8?)
    data_bin = if pad_to_8?, do: pad_binary_to_8(arr.data), else: arr.data

    %{
      length: arr.length,
      null_count: arr.null_count,
      buffers: [validity_bin, data_bin]
    }
  end

  # ============================================================================
  # Internal Helpers
  # ============================================================================

  defp do_export_variable_buffers(arr, opts) do
    pad_to_8? = Keyword.get(opts, :pad_to_8, true)

    validity_bin = export_validity_bitmap(arr.validity, arr.length, arr.null_count, pad_to_8?)
    offsets_bin = if pad_to_8?, do: pad_binary_to_8(arr.offsets), else: arr.offsets
    data_bin = if pad_to_8?, do: pad_binary_to_8(arr.data), else: arr.data

    %{
      length: arr.length,
      null_count: arr.null_count,
      buffers: [validity_bin, offsets_bin, data_bin]
    }
  end

  defp export_validity_bitmap(_validity, _length, 0 = _null_count, _pad?) do
    # When null_count is 0, Arrow allows Buffer 0 to be empty or null
    <<>>
  end

  defp export_validity_bitmap(validity, length, _null_count, pad_to_8?) do
    # Pad bitstring to full byte boundary first
    bit_rem = rem(length, 8)

    byte_padded =
      if bit_rem == 0, do: validity, else: <<validity::bitstring, 0::size(8 - bit_rem)>>

    if pad_to_8? do
      pad_binary_to_8(byte_padded)
    else
      byte_padded
    end
  end

  defp pad_binary_to_8(bin) when is_binary(bin) do
    size = byte_size(bin)
    pad = rem(8 - rem(size, 8), 8)
    if pad == 0, do: bin, else: <<bin::binary, 0::size(pad)-unit(8)>>
  end

  defp format_for_numeric_type(:s8), do: "c"
  defp format_for_numeric_type(:u8), do: "C"
  defp format_for_numeric_type(:s16), do: "s"
  defp format_for_numeric_type(:u16), do: "S"
  defp format_for_numeric_type(:s32), do: "i"
  defp format_for_numeric_type(:u32), do: "I"
  defp format_for_numeric_type(:s64), do: "l"
  defp format_for_numeric_type(:u64), do: "L"
  defp format_for_numeric_type(:s128), do: "d:38,0"
  defp format_for_numeric_type(:u128), do: "w:16"
  defp format_for_numeric_type(:s256), do: "d:76,0"
  defp format_for_numeric_type(:u256), do: "w:32"
  defp format_for_numeric_type(:f32), do: "f"
  defp format_for_numeric_type(:f64), do: "g"
end
