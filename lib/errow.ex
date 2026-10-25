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
  # Typed Arrow Shorthand Constructors
  # ============================================================================

  @doc """
  Creates an empty signed 8-bit integer array (`:s8`).
  Usable directly in comprehensions: `into: Errow.s8` or `into: Errow.s8()`.
  """
  def s8(), do: Errow.Numeric.new(:s8)
  def s8(enum), do: Errow.Numeric.from_list(enum, :s8)

  @doc """
  Creates an empty unsigned 8-bit integer array (`:u8`).
  Usable directly in comprehensions: `into: Errow.u8` or `into: Errow.u8()`.
  """
  def u8(), do: Errow.Numeric.new(:u8)
  def u8(enum), do: Errow.Numeric.from_list(enum, :u8)

  @doc "Creates a signed 16-bit integer array (`:s16`)."
  def s16(), do: Errow.Numeric.new(:s16)
  def s16(enum), do: Errow.Numeric.from_list(enum, :s16)

  @doc "Creates an unsigned 16-bit integer array (`:u16`)."
  def u16(), do: Errow.Numeric.new(:u16)
  def u16(enum), do: Errow.Numeric.from_list(enum, :u16)

  @doc "Creates a signed 32-bit integer array (`:s32`)."
  def s32(), do: Errow.Numeric.new(:s32)
  def s32(enum), do: Errow.Numeric.from_list(enum, :s32)

  @doc "Creates an unsigned 32-bit integer array (`:u32`)."
  def u32(), do: Errow.Numeric.new(:u32)
  def u32(enum), do: Errow.Numeric.from_list(enum, :u32)

  @doc "Creates a signed 64-bit integer array (`:s64`)."
  def s64(), do: Errow.Numeric.new(:s64)
  def s64(enum), do: Errow.Numeric.from_list(enum, :s64)

  @doc "Creates an unsigned 64-bit integer array (`:u64`)."
  def u64(), do: Errow.Numeric.new(:u64)
  def u64(enum), do: Errow.Numeric.from_list(enum, :u64)

  @doc "Creates a signed 128-bit integer array (`:s128`)."
  def s128(), do: Errow.Numeric.new(:s128)
  def s128(enum), do: Errow.Numeric.from_list(enum, :s128)

  @doc "Creates an unsigned 128-bit integer array (`:u128`)."
  def u128(), do: Errow.Numeric.new(:u128)
  def u128(enum), do: Errow.Numeric.from_list(enum, :u128)

  @doc "Creates a signed 256-bit integer array (`:s256`)."
  def s256(), do: Errow.Numeric.new(:s256)
  def s256(enum), do: Errow.Numeric.from_list(enum, :s256)

  @doc "Creates an unsigned 256-bit integer array (`:u256`)."
  def u256(), do: Errow.Numeric.new(:u256)
  def u256(enum), do: Errow.Numeric.from_list(enum, :u256)

  @doc "Creates a 32-bit float array (`:f32`)."
  def f32(), do: Errow.Numeric.new(:f32)
  def f32(enum), do: Errow.Numeric.from_list(enum, :f32)

  @doc "Creates a 64-bit float array (`:f64`)."
  def f64(), do: Errow.Numeric.new(:f64)
  def f64(enum), do: Errow.Numeric.from_list(enum, :f64)

  # ============================================================================
  # Bit-width Aliases (numeric_8, numeric_16, etc.)
  # ============================================================================

  @doc """
  Creates an 8-bit integer array (`:s8` by default, or `:u8`).
  Usable directly in comprehensions: `into: Errow.numeric_8` or `into: Errow.numeric_8()`
  """
  def numeric_8(), do: Errow.Numeric.new(:s8)
  def numeric_8(type) when is_atom(type), do: Errow.Numeric.new(type)
  def numeric_8(enum), do: Errow.Numeric.from_list(enum, :s8)
  def numeric_8(enum, type), do: Errow.Numeric.from_list(enum, type)

  def numeric_u8(), do: Errow.Numeric.new(:u8)
  def numeric_u8(enum), do: Errow.Numeric.from_list(enum, :u8)

  def numeric_16(), do: Errow.Numeric.new(:s16)
  def numeric_16(type) when is_atom(type), do: Errow.Numeric.new(type)
  def numeric_16(enum), do: Errow.Numeric.from_list(enum, :s16)
  def numeric_16(enum, type), do: Errow.Numeric.from_list(enum, type)

  def numeric_u16(), do: Errow.Numeric.new(:u16)
  def numeric_u16(enum), do: Errow.Numeric.from_list(enum, :u16)

  def numeric_32(), do: Errow.Numeric.new(:s32)
  def numeric_32(type) when is_atom(type), do: Errow.Numeric.new(type)
  def numeric_32(enum), do: Errow.Numeric.from_list(enum, :s32)
  def numeric_32(enum, type), do: Errow.Numeric.from_list(enum, type)

  def numeric_u32(), do: Errow.Numeric.new(:u32)
  def numeric_u32(enum), do: Errow.Numeric.from_list(enum, :u32)

  def numeric_64(), do: Errow.Numeric.new(:s64)
  def numeric_64(type) when is_atom(type), do: Errow.Numeric.new(type)
  def numeric_64(enum), do: Errow.Numeric.from_list(enum, :s64)
  def numeric_64(enum, type), do: Errow.Numeric.from_list(enum, type)

  def numeric_u64(), do: Errow.Numeric.new(:u64)
  def numeric_u64(enum), do: Errow.Numeric.from_list(enum, :u64)

  def numeric_128(), do: Errow.Numeric.new(:s128)
  def numeric_128(type) when is_atom(type), do: Errow.Numeric.new(type)
  def numeric_128(enum), do: Errow.Numeric.from_list(enum, :s128)
  def numeric_128(enum, type), do: Errow.Numeric.from_list(enum, type)

  def numeric_u128(), do: Errow.Numeric.new(:u128)
  def numeric_u128(enum), do: Errow.Numeric.from_list(enum, :u128)

  def numeric_256(), do: Errow.Numeric.new(:s256)
  def numeric_256(type) when is_atom(type), do: Errow.Numeric.new(type)
  def numeric_256(enum), do: Errow.Numeric.from_list(enum, :s256)
  def numeric_256(enum, type), do: Errow.Numeric.from_list(enum, type)

  def numeric_u256(), do: Errow.Numeric.new(:u256)
  def numeric_u256(enum), do: Errow.Numeric.from_list(enum, :u256)

  def numeric_f32(), do: Errow.Numeric.new(:f32)
  def numeric_f32(enum), do: Errow.Numeric.from_list(enum, :f32)

  def numeric_f64(), do: Errow.Numeric.new(:f64)
  def numeric_f64(enum), do: Errow.Numeric.from_list(enum, :f64)

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
