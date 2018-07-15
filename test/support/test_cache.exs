defmodule Nebulex.Version.Timestamp do
  @behaviour Nebulex.Object.Version

  @impl true
  def generate(_) do
    DateTime.utc_now |> DateTime.to_unix(:nanoseconds)
  end
end

defmodule Nebulex.TestCache do
  :ok = Application.put_env(:nebulex, :nodes, [:"node1@127.0.0.1", :"node2@127.0.0.1"])

  defmodule Hooks do
    defmacro __using__(_opts) do
      quote do
        def pre_hooks do
          pre_hook =
            fn
              (result, {_, :get, _} = call) ->
                send(:hooked_cache, call)

              (_, _) ->
                :noop
            end

          [pre_hook]
        end

        def post_hooks do
          wrong_hook = fn(var) -> var end
          [wrong_hook, &post_hook/2]
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

  :ok = Application.put_env(:nebulex, Nebulex.TestCache.Local, version_generator: Nebulex.Version.Timestamp)

  defmodule Local do
    use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Local
  end

  :ok = Application.put_env(:nebulex, Nebulex.TestCache.Hooked.C1, post_hooks_mode: :async)
  :ok = Application.put_env(:nebulex, Nebulex.TestCache.Hooked.C2, post_hooks_mode: :pipe)
  :ok = Application.put_env(:nebulex, Nebulex.TestCache.Hooked.C3, post_hooks_mode: :sync)

  defmodule Hooked do
    defmodule C1 do
      use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Local
      use Hooks
    end

    defmodule C2 do
      use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Local
      use Hooks
    end

    defmodule C3 do
      use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Local
      use Hooks
    end
  end

  :ok = Application.put_env(:nebulex, Nebulex.TestCache.CacheStats, stats: true, post_hooks_mode: :pipe)

  defmodule CacheStats do
    use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Local
  end

  for mod <- [Nebulex.TestCache.LocalWithGC, Nebulex.TestCache.DistLocal] do
    :ok = Application.put_env(:nebulex, mod, gc_interval: 3600, version_generator: Nebulex.Version.Timestamp)

    defmodule mod do
      use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Local
    end
  end

  :ok = Application.put_env(:nebulex, Nebulex.TestCache.Dist, local: Nebulex.TestCache.DistLocal)

  defmodule Dist do
    use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Dist

    def reducer_fun({key, value}, {acc1, acc2}) do
      if Map.has_key?(acc1, key),
        do: {acc1, acc2},
        else: {Map.put(acc1, key, value), value + acc2}
    end

    def get_and_update_fun(nil), do: {nil, 1}
    def get_and_update_fun(current) when is_integer(current), do: {current, current * 2}

    def wrong_get_and_update_fun(_), do: :other

    def update_fun(nil), do: 1
    def update_fun(current) when is_integer(current), do: current * 2
  end

  for mod <- [Nebulex.TestCache.Multilevel, Nebulex.TestCache.MultilevelExclusive] do
    levels =
      for l <- 1..3 do
        level = String.to_atom("#{mod}.L#{l}")
        :ok = Application.put_env(:nebulex, level, n_shards: 2, gc_interval: 3600)
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
      use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Multilevel

      defmodule L1 do
        use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Local
      end

      defmodule L2 do
        use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Local
      end

      defmodule L3 do
        use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Local
      end

      def fallback(_key) do
        # maybe fetch the data from Database
        nil
      end
    end
  end
end
