defmodule Errow.Numeric do
  @moduledoc """
  An immutable, continuous-memory numerical array implementing the Apache Arrow Primitive columnar format.

  Under the hood, data is organized in two buffers:
    1. **Data buffer** (`data`): a continuous binary of fixed-width numbers in little-endian.
    2. **Validity bitmap** (`validity`): a bitstring tracking null (`nil`) values (1 bit per element).

  ## Supported Types
  * Signed Integers: `:s8, :s16, :s32, :s64, :s128, :s256`
  * Unsigned Integers: `:u8, :u16, :u32, :u64, :u128, :u256`
  * Floating Point: `:f32, :f64`

  Notice that `:s128`, `:u128`, `:s256`, and `:u256` are natively supported in little-endian binary format,
  mapping directly to Arrow `Decimal128`, `Decimal256`, and `FixedSizeBinary`.
  """

  @behaviour Access

  @valid_types [
    :s8,
    :u8,
    :s16,
    :u16,
    :s32,
    :u32,
    :s64,
    :u64,
    :s128,
    :u128,
    :s256,
    :u256,
    :f32,
    :f64
  ]

  @type numeric_type ::
          :s8
          | :u8
          | :s16
          | :u16
          | :s32
          | :u32
          | :s64
          | :u64
          | :s128
          | :u128
          | :s256
          | :u256
          | :f32
          | :f64

  @type t :: %__MODULE__{
          type: numeric_type(),
          item_size: pos_integer(),
          validity: bitstring(),
          data: binary(),
          length: non_neg_integer(),
          null_count: non_neg_integer()
        }

  defstruct [
    :type,
    :item_size,
    validity: <<>>,
    data: <<>>,
    length: 0,
    null_count: 0
  ]

  @doc """
  Creates a new empty `Errow.Numeric` array of the given type (defaults to `:s64`).
  """
  @spec new(numeric_type()) :: t()
  def new(type \\ :s64) when type in @valid_types do
    %__MODULE__{
      type: type,
      item_size: byte_size_for_type(type),
      validity: <<>>,
      data: <<>>,
      length: 0,
      null_count: 0
    }
  end

  @doc """
  Builds an `Errow.Numeric` array from a list or enumerable of numbers and optional `nil`s.
  """
  @spec from_list(Enumerable.t(), numeric_type()) :: t()
  def from_list(enumerable, type \\ :s64) do
    Enum.into(enumerable, new(type))
  end

  @doc """
  Appends a number or `nil` to the array.
  """
  @spec append(t(), number() | nil) :: t()
  def append(%__MODULE__{} = arr, nil) do
    zero_bytes = <<0::size(arr.item_size * 8)>>

    %__MODULE__{
      arr
      | validity: <<arr.validity::bitstring, 0::1>>,
        data: <<arr.data::binary, zero_bytes::binary>>,
        length: arr.length + 1,
        null_count: arr.null_count + 1
    }
  end

  def append(%__MODULE__{type: type} = arr, val) when is_number(val) do
    bin_val = encode_value(val, type)

    %__MODULE__{
      arr
      | validity: <<arr.validity::bitstring, 1::1>>,
        data: <<arr.data::binary, bin_val::binary>>,
        length: arr.length + 1
    }
  end

  @doc """
  Returns the number of elements in the array.
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{length: len}), do: len

  @doc """
  Returns the byte size of the continuous data buffer.
  """
  @spec buffer_byte_size(t()) :: non_neg_integer()
  def buffer_byte_size(%__MODULE__{data: data}), do: byte_size(data)

  @doc """
  Returns the count of null values.
  """
  @spec null_count(t()) :: non_neg_integer()
  def null_count(%__MODULE__{null_count: count}), do: count

  @doc """
  Checks if the value at the given index is null (`nil`).
  """
  @spec null?(t(), integer()) :: boolean()
  def null?(%__MODULE__{length: len, validity: validity}, idx) when is_integer(idx) do
    norm_idx = normalize_index(idx, len)

    if norm_idx do
      <<_::bitstring-size(^norm_idx), bit::1, _::bitstring>> = validity
      bit == 0
    else
      false
    end
  end

  @doc """
  Fetches the element at the given index or a slice specified by a range.
  Supports negative indices (e.g. `-1` for the last element).
  """
  @spec fetch(t(), integer() | Range.t()) :: {:ok, number() | nil | list()} | :error
  @impl Access
  def fetch(%__MODULE__{length: len} = arr, idx) when is_integer(idx) do
    norm_idx = normalize_index(idx, len)

    if norm_idx do
      <<_::bitstring-size(^norm_idx), bit::1, _::bitstring>> = arr.validity

      if bit == 0 do
        {:ok, nil}
      else
        offset = norm_idx * arr.item_size
        raw_bytes = binary_part(arr.data, offset, arr.item_size)
        {:ok, decode_value(raw_bytes, arr.type)}
      end
    else
      :error
    end
  end

  @impl Access
  def fetch(%__MODULE__{length: len} = arr, first..last//step) do
    norm_first = if first < 0, do: len + first, else: first
    norm_last = if last < 0, do: len + last, else: last

    actual_step =
      cond do
        norm_first <= norm_last and step < 0 and last < 0 and first >= 0 -> 1
        norm_first >= norm_last and step > 0 and first < 0 and last >= 0 -> -1
        true -> step
      end

    indices = Range.new(norm_first, norm_last, actual_step)
    result = for i <- indices, i >= 0 and i < len, do: get(arr, i)
    {:ok, result}
  end

  @impl Access
  def fetch(_arr, _other), do: :error

  @doc """
  Gets the value at index `idx` or returns `default` if out of bounds.
  """
  @spec get(t(), integer(), any()) :: number() | nil | any()
  def get(arr, idx, default \\ nil) do
    case fetch(arr, idx) do
      {:ok, val} -> val
      :error -> default
    end
  end

  @doc """
  Replaces the element at the given index with a new number or `nil`.
  """
  @spec replace_at(t(), integer(), number() | nil) :: t()
  def replace_at(%__MODULE__{length: len} = arr, idx, new_val) when is_integer(idx) do
    norm_idx = normalize_index(idx, len)

    unless norm_idx do
      raise ArgumentError, "index #{idx} out of bounds for array of size #{len}"
    end

    case fetch(arr, norm_idx) do
      {:ok, ^new_val} ->
        arr

      {:ok, old_val} ->
        do_replace_at(arr, norm_idx, old_val, new_val)
    end
  end

  @doc """
  Deletes the element at index `idx`.
  """
  @spec delete_at(t(), integer()) :: t()
  def delete_at(%__MODULE__{length: len} = arr, idx) when is_integer(idx) do
    norm_idx = normalize_index(idx, len)

    unless norm_idx do
      raise ArgumentError, "index #{idx} out of bounds for array of size #{len}"
    end

    {:ok, old_val} = fetch(arr, norm_idx)
    do_delete_at(arr, norm_idx, old_val)
  end

  @doc """
  Converts the `Errow.Numeric` array into a standard Elixir list.
  """
  @spec to_list(t()) :: [number() | nil]
  def to_list(%__MODULE__{length: len} = arr) do
    for i <- 0..(len - 1)//1, len > 0, do: get(arr, i)
  end

  # ============================================================================
  # Aggregations (Native zero-overhead continuous binary reduction)
  # ============================================================================

  @doc """
  Calculates the sum of elements in the array.
  Options:
    * `:skip_nulls` - boolean, defaults to `true`.
  """
  @spec sum(t(), keyword()) :: number() | nil
  def sum(arr, opts \\ [])
  def sum(%__MODULE__{length: 0}, _opts), do: 0

  def sum(%__MODULE__{null_count: count} = arr, opts) when count > 0 do
    if Keyword.get(opts, :skip_nulls, true) do
      reduce_with_validity(arr, 0, fn val, acc -> acc + val end)
    else
      nil
    end
  end

  def sum(%__MODULE__{data: data, type: type}, _opts) do
    do_sum(data, type, 0)
  end

  @doc """
  Calculates the product of elements in the array.
  Options:
    * `:skip_nulls` - boolean, defaults to `true`.
  """
  @spec product(t(), keyword()) :: number() | nil
  def product(arr, opts \\ [])
  def product(%__MODULE__{length: 0}, _opts), do: 1

  def product(%__MODULE__{null_count: count} = arr, opts) when count > 0 do
    if Keyword.get(opts, :skip_nulls, true) do
      reduce_with_validity(arr, 1, fn val, acc -> acc * val end)
    else
      nil
    end
  end

  def product(%__MODULE__{data: data, type: type}, _opts) do
    do_product(data, type, 1)
  end

  @doc """
  Finds the minimum value in the array.
  """
  @spec min(t(), keyword()) :: number() | nil
  def min(arr, opts \\ [])
  def min(%__MODULE__{length: 0}, _opts), do: nil

  def min(%__MODULE__{null_count: count} = arr, opts) when count > 0 do
    if Keyword.get(opts, :skip_nulls, true) do
      case reduce_with_validity(arr, :none, fn val, acc ->
             if acc == :none, do: val, else: Kernel.min(acc, val)
           end) do
        :none -> nil
        res -> res
      end
    else
      nil
    end
  end

  def min(%__MODULE__{data: data, type: type, item_size: size}, _opts) do
    <<first_chunk::binary-size(^size), rest::binary>> = data
    first_val = decode_value(first_chunk, type)
    do_min(rest, type, first_val)
  end

  @doc """
  Finds the maximum value in the array.
  """
  @spec max(t(), keyword()) :: number() | nil
  def max(arr, opts \\ [])
  def max(%__MODULE__{length: 0}, _opts), do: nil

  def max(%__MODULE__{null_count: count} = arr, opts) when count > 0 do
    if Keyword.get(opts, :skip_nulls, true) do
      case reduce_with_validity(arr, :none, fn val, acc ->
             if acc == :none, do: val, else: Kernel.max(acc, val)
           end) do
        :none -> nil
        res -> res
      end
    else
      nil
    end
  end

  def max(%__MODULE__{data: data, type: type, item_size: size}, _opts) do
    <<first_chunk::binary-size(^size), rest::binary>> = data
    first_val = decode_value(first_chunk, type)
    do_max(rest, type, first_val)
  end

  @doc """
  Returns a `{min, max}` tuple in a single pass over the array.
  """
  @spec min_max(t(), keyword()) :: {number(), number()} | nil
  def min_max(arr, opts \\ [])
  def min_max(%__MODULE__{length: 0}, _opts), do: nil

  def min_max(%__MODULE__{null_count: count} = arr, opts) when count > 0 do
    if Keyword.get(opts, :skip_nulls, true) do
      case reduce_with_validity(arr, :none, fn val, acc ->
             case acc do
               :none -> {val, val}
               {min_v, max_v} -> {Kernel.min(min_v, val), Kernel.max(max_v, val)}
             end
           end) do
        :none -> nil
        res -> res
      end
    else
      nil
    end
  end

  def min_max(%__MODULE__{data: data, type: type, item_size: size}, _opts) do
    <<first_chunk::binary-size(^size), rest::binary>> = data
    first_val = decode_value(first_chunk, type)
    do_min_max(rest, type, first_val, first_val)
  end

  @doc """
  Calculates the arithmetic mean (average) of the elements as a float.
  """
  @spec mean(t(), keyword()) :: float() | nil
  def mean(arr, opts \\ [])
  def mean(%__MODULE__{length: 0}, _opts), do: nil

  def mean(%__MODULE__{length: len, null_count: nulls} = arr, opts) do
    valid_count = len - nulls

    if valid_count > 0 do
      sum_val = sum(arr, opts)
      if is_nil(sum_val), do: nil, else: sum_val / valid_count
    else
      nil
    end
  end

  # ============================================================================
  # Access Behaviour
  # ============================================================================

  @impl Access
  def get_and_update(%__MODULE__{length: len} = arr, idx, fun) when is_integer(idx) do
    norm_idx = normalize_index(idx, len)

    unless norm_idx do
      raise ArgumentError, "index #{idx} out of bounds for array of size #{len}"
    end

    {:ok, current_val} = fetch(arr, norm_idx)

    case fun.(current_val) do
      {get_val, new_val} when is_number(new_val) or is_nil(new_val) ->
        {get_val, replace_at(arr, norm_idx, new_val)}

      :pop ->
        pop(arr, norm_idx)

      other ->
        raise "Access callback fun must return {get_value, new_value} or :pop, got: #{inspect(other)}"
    end
  end

  @impl Access
  def pop(%__MODULE__{length: len} = arr, idx) when is_integer(idx) do
    norm_idx = normalize_index(idx, len)

    if norm_idx do
      {:ok, current_val} = fetch(arr, norm_idx)
      {current_val, delete_at(arr, norm_idx)}
    else
      {nil, arr}
    end
  end

  # ============================================================================
  # Internal Helpers & Encoding/Decoding
  # ============================================================================

  defp normalize_index(idx, len) do
    norm = if idx < 0, do: len + idx, else: idx
    if norm >= 0 and norm < len, do: norm, else: nil
  end

  defp do_replace_at(%__MODULE__{} = arr, idx, old_val, new_val) do
    <<val_before::bitstring-size(^idx), _old_bit::1, val_after::bitstring>> = arr.validity
    new_bit = if is_nil(new_val), do: 0, else: 1
    new_validity = <<val_before::bitstring, new_bit::1, val_after::bitstring>>

    offset = idx * arr.item_size
    data_before = binary_part(arr.data, 0, offset)

    data_after =
      binary_part(
        arr.data,
        offset + arr.item_size,
        byte_size(arr.data) - (offset + arr.item_size)
      )

    new_bin =
      if is_nil(new_val) do
        <<0::size(arr.item_size * 8)>>
      else
        encode_value(new_val, arr.type)
      end

    updated_data = <<data_before::binary, new_bin::binary, data_after::binary>>

    new_null_count =
      cond do
        is_nil(old_val) and not is_nil(new_val) -> arr.null_count - 1
        not is_nil(old_val) and is_nil(new_val) -> arr.null_count + 1
        true -> arr.null_count
      end

    %__MODULE__{
      arr
      | validity: new_validity,
        data: updated_data,
        null_count: new_null_count
    }
  end

  defp do_delete_at(%__MODULE__{} = arr, idx, _old_val) do
    <<val_before::bitstring-size(^idx), old_bit::1, val_after::bitstring>> = arr.validity
    new_validity = <<val_before::bitstring, val_after::bitstring>>

    offset = idx * arr.item_size
    data_before = binary_part(arr.data, 0, offset)

    data_after =
      binary_part(
        arr.data,
        offset + arr.item_size,
        byte_size(arr.data) - (offset + arr.item_size)
      )

    updated_data = <<data_before::binary, data_after::binary>>

    new_null_count = if old_bit == 0, do: arr.null_count - 1, else: arr.null_count

    %__MODULE__{
      arr
      | validity: new_validity,
        data: updated_data,
        length: arr.length - 1,
        null_count: new_null_count
    }
  end

  defp byte_size_for_type(:s8), do: 1
  defp byte_size_for_type(:u8), do: 1
  defp byte_size_for_type(:s16), do: 2
  defp byte_size_for_type(:u16), do: 2
  defp byte_size_for_type(:s32), do: 4
  defp byte_size_for_type(:u32), do: 4
  defp byte_size_for_type(:s64), do: 8
  defp byte_size_for_type(:u64), do: 8
  defp byte_size_for_type(:s128), do: 16
  defp byte_size_for_type(:u128), do: 16
  defp byte_size_for_type(:s256), do: 32
  defp byte_size_for_type(:u256), do: 32
  defp byte_size_for_type(:f32), do: 4
  defp byte_size_for_type(:f64), do: 8

  # Encoders
  @doc false
  def encoder_for(:s8), do: fn val when val >= -128 and val <= 127 -> <<val::8-little-signed>> end
  def encoder_for(:u8), do: fn val when val >= 0 and val <= 255 -> <<val::8-little-unsigned>> end

  def encoder_for(:s16),
    do: fn val when val >= -32768 and val <= 32767 -> <<val::16-little-signed>> end

  def encoder_for(:u16),
    do: fn val when val >= 0 and val <= 65535 -> <<val::16-little-unsigned>> end

  def encoder_for(:s32),
    do: fn val when val >= -2_147_483_648 and val <= 2_147_483_647 ->
      <<val::32-little-signed>>
    end

  def encoder_for(:u32),
    do: fn val when val >= 0 and val <= 4_294_967_295 -> <<val::32-little-unsigned>> end

  def encoder_for(:s64),
    do: fn
      val when val >= -9_223_372_036_854_775_808 and val <= 9_223_372_036_854_775_807 ->
        <<val::64-little-signed>>
    end

  def encoder_for(:u64),
    do: fn val when val >= 0 and val <= 18_446_744_073_709_551_615 ->
      <<val::64-little-unsigned>>
    end

  def encoder_for(:s128),
    do: fn
      val
      when val >= -0x80000000000000000000000000000000 and
             val <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF ->
        <<val::128-little-signed>>
    end

  def encoder_for(:u128),
    do: fn val when val >= 0 and val <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF ->
      <<val::128-little-unsigned>>
    end

  def encoder_for(:s256),
    do: fn
      val
      when val >= -0x8000000000000000000000000000000000000000000000000000000000000000 and
             val <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF ->
        <<val::256-little-signed>>
    end

  def encoder_for(:u256),
    do: fn
      val
      when val >= 0 and val <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF ->
        <<val::256-little-unsigned>>
    end

  def encoder_for(:f32), do: fn val -> <<:erlang.float(val)::32-little-float>> end
  def encoder_for(:f64), do: fn val -> <<:erlang.float(val)::64-little-float>> end

  # Encoding
  @doc false
  def encode_value(val, :s8) when val >= -128 and val <= 127, do: <<val::8-little-signed>>
  def encode_value(val, :u8) when val >= 0 and val <= 255, do: <<val::8-little-unsigned>>
  def encode_value(val, :s16) when val >= -32768 and val <= 32767, do: <<val::16-little-signed>>
  def encode_value(val, :u16) when val >= 0 and val <= 65535, do: <<val::16-little-unsigned>>

  def encode_value(val, :s32) when val >= -2_147_483_648 and val <= 2_147_483_647,
    do: <<val::32-little-signed>>

  def encode_value(val, :u32) when val >= 0 and val <= 4_294_967_295,
    do: <<val::32-little-unsigned>>

  def encode_value(val, :s64)
      when val >= -9_223_372_036_854_775_808 and val <= 9_223_372_036_854_775_807,
      do: <<val::64-little-signed>>

  def encode_value(val, :u64) when val >= 0 and val <= 18_446_744_073_709_551_615,
    do: <<val::64-little-unsigned>>

  def encode_value(val, :s128)
      when val >= -0x80000000000000000000000000000000 and
             val <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
      do: <<val::128-little-signed>>

  def encode_value(val, :u128) when val >= 0 and val <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
    do: <<val::128-little-unsigned>>

  def encode_value(val, :s256)
      when val >= -0x8000000000000000000000000000000000000000000000000000000000000000 and
             val <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
      do: <<val::256-little-signed>>

  def encode_value(val, :u256)
      when val >= 0 and val <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
      do: <<val::256-little-unsigned>>

  def encode_value(val, :f32), do: <<:erlang.float(val)::32-little-float>>
  def encode_value(val, :f64), do: <<:erlang.float(val)::64-little-float>>

  def encode_value(val, type) do
    raise ArgumentError,
          "value #{inspect(val)} is invalid or out of bounds for numeric type #{inspect(type)}"
  end

  # Decoding
  defp decode_value(<<val::8-little-signed>>, :s8), do: val
  defp decode_value(<<val::8-little-unsigned>>, :u8), do: val
  defp decode_value(<<val::16-little-signed>>, :s16), do: val
  defp decode_value(<<val::16-little-unsigned>>, :u16), do: val
  defp decode_value(<<val::32-little-signed>>, :s32), do: val
  defp decode_value(<<val::32-little-unsigned>>, :u32), do: val
  defp decode_value(<<val::64-little-signed>>, :s64), do: val
  defp decode_value(<<val::64-little-unsigned>>, :u64), do: val
  defp decode_value(<<val::128-little-signed>>, :s128), do: val
  defp decode_value(<<val::128-little-unsigned>>, :u128), do: val
  defp decode_value(<<val::256-little-signed>>, :s256), do: val
  defp decode_value(<<val::256-little-unsigned>>, :u256), do: val
  defp decode_value(<<val::32-little-float>>, :f32), do: val
  defp decode_value(<<val::64-little-float>>, :f64), do: val

  # Aggregation loops
  defp reduce_with_validity(
         %__MODULE__{
           data: data,
           validity: validity,
           type: type,
           item_size: size,
           length: len
         },
         initial,
         fun
       ) do
    do_reduce_validity(validity, data, type, size, 0, len, initial, fun)
  end

  defp do_reduce_validity(_validity, _data, _type, _size, idx, len, acc, _fun) when idx >= len,
    do: acc

  defp do_reduce_validity(
         <<0::1, val_rest::bitstring>>,
         data,
         type,
         size,
         idx,
         len,
         acc,
         fun
       ) do
    <<_chunk::binary-size(^size), data_rest::binary>> = data
    do_reduce_validity(val_rest, data_rest, type, size, idx + 1, len, acc, fun)
  end

  defp do_reduce_validity(
         <<1::1, val_rest::bitstring>>,
         data,
         type,
         size,
         idx,
         len,
         acc,
         fun
       ) do
    <<chunk::binary-size(^size), data_rest::binary>> = data
    val = decode_value(chunk, type)
    do_reduce_validity(val_rest, data_rest, type, size, idx + 1, len, fun.(val, acc), fun)
  end

  # do_sum
  defp do_sum(<<>>, _type, acc), do: acc
  defp do_sum(<<x::8-little-signed, rest::binary>>, :s8, acc), do: do_sum(rest, :s8, acc + x)
  defp do_sum(<<x::8-little-unsigned, rest::binary>>, :u8, acc), do: do_sum(rest, :u8, acc + x)
  defp do_sum(<<x::16-little-signed, rest::binary>>, :s16, acc), do: do_sum(rest, :s16, acc + x)
  defp do_sum(<<x::16-little-unsigned, rest::binary>>, :u16, acc), do: do_sum(rest, :u16, acc + x)
  defp do_sum(<<x::32-little-signed, rest::binary>>, :s32, acc), do: do_sum(rest, :s32, acc + x)
  defp do_sum(<<x::32-little-unsigned, rest::binary>>, :u32, acc), do: do_sum(rest, :u32, acc + x)
  defp do_sum(<<x::64-little-signed, rest::binary>>, :s64, acc), do: do_sum(rest, :s64, acc + x)
  defp do_sum(<<x::64-little-unsigned, rest::binary>>, :u64, acc), do: do_sum(rest, :u64, acc + x)

  defp do_sum(<<x::128-little-signed, rest::binary>>, :s128, acc),
    do: do_sum(rest, :s128, acc + x)

  defp do_sum(<<x::128-little-unsigned, rest::binary>>, :u128, acc),
    do: do_sum(rest, :u128, acc + x)

  defp do_sum(<<x::256-little-signed, rest::binary>>, :s256, acc),
    do: do_sum(rest, :s256, acc + x)

  defp do_sum(<<x::256-little-unsigned, rest::binary>>, :u256, acc),
    do: do_sum(rest, :u256, acc + x)

  defp do_sum(<<x::32-little-float, rest::binary>>, :f32, acc), do: do_sum(rest, :f32, acc + x)
  defp do_sum(<<x::64-little-float, rest::binary>>, :f64, acc), do: do_sum(rest, :f64, acc + x)

  # do_product
  defp do_product(<<>>, _type, acc), do: acc

  defp do_product(<<x::8-little-signed, rest::binary>>, :s8, acc),
    do: do_product(rest, :s8, acc * x)

  defp do_product(<<x::8-little-unsigned, rest::binary>>, :u8, acc),
    do: do_product(rest, :u8, acc * x)

  defp do_product(<<x::16-little-signed, rest::binary>>, :s16, acc),
    do: do_product(rest, :s16, acc * x)

  defp do_product(<<x::16-little-unsigned, rest::binary>>, :u16, acc),
    do: do_product(rest, :u16, acc * x)

  defp do_product(<<x::32-little-signed, rest::binary>>, :s32, acc),
    do: do_product(rest, :s32, acc * x)

  defp do_product(<<x::32-little-unsigned, rest::binary>>, :u32, acc),
    do: do_product(rest, :u32, acc * x)

  defp do_product(<<x::64-little-signed, rest::binary>>, :s64, acc),
    do: do_product(rest, :s64, acc * x)

  defp do_product(<<x::64-little-unsigned, rest::binary>>, :u64, acc),
    do: do_product(rest, :u64, acc * x)

  defp do_product(<<x::128-little-signed, rest::binary>>, :s128, acc),
    do: do_product(rest, :s128, acc * x)

  defp do_product(<<x::128-little-unsigned, rest::binary>>, :u128, acc),
    do: do_product(rest, :u128, acc * x)

  defp do_product(<<x::256-little-signed, rest::binary>>, :s256, acc),
    do: do_product(rest, :s256, acc * x)

  defp do_product(<<x::256-little-unsigned, rest::binary>>, :u256, acc),
    do: do_product(rest, :u256, acc * x)

  defp do_product(<<x::32-little-float, rest::binary>>, :f32, acc),
    do: do_product(rest, :f32, acc * x)

  defp do_product(<<x::64-little-float, rest::binary>>, :f64, acc),
    do: do_product(rest, :f64, acc * x)

  # do_min / do_max / do_min_max
  defp do_min(<<>>, _type, acc), do: acc

  defp do_min(data, type, acc) do
    size = byte_size_for_type(type)
    <<chunk::binary-size(^size), rest::binary>> = data
    val = decode_value(chunk, type)
    do_min(rest, type, Kernel.min(acc, val))
  end

  defp do_max(<<>>, _type, acc), do: acc

  defp do_max(data, type, acc) do
    size = byte_size_for_type(type)
    <<chunk::binary-size(^size), rest::binary>> = data
    val = decode_value(chunk, type)
    do_max(rest, type, Kernel.max(acc, val))
  end

  defp do_min_max(<<>>, _type, min_acc, max_acc), do: {min_acc, max_acc}

  defp do_min_max(data, type, min_acc, max_acc) do
    size = byte_size_for_type(type)
    <<chunk::binary-size(^size), rest::binary>> = data
    val = decode_value(chunk, type)
    do_min_max(rest, type, Kernel.min(min_acc, val), Kernel.max(max_acc, val))
  end
end

# ==============================================================================
# Protocol Implementations
# ==============================================================================

defimpl Enumerable, for: Errow.Numeric do
  def count(%Errow.Numeric{length: len}), do: {:ok, len}

  def member?(%Errow.Numeric{length: 0}, _elem), do: {:ok, false}

  def member?(%Errow.Numeric{} = arr, element) do
    found? =
      reduce(arr, {:cont, false}, fn
        item, _acc when item == element -> {:halt, true}
        _item, acc -> {:cont, acc}
      end)

    case found? do
      {:done, res} -> {:ok, res}
      {:halted, res} -> {:ok, res}
    end
  end

  def slice(%Errow.Numeric{length: len} = arr) do
    slicing_fun = fn start, amount, step ->
      for idx <- start..(start + (amount - 1) * step)//step, idx >= 0 and idx < len do
        Errow.Numeric.get(arr, idx)
      end
    end

    {:ok, len, slicing_fun}
  end

  def reduce(%Errow.Numeric{length: len} = arr, acc, fun) do
    do_reduce(arr, acc, fun, 0, len)
  end

  defp do_reduce(_arr, {:cont, acc}, _fun, idx, len) when idx >= len do
    {:done, acc}
  end

  defp do_reduce(_arr, {:halt, acc}, _fun, _idx, _len) do
    {:halted, acc}
  end

  defp do_reduce(arr, {:suspend, acc}, fun, idx, len) do
    {:suspended, acc, &do_reduce(arr, &1, fun, idx, len)}
  end

  defp do_reduce(arr, {:cont, acc}, fun, idx, len) do
    val = Errow.Numeric.get(arr, idx)
    do_reduce(arr, fun.(val, acc), fun, idx + 1, len)
  end
end

defimpl Collectable, for: Errow.Numeric do
  def into(%Errow.Numeric{type: type, item_size: item_size} = original) do
    zero_bytes = <<0::size(item_size * 8)>>
    encoder = Errow.Numeric.encoder_for(type)

    collector_fun = fn
      {validity_acc, data_acc, len, nulls}, {:cont, nil} ->
        {<<validity_acc::bitstring, 0::1>>, <<data_acc::binary, zero_bytes::binary>>, len + 1,
         nulls + 1}

      {validity_acc, data_acc, len, nulls}, {:cont, elem} when is_number(elem) ->
        bin_val = encoder.(elem)
        {<<validity_acc::bitstring, 1::1>>, <<data_acc::binary, bin_val::binary>>, len + 1, nulls}

      {validity_acc, data_acc, len, nulls}, :done ->
        %Errow.Numeric{
          original
          | validity: validity_acc,
            data: data_acc,
            length: len,
            null_count: nulls
        }

      _acc, :halt ->
        :ok
    end

    initial_acc = {original.validity, original.data, original.length, original.null_count}
    {initial_acc, collector_fun}
  end
end

defimpl Inspect, for: Errow.Numeric do
  import Inspect.Algebra

  def inspect(%Errow.Numeric{type: type, length: len, null_count: nulls} = arr, opts) do
    preview_limit = 5
    items = for i <- 0..min(len - 1, preview_limit - 1)//1, len > 0, do: Errow.Numeric.get(arr, i)

    preview_docs =
      items
      |> Enum.map(&to_doc(&1, opts))
      |> Enum.intersperse(concat([",", line()]))

    preview_docs =
      if len > preview_limit do
        preview_docs ++ [concat([",", line(), "... (total #{len} items, #{nulls} nulls)"])]
      else
        preview_docs
      end

    concat([
      "#Errow.Numeric<#{type}, [",
      nest(concat([line(), concat(preview_docs)]), 2),
      line(),
      "]>"
    ])
  end
end
