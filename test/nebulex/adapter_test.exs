defmodule Nebulex.AdapterTest do
  use ExUnit.Case, async: true

  describe "defcommand/2" do
    test "ok: function is created" do
      defmodule Test1 do
        import Nebulex.Adapter, only: [defcommand: 1, defcommand: 2]

        defcommand c1(a1)

        defcommand c2(a1), command: :c11

        defcommand c3(a1), command: :c11, largs: [:l], rargs: [:r]
      end
    end
  end

  describe "defcommandp/2" do
    test "ok: function is created" do
      defmodule Test2 do
        import Nebulex.Adapter, only: [defcommandp: 1, defcommandp: 2]

        defcommandp c1(a1)

        defcommandp c2(a1), command: :c11

        defcommandp c3(a1), command: :c11, largs: [:l], rargs: [:r]
      end
    end
  end
end
