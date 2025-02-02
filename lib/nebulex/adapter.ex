defmodule Nebulex.Adapter do
  @moduledoc """
  Specifies the minimal API required from adapters.
  """

  import Nebulex.Utils, only: [is_nebulex_wrappable_exception: 1]

  alias Nebulex.Cache.Options
  alias Nebulex.Error, as: NbxError
  alias Nebulex.Telemetry

  @typedoc "Adapter"
  @type t() :: module()

  @typedoc """
  The metadata returned by the adapter `c:init/1`.

  It must be a map and Nebulex itself will always inject
  the following keys into the meta:

    * `:cache` - The defined cache module.
    * `:name` - The name of the cache supervisor process.
    * `:pid` - The PID returned by the child spec returned in `c:init/1`.
    * `:adapter` - The defined cache adapter.
    * `:telemetry` - Whether Telemetry is enabled or not.
    * `:telemetry_prefix` – The Telemetry prefix.

  """
  @type adapter_meta() :: %{optional(atom()) => any()}

  @typedoc "Nebulex wrappable error types"
  @type nbx_error() :: Nebulex.Error.t() | Nebulex.KeyError.t()

  ## Callbacks

  @doc """
  The callback invoked in case the adapter needs to inject code.
  """
  @macrocallback __before_compile__(env :: Macro.Env.t()) :: Macro.t()

  @doc """
  Initializes the adapter supervision tree by returning the children
  and adapter metadata.
  """
  @callback init(config :: keyword()) :: {:ok, :supervisor.child_spec(), adapter_meta()}

  # Define optional callbacks
  @optional_callbacks __before_compile__: 1

  ## API

  # Inline common instructions
  @compile {:inline, lookup_meta: 1}

  @doc """
  Returns the adapter metadata from its `c:init/1` callback.

  It expects a process name of the cache. The name is either
  an atom or a PID. For a given cache, you often want to call
  this function based on the dynamic cache:

      Nebulex.Adapter.lookup_meta(cache.get_dynamic_cache())

  """
  @spec lookup_meta(atom() | pid()) :: adapter_meta()
  defdelegate lookup_meta(name_or_pid), to: Nebulex.Cache.Registry, as: :lookup

  ## Helpers

  @doc """
  Builds up a public wrapper function for invoking an adapter command.

  **NOTE:** Internal purposes only.
  """
  defmacro defcommand(fun, opts \\ []) do
    build_defcommand(:public, fun, opts)
  end

  @doc """
  Builds up a private wrapper function for invoking an adapter command.

  **NOTE:** Internal purposes only.
  """
  defmacro defcommandp(fun, opts \\ []) do
    build_defcommand(:private, fun, opts)
  end

  defp build_defcommand(public_or_private, fun, opts) do
    # Decompose the function call
    {function_name, [name_or_pid | args_tl] = args} = Macro.decompose_call(fun)

    # Get the command or action
    command = Keyword.get(opts, :command, function_name)

    # Split the arguments to get the last one (options argument)
    {args_tl, opts_arg} =
      with {trimmed_args_tl, [value]} <- Enum.split(args_tl, -1) do
        {trimmed_args_tl, value}
      end

    # Build the function
    case public_or_private do
      :public ->
        quote do
          def unquote(function_name)(unquote_splicing(args)) do
            unquote(command_call(name_or_pid, command, args_tl, opts_arg))
          end
        end

      :private ->
        quote do
          defp unquote(function_name)(unquote_splicing(args)) do
            unquote(command_call(name_or_pid, command, args_tl, opts_arg))
          end
        end
    end
  end

  defp command_call(name_or_pid, command, args, opts_arg) do
    quote do
      unquote(name_or_pid)
      |> unquote(__MODULE__).lookup_meta()
      |> unquote(__MODULE__).run_command(
        unquote(command),
        unquote(args),
        unquote(opts_arg)
      )
      |> unquote(__MODULE__).handle_command_response()
    end
  end

  @doc """
  Convenience function for invoking the adapter running a command.

  **NOTE:** Internal purposes only.
  """
  @spec run_command(adapter_meta(), atom(), [any()], keyword()) :: any()
  def run_command(
        %{
          telemetry: telemetry?,
          telemetry_prefix: telemetry_prefix,
          adapter: adapter
        } = adapter_meta,
        command,
        args,
        opts
      ) do
    opts = Options.validate_telemetry_opts!(opts)
    args = args ++ [opts]

    if telemetry? do
      metadata = %{
        adapter_meta: adapter_meta,
        command: command,
        args: args,
        extra_metadata: Keyword.get(opts, :telemetry_metadata, %{})
      }

      opts
      |> Keyword.get(:telemetry_event, telemetry_prefix ++ [:command])
      |> Telemetry.span(
        metadata,
        fn ->
          result = apply(adapter, command, [adapter_meta | args])

          {result, Map.put(metadata, :result, result)}
        end
      )
    else
      apply(adapter, command, [adapter_meta | args])
    end
  end

  @doc """
  Helper function for handling a Nebulex command response.

  ## Examples

      iex> Nebulex.Adapter.handle_command_response({:ok, "ok"})
      {:ok, "ok"}

      iex> Nebulex.Adapter.handle_command_response(:ok)
      :ok

      iex> Nebulex.Adapter.handle_command_response(
      ...>   {:error, %Nebulex.Error{reason: :error}}
      ...> )
      {:error, %Nebulex.Error{reason: :error}}

      iex> Nebulex.Adapter.handle_command_response({:error, :error})
      {:error, %Nebulex.Error{reason: :error}}

      iex> Nebulex.Adapter.handle_command_response({:error, %RuntimeError{}})
      {:error, %Nebulex.Error{reason: %RuntimeError{}}}

  """
  @spec handle_command_response(ok | {:error, any()}) :: ok | {:error, nbx_error()}
        when ok: :ok | {:ok, any()}
  def handle_command_response(response)

  def handle_command_response({:ok, _} = ok) do
    ok
  end

  def handle_command_response(:ok) do
    :ok
  end

  def handle_command_response({:error, reason} = error)
      when is_nebulex_wrappable_exception(reason) do
    error
  end

  def handle_command_response({:error, reason}) do
    {:error, NbxError.exception(reason: reason)}
  end
end
