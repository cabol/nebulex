defmodule Nebulex.Adapters.Local.Metadata do
  @moduledoc false

  defstruct generations: [], max_generations: 2

  @type t :: %__MODULE__{generations: [atom], max_generations: pos_integer}

  @spec create(cache :: Nebulex.Cache.t(), initial :: t) :: t
  def create(cache, %__MODULE__{} = initial \\ %__MODULE__{}) do
    ^cache = :ets.new(cache, [:named_table, read_concurrency: true])
    true = :ets.insert(cache, metadata: initial)
    initial
  end

  @spec get(cache :: Nebulex.Cache.t()) :: t
  def get(cache) do
    :ets.lookup_element(cache, :metadata, 2)
  end

  @spec update(metadata :: t, cache :: Nebulex.Cache.t()) :: t
  def update(%__MODULE__{} = metadata, cache) do
    true = :ets.update_element(cache, :metadata, {2, metadata})
    metadata
  end

  @spec push_generation(gen :: atom, cache :: Nebulex.Cache.t()) :: t
  def push_generation(gen, cache) do
    cache
    |> get()
    |> push_generation(gen, cache)
  end

  ## Private Functions

  defp push_generation(%__MODULE__{generations: gens, max_generations: max} = meta, gen, cache)
       when length(gens) >= max do
    meta
    |> Map.update!(:generations, &[gen | Enum.drop(&1, -1)])
    |> update(cache)
    |> delete_generation(cache, List.last(gens))
  end

  defp push_generation(%__MODULE__{} = meta, gen, cache) do
    meta
    |> Map.update!(:generations, &[gen | &1])
    |> update(cache)
  end

  defp delete_generation(meta, cache, dropped) do
    _ = cache.__backend__.delete(dropped)
    meta
  end
end
