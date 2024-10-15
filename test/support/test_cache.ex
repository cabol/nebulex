defmodule Nebulex.TestCache do
  @moduledoc false

  defmodule Common do
    @moduledoc false

    defmacro __using__(_opts) do
      quote do
        def get_and_update_fun(nil), do: {nil, 1}
        def get_and_update_fun(current) when is_integer(current), do: {current, current * 2}

        def get_and_update_bad_fun(_), do: :other
      end
    end
  end

  defmodule TestHook do
    @moduledoc false
    use GenServer

    alias Nebulex.Hook

    @actions [:get, :put]

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    ## Hook Function

    def track(%Hook{step: :before, name: name}) when name in @actions do
      System.system_time(:microsecond)
    end

    def track(%Hook{step: :after_return, name: name} = event) when name in @actions do
      GenServer.cast(__MODULE__, {:track, event})
    end

    def track(hook), do: hook

    ## Error Hook Function

    def hook_error(%Hook{name: :get}), do: raise(ArgumentError, "error")

    def hook_error(hook), do: hook

    ## GenServer

    @impl GenServer
    def init(_opts) do
      {:ok, %{}}
    end

    @impl GenServer
    def handle_cast({:track, %Hook{acc: start} = hook}, state) do
      _ = send(:hooked_cache, %{hook | acc: System.system_time(:microsecond) - start})
      {:noreply, state}
    end
  end

  defmodule Cache do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local

    use Nebulex.TestCache.Common
  end

  defmodule Partitioned do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Partitioned

    use Nebulex.TestCache.Common
  end

  defmodule Replicated do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Replicated

    use Nebulex.TestCache.Common
  end

  defmodule Multilevel do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Multilevel

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
        adapter: Nebulex.Adapters.Replicated
    end

    defmodule L3 do
      @moduledoc false
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Partitioned
    end
  end

  defmodule DelayedReadAdapter do
    @moduledoc false

    require Nebulex.Adapters.Local

    @behaviour Nebulex.Adapter
    @behaviour Nebulex.Adapter.Entry
    @behaviour Nebulex.Adapter.Queryable

    @fallback_adapter Nebulex.Adapters.Local

    @impl true
    defmacro __before_compile__(opts) do
      quote do
        require unquote(@fallback_adapter)

        unquote(@fallback_adapter).__before_compile__(unquote(Macro.escape(opts)))
      end
    end

    @impl true
    defdelegate init(opts), to: @fallback_adapter

    @impl true
    def get(adapter_meta, key, opts) do
      delay()
      @fallback_adapter.get(adapter_meta, key, opts)
    end

    @impl true
    def get_all(adapter_meta, list, opts) do
      delay()
      @fallback_adapter.get_all(adapter_meta, list, opts)
    end

    @impl true
    defdelegate put(adapter_meta, key, value, ttl, on_write, opts), to: @fallback_adapter

    @impl true
    defdelegate put_all(adapter_meta, entries, ttl, on_write, opts), to: @fallback_adapter

    @impl true
    defdelegate delete(adapter_meta, key, opts), to: @fallback_adapter

    @impl true
    defdelegate take(adapter_meta, key, opts), to: @fallback_adapter

    @impl true
    def has_key?(adapter_meta, key) do
      delay()
      @fallback_adapter.has_key?(adapter_meta, key)
    end

    @impl true
    def ttl(adapter_meta, key) do
      delay()
      @fallback_adapter.ttl(adapter_meta, key)
    end

    @impl true
    defdelegate expire(adapter_meta, key, ttl), to: @fallback_adapter

    @impl true
    defdelegate touch(adapter_meta, key), to: @fallback_adapter

    @impl true
    defdelegate update_counter(adapter_meta, key, amount, ttl, default, opts), to: @fallback_adapter

    @impl true
    defdelegate execute(adapter_meta, command, args, opts), to: @fallback_adapter

    @impl true
    defdelegate stream(adapter_meta, query, opts), to: @fallback_adapter

    @read_delay_key {__MODULE__, :read_delay}

    def put_read_delay(delay) when is_integer(delay) do
      Process.put(@read_delay_key, delay)
    end

    defp delay do
      delay = Process.get(@read_delay_key, 1000)

      Process.sleep(delay)
    end
  end

  defmodule MultilevelWithDelay do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Multilevel

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
        adapter: Nebulex.TestCache.DelayedReadAdapter
    end
  end

  ## Mocks

  defmodule AdapterMock do
    @moduledoc false
    @behaviour Nebulex.Adapter
    @behaviour Nebulex.Adapter.Entry
    @behaviour Nebulex.Adapter.Queryable

    @impl true
    defmacro __before_compile__(_), do: :ok

    @impl true
    def init(opts) do
      child = {
        {Agent, System.unique_integer([:positive, :monotonic])},
        {Agent, :start_link, [fn -> :ok end, [name: opts[:child_name]]]},
        :permanent,
        5_000,
        :worker,
        [Agent]
      }

      {:ok, child, %{}}
    end

    @impl true
    def get(_, key, _) do
      if is_integer(key) do
        raise ArgumentError, "Error"
      else
        :ok
      end
    end

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
    def has_key?(_, _), do: true

    @impl true
    def ttl(_, _), do: nil

    @impl true
    def expire(_, _, _), do: true

    @impl true
    def touch(_, _), do: true

    @impl true
    def update_counter(_, _, _, _, _, _), do: 1

    @impl true
    def get_all(_, _, _) do
      :ok = Process.sleep(1000)
      %{}
    end

    @impl true
    def put_all(_, _, _, _, _), do: Process.exit(self(), :normal)

    @impl true
    def execute(_, :count_all, _, _) do
      _ = Process.exit(self(), :normal)
      0
    end

    def execute(_, :delete_all, _, _) do
      Process.sleep(2000)
      0
    end

    @impl true
    def stream(_, _, _), do: 1..10
  end

  defmodule PartitionedMock do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Partitioned,
      primary_storage_adapter: Nebulex.TestCache.AdapterMock
  end

  defmodule ReplicatedMock do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Replicated,
      primary_storage_adapter: Nebulex.TestCache.AdapterMock
  end
end
