defmodule Nebulex.Adapter.Queryable do
  @moduledoc """
  Specifies the query API required from adapters.

  ## Query values

  If `nil` is given as query value, all entries in cache will match and return
  based on the `:return` option. Only the `nil` query is shared for all the
  adapters. Other than `nil` query, the adapter is responsible to define the
  query specification. For example, the built-in `Nebulex.Adapters.Local`
  adapter defines `:ets.match_spec()`, `:unexpired` and `:expired` as query
  values aside form `nil`.
  """

  @doc """
  Fetches all entries from cache matching the given `query`.

  Raises `Nebulex.QueryError` if query is invalid.

  See `c:Nebulex.Cache.all/2`.
  """
  @callback all(Nebulex.Adapter.adapter_meta(), query :: any, Nebulex.Cache.opts()) :: [any]

  @doc """
  Streams the given `query`.

  Raises `Nebulex.QueryError` if query is invalid.

  See `c:Nebulex.Cache.stream/2`.
  """
  @callback stream(Nebulex.Adapter.adapter_meta(), query :: any, Nebulex.Cache.opts()) ::
              Enumerable.t()
end
