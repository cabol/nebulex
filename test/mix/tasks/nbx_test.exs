defmodule Mix.Tasks.NbxTest do
  use ExUnit.Case

  alias Mix.Tasks.Nbx

  test "provide a list of available nbx mix tasks" do
    Nbx.run([])
    assert_received {:mix_shell, :info, ["mix nbx.gen.cache" <> _]}
  end

  test "expects no arguments" do
    assert_raise Mix.Error, fn ->
      Nbx.run(["invalid"])
    end
  end
end
