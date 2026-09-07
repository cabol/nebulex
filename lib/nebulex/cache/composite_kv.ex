defmodule Nebulex.Cache.CompositeKV do
  @moduledoc false

  import Nebulex.Adapter, only: [defcommandp: 2]
  import Nebulex.Utils, only: [unwrap_or_raise: 1]

  alias Nebulex.Cache.Options

  # Inline common instructions
  @compile inline: [
             do_get_and_update: 6,
             do_update: 7,
             do_fetch_or_store: 6,
             do_get_or_store: 6
           ]

  @doc """
  Implementation for `c:Nebulex.Cache.get_and_update/3`.
  """
  def get_and_update(name, key, fun, opts) when is_function(fun, 1) do
    {ttl, opts} = Options.pop_and_validate_timeout!(opts, :ttl)
    {keep_ttl?, opts} = Options.pop_and_validate_boolean!(opts, :keep_ttl)

    do_get_and_update(name, key, fun, ttl, keep_ttl?, opts)
  end

  defcommandp do_get_and_update(name, key, fun, ttl, keep_ttl?, opts), command: :get_and_update

  @doc """
  Implementation for `c:Nebulex.Cache.get_and_update!/3`.
  """
  def get_and_update!(name, key, fun, opts) do
    unwrap_or_raise get_and_update(name, key, fun, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.update/4`.
  """
  def update(name, key, initial, fun, opts) when is_function(fun, 1) do
    {ttl, opts} = Options.pop_and_validate_timeout!(opts, :ttl)
    {keep_ttl?, opts} = Options.pop_and_validate_boolean!(opts, :keep_ttl)

    do_update(name, key, initial, fun, ttl, keep_ttl?, opts)
  end

  defcommandp do_update(name, key, initial, fun, ttl, keep_ttl?, opts), command: :update

  @doc """
  Implementation for `c:Nebulex.Cache.update!/4`.
  """
  def update!(name, key, initial, fun, opts) do
    unwrap_or_raise update(name, key, initial, fun, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.fetch_or_store/3`.
  """
  def fetch_or_store(name, key, fun, opts) do
    {ttl, opts} = Options.pop_and_validate_timeout!(opts, :ttl)
    {keep_ttl?, opts} = Options.pop_and_validate_boolean!(opts, :keep_ttl)

    do_fetch_or_store(name, key, fun, ttl, keep_ttl?, opts)
  end

  defcommandp do_fetch_or_store(name, key, fun, ttl, keep_ttl?, opts), command: :fetch_or_store

  @doc """
  Implementation for `c:Nebulex.Cache.fetch_or_store!/3`.
  """
  def fetch_or_store!(name, key, fun, opts) do
    unwrap_or_raise fetch_or_store(name, key, fun, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.get_or_store/3`.
  """
  def get_or_store(name, key, fun, opts) do
    {ttl, opts} = Options.pop_and_validate_timeout!(opts, :ttl)
    {keep_ttl?, opts} = Options.pop_and_validate_boolean!(opts, :keep_ttl)

    do_get_or_store(name, key, fun, ttl, keep_ttl?, opts)
  end

  defcommandp do_get_or_store(name, key, fun, ttl, keep_ttl?, opts), command: :get_or_store

  @doc """
  Implementation for `c:Nebulex.Cache.get_or_store!/3`.
  """
  def get_or_store!(name, key, fun, opts) do
    unwrap_or_raise get_or_store(name, key, fun, opts)
  end
end
