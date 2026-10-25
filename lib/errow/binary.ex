defmodule Errow.Binary do
  @moduledoc """
  An immutable, continuous-memory binary array implementing the Apache Arrow `Binary` columnar format (for raw byte blobs).

  Under the hood, data is organized in three buffers:
    1. **Offsets buffer** (`offsets`): a continuous binary of 32-bit signed integers in little-endian.
    2. **Data buffer** (`data`): a continuous binary containing the concatenated raw byte blobs.
    3. **Validity bitmap** (`validity`): a bitstring tracking null (`nil`) values (1 bit per element).

  Unlike `Errow.String`, `Errow.Binary` is meant for opaque byte slices, hashes, PNG/JPEG payloads,
  UUIDs, Protobuf blobs, etc.
  """

  @behaviour Access

  @type t :: %__MODULE__{
          validity: bitstring(),
          offsets: binary(),
          data: binary(),
          length: non_neg_integer(),
          null_count: non_neg_integer()
        }

  defstruct validity: <<>>,
            offsets: <<0::32-little>>,
            data: <<>>,
            length: 0,
            null_count: 0

  @doc """
  Creates a new empty `Errow.Binary` array.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Builds an `Errow.Binary` array from a list or enumerable of binaries and optional `nil`s.
  """
  @spec from_list(Enumerable.t()) :: t()
  def from_list(enumerable) do
    Enum.into(enumerable, new())
  end

  @doc """
  Appends a binary blob or `nil` to the array.
  """
  @spec append(t(), binary() | nil) :: t()
  def append(%__MODULE__{} = arr, bin) when is_binary(bin) do
    new_data = <<arr.data::binary, bin::binary>>
    new_offset = byte_size(new_data)

    %__MODULE__{
      arr
      | validity: <<arr.validity::bitstring, 1::1>>,
        offsets: <<arr.offsets::binary, new_offset::32-little>>,
        data: new_data,
        length: arr.length + 1
    }
  end

  def append(%__MODULE__{} = arr, nil) do
    current_offset = byte_size(arr.data)

    %__MODULE__{
      arr
      | validity: <<arr.validity::bitstring, 0::1>>,
        offsets: <<arr.offsets::binary, current_offset::32-little>>,
        length: arr.length + 1,
        null_count: arr.null_count + 1
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
  @spec fetch(t(), integer() | Range.t()) :: {:ok, any()} | :error
  @impl Access
  def fetch(%__MODULE__{length: len} = arr, idx) when is_integer(idx) do
    norm_idx = normalize_index(idx, len)

    if norm_idx do
      <<_::bitstring-size(^norm_idx), bit::1, _::bitstring>> = arr.validity

      if bit == 0 do
        {:ok, nil}
      else
        <<_::binary-size(^norm_idx * 4), start::32-little, stop::32-little, _::binary>> =
          arr.offsets

        {:ok, binary_part(arr.data, start, stop - start)}
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
  @spec get(t(), integer(), any()) :: binary() | nil | any()
  def get(arr, idx, default \\ nil) do
    case fetch(arr, idx) do
      {:ok, val} -> val
      :error -> default
    end
  end

  @doc """
  Replaces the element at the given index with a new binary blob or `nil`.
  """
  @spec replace_at(t(), integer(), binary() | nil) :: t()
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
  Converts the `Errow.Binary` array into a standard Elixir list.
  """
  @spec to_list(t()) :: [binary() | nil]
  def to_list(%__MODULE__{length: len} = arr) do
    for i <- 0..(len - 1)//1, len > 0, do: get(arr, i)
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
      {get_val, new_val} when is_binary(new_val) or is_nil(new_val) ->
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
  # Internal Helpers
  # ============================================================================

  defp normalize_index(idx, len) do
    norm = if idx < 0, do: len + idx, else: idx
    if norm >= 0 and norm < len, do: norm, else: nil
  end

  defp do_replace_at(%__MODULE__{} = arr, idx, old_val, new_val) do
    <<val_before::bitstring-size(^idx), _old_bit::1, val_after::bitstring>> = arr.validity
    new_bit = if is_nil(new_val), do: 0, else: 1
    new_validity = <<val_before::bitstring, new_bit::1, val_after::bitstring>>

    <<offsets_before::binary-size((^idx + 1) * 4), offsets_after::binary>> = arr.offsets
    <<_::binary-size(^idx * 4), start::32-little, stop::32-little, _::binary>> = arr.offsets

    old_byte_len = if is_nil(old_val), do: 0, else: byte_size(old_val)
    new_byte_len = if is_nil(new_val), do: 0, else: byte_size(new_val)
    delta = new_byte_len - old_byte_len

    data_before = binary_part(arr.data, 0, start)
    data_after = binary_part(arr.data, stop, byte_size(arr.data) - stop)
    new_data_content = if is_nil(new_val), do: <<>>, else: new_val
    updated_data = <<data_before::binary, new_data_content::binary, data_after::binary>>

    updated_offsets_after =
      for <<off::32-little <- offsets_after>>, into: <<>> do
        <<off + delta::32-little>>
      end

    new_null_count =
      cond do
        is_nil(old_val) and not is_nil(new_val) -> arr.null_count - 1
        not is_nil(old_val) and is_nil(new_val) -> arr.null_count + 1
        true -> arr.null_count
      end

    %__MODULE__{
      arr
      | validity: new_validity,
        offsets: <<offsets_before::binary, updated_offsets_after::binary>>,
        data: updated_data,
        null_count: new_null_count
    }
  end

  defp do_delete_at(%__MODULE__{} = arr, idx, old_val) do
    <<val_before::bitstring-size(^idx), old_bit::1, val_after::bitstring>> = arr.validity
    new_validity = <<val_before::bitstring, val_after::bitstring>>

    <<offsets_before::binary-size((^idx + 1) * 4), _del_offset::32-little, offsets_after::binary>> =
      arr.offsets

    <<_::binary-size(^idx * 4), start::32-little, stop::32-little, _::binary>> = arr.offsets

    old_byte_len = if is_nil(old_val), do: 0, else: byte_size(old_val)

    data_before = binary_part(arr.data, 0, start)
    data_after = binary_part(arr.data, stop, byte_size(arr.data) - stop)
    updated_data = <<data_before::binary, data_after::binary>>

    updated_offsets_after =
      for <<off::32-little <- offsets_after>>, into: <<>> do
        <<off - old_byte_len::32-little>>
      end

    new_null_count = if old_bit == 0, do: arr.null_count - 1, else: arr.null_count

    %__MODULE__{
      arr
      | validity: new_validity,
        offsets: <<offsets_before::binary, updated_offsets_after::binary>>,
        data: updated_data,
        length: arr.length - 1,
        null_count: new_null_count
    }
  end
end

# ==============================================================================
# Protocol Implementations
# ==============================================================================

defimpl Enumerable, for: Errow.Binary do
  def count(%Errow.Binary{length: len}), do: {:ok, len}

  def member?(%Errow.Binary{length: 0}, _elem), do: {:ok, false}

  def member?(%Errow.Binary{} = arr, element) do
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

  def slice(%Errow.Binary{length: len} = arr) do
    slicing_fun = fn start, amount ->
      for idx <- start..(start + amount - 1), idx < len do
        Errow.Binary.get(arr, idx)
      end
    end

    {:ok, len, slicing_fun}
  end

  def reduce(%Errow.Binary{length: len} = arr, acc, fun) do
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
    val = Errow.Binary.get(arr, idx)
    do_reduce(arr, fun.(val, acc), fun, idx + 1, len)
  end
end

defimpl Collectable, for: Errow.Binary do
  def into(original) do
    collector_fun = fn
      acc, {:cont, elem} when is_binary(elem) or is_nil(elem) ->
        Errow.Binary.append(acc, elem)

      acc, :done ->
        acc

      _acc, :halt ->
        :ok
    end

    {original, collector_fun}
  end
end

defimpl Inspect, for: Errow.Binary do
  import Inspect.Algebra

  def inspect(%Errow.Binary{length: len, null_count: nulls} = arr, opts) do
    preview_limit = 5
    items = for i <- 0..min(len - 1, preview_limit - 1)//1, len > 0, do: Errow.Binary.get(arr, i)

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
      "#Errow.Binary<[",
      nest(concat([line(), concat(preview_docs)]), 2),
      line(),
      "]>"
    ])
  end
end
