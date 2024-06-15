defmodule Nebulex.Error do
  @moduledoc """
  This exception represents command execution errors. For example, the cache
  cannot perform a command because it has not started, it does not exist, or
  the adapter failed to perform it for any reason.

  ## Exception fields

  See `t:t/0`.

  ## Error reasons

  The `:reason` field can assume the following values:

    * `:registry_lookup_error` - the cache cannot be retrieved from
      the registry because it was not started or it does not exist.

    * `:timeout` - if there is a timeout when executing the cache command.

    * `:transaction_aborted` - if a transaction execution fails and aborts.

    * `t:Exception.t/0` - if the underlying adapter fails due to an exception.

    * `t:any/0` - the command fails with an adapter-specific error.

  """

  @typedoc "Error reason type"
  @type reason() :: atom() | {atom(), any()} | Exception.t()

  @typedoc """
  The type for this exception struct.

  This exception has the following public fields:

    * `:reason` - the error reason. It can be one of the Nebulex-specific
      reasons described in the ["Error reasons"](#module-error-reasons)
      section in the module documentation.

    * `:module` - a custom error formatter module. When it is present, it
      invokes `module.format_error(reason, opts)` to format the error reason.
      The argument `opts` is a keyword with the options (or metadata) given
      to the exception. See `format_error/2` for more information.

  """
  @type t() :: %__MODULE__{reason: reason(), module: module(), opts: keyword()}

  # Exception struct
  defexception reason: nil, module: __MODULE__, opts: []

  ## Callbacks

  @impl true
  def exception(opts) do
    {reason, opts} = Keyword.pop!(opts, :reason)
    {module, opts} = Keyword.pop(opts, :module, __MODULE__)

    %__MODULE__{reason: reason, module: module, opts: opts}
  end

  @impl true
  def message(%__MODULE__{reason: reason, module: module, opts: opts}) do
    module.format_error(reason, opts)
  end

  ## Helpers

  @doc """
  A callback invoked when a custom formatter module is provided.

  ## Arguments

    * `reason` - the error reason.
    * `opts` - a keyword with the options (or metadata) given to the exception.

  For example, if an adapter returns:

      wrap_error Nebulex.Error,
        reason: :my_reason,
        module: MyAdapter.Formatter,
        foo: :bar

  the exception invokes:

      MyAdapter.Formatter.format_error(:my_reason, foo: :bar)

  """
  @spec format_error(any(), keyword()) :: binary()
  def format_error(reason, opts)

  def format_error(:registry_lookup_error, opts) do
    cache = Keyword.get(opts, :cache)

    "could not lookup Nebulex cache #{inspect(cache)} because it was " <>
      "not started or it does not exist"
  end

  def format_error(:timeout, _opts) do
    "command execution timed out"
  end

  def format_error(:transaction_aborted, _opts) do
    "transaction aborted"
  end

  def format_error(exception, opts) when is_exception(exception) do
    stacktrace = Keyword.get(opts, :stacktrace, [])

    """
    the following exception occurred when executing a command.

        #{Exception.format(:error, exception, stacktrace) |> String.replace("\n", "\n    ")}

    """
  end

  def format_error(reason, _opts) do
    "command failed with reason: #{inspect(reason)}"
  end
end

defmodule Nebulex.KeyError do
  @moduledoc """
  Raised at runtime when a key does not exist in the cache.

  This exception denotes the cache executed a command, but there was an issue
  with the requested key; for example, it doesn't exist.

  ## Exception fields

  See `t:t/0`.

  ## Error reasons

  The `:reason` field can assume a few Nebulex-specific values:

    * `:not_found` - the key doesn't exist in the cache.

    * `:expired` - The key doesn't exist in the cache because it is expired.

  """

  @typedoc """
  The type for this exception struct.

  This exception has the following public fields:

    * `:key` - the requested key.

    * `:reason` - the error reason. The two possible reasons are `:not_found`
      or `:expired`. Defaults to `:not_found`.

  """
  @type t() :: %__MODULE__{key: any(), reason: atom()}

  # Exception struct
  defexception key: nil, reason: :not_found

  ## Callbacks

  @impl true
  def exception(opts) do
    key = Keyword.fetch!(opts, :key)
    reason = Keyword.get(opts, :reason, :not_found)

    %__MODULE__{key: key, reason: reason}
  end

  @impl true
  def message(%__MODULE__{key: key, reason: reason}) do
    format_reason(reason, key)
  end

  ## Helpers

  defp format_reason(:not_found, key) do
    "key #{inspect(key)} not found"
  end

  defp format_reason(:expired, key) do
    "key #{inspect(key)} has expired"
  end
end

defmodule Nebulex.QueryError do
  @moduledoc """
  Raised at runtime when the query is invalid.
  """

  @typedoc """
  The type for this exception struct.

  This exception has the following public fields:

    * `:message` - the error message.

    * `:query` - the query value.

  """
  @type t() :: %__MODULE__{message: binary(), query: any()}

  # Exception struct
  defexception query: nil, message: nil

  ## Callbacks

  @impl true
  def exception(opts) do
    query = Keyword.fetch!(opts, :query)

    message =
      Keyword.get_lazy(opts, :message, fn ->
        """
        invalid query:

        #{inspect(query)}
        """
      end)

    %__MODULE__{query: query, message: message}
  end
end
