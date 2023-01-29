defmodule Nebulex.Cache.EntryBooleanValuesTest do
  import Nebulex.CacheCase

  deftests do
    describe "boolean values:" do
      test "get and get_all", %{cache: cache} do
        :ok = cache.put_all!(a: true, b: false)

        assert cache.get!(:a) == true
        assert cache.get!(:b) == false

        assert cache.get_all!([:a, :b]) == %{a: true, b: false}
      end

      test "take", %{cache: cache} do
        :ok = cache.put_all!(a: true, b: false)

        assert cache.take!(:a) == true
        assert cache.take!(:b) == false

        assert cache.get_all!([:a, :b]) == %{}
      end

      test "delete true value", %{cache: cache} do
        :ok = cache.put!(:a, true)

        assert cache.get!(:a) == true
        assert cache.delete!(:a) == :ok
        assert cache.get!(:a) == nil
      end

      test "delete false value", %{cache: cache} do
        :ok = cache.put!(:a, false)

        assert cache.get!(:a) == false
        assert cache.delete!(:a) == :ok
        assert cache.get!(:a) == nil
      end

      test "put_new", %{cache: cache} do
        assert cache.put_new!(:a, true)

        :ok = cache.put!(:a, false)

        refute cache.put_new!(:a, false)
        assert cache.get!(:a) == false
      end

      test "has_key?", %{cache: cache} do
        :ok = cache.put!(:a, true)

        assert cache.has_key?(:a) == {:ok, true}
        assert cache.has_key?(:b) == {:ok, false}
      end
    end
  end
end
