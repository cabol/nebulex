defmodule Nebulex.Cache.HooksTest do
  use ExUnit.Case, async: true

  alias Nebulex.TestCache.Hooked.C1, as: Hooked1
  alias Nebulex.TestCache.Hooked.C2, as: Hooked2
  alias Nebulex.TestCache.Hooked.C3, as: Hooked3

  setup do
    caches_and_pids = start_caches([Hooked1, Hooked2, Hooked3])
    :ok

    on_exit fn ->
      stop_caches(caches_and_pids)
    end
  end

  test "pre_hooks async" do
    true = Process.register(self(), :hooked_cache)
    Hooked1.new_generation()

    refute Hooked1.get("foo")
    assert_receive {Hooked1, :get, ["foo", []]}, 200
    assert Hooked1.set("foo", "bar") == "bar"
    assert Hooked1.set("hello", "world") == "world"

    assert Hooked1.get("foo") == "bar"
    assert_receive {Hooked1, :get, ["foo", []]}, 200
    assert Hooked1.get("hello") == "world"
    assert_receive {Hooked1, :get, ["hello", []]}, 200
  end

  test "post_hooks async" do
    true = Process.register(self(), :hooked_cache)
    Hooked1.new_generation()

    assert Hooked1.set("foo", "bar") == "bar"
    assert_receive {Hooked1, :set, ["foo", "bar", []]}, 200
    assert Hooked1.get("foo") == "bar"
    assert Hooked1.set("hello", "world") == "world"
    assert_receive {Hooked1, :set, ["hello", "world", []]}, 200
    assert Hooked1.get("hello") == "world"
  end

  test "post_hooks pipe" do
    true = Process.register(self(), :hooked_cache)
    Hooked2.new_generation()

    assert Hooked2.get("foo") == "hello"
    assert_receive {Hooked2, :get, ["foo", []]}, 200
    assert Hooked2.set("foo", "bar") == "bar"
    assert_receive {Hooked2, :set, ["foo", "bar", []]}, 200
    assert Hooked2.get("foo") == "bar"
    assert_receive {Hooked2, :get, ["foo", []]}, 200
  end

  test "post_hooks sync" do
    true = Process.register(self(), :hooked_cache)
    Hooked3.new_generation()

    refute Hooked3.get("foo")
    assert_receive {Hooked3, :get, ["foo", []]}, 200
    assert Hooked3.set("foo", "bar") == "bar"
    assert_receive {Hooked3, :set, ["foo", "bar", []]}, 200
    assert Hooked3.get("foo") == "bar"
    assert_receive {Hooked3, :get, ["foo", []]}, 200
  end

  ## Helpers

  defp start_caches(caches) do
    for cache <- caches do
      {:ok, pid} = cache.start_link(n_generations: 2)
      {cache, pid}
    end
  end

  defp stop_caches(caches_and_pids) do
    for {cache, pid} <- caches_and_pids do
      _ = :timer.sleep(10)
      if Process.alive?(pid), do: cache.stop(pid, 1)
    end
  end
end
