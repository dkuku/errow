defmodule ErrowStringTest do
  use ExUnit.Case, async: true
  doctest Errow

  describe "Errow.String creation and basic access" do
    test "new/0 creates an empty string array" do
      arr = Errow.string()
      assert Errow.String.size(arr) == 0
      assert Errow.String.null_count(arr) == 0
      assert Errow.String.to_list(arr) == []
    end

    test "append/2 and fetch/2" do
      arr =
        Errow.string()
        |> Errow.String.append("Daniel")
        |> Errow.String.append("Kuku")
        |> Errow.String.append(nil)
        |> Errow.String.append("Elixir")

      assert Errow.String.size(arr) == 4
      assert Errow.String.null_count(arr) == 1

      assert arr[0] == "Daniel"
      assert arr[1] == "Kuku"
      assert arr[2] == nil
      assert arr[3] == "Elixir"

      # Negative index
      assert arr[-1] == "Elixir"
      assert arr[-2] == nil
      assert arr[-4] == "Daniel"

      # Out of bounds
      assert arr[4] == nil
      assert arr[-5] == nil
      assert Errow.String.fetch(arr, 10) == :error
    end

    test "null?/2 predicate" do
      arr = Errow.string(["a", nil, "b"])
      refute Errow.String.null?(arr, 0)
      assert Errow.String.null?(arr, 1)
      refute Errow.String.null?(arr, 2)
      refute Errow.String.null?(arr, 99)
    end
  end

  describe "Access protocol: ranges, put_in, update_in, pop_in" do
    test "range slicing via access" do
      arr = Errow.string(["A", "B", "C", "D", "E"])
      assert arr[1..3] == ["B", "C", "D"]
      assert arr[0..-1//1] == ["A", "B", "C", "D", "E"]
      assert arr[0..-1//2] == ["A", "C", "E"]
    end

    test "put_in and replace_at" do
      arr = Errow.string(["A", "B", "C"])
      arr2 = put_in(arr[1], "SUPER_LONG_STRING")

      assert arr2[0] == "A"
      assert arr2[1] == "SUPER_LONG_STRING"
      assert arr2[2] == "C"
      assert Errow.String.size(arr2) == 3

      # Replace with nil
      arr3 = put_in(arr2[0], nil)
      assert arr3[0] == nil
      assert Errow.String.null_count(arr3) == 1

      # Replace nil with string
      arr4 = put_in(arr3[0], "RESTORED")
      assert arr4[0] == "RESTORED"
      assert Errow.String.null_count(arr4) == 0
    end

    test "update_in" do
      arr = Errow.string(["hello", "world"])
      arr2 = update_in(arr[0], &String.upcase/1)
      assert arr2[0] == "HELLO"
      assert arr2[1] == "world"
    end

    test "pop_in and pop/2" do
      arr = Errow.string(["A", "B", "C"])
      {popped, remaining} = pop_in(arr[1])

      assert popped == "B"
      assert Errow.String.size(remaining) == 2
      assert remaining[0] == "A"
      assert remaining[1] == "C"
    end
  end

  describe "Enumerable & Collectable protocols" do
    test "Collectable: for ... into: Errow.string()" do
      arr =
        for x <- ["one", "two", "three"], into: Errow.string() do
          String.upcase(x)
        end

      assert arr[0] == "ONE"
      assert arr[1] == "TWO"
      assert arr[2] == "THREE"
      assert Errow.String.size(arr) == 3
    end

    test "Enum functions: map, filter, count, member?" do
      arr = Errow.string(["apple", "banana", "cherry"])

      assert Enum.count(arr) == 3
      assert Enum.member?(arr, "banana")
      refute Enum.member?(arr, "orange")

      mapped = Enum.map(arr, &String.length/1)
      assert mapped == [5, 6, 6]
    end

    test "Stream functions: lazy zip and take" do
      arr = Errow.string(["first", "second", "third", "fourth"])

      res =
        arr
        |> Stream.zip(1..10)
        |> Enum.take(2)

      assert res == [{"first", 1}, {"second", 2}]
    end
  end

  describe "Inspect protocol" do
    test "pretty prints string array" do
      arr = Errow.string(["elixir", "beam"])
      inspected = inspect(arr)
      assert inspected =~ "#Errow.String<["
      assert inspected =~ ~s("elixir")
      assert inspected =~ ~s("beam")
    end
  end

  describe "String Aggregations" do
    test "join/2 with and without nulls" do
      arr = Errow.string(["Hello", "World", "BEAM"])
      assert Errow.join(arr, " ") == "Hello World BEAM"
      assert Errow.join(arr, "") == "HelloWorldBEAM"

      with_nulls = Errow.string(["A", nil, "B"])
      assert Errow.join(with_nulls, "-") == "A-B"
      assert Errow.join(with_nulls, "-", skip_nulls: false) == "A--B"
    end

    test "min/2 and max/2 lexicographical" do
      arr = Errow.string(["banana", "apple", "cherry"])
      assert Errow.min(arr) == "apple"
      assert Errow.max(arr) == "cherry"
    end

    test "total_bytes/1" do
      arr = Errow.string(["abc", "de"])
      assert Errow.String.total_bytes(arr) == 5
    end
  end
end
