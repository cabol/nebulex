defmodule Nebulex.Adapter do
  @moduledoc """
  Specifies the minimal API required from adapters.
  """

  alias Nebulex.Telemetry

  @typedoc "Adapter"
  @type t :: module

  @typedoc "Metadata type"
  @type metadata :: %{optional(atom) => term}

  @typedoc """
  The metadata returned by the adapter `c:init/1`.

  It must be a map and Nebulex itself will always inject
  the following keys into the meta:

    * `:cache` - The cache module.
    * `:pid` - The PID returned by the child spec returned in `c:init/1`.
    * `:adapter` - The defined cache adapter.

  """
  @type adapter_meta :: metadata

  ## Callbacks

  @doc """
  The callback invoked in case the adapter needs to inject code.
  """
  @macrocallback __before_compile__(env :: Macro.Env.t()) :: Macro.t()

  @doc """
  Initializes the adapter supervision tree by returning the children.
  """
  @callback init(config :: keyword) :: {:ok, :supervisor.child_spec(), adapter_meta}

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
  @spec lookup_meta(atom | pid) :: {:ok, adapter_meta} | {:error, Nebulex.Error.t()}
  defdelegate lookup_meta(name_or_pid), to: Nebulex.Cache.Registry, as: :lookup

  @doc """
  Executes the function `fun` passing as parameters the adapter and metadata
  (from the `c:init/1` callback) associated with the given cache `name_or_pid`.

  It expects a name or a PID representing the cache.
  """
  @spec with_meta(atom | pid, (adapter_meta -> term)) :: term | {:error, Nebulex.Error.t()}
  def with_meta(name_or_pid, fun) do
    with {:ok, adapter_meta} <- lookup_meta(name_or_pid) do
      fun.(adapter_meta)
    end
  end

  # FIXME: ExCoveralls does not mark most of this section as covered
  # coveralls-ignore-start

  @doc """
  Helper macro for the adapters so they can add the logic for emitting the
  recommended Telemetry events.

  See the built-in adapters for more information on how to use this macro.
  """
  defmacro defspan(fun, opts \\ [], do: block) do
    {name, [adapter_meta | args_tl], as, [_ | as_args_tl] = as_args} = build_defspan(fun, opts)

    quote do
      def unquote(name)(unquote_splicing(as_args))

      def unquote(name)(%{telemetry: false} = unquote(adapter_meta), unquote_splicing(args_tl)) do
        unquote(block)
      end

      def unquote(name)(unquote_splicing(as_args)) do
        metadata = %{
          adapter_meta: unquote(adapter_meta),
          function_name: unquote(as),
          args: unquote(as_args_tl)
        }

        Telemetry.span(
          unquote(adapter_meta).telemetry_prefix ++ [:command],
          metadata,
          fn ->
            result =
              unquote(name)(
                Map.merge(unquote(adapter_meta), %{telemetry: false, in_span?: true}),
                unquote_splicing(as_args_tl)
              )

            {result, Map.put(metadata, :result, result)}
          end
        )
      end
    end
  end

  ## Private Functions

  defp build_defspan(ast, opts) when is_list(opts) do
    {name, args} =
      case Macro.decompose_call(ast) do
        {_, _} = parts -> parts
        _ -> raise ArgumentError, "invalid syntax in defspan #{Macro.to_string(ast)}"
      end

    as = Keyword.get(opts, :as, name)
    as_args = build_as_args(args)

    {name, args, as, as_args}
  end

  defp build_as_args(args) do
    for {arg, idx} <- Enum.with_index(args) do
      arg
      |> Macro.to_string()
      |> build_as_arg({arg, idx})
    end
  end

  # sobelow_skip ["DOS.BinToAtom"]
  defp build_as_arg("_" <> _, {{_e1, e2, e3}, idx}), do: {:"var#{idx}", e2, e3}
  defp build_as_arg(_, {arg, _idx}), do: arg

  # coveralls-ignore-stop
end
