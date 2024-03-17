defmodule Nebulex.Adapter.Persistence do
  @moduledoc """
  Specifies the adapter Persistence API.
  """

  @doc """
  Dumps a cache to the given file `path`.

  Returns `:ok` if successful, `{:error, reason}` otherwise.

  See `c:Nebulex.Cache.dump/2`.
  """
  @callback dump(Nebulex.Adapter.adapter_meta(), Path.t(), Nebulex.Cache.opts()) ::
              :ok | Nebulex.Cache.error_tuple()

  @doc """
  Loads a dumped cache from the given `path`.

  Returns `:ok` if successful, `{:error, reason}` otherwise.

  See `c:Nebulex.Cache.load/2`.
  """
  @callback load(Nebulex.Adapter.adapter_meta(), Path.t(), Nebulex.Cache.opts()) ::
              :ok | Nebulex.Cache.error_tuple()
end
