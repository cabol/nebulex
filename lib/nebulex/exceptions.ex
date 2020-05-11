defmodule Nebulex.KeyAlreadyExistsError do
  @moduledoc """
  Raised at runtime when a key already exists in cache.
  """
  defexception [:key, :cache]

  @impl true
  def message(%{key: key, cache: cache}) do
    "key #{inspect(key)} already exists in cache #{inspect(cache)}"
  end
end

defmodule Nebulex.QueryError do
  @moduledoc """
  Raised at runtime when the query is invalid.
  """
  defexception [:message]

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
  defexception [:message]

  def exception(opts) do
    action = Keyword.fetch!(opts, :action)
    errors = Keyword.fetch!(opts, :errors)

    message = """
    RPC error executing action: #{action}

    Errors:

    #{inspect(errors, pretty: true)}
    """

    %__MODULE__{message: message}
  end
end
