defmodule Nebulex.AdapterTest do
  use ExUnit.Case, async: true
  doctest Nebulex.Adapter

  describe "defcommand/2" do
    test "ok: function is created" do
      defmodule Test1 do
        import Nebulex.Adapter, only: [defcommand: 1, defcommand: 2]

        defcommand c1(a1)

        defcommand c2(a1), command: :c11
      end
    end
  end

  describe "defcommandp/2" do
    test "ok: function is created" do
      defmodule Test2 do
        import Nebulex.Adapter, only: [defcommandp: 1, defcommandp: 2]

        defcommandp c1(a1)

        defcommandp c2(a1), command: :c11
      end
    end
  end
end
