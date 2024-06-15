defmodule Mix.NebulexTest do
  use ExUnit.Case, async: true
  use Mimic

  import Mix.Nebulex

  test "fail because umbrella project" do
    Mix.Project
    |> expect(:umbrella?, fn -> true end)

    assert_raise Mix.Error, ~r"Cannot run task", fn ->
      no_umbrella!("nebulex.gen.cache")
    end
  end
end
