defmodule Nebulex.Version.Timestamp do
  @behaviour Nebulex.Object.Version

  alias Nebulex.Object

  @impl true
  def generate(nil), do: now()
  def generate(%Object{}), do: now()

  defp now, do: DateTime.to_unix(DateTime.utc_now(), :nanosecond)
end

defmodule Nebulex.TestCache do
  defmodule Hooks do
    defmacro __using__(opts) do
      quote bind_quoted: [opts: opts] do
        @opts opts

        def pre_hooks do
          pre_hook = fn
            result, {_, :get, _} = call ->
              send(:hooked_cache, call)

            _, _ ->
              :noop
          end

          {@opts[:pre_hooks_mode] || :async, [pre_hook]}
        end

        def post_hooks do
          wrong_hook = fn var -> var end
          {@opts[:post_hooks_mode] || :async, [wrong_hook, &post_hook/2]}
        end

        def post_hook(result, {_, :set, _} = call) do
          _ = send(:hooked_cache, call)
          result
        end

        def post_hook(nil, {_, :get, _}) do
          "hello"
        end

        def post_hook(result, _) do
          result
        end
      end
    end
  end

  defmodule Local do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local,
      version_generator: Nebulex.Version.Timestamp
  end

  defmodule Versionless do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local
  end

  defmodule HookableCache do
    defmodule C1 do
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Local

      use Hooks
    end

    defmodule C2 do
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Local

      use Hooks, post_hooks_mode: :pipe
    end

    defmodule C3 do
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Local

      use Hooks, post_hooks_mode: :sync
    end
  end

  :ok = Application.put_env(:nebulex, Nebulex.TestCache.CacheStats, stats: true)

  defmodule CacheStats do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local

    def post_hooks do
      {:pipe, []}
    end
  end

  defmodule LocalWithGC do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local,
      version_generator: Nebulex.Version.Timestamp
  end

  :ok =
    Application.put_env(
      :nebulex,
      Nebulex.TestCache.LocalWithSizeLimit,
      allocated_memory: 100_000,
      gc_cleanup_interval: 2
    )

  defmodule LocalWithSizeLimit do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local,
      version_generator: Nebulex.Version.Timestamp,
      gc_interval: 3600,
      n_generations: 3
  end

  defmodule Partitioned do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Partitioned,
      primary: Nebulex.TestCache.Partitioned.Primary,
      version_generator: Nebulex.Version.Timestamp

    defmodule Primary do
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Local,
        gc_interval: 3600
    end

    def reducer_fun(object, {acc1, acc2}) do
      if Map.has_key?(acc1, object.key),
        do: {acc1, acc2},
        else: {Map.put(acc1, object.key, object.value), object.value + acc2}
    end

    def get_and_update_fun(nil), do: {nil, 1}
    def get_and_update_fun(current) when is_integer(current), do: {current, current * 2}

    def get_and_update_bad_fun(_), do: :other

    def get_and_update_timeout_fun(value) do
      :ok = Process.sleep(5000)
      {value, value}
    end

    def update_fun(nil), do: 1
    def update_fun(current) when is_integer(current), do: current * 2
  end

  defmodule PartitionedWithCustomHashSlot do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Partitioned,
      primary: Nebulex.TestCache.PartitionedWithCustomHashSlot.Primary,
      hash_slot: Nebulex.TestCache.PartitionedWithCustomHashSlot.HashSlot

    defmodule Primary do
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Local
    end

    defmodule HashSlot do
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
    levels =
      for l <- 1..3 do
        level = String.to_atom("#{mod}.L#{l}")
        :ok = Application.put_env(:nebulex, level, gc_interval: 3600)
        level
      end

    config =
      case mod do
        Nebulex.TestCache.Multilevel ->
          [levels: levels, fallback: &mod.fallback/1]

        _ ->
          [cache_model: :exclusive, levels: levels, fallback: &mod.fallback/1]
      end

    :ok = Application.put_env(:nebulex, mod, config)

    defmodule mod do
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Multilevel

      defmodule L1 do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.Adapters.Local
      end

      defmodule L2 do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.Adapters.Local
      end

      defmodule L3 do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: Nebulex.Adapters.Local
      end

      def fallback(_key) do
        # maybe fetch the data from Database
        nil
      end
    end
  end

  ## Mocks

  :ok =
    Application.put_env(
      :nebulex,
      Nebulex.TestCache.PartitionedMock,
      primary: Nebulex.TestCache.LocalMock
    )

  :ok = Application.put_env(:nebulex, Nebulex.TestCache.LocalMock, [])

  defmodule AdapterMock do
    @behaviour Nebulex.Adapter

    @impl true
    defmacro __before_compile__(_), do: :ok

    @impl true
    def init(_), do: {:ok, []}

    @impl true
    def get(_, _, _), do: raise(ArgumentError, "Error")

    @impl true
    def set(_, _, _), do: :timer.sleep(1000)

    @impl true
    def delete(_, _, _), do: :ok

    @impl true
    def take(_, _, _), do: nil

    @impl true
    def has_key?(_, _), do: nil

    @impl true
    def object_info(_, _, _), do: nil

    @impl true
    def expire(_, _, _), do: nil

    @impl true
    def update_counter(_, _, _, _), do: 1

    @impl true
    def size(_), do: Process.exit(self(), :normal)

    @impl true
    def flush(_), do: :ok

    @impl true
    def get_many(_, _, _), do: :timer.sleep(1000)

    @impl true
    def set_many(_, _, _), do: Process.exit(self(), :normal)
  end

  defmodule LocalMock do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.TestCache.AdapterMock
  end

  defmodule PartitionedMock do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Partitioned
  end
end
