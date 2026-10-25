# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-10-25

### Added
- **`Errow.String`**: Columnar string array compliant with Apache Arrow `Utf8` (`"u"`).
  - Continuous data buffer with little-endian 32-bit offsets and 1-bit validity bitmap.
  - $O(1)$ random access slicing via BEAM sub-binaries without copying.
- **`Errow.Binary`**: Columnar array for opaque byte buffers compliant with Apache Arrow `Binary` (`"z"`).
- **`Errow.Numeric`**: Fixed-width primitive numerical array compliant with Apache Arrow `Primitive`.
  - Supported signed types: `:s8, :s16, :s32, :s64, :s128, :s256`.
  - Supported unsigned types: `:u8, :u16, :u32, :u64, :u128, :u256`.
  - Supported floating point: `:f32, :f64`.
  - 128-bit and 256-bit BigInt support mapped directly to Arrow Decimal / FixedSizeBinary.
- **Typed Shorthand Constructors & Aliases**:
  - `Errow.s8/0,1`, `Errow.u8/0,1` .. `Errow.s256/0,1`, `Errow.u256/0,1`.
  - `Errow.f32/0,1`, `Errow.f64/0,1`.
  - `Errow.numeric_8/0,1`, `Errow.numeric_16/0,1`, `Errow.numeric_32/0,1`, etc.
  - Usable without parentheses in comprehensions: `for x <- stream, into: Errow.s8, do: x`.
- **High-Performance Native Aggregations**:
  - Unrolled binary loops executing at JIT speed: `sum/2`, `product/2`, `min/2`, `max/2`, `min_max/2`, `mean/2`, `join/3`.
  - Null skipping (`skip_nulls: true` by default) and $O(1)$ count lookup.
- **Apache Arrow C Data Interface (`Errow.CData`)**:
  - `export_schema/2`: Generates standard Arrow C schema metadata (`format`, `name`, `flags`, `n_buffers`).
  - `export_buffers/2`: Exports 8-byte aligned raw buffers (`validity`, `offsets`, `data`) ready for zero-copy consumption by C, Rust (`arrow-rs`, `rustler`), Zig, DuckDB, or Polars.
- **Elixir Protocol Implementations**:
  - `Access`: `arr[i]`, `arr[-1]`, `arr[0..-1//1]`, `put_in/2`, `update_in/2`, `pop_in/2`.
  - `Enumerable`: $O(1)$ `count/1`, `member?/2`, 3-arity `slice/1`, and `reduce/3`.
  - `Collectable`: Specialized tuple accumulator avoiding intermediate struct allocations.
  - `Inspect`: Concise columnar preview with null count and length indicators.
- **Apache Arrow IPC Test Fixture**: Verified against official `apache/arrow-testing` binary IPC stream.
