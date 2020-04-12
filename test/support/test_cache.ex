defmodule Nebulex.TestCache do
  @moduledoc false

  defmodule Hooks do
    @moduledoc false

    defmodule TestHook do
      @moduledoc false
      use Nebulex.Hook

      use GenServer

      alias Nebulex.Hook.Event

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
        _ = send(:hooked_cache, %{event | acc: System.system_time(:microsecond) - start})
        {:noreply, state}
      end
    end

    defmodule HookError do
      @moduledoc false
      use Nebulex.Hook

      alias Nebulex.Hook.Event

      def handle_post(%Event{name: :get}), do: raise(ArgumentError, "error")

      def handle_post(event), do: event
    end
  end

  defmodule Local do
    @moduledoc false

    defmodule ETS do
      @moduledoc false
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Local,
        backend: :ets
    end

    defmodule Shards do
      @moduledoc false
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Local,
        backend: :shards
    end
  end

  defmodule HookableCache do
    @moduledoc false
    use Nebulex.Decorators
    @decorate_all hook(Nebulex.TestCache.Hooks.TestHook)

    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local

    alias Nebulex.TestCache.Hooks.TestHook

    def init(opts) do
      {:ok, pid} = TestHook.start_link()
      {:ok, Keyword.put(opts, :hook_pid, pid)}
    end
  end

  defmodule ErrorHookableCache do
    @moduledoc false
    use Nebulex.Decorators
    @decorate_all hook(Nebulex.TestCache.Hooks.HookError)

    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local
  end

  defmodule CacheStats do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local,
      stats: true

    def post_hooks do
      {:pipe, []}
    end
  end

  defmodule LocalWithGC do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local
  end

  defmodule LocalWithSizeLimit do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local,
      gc_interval: 3600,
      n_generations: 3
  end

  defmodule Partitioned do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Partitioned,
      primary: Nebulex.TestCache.Partitioned.Primary

    defmodule Primary do
      @moduledoc false
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Local,
        gc_interval: 3600
    end

    def get_and_update_fun(nil), do: {nil, 1}
    def get_and_update_fun(current) when is_integer(current), do: {current, current * 2}

    def get_and_update_bad_fun(_), do: :other
  end

  defmodule PartitionedWithCustomHashSlot do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Partitioned,
      primary: Nebulex.TestCache.PartitionedWithCustomHashSlot.Primary,
      hash_slot: Nebulex.TestCache.PartitionedWithCustomHashSlot.HashSlot

    defmodule Primary do
      @moduledoc false
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Local
    end

    defmodule HashSlot do
      @moduledoc false
      @behaviour Nebulex.Adapter.HashSlot

      @impl true
      def keyslot(key, range) do
        key
        |> :erlang.phash2()
        |> rem(range)
      end
    end
  end

  for mod <- [Nebulex.TestCache.Multilevel, Nebulex.TestCache.MultilevelExclusive] do
    levels = for l <- 1..3, do: String.to_atom("#{mod}.L#{l}")

    cache_model =
      case mod do
        Nebulex.TestCache.Multilevel -> :inclusive
        _ -> :exclusive
      end

    defmodule mod do
      @moduledoc false
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Multilevel,
        levels: levels,
        fallback: &mod.fallback/1,
        cache_model: cache_model

      defmodule L1 do
        @moduledoc false
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.Adapters.Local
      end

      defmodule L2 do
        @moduledoc false
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.Adapters.Local
      end

      defmodule L3 do
        @moduledoc false
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.Adapters.Local,
          backend: :shards
      end

      def fallback(_key) do
        # maybe fetch the data from Database
        nil
      end
    end
  end

  defmodule Replicated do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Replicated,
      primary: Nebulex.TestCache.Replicated.Primary

    defmodule Primary do
      @moduledoc false
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Local
    end
  end

  ## Mocks

  defmodule AdapterMock do
    @moduledoc false
    @behaviour Nebulex.Adapter

    @impl true
    defmacro __before_compile__(_), do: :ok

    @impl true
    def init(_) do
      {:ok, nil}
    end

    @impl true
    def get(_, _, _), do: raise(ArgumentError, "Error")

    @impl true
    def put(_, _, _, _, _, _) do
      :ok = Process.sleep(1000)
      true
    end

    @impl true
    def delete(_, _, _), do: :ok

    @impl true
    def take(_, _, _), do: nil

    @impl true
    def has_key?(_, _), do: nil

    @impl true
    def ttl(_, _), do: nil

    @impl true
    def expire(_, _, _), do: nil

    @impl true
    def touch(_, _), do: true

    @impl true
    def incr(_, _, _, _, _), do: 1

    @impl true
    def size(_), do: Process.exit(self(), :normal)

    @impl true
    def flush(_) do
      Process.sleep(2000)
      0
    end

    @impl true
    def get_all(_, _, _), do: Process.sleep(1000)

    @impl true
    def put_all(_, _, _, _, _), do: Process.exit(self(), :normal)
  end

  defmodule PartitionedMock do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Partitioned,
      primary: Nebulex.TestCache.PartitionedMock.Primary

    defmodule Primary do
      @moduledoc false
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.TestCache.AdapterMock
    end
  end

  defmodule ReplicatedMock do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Replicated,
      primary: Nebulex.TestCache.ReplicatedMock.Primary

    defmodule Primary do
      @moduledoc false
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.TestCache.AdapterMock
    end
  end
end
