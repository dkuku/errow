defmodule Benchmark do
  def run do
    IO.puts("\n========================================================")
    IO.puts("              ERROW BENCHMARK SUITE")
    IO.puts("========================================================\n")

    bench_memory()
    bench_random_access()
    bench_sum_aggregation()
    bench_strings()

    IO.puts("\n========================================================")
    IO.puts("              BENCHMARK COMPLETED")
    IO.puts("========================================================\n")
  end

  defp bench_memory do
    n = 100_000
    IO.puts("--- 1. Memory Footprint (#{n} elements) ---")

    list = Enum.to_list(1..n)
    list_words = :erts_debug.size(list)
    list_bytes = list_words * :erlang.system_info(:wordsize)

    errow_arr = Errow.numeric(list, :s32)
    # Errow data buffer is a pure binary
    errow_bytes = byte_size(errow_arr.data)

    erl_array = :array.from_list(list)
    erl_words = :erts_debug.size(erl_array)
    erl_bytes = erl_words * :erlang.system_info(:wordsize)

    IO.puts("  * Standard List:  #{format_bytes(list_bytes)} (#{Float.round(list_bytes / errow_bytes, 1)}x larger)")
    IO.puts("  * Erlang :array:  #{format_bytes(erl_bytes)} (#{Float.round(erl_bytes / errow_bytes, 1)}x larger)")
    IO.puts("  * Errow.Numeric:  #{format_bytes(errow_bytes)} (exact compact Arrow i32)")
    IO.puts("")
  end

  defp bench_random_access do
    n = 100_000
    queries = 50_000
    IO.puts("--- 2. Random Access (#{queries} lookups across #{n} items) ---")

    list = Enum.to_list(1..n)
    errow_arr = Errow.numeric(list, :s32)
    erl_array = :array.from_list(list)

    indices = for i <- 1..queries, do: rem(i * 37, n)

    {t_errow, _} =
      :timer.tc(fn ->
        Enum.each(indices, fn idx -> errow_arr[idx] end)
      end)

    {t_erl, _} =
      :timer.tc(fn ->
        Enum.each(indices, fn idx -> :array.get(idx, erl_array) end)
      end)

    {t_list, _} =
      :timer.tc(fn ->
        # List is O(N), so we only sample 500 lookups to keep benchmark fast
        sample_indices = Enum.take(indices, 500)
        Enum.each(sample_indices, fn idx -> Enum.at(list, idx) end)
      end)

    IO.puts("  * Errow.Numeric (binary_part O(1)): #{t_errow} µs (#{Float.round(t_errow / queries, 3)} µs/op)")
    IO.puts("  * Erlang :array (tree lookup):      #{t_erl} µs (#{Float.round(t_erl / queries, 3)} µs/op)")
    IO.puts("  * List (extrapolated O(N)):         #{t_list * 100} µs (O(N) traversal is hundreds of times slower)")
    IO.puts("")
  end

  defp bench_sum_aggregation do
    n = 500_000
    IO.puts("--- 3. Sum Aggregation (#{n} 32-bit integers) ---")

    list = Enum.to_list(1..n)
    errow_arr = Errow.numeric(list, :s32)

    # Warmup
    Errow.sum(errow_arr)
    Enum.sum(list)

    {t_errow, s_errow} = :timer.tc(fn -> Errow.sum(errow_arr) end)
    {t_minmax, {min_v, max_v}} = :timer.tc(fn -> Errow.min_max(errow_arr) end)
    {t_enum_errow, _} = :timer.tc(fn -> Enum.sum(errow_arr) end)
    {t_list, s_list} = :timer.tc(fn -> Enum.sum(list) end)

    IO.puts("  * Errow native sum (continuous binary loop):     #{t_errow} µs (#{Float.round(t_errow / 1000, 2)} ms) -> #{s_errow}")
    IO.puts("  * Errow native min_max (continuous binary loop): #{t_minmax} µs (#{Float.round(t_minmax / 1000, 2)} ms) -> {#{min_v}, #{max_v}}")
    IO.puts("  * Errow via Enum.sum (Enumerable protocol):      #{t_enum_errow} µs (#{Float.round(t_enum_errow / 1000, 2)} ms)")
    IO.puts("  * List via Enum.sum:                             #{t_list} µs (#{Float.round(t_list / 1000, 2)} ms) -> #{s_list}")
    IO.puts("")
  end

  defp bench_strings do
    n = 50_000
    IO.puts("--- 4. String Array (#{n} strings) ---")

    raw_strings = for i <- 1..n, do: "user_identifier_#{i}"
    errow_str = Errow.string(raw_strings)

    # Memory
    str_data_bytes = byte_size(errow_str.data)
    offsets_bytes = byte_size(errow_str.offsets)

    # Fast Join
    {t_join_errow, _} = :timer.tc(fn -> Errow.join(errow_str, ",") end)
    {t_join_list, _} = :timer.tc(fn -> Enum.join(raw_strings, ",") end)

    IO.puts("  * Errow continuous data buffer:  #{format_bytes(str_data_bytes)}")
    IO.puts("  * Errow offsets buffer:          #{format_bytes(offsets_bytes)}")
    IO.puts("  * Errow.join/2:                  #{t_join_errow} µs (#{Float.round(t_join_errow / 1000, 2)} ms)")
    IO.puts("  * Enum.join(list):               #{t_join_list} µs (#{Float.round(t_join_list / 1000, 2)} ms)")
    IO.puts("")
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 2)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024), 2)} MB"
end

Benchmark.run()
