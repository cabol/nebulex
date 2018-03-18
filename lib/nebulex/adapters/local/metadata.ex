defmodule Nebulex.Adapters.Local.Metadata do
  @moduledoc false

  defstruct [generations: [], n_generations: 2]

  @type t :: %__MODULE__{generations: [atom], n_generations: integer}

  alias Nebulex.Adapters.Local.Metadata

  @spec create(cache :: Nebulex.Cache.t, initial :: Metadata.t) :: Metadata.t
  def create(cache, %Metadata{} = initial \\ %Metadata{}) do
    ^cache = :ets.new(cache, [:named_table, read_concurrency: true])
    true = :ets.insert(cache, metadata: initial)
    initial
  end

  @spec get(cache :: Nebulex.Cache.t) :: Metadata.t
  def get(cache) do
    :ets.lookup_element(cache, :metadata, 2)
  end

  @spec update(metadata :: Metadata.t, cache :: Nebulex.Cache.t) :: Metadata.t
  def update(%Metadata{} = metadata, cache) do
    true = :ets.update_element(cache, :metadata, {2, metadata})
    metadata
  end

  @spec new_generation(gen :: atom, cache :: Nebulex.Cache.t) ::
        {generations :: [atom], dropped_generation :: atom | nil}
  def new_generation(gen, cache) do
    metadata = get(cache)

    if length(metadata.generations) >= metadata.n_generations do
      new_metadata =
        metadata
        |> Map.update!(:generations, &([gen | Enum.drop(&1, -1)]))
        |> update(cache)
      {new_metadata.generations, List.last(metadata.generations)}
    else
      new_metadata =
        metadata
        |> Map.update!(:generations, &([gen | &1]))
        |> update(cache)
      {new_metadata.generations, nil}
    end
  end
end
