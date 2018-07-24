defmodule Mix.NebulexTest do
  use ExUnit.Case, async: false

  import Mix.Nebulex
  import Mock

  test "provide a list of available nebulex mix tasks" do
    Mix.Tasks.Nebulex.run([])
    assert_received {:mix_shell, :info, ["Nebulex v" <> _]}
    assert_received {:mix_shell, :info, ["mix nebulex.gen.cache" <> _]}
  end

  test "expects no arguments" do
    assert_raise Mix.Error, fn ->
      Mix.Tasks.Nebulex.run(["invalid"])
    end
  end

  test "fail because umbrella project" do
    with_mock Mix.Project, umbrella?: fn -> true end do
      assert_raise Mix.Error, ~r"Cannot run task", fn ->
        no_umbrella!("nebulex.gen.cache")
      end
    end
  end
end
