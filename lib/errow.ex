defmodule Errow do
  @moduledoc """
  `Errow` - Zero-copy, Apache Arrow-compliant packed arrays for Elixir and the BEAM.

  `Errow` provides columnar in-memory arrays backed by continuous BEAM binaries,
  fully integrated with standard Elixir protocols (`Enumerable`, `Collectable`, `Access`),
  and 100% byte-for-byte compliant with the **Apache Arrow Columnar Specification** and
  **Arrow C Data Interface**.

  ## Modules
  * `Errow.String`: UTF-8 variable-length string arrays (Arrow `Utf8` / VARCHAR).
  * `Errow.Binary`: Opaque raw byte blob arrays (Arrow `Binary` / BLOB).
  * `Errow.Numeric`: Fixed-width primitive arrays (`:s8`..`:s256`, `:u8`..`:u256`, `:f32`, `:f64`).
  * `Errow.CData`: Exporters for Arrow C Data Interface (`ArrowArray` / `ArrowSchema` metadata and buffers).

  ## Quick Examples

  ### Strings & Comprehensions (`Collectable` + `Enumerable`)
      iex> arr = for name <- ["Elixir", "Arrow", "BEAM"], into: Errow.string() do
      ...>   String.upcase(name)
      ...> end
      iex> arr[0]
      "ELIXIR"
      iex> arr[-1]
      "BEAM"
      iex> arr[0..1]
      ["ELIXIR", "ARROW"]

  ### Numerics with 128-bit / 256-bit BigInt Support
      iex> num = Errow.numeric([10, 20, 30], :s32)
      iex> Enum.sum(num)
      60
      iex> put_in(num[1], 99)[1]
      99

  ### Zero-Copy Arrow Export
      iex> arr = Errow.string(["Elixir", "Arrow"])
      iex> schema = Errow.CData.export_schema(arr)
      iex> schema.format
      "u"
      iex> %{buffers: [_validity, _offsets, _data]} = Errow.CData.export_buffers(arr)
  """

  @doc """
  Creates a new empty `Errow.String` array.
  """
  defdelegate string(), to: Errow.String, as: :new

  @doc """
  Builds an `Errow.String` array from an enumerable.
  """
  defdelegate string(enumerable), to: Errow.String, as: :from_list

  @doc """
  Creates a new empty `Errow.Binary` array.
  """
  defdelegate binary(), to: Errow.Binary, as: :new

  @doc """
  Builds an `Errow.Binary` array from an enumerable.
  """
  defdelegate binary(enumerable), to: Errow.Binary, as: :from_list

  @doc """
  Creates a new empty `Errow.Numeric` array of the given type (default `:s64`).
  """
  defdelegate numeric(type \\ :s64), to: Errow.Numeric, as: :new

  @doc """
  Builds an `Errow.Numeric` array from an enumerable of numbers and optional `nil`s.
  """
  defdelegate numeric(enumerable, type), to: Errow.Numeric, as: :from_list
end
