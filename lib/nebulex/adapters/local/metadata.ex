defmodule Nebulex.Adapters.Local.Metadata do
  @moduledoc false

  @type tab :: :ets.tid() | atom

  @spec init :: tab
  def init do
    :ets.new(__MODULE__, [:public, read_concurrency: true])
  end

  @spec get(tab, term, term) :: term
  def get(tab, key, default \\ nil) do
    :ets.lookup_element(tab, key, 2)
  rescue
    ArgumentError -> default
  end

  @spec fetch!(tab, term) :: term
  def fetch!(tab, key) do
    :ets.lookup_element(tab, key, 2)
  end

  @spec put(tab, term, term) :: :ok
  def put(tab, key, value) do
    true = :ets.insert(tab, {key, value})
    :ok
  end
end
