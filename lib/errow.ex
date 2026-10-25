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

  import Kernel, except: [min: 2, max: 2]

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

  # ============================================================================
  # Aggregations
  # ============================================================================

  @doc """
  Calculates the sum of elements in a numeric array.
  """
  defdelegate sum(arr, opts \\ []), to: Errow.Numeric

  @doc """
  Calculates the product of elements in a numeric array.
  """
  defdelegate product(arr, opts \\ []), to: Errow.Numeric

  @doc """
  Calculates the arithmetic mean of elements in a numeric array.
  """
  defdelegate mean(arr, opts \\ []), to: Errow.Numeric

  @doc """
  Returns `{min, max}` in a single pass.
  """
  def min_max(%Errow.Numeric{} = arr, opts \\ []), do: Errow.Numeric.min_max(arr, opts)

  @doc """
  Returns the minimum value in a numeric or string array.
  """
  def min(%Errow.Numeric{} = arr, opts), do: Errow.Numeric.min(arr, opts)
  def min(%Errow.String{} = arr, opts), do: Errow.String.min(arr, opts)
  def min(arr), do: min(arr, [])

  @doc """
  Returns the maximum value in a numeric or string array.
  """
  def max(%Errow.Numeric{} = arr, opts), do: Errow.Numeric.max(arr, opts)
  def max(%Errow.String{} = arr, opts), do: Errow.String.max(arr, opts)
  def max(arr), do: max(arr, [])

  @doc """
  Joins string elements with the given separator.
  """
  defdelegate join(arr, separator \\ "", opts \\ []), to: Errow.String
end
