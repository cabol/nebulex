defmodule Nebulex.Hook do
  @moduledoc ~S"""
  This module specifies the behaviour for pre and post hooks.

  These functions are defined in order to intercept any cache operation
  and be able to execute a set of actions before and/or after the operation
  takes place.

  ## Example

      defmodule MyApp.TraceHook do
        use Nebulex.Hook
        use GenServer

        alias Nebulex.Hook.Event

        require Logger

        @hookable_actions [:get, :put]

        @doc false
        def start_link(opts \\ []) do
          GenServer.start_link(__MODULE__, opts, name: __MODULE__)
        end

        ## Nebulex.Hook

        @impl Nebulex.Hook
        def handle_pre(%Event{name: name}) when name in @hookable_actions do
          System.system_time(:microsecond)
        end

        def handle_pre(event), do: event

        @impl Nebulex.Hook
        def handle_post(%Event{name: name} = event) when name in @hookable_actions do
          GenServer.cast(__MODULE__, {:trace, event})
        end

        def handle_post(event), do: event

        ## GenServer

        @impl GenServer
        def init(_opts) do
          {:ok, %{}}
        end

        @impl GenServer
        def handle_cast({:trace, %Event{acc: start} = event}, state) do
          diff = System.system_time(:microsecond) - start
          Logger.info("#=> #{event.module}.#{event.name}/#{event.arity}, Duration: #{diff}")
          {:noreply, state}
        end
      end

      defmodule MyApp.MyCache do
        use Nebulex.Decorators
        @decorate_all hook(MyApp.TraceHook)

        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Local

        alias MyApp.TraceHook

        @impl true
        def init(opts) do
          {:ok, pid} = TraceHook.start_link()
          {:ok, Keyword.put(opts, :trace_hook_pid, pid)}
        end
      end
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Nebulex.Hook

      @impl true
      def handle_pre(event), do: event

      @impl true
      def handle_post(event), do: event

      defoverridable handle_pre: 1, handle_post: 1
    end
  end

  defmodule Event do
    @moduledoc """
    Defines a hook event.
    """

    @enforce_keys [:module, :name, :arity]
    defstruct [:module, :name, :arity, :result, :acc]

    @type t :: %__MODULE__{
            module: Nebulex.Cache.t(),
            name: atom,
            arity: non_neg_integer,
            result: term,
            acc: term
          }
  end

  @doc """
  Invoked to handle synchronous pre-hooks.

  `handle_pre/1` will block until the hook's logic is executed. Therefore,
  the hook logic should be lightweight, for example, just sending or hand over
  the event to another process running the hook's logic there without affect
  cache performance.
  """
  @callback handle_pre(Nebulex.Hook.Event.t()) :: term

  @doc """
  Invoked to handle synchronous post-hooks.

  `handle_post/1` will block until the hook's logic is executed. Therefore,
  the hook logic should be lightweight, for example, just sending or hand over
  the event to another process running the hook's logic there without affect
  cache performance.
  """
  @callback handle_post(Nebulex.Hook.Event.t()) :: term
end
