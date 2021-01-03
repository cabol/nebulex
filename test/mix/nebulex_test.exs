defmodule Mix.NebulexTest do
  use ExUnit.Case, async: true

  import Mix.Nebulex
  import Mock

  test "fail because umbrella project" do
    with_mock Mix.Project, umbrella?: fn -> true end do
      assert_raise Mix.Error, ~r"Cannot run task", fn ->
        no_umbrella!("nebulex.gen.cache")
      end
    end
  end
end
