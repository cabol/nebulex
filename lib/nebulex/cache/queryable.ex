defmodule Nebulex.Cache.Queryable do
  @moduledoc false

  import Nebulex.Adapter, only: [defcommandp: 1, defcommandp: 2]
  import Nebulex.Utils, only: [unwrap_or_raise: 1]

  alias Nebulex.Cache.{Options, QuerySpec}

  @doc """
  Implementation for `c:Nebulex.Cache.get_all/2`.
  """
  def get_all(name, query_spec, opts) do
    execute(name, query_meta(query_spec, :get_all), opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.get_all!/2`.
  """
  def get_all!(name, query_spec, opts) do
    unwrap_or_raise get_all(name, query_spec, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.count_all/2`.
  """
  def count_all(name, query_spec, opts) do
    execute(name, query_meta(query_spec, :count_all), opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.count_all!/2`.
  """
  def count_all!(name, query_spec, opts) do
    unwrap_or_raise count_all(name, query_spec, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.delete_all/2`.
  """
  def delete_all(name, query_spec, opts) do
    execute(name, query_meta(query_spec, :delete_all), opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.delete_all!/2`.
  """
  def delete_all!(name, query_spec, opts) do
    unwrap_or_raise delete_all(name, query_spec, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.stream/2`.
  """
  def stream(name, query_spec, opts) do
    opts = Options.validate_stream_opts!(opts)

    do_stream(name, query_meta(query_spec, :stream), opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.stream!/2`.
  """
  def stream!(name, query, opts) do
    unwrap_or_raise stream(name, query, opts)
  end

  ## Private functions

  # Inline common instructions
  @compile {:inline, execute: 3, do_stream: 3}

  # Execute wrapper
  defcommandp execute(name, query_meta, opts)

  # Stream wrapper
  defcommandp do_stream(name, query_spec, opts), command: :stream

  # Helper for building the query
  defp query_meta(query_spec, op) when is_list(query_spec) do
    query_spec = QuerySpec.validate!(query_spec)

    select = Keyword.fetch!(query_spec, :select)

    query =
      case Keyword.fetch(query_spec, :in) do
        {:ok, keys} -> {:in, keys}
        :error -> {:q, Keyword.fetch!(query_spec, :query)}
      end

    %{op: op, select: select, query: query}
  end

  defp query_meta(query_spec, _op) do
    raise ArgumentError, "invalid query spec: expected a keyword list, got: #{inspect(query_spec)}"
  end
end
