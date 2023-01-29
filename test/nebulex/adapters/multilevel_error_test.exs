defmodule Nebulex.Adapters.MultilevelErrorTest do
  use ExUnit.Case, async: false
  use Mimic

  import Nebulex.CacheCase, only: [setup_with_dynamic_cache: 3]

  alias Nebulex.TestCache.Multilevel
  alias Nebulex.TestCache.Multilevel.{L1, L2, L3}

  @gc_interval :timer.hours(1)

  @levels [
    {L1, name: :multilevel_error_cache_l1, gc_interval: @gc_interval},
    {L2, name: :multilevel_error_cache_l2, primary: [gc_interval: @gc_interval]},
    {L3, name: :multilevel_error_cache_l3, primary: [gc_interval: @gc_interval]}
  ]

  setup_with_dynamic_cache Multilevel, :multilevel_error_cache, levels: @levels

  describe "cache level error" do
    test "fetch/2", %{cache: cache} do
      L1
      |> expect(:fetch, fn _, _ -> {:error, %Nebulex.Error{reason: :error}} end)

      assert cache.fetch(1) == {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
    end

    test "get_all/2", %{cache: cache} do
      L1
      |> expect(:get_all, fn _, _ -> {:error, %Nebulex.Error{reason: :error}} end)

      assert cache.get_all(1) == {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
    end

    test "put/3", %{cache: cache} do
      L1
      |> expect(:put, fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end)

      assert cache.put("hello", "world") ==
               {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
    end

    test "put_all/2", %{cache: cache} do
      L1
      |> expect(:put_all, fn _, _ -> {:error, %Nebulex.Error{reason: :error}} end)

      assert cache.put_all(%{"apples" => 1, "bananas" => 3}) ==
               {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
    end

    test "has_key?/1", %{cache: cache} do
      L1
      |> expect(:has_key?, fn _, _ -> {:error, %Nebulex.Error{reason: :error}} end)

      assert cache.has_key?("error") ==
               {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
    end

    test "expire!/2", %{cache: cache} do
      L1
      |> expect(:expire, fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end)

      assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
        cache.expire!(:raise, 100)
      end
    end

    test "touch!/1", %{cache: cache} do
      L1
      |> expect(:touch, fn _, _ -> {:error, %Nebulex.Error{reason: :error}} end)

      assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
        cache.touch!(:raise)
      end
    end

    test "ttl/1", %{cache: cache} do
      L1
      |> expect(:ttl, fn _, _ -> {:error, %Nebulex.Error{reason: :error}} end)

      assert cache.ttl(1) == {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
    end
  end
end
