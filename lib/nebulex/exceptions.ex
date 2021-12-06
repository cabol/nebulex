defmodule Nebulex.Error do
  @moduledoc """
  Nebulex error.
  """

  @type reason :: :atom | {:atom, term}

  @type t :: %__MODULE__{reason: reason, module: module}

  defexception reason: nil, module: __MODULE__

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

  def format_error({:registry_error, name_or_pid}) do
    "could not lookup Nebulex cache #{inspect(name_or_pid)} because it was " <>
      "not started or it does not exist"
  end

  def format_error({:transaction_aborted, cache, nodes}) do
    "Cache #{inspect(cache)} has aborted a transaction on nodes: #{inspect(nodes)}"
  end

  def format_error(exception) when is_exception(exception) do
    exception.__struct__.message(exception)
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

  @type t :: %__MODULE__{key: term, cache: atom, reason: atom}

  defexception [:key, :cache, :reason]

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

defmodule Nebulex.RegistryLookupError do
  @moduledoc """
  Raised at runtime when the cache was not started or it does not exist.
  """

  @type t :: %__MODULE__{message: binary, name: atom}

  defexception [:message, :name]

  @doc false
  def exception(opts) do
    name = Keyword.fetch!(opts, :name)

    msg =
      "could not lookup Nebulex cache #{inspect(name)} because it was " <>
        "not started or it does not exist"

    %__MODULE__{message: msg, name: name}
  end
end

defmodule Nebulex.QueryError do
  @moduledoc """
  Raised at runtime when the query is invalid.
  """

  @type t :: %__MODULE__{message: binary}

  defexception [:message]

  @doc false
  def exception(opts) do
    message = Keyword.fetch!(opts, :message)
    query = Keyword.fetch!(opts, :query)

    message = """
    #{message}

    #{inspect(query, pretty: true)}
    """

    %__MODULE__{message: message}
  end
end

defmodule Nebulex.RPCMulticallError do
  @moduledoc """
  Raised at runtime when a RPC multi_call error occurs.
  """

  @type t :: %__MODULE__{action: atom, errors: [term], responses: [term]}

  defexception [:action, :errors, :responses]

  @doc false
  def exception(opts) do
    action = Keyword.fetch!(opts, :action)
    errors = Keyword.fetch!(opts, :errors)
    responses = Keyword.fetch!(opts, :responses)

    %__MODULE__{action: action, errors: errors, responses: responses}
  end

  @doc false
  def message(%__MODULE__{action: action, errors: errors, responses: responses}) do
    """
    RPC error while executing action #{inspect(action)}

    Successful responses:

    #{inspect(responses, pretty: true)}

    Remote errors:

    #{inspect(errors, pretty: true)}
    """
  end
end

defmodule Nebulex.RPCError do
  @moduledoc """
  Raised at runtime when a RPC error occurs.
  """

  @type t :: %__MODULE__{reason: term, node: node}

  defexception [:reason, :node]

  @doc false
  def message(%__MODULE__{reason: reason, node: node}) do
    "RPC call failed on node #{inspect(node)} with reason: #{inspect(reason)}"
  end
end
