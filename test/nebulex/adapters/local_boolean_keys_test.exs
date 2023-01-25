defmodule Nebulex.Adapters.LocalBooleanKeysTest do
  use ExUnit.Case, async: true

  defmodule ETS do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local
  end

  defmodule Shards do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local
  end

  alias Nebulex.Adapters.LocalBooleanKeysTest.{ETS, Shards}

  setup do
    {:ok, ets} = ETS.start_link()
    {:ok, shards} = Shards.start_link(backend: :shards)

    on_exit(fn ->
      :ok = Process.sleep(100)
      if Process.alive?(ets), do: ETS.stop()
      if Process.alive?(shards), do: Shards.stop()
    end)

    {:ok, caches: [ETS, Shards]}
  end

  describe "boolean keys" do
    test "get and get_all", %{caches: caches} do
      for_all_caches(caches, fn cache ->
        :ok = cache.put_all(a: true, b: false)

        assert cache.get(:a) == true
        assert cache.get(:b) == false

        assert cache.get_all([:a, :b]) == %{a: true, b: false}
      end)
    end

    test "take", %{caches: caches} do
      for_all_caches(caches, fn cache ->
        :ok = cache.put_all(a: true, b: false)

        assert cache.take(:a) == true
        assert cache.take(:b) == false

        assert cache.get_all([:a, :b]) == %{}
      end)
    end

    test "delete true value", %{caches: caches} do
      for_all_caches(caches, fn cache ->
        :ok = cache.put(:a, true)

        assert cache.get(:a) == true
        assert cache.delete(:a)
        assert cache.get(:a) == nil
      end)
    end

    test "delete false value", %{caches: caches} do
      for_all_caches(caches, fn cache ->
        :ok = cache.put(:a, false)

        assert cache.get(:a) == false
        assert cache.delete(:a)
        assert cache.get(:a) == nil
      end)
    end

    test "put_new", %{caches: caches} do
      for_all_caches(caches, fn cache ->
        assert cache.put_new(:a, true)
        :ok = cache.put(:a, false)
        refute cache.put_new(:a, false)

        assert cache.get(:a) == false
      end)
    end

    test "has_key?", %{caches: caches} do
      for_all_caches(caches, fn cache ->
        :ok = cache.put(:a, true)

        assert cache.has_key?(:a)
        refute cache.has_key?(:b)
      end)
    end
  end

  ## Helpers

  defp for_all_caches(caches, fun) do
    Enum.each(caches, fn cache ->
      fun.(cache)
    end)
  end
end
