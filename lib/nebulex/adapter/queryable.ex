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

  This callback returns:

    * `{:ok, query_result}` - the query is valid, then it is executed
      and the result returned.

    * `{:error, Nebulex.QueryError.t()}` - the query validation failed.

    * `{:error, reason}` - an error occurred while executing the command.

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
            ) ::
              Nebulex.Cache.ok_error_tuple(
                [term] | non_neg_integer,
                Nebulex.Cache.query_error_reason()
              )

  @doc """
  Streams the given `query`.

  This callback returns:

    * `{:ok, stream}` - the query is valid, then the stream is built
      and returned.

    * `{:error, Nebulex.QueryError.t()}` - the query validation failed.

    * `{:error, reason}` - an error occurred while executing the command.

  See `c:Nebulex.Cache.stream/2`.
  """
  @callback stream(adapter_meta, query :: term, opts) ::
              Nebulex.Cache.ok_error_tuple(Enumerable.t(), Nebulex.Cache.query_error_reason())
end
