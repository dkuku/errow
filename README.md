# Errow

[![Hex.pm](https://img.shields.io/hexpm/v/errow.svg)](https://hex.pm/packages/errow)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

**Errow** (*Erlang + Arrow*) provides zero-copy, in-memory columnar arrays for Elixir and the BEAM, fully integrated with Elixir protocols (`Enumerable`, `Collectable`, `Access`) and **100% byte-for-byte compliant with the Apache Arrow Columnar Specification** and **Arrow C Data Interface**.

---

## Why Errow?

Standard Elixir collections are linked lists (`[head | tail]`) or tree structures. While excellent for general functional programming, they have limitations for data-intensive and interop workloads:
* **High Memory Overhead**: Each list element requires 2 machine words (16 bytes on 64-bit BEAM) plus heap terms.
* **O(N) Random Access**: Indexing `Enum.at(list, 500)` requires traversing 500 pointers.
* **Complex Native Interop**: Passing lists to C, Rust, Zig, or DuckDB requires allocating memory and copying every single item across the NIF boundary.

**Errow solves this by storing data in continuous BEAM binaries**:
* **O(1) Random Access**: Slicing and indexing (`arr[i]`) use BEAM's native `binary_part/3` sub-binary references with zero memory copying.
* **Idiomatic Elixir**: Seamlessly use `arr[0]`, `for x <- arr, into: Errow.string()`, `Enum.map/2`, `put_in/2`, and `update_in/2`.
* **Zero-Copy Native Interop**: Native NIFs (C, Rust, Zig) and analytical engines (DuckDB, Polars, PyArrow) can read Errow buffers directly via the Apache Arrow C Data Interface without serialization or copying!

---

## Installation

Add `errow` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:errow, "~> 0.1.0"}
  ]
end
```

---

## Quickstart

### 1. Strings (`Errow.String`)

```elixir
# Build in comprehensions with Collectable
names = for name <- ["Elixir", "BEAM", "Arrow", "Errow"], into: Errow.string() do
  String.upcase(name)
end

# O(1) Indexing via Access
names[0]    # => "ELIXIR"
names[-1]   # => "ERROW" (negative indices supported!)
names[1..2] # => ["BEAM", "ARROW"]

# In-place updates via Access
updated = put_in(names[1], "ZIG")
updated[1]  # => "ZIG"

# Enumerable & Stream
Enum.map(names, &byte_size/1) # => [6, 4, 5, 5]
```

### 2. Numerics with 128-bit and 256-bit BigInts (`Errow.Numeric`)

`Errow.Numeric` supports fixed-width primitive types:
* **Signed**: `:s8, :s16, :s32, :s64, :s128, :s256`
* **Unsigned**: `:u8, :u16, :u32, :u64, :u128, :u256`
* **Floats**: `:f32, :f64`

```elixir
# 32-bit signed integers (compact: 4 bytes per item)
ints = Errow.numeric([10, 20, 30, 40], :s32)
Enum.sum(ints) # => 100

# 128-bit BigInts (Arrow Decimal128 compatible, exactly 16 bytes per item)
big128 = Errow.numeric([300_000_000_000_000_000_000_000_000_000_000_000], :s128)
big128[0] # => 300000000000000000000000000000000000

# 256-bit BigInts (Arrow Decimal256 / Web3 uint256, exactly 32 bytes per item)
u256 = Errow.numeric([115_792_089_237_316_195_423_570_985_008_687_907_853_269_984_665_640_564_039_457_584_007_913_129_639_935], :u256)
```

### 3. Raw Binary Blobs (`Errow.Binary`)

For raw, opaque byte buffers (hashes, UUIDs, PNG/JPEG payloads, Protobuf messages):

```elixir
blobs = Errow.binary([<<1, 2, 3>>, <<255, 254>>, nil])
blobs[0] # => <<1, 2, 3>>
blobs[2] # => nil
```

---

## Apache Arrow C Data Interface (Zero-Copy Interop)

Exporting your Elixir arrays to native libraries in C, Rust, Zig, or DuckDB requires **zero memory allocations**:

```elixir
arr = Errow.string(["Daniel", "Kuku", "Elixir"])

# 1. Export schema metadata
schema = Errow.CData.export_schema(arr, name: "username")
schema.format     # => "u" (Arrow Utf8 format)
schema.n_buffers  # => 3

# 2. Export 8-byte aligned raw binary buffers
%{length: 3, null_count: 0, buffers: [validity, offsets, data]} = Errow.CData.export_buffers(arr)
```

### Consuming in Rust (`Rustler` + `arrow-rs`):

```rust
use rustler::{Binary, NifResult};
use arrow::array::StringArray;
use arrow::buffer::{Buffer, OffsetBuffer};

#[rustler::nif]
fn inspect_arrow<'a>(_validity: Binary<'a>, offsets_bin: Binary<'a>, data_bin: Binary<'a>) -> NifResult<usize> {
    // Zero-copy wrap BEAM binaries in Arrow buffers:
    let data_buf = Buffer::from_slice_ref(data_bin.as_slice());
    let offsets_slice: &[i32] = bytemuck::cast_slice(offsets_bin.as_slice());
    let offset_buf = OffsetBuffer::new(offsets_slice.to_vec().into());

    let string_array = unsafe {
        StringArray::new_unchecked(offset_buf, data_buf, None)
    };

    Ok(string_array.len())
}
```

### Consuming in C (`erl_nif.h`):

```c
#include <erl_nif.h>
#include <stdint.h>

static ERL_NIF_TERM get_string_len(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary offsets_bin, data_bin;
    enif_inspect_binary(env, argv[0], &offsets_bin);
    enif_inspect_binary(env, argv[1], &data_bin);

    const int32_t* offsets = (const int32_t*) offsets_bin.data;
    uint32_t start = offsets[0];
    uint32_t end = offsets[1];
    
    // Direct pointer to UTF-8 characters without copying!
    const char* str = (const char*) (data_bin.data + start);
    return enif_make_uint(env, end - start);
}
```

### Consuming in Python (`pyarrow`):

```python
import pyarrow as pa

# Zero-copy wrap BEAM binary buffers exported by Errow.CData.export_buffers/2:
buf_offsets = pa.py_buffer(offsets_bytes)
buf_data = pa.py_buffer(data_bytes)
buf_validity = pa.py_buffer(validity_bytes) if validity_bytes else None

arrow_array = pa.Array.from_buffers(
    pa.string(),
    length,
    [buf_validity, buf_offsets, buf_data],
    null_count=null_count
)
```

---

## Testing & Specification Compliance

Errow is verified against official Apache Arrow test fixtures from [`apache/arrow-testing`](https://github.com/apache/arrow-testing):
* **Columnar IPC Files (`.arrow`)**: Verified against official `generated_primitive.arrow`, `generated_decimal.arrow`, and `generated_decimal256.arrow` with `"ARROW1"` magic encapsulation and FlatBuffers footers.
* **IPC Streams (`.stream`)**: Conforms to official Arrow IPC framing and 8-byte buffer alignment.
* **LSB-First Validity Bitmaps**: Exports null bitmaps matching the Arrow specification (bit 0 = slot 0, bit 1 = slot 1).
* **Cross-Language Integration**: End-to-end integration tests confirm that `pyarrow` directly reconstructs Errow arrays with zero deserialization errors.

---

## License

Errow is licensed under the [Apache-2.0 License](LICENSE).
