defmodule Nebulex.Error do
  @moduledoc """
  Nebulex error.
  """

  @typedoc "Error reason type"
  @type reason :: :atom | {:atom, term}

  @typedoc "Error type"
  @type t :: %__MODULE__{reason: reason, module: module}

  # Exception struct
  defexception reason: nil, module: __MODULE__

  ## API

  @doc false
  def exception(opts) do
    reason = Keyword.fetch!(opts, :reason)
    module = Keyword.get(opts, :module, __MODULE__)

    %__MODULE__{reason: reason, module: module}
  end

  @doc false
  def message(%__MODULE__{reason: reason, module: module}) do
    module.format_error(reason)
  end

  ## Helpers

  def format_error({:registry_lookup_error, name_or_pid}) do
    "could not lookup Nebulex cache #{inspect(name_or_pid)} because it was " <>
      "not started or it does not exist"
  end

  def format_error({:transaction_aborted, cache, nodes}) do
    "cache #{inspect(cache)} has aborted a transaction on nodes: #{inspect(nodes)}"
  end

  def format_error({:stats_error, cache}) do
    "stats disabled or not supported by the cache #{inspect(cache)}"
  end

  def format_error(exception) when is_exception(exception) do
    Exception.message(exception)
  end

  def format_error(reason) do
    """
    Nebulex error:

    #{inspect(reason, pretty: true)}
    """
  end
end

defmodule Nebulex.KeyError do
  @moduledoc """
  Raised at runtime when a key does not exist in cache.
  """

  @typedoc "Error type"
  @type t :: %__MODULE__{key: term, cache: atom, reason: atom}

  # Exception struct
  defexception [:key, :cache, :reason]

  ## API

  @doc false
  def exception(opts) do
    key = Keyword.fetch!(opts, :key)
    cache = Keyword.fetch!(opts, :cache)
    reason = Keyword.get(opts, :reason, :not_found)

    %__MODULE__{key: key, cache: cache, reason: reason}
  end

  @doc false
  def message(%__MODULE__{key: key, cache: cache, reason: reason}) do
    format_reason(reason, key, cache)
  end

  ## Helpers

  defp format_reason(:not_found, key, cache) do
    "key #{inspect(key)} not found in cache: #{inspect(cache)}"
  end

  defp format_reason(:expired, key, cache) do
    "key #{inspect(key)} has expired in cache: #{inspect(cache)}"
  end
end

defmodule Nebulex.QueryError do
  @moduledoc """
  Raised at runtime when the query is invalid.
  """

  @typedoc "Error type"
  @type t :: %__MODULE__{message: binary}

  # Exception struct
  defexception [:message]

  ## API

  @doc false
  def exception(opts) do
    query = Keyword.fetch!(opts, :query)

    message =
      Keyword.get_lazy(opts, :message, fn ->
        "invalid query #{inspect(query, pretty: true)}"
      end)

    %__MODULE__{message: message}
  end
end
