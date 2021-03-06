defmodule Nebulex.Adapter.Queryable do
  @moduledoc """
  Specifies the query API required from adapters.

  ## Query values

  There are two types of query values. The ones shared and implemented
  by all adapters and the ones that are adapter specific.

  ### Common queries

  The following query values are shared and/or supported for all adapters:

    * `nil` - Matches all cached entries.

  ### Adapter-specific queries

  The `query` value depends entirely on the adapter implementation; it could
  any term. Therefore, it is highly recommended to see adapters' documentation
  for more information about building queries. For example, the built-in
  `Nebulex.Adapters.Local` adapter uses `:ets.match_spec()` for queries,
  as well as other pre-defined ones like `:unexpired` and `:expired`.
  """

  @typedoc "Proxy type to the adapter meta"
  @type adapter_meta :: Nebulex.Adapter.adapter_meta()

  @typedoc "Proxy type to the cache options"
  @type opts :: Nebulex.Cache.opts()

  @doc """
  Executes the `query` according to the given `operation`.

  Raises `Nebulex.QueryError` if query is invalid.

  In the the adapter does not support the given `operation`, an `ArgumentError`
  exception should be raised.

  ## Operations

    * `:all` - Returns a list with all entries from cache matching the given
      `query`.
    * `:count_all` - Returns the number of matched entries with the given
      `query`.
    * `:delete_all` - Deletes all entries matching the given `query`.
      It returns the number of deleted entries.

  It is used on `c:Nebulex.Cache.all/2`, `c:Nebulex.Cache.count_all/2`,
  and `c:Nebulex.Cache.delete_all/2`.
  """
  @callback execute(
              adapter_meta,
              operation :: :all | :count_all | :delete_all,
              query :: term,
              opts
            ) :: [term] | integer

  @doc """
  Streams the given `query`.

  Raises `Nebulex.QueryError` if query is invalid.

  See `c:Nebulex.Cache.stream/2`.
  """
  @callback stream(adapter_meta, query :: term, opts) :: Enumerable.t()
end
