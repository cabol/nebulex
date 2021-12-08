defmodule Nebulex.Adapters.MultilevelErrorTest do
  use ExUnit.Case, async: false
  use Nebulex.Cache.EntryErrorTest

  import Mock
  import Nebulex.CacheCase

  alias Nebulex.TestCache.Multilevel
  alias Nebulex.TestCache.Multilevel.{L1, L2, L3}

  @gc_interval :timer.hours(1)

  @levels [
    {L1, name: :multilevel_error_cache_l1, gc_interval: @gc_interval},
    {L2, name: :multilevel_error_cache_l2, primary: [gc_interval: @gc_interval]},
    {L3, name: :multilevel_error_cache_l3, primary: [gc_interval: @gc_interval]}
  ]

  setup_with_dynamic_cache(Multilevel, :multilevel_error_cache, levels: @levels)

  describe "cache level error" do
    test_with_mock "fetch/2", %{cache: cache}, L1.__adapter__(), [:passthrough],
      fetch: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
      assert cache.fetch(1) == {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
    end

    test_with_mock "get_all/2", %{cache: cache}, L1.__adapter__(), [:passthrough],
      get_all: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
      assert cache.get_all(1) == {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
    end

    test_with_mock "put/3", %{cache: cache}, L1.__adapter__(), [:passthrough],
      put: fn _, _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
      assert cache.put("hello", "world") ==
               {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
    end

    test_with_mock "put_all/2", %{cache: cache}, L1.__adapter__(), [:passthrough],
      put_all: fn _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
      assert cache.put_all(%{"apples" => 1, "bananas" => 3}) ==
               {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
    end

    test_with_mock "exists?/1", %{cache: cache}, L1.__adapter__(), [:passthrough],
      exists?: fn _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
      assert cache.exists?("error") ==
               {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
    end

    test_with_mock "expire!/2", %{cache: cache}, L1.__adapter__(), [:passthrough],
      expire: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
      assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
        cache.expire!(:raise, 100)
      end
    end

    test_with_mock "touch!/1", %{cache: cache}, L1.__adapter__(), [:passthrough],
      touch: fn _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
      assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
        cache.touch!(:raise)
      end
    end

    test_with_mock "ttl/1", %{cache: cache}, L1.__adapter__(), [:passthrough],
      ttl: fn _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
      assert cache.ttl(1) == {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
    end
  end
end
