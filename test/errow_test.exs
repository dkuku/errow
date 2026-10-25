defmodule ErrowTest do
  use ExUnit.Case, async: true
  doctest Errow

  test "Errow facade delegations" do
    s = Errow.string(["A", "B"])
    assert Errow.String.size(s) == 2

    b = Errow.binary([<<1>>, <<2>>])
    assert Errow.Binary.size(b) == 2

    n = Errow.numeric([10, 20], :s32)
    assert Errow.Numeric.size(n) == 2
  end
end
