defmodule SolarsystemTest do
  use ExUnit.Case
  doctest Solarsystem

  test "greets the world" do
    assert Solarsystem.hello() == :world
  end
end
