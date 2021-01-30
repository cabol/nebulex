defmodule Nebulex.Adapter.Queryable do
  @moduledoc """
  Specifies the query API required from adapters.

  ## Query values

  Only the `nil` query is shared for all the adapters and it means all entries
  in cache will match and the returned values depend on the `:return` option.
  In case of `delete_all/3`, all enetris are deleted.. Other than `nil` query,
  the adapter is responsible to define the query specification. For example,
  the built-in `Nebulex.Adapters.Local` adapter defines `:ets.match_spec()`,
  `:unexpired` and `:expired` as query values aside form `nil`.
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

  @doc """
  Deletes all entries matching the given `query`.

  It returns the number of deleted entries.

  Raises `Nebulex.QueryError` if query is invalid.

  See `c:Nebulex.Cache.delete_all/2`.
  """
  @callback delete_all(Nebulex.Adapter.adapter_meta(), query :: any, Nebulex.Cache.opts()) ::
              integer
end
