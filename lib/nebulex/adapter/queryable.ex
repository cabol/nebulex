defmodule Nebulex.Adapter.Queryable do
  @moduledoc """
  Specifies the adapter Query API.
  """

  @typedoc "Proxy type to the adapter meta"
  @type adapter_meta() :: Nebulex.Adapter.adapter_meta()

  @typedoc "Proxy type to the cache options"
  @type opts() :: Nebulex.Cache.opts()

  @typedoc """
  Query metadata fields.

  ## Operation

  The field `:op` defines the type of query operation. The possible values are:

    * `:get_all` - Returns a list with all entries from cache matching the given
      query.
    * `:count_all` - Returns the number of matched entries with the given query.
    * `:delete_all` - Deletes all entries matching the given query. It returns
      the number of deleted entries.
    * `:stream` - Similar to `:get_all` but returns a lazy enumerable that emits
      all entries from the cache matching the given query.

  ## Query

  The field `:query` defines the entries in the cache to match. There are two
  types of query values. The ones recommended by Nebulex for all adapters to
  implement (shared queries) and the adapter-specific ones.

  ### Shared queries

  The following query values are the ones recommended by Nebulex
  for all adapters to implement:

    * `{:in, keys}` - Query the entries associated with the set of `keys`
      requested.
    * `{:q, nil}` - Query all the entries in the cache.

  ### Adapter-specific queries

  For any other query the value must be:

    * `{:q, query_value}` - Queries the entries in the cache matching with the
      given `query_value`.

  The `query_value` depends entirely on the adapter implementation, it could
  any term. Therefore, it is highly recommended to see adapters' documentation
  for more information about building queries. For example, the
  `Nebulex.Adapters.Local` adapter supports
  [**"ETS Match Spec"**](https://www.erlang.org/doc/man/ets#match_spec).

  ## Select fields to return

  The field `:select` defines the fields of the cached entry to return.

  See [Nebulex.Cache.get_all/2 options][get_all_opts] for the possible values.

  [get_all_opts]: https://hexdocs.pm/nebulex/Nebulex.Cache.html#c:get_all/2-options
  """
  @type query_meta() :: %{
          op: :get_all | :count_all | :delete_all,
          query: {:in, [keys :: any()]} | {:q, query_value :: any()},
          select: {:key, :value} | :key | :value | :entry
        }

  @doc """
  Executes a previously prepared query.

  The `query_meta` field is a map containing some fields found in the query
  options after they have been normalized. For example, the query value and
  the selected entry fields to return can be found in the `query_meta`.

   Finally, `opts` is a keyword list of options given to the `Nebulex.Cache`
   operation that triggered the adapter call. Any option is allowed, as this
   is a mechanism to customize the adapter behavior per operation.

  This callback returns:

    * `{:ok, result}` - The query was successfully executed. The `result`
      could be a list with the matched entries or its count.

    * `{:error, reason}` - An error occurred executing the command.
      `reason` is the cause of the error.

  It is used on `c:Nebulex.Cache.get_all/2`, `c:Nebulex.Cache.count_all/2`,
  and `c:Nebulex.Cache.delete_all/2`.
  """
  @callback execute(adapter_meta(), query_meta(), opts()) ::
              Nebulex.Cache.ok_error_tuple([any()] | non_neg_integer())

  @doc """
  Streams a previously prepared query.

  See `c:execute/3` for a description of arguments.

  This callback returns:

    * `{:ok, stream}` - The query is valid, then the stream is returned.

    * `{:error, reason}` - An error occurred executing the command.
      `reason` is the cause of the error.

  See `c:Nebulex.Cache.stream/2`.
  """
  @callback stream(adapter_meta(), query_meta(), opts()) ::
              Nebulex.Cache.ok_error_tuple(Enumerable.t())
end
