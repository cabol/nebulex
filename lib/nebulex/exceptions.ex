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

defmodule Nebulex.KeyAlreadyExistsError do
  @moduledoc """
  Raised at runtime when a key already exists in cache.
  """

  @type t :: %__MODULE__{key: term, cache: atom}

  defexception [:key, :cache]

  @doc false
  def message(%{key: key, cache: cache}) do
    "key #{inspect(key)} already exists in cache #{inspect(cache)}"
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
    #{message} in query:

    #{inspect(query, pretty: true)}
    """

    %__MODULE__{message: message}
  end
end

defmodule Nebulex.RPCMultiCallError do
  @moduledoc """
  Raised at runtime when a RPC multi_call error occurs.
  """

  @type t :: %__MODULE__{message: binary}

  defexception [:message]

  @doc false
  def exception(opts) do
    action = Keyword.fetch!(opts, :action)
    errors = Keyword.fetch!(opts, :errors)
    responses = Keyword.fetch!(opts, :responses)

    message = """
    RPC error while executing action #{inspect(action)}

    Successful responses:

    #{inspect(responses, pretty: true)}

    Remote errors:

    #{inspect(errors, pretty: true)}
    """

    %__MODULE__{message: message}
  end
end

defmodule Nebulex.RPCError do
  @moduledoc """
  Raised at runtime when a RPC error occurs.
  """

  @type t :: %__MODULE__{reason: atom, node: node}

  defexception [:reason, :node]

  @doc false
  def message(%__MODULE__{reason: reason, node: node}) do
    format_reason(reason, node)
  end

  # :erpc.call/5 doesn't format error messages.
  defp format_reason({:erpc, _} = reason, node) do
    """
    The RPC operation failed on node #{inspect(node)} with reason:

    #{inspect(reason)}

    See :erpc.call/5 for more information about the error reasons.
    """
  end
end
