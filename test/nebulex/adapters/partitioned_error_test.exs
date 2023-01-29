defmodule Nebulex.Adapters.PartitionedErrorTest do
  use ExUnit.Case, async: true
  use Mimic

  # Inherit error tests
  use Nebulex.Cache.EntryErrorTest
  use Nebulex.Cache.EntryExpirationErrorTest

  import Nebulex.CacheCase, only: [setup_with_dynamic_cache: 2]

  setup_with_dynamic_cache Nebulex.TestCache.Partitioned, :partitioned_error_cache

  setup do
    Nebulex.RPC
    |> stub(:call, fn _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end)
    |> stub(:multicall, fn _ -> {[], [:error]} end)
    |> stub(:multicall, fn _, _ -> {[], [:error]} end)
    |> stub(:multicall, fn _, _, _, _ -> {[], [:error]} end)
    |> stub(:multicall, fn _, _, _, _, _ -> {[], [:error]} end)

    {:ok,
     %{
       error_module: &(&1 in [Nebulex.Error, Nebulex.RPC]),
       error_reason: &(&1 in [:error, {:rpc_multicall_error, [:error]}])
     }}
  end
end
