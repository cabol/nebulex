defmodule Nebulex.Error do
  @moduledoc """
  This exception represents command execution errors. For example, the cache
  cannot perform a command because it has not started, it does not exist, or
  the adapter failed to perform it for any reason.

  ## Exception fields

  See `t:t/0`.

  ## Error reasons

  The `:reason` field can assume the following values:

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
      invokes `module.format_error(reason, metadata)` to format the error
      reason. The argument `metadata` is a keyword with the metadata given
      to the exception. See `format_error/2` for more information.

    * `:metadata` - the metadata contains the options given to the
      exception excluding the `:reason` and `:module` that are part
      of the exception fields. For example, when raising an exception
      `raise Nebulex.Error, reason: :test, foo: :bar`, the metadata
      will be `[foo: :bar]`.

  """
  @type t() :: %__MODULE__{reason: reason(), module: module(), metadata: keyword()}

  # Exception struct
  defexception reason: nil, module: __MODULE__, metadata: []

  ## Callbacks

  @impl true
  def exception(opts) do
    {reason, opts} = Keyword.pop!(opts, :reason)
    {module, opts} = Keyword.pop(opts, :module, __MODULE__)

    %__MODULE__{reason: reason, module: module, metadata: opts}
  end

  @impl true
  def message(%__MODULE__{reason: reason, module: module, metadata: metadata}) do
    module.format_error(reason, metadata)
  end

  ## Helpers

  @doc """
  A callback invoked when a custom formatter module is provided.

  ## Arguments

    * `reason` - the error reason.
    * `metadata` - a keyword with the metadata given to the exception.

  For example, if an adapter returns:

      wrap_error Nebulex.Error,
        reason: :my_reason,
        module: MyAdapter.Formatter,
        foo: :bar

  the exception invokes:

      MyAdapter.Formatter.format_error(:my_reason, foo: :bar)

  """
  @spec format_error(any(), keyword()) :: binary()
  def format_error(reason, metadata)

  def format_error(:timeout, metadata) do
    "command execution timed out"
    |> maybe_format_metadata(metadata)
  end

  def format_error(:transaction_aborted, metadata) do
    "transaction aborted"
    |> maybe_format_metadata(metadata)
  end

  def format_error(exception, metadata) when is_exception(exception) do
    {stacktrace, metadata} = Keyword.pop(metadata, :stacktrace, [])

    """
    the following exception occurred when executing a command.

        #{Exception.format(:error, exception, stacktrace) |> String.replace("\n", "\n    ")}
    """
    |> maybe_format_metadata(metadata)
  end

  def format_error(reason, metadata) do
    "command failed with reason: #{inspect(reason)}"
    |> maybe_format_metadata(metadata)
  end

  @doc """
  Formats the error metadata when not empty.
  """
  @spec maybe_format_metadata(binary(), keyword()) :: binary()
  def maybe_format_metadata(msg, metadata) do
    if Enum.count(metadata) > 0 do
      """
      #{msg}

      Error metadata:

      #{inspect(metadata)}
      """
    else
      msg
    end
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

    * `:reason` - the error reason. The two possible reasons are `:not_found`
      or `:expired`. Defaults to `:not_found`.

    * `:key` - the requested key.

    * `:metadata` - the metadata contains the options given to the
      exception excluding the `:reason` and `:key` that are part of
      the exception fields. For example, when raising an exception
      `raise Nebulex.KeyError, key: :test, foo: :bar`, the metadata
      will be `[foo: :bar]`.

  """
  @type t() :: %__MODULE__{reason: atom(), key: any(), metadata: keyword()}

  # Exception struct
  defexception reason: :not_found, key: nil, metadata: []

  import Nebulex.Error, only: [maybe_format_metadata: 2]

  ## Callbacks

  @impl true
  def exception(opts) do
    {key, opts} = Keyword.pop!(opts, :key)
    {reason, opts} = Keyword.pop(opts, :reason, :not_found)

    %__MODULE__{reason: reason, key: key, metadata: opts}
  end

  @impl true
  def message(%__MODULE__{reason: reason, key: key, metadata: metadata}) do
    format_reason(reason, key, metadata)
  end

  ## Helpers

  defp format_reason(:not_found, key, metadata) do
    "key #{inspect(key)} not found"
    |> maybe_format_metadata(metadata)
  end

  defp format_reason(:expired, key, metadata) do
    "key #{inspect(key)} has expired"
    |> maybe_format_metadata(metadata)
  end
end

defmodule Nebulex.CacheNotFoundError do
  @moduledoc """
  It is raised when the cache cannot be retrieved from the registry
  because it was not started or does not exist.
  """

  @typedoc """
  The type for this exception struct.

  This exception has the following public fields:

    * `:message` - the error message.

    * `:cache` - the cache name or its PID.

  """
  @type t() :: %__MODULE__{message: binary(), cache: atom() | pid()}

  # Exception struct
  defexception message: nil, cache: nil

  @impl true
  def exception(opts) do
    cache = Keyword.fetch!(opts, :cache)

    msg =
      "unable to find cache: #{inspect(cache)}. Either the cache name is " <>
        "invalid or the cache is not running, possibly because it is not " <>
        "started or does not exist"

    %__MODULE__{message: msg, cache: cache}
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
  defexception message: nil, query: nil

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
