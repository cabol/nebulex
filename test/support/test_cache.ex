defmodule Nebulex.TestCache do
  @moduledoc false

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
  end

  defmodule Partitioned do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Partitioned

    def get_and_update_fun(nil), do: {nil, 1}
    def get_and_update_fun(current) when is_integer(current), do: {current, current * 2}

    def get_and_update_bad_fun(_), do: :other
  end

  defmodule Replicated do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Replicated
  end

  defmodule Multilevel do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Multilevel
  end

  ## Mocks

  defmodule AdapterMock do
    @moduledoc false
    @behaviour Nebulex.Adapter

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
      if is_integer(key), do: raise(ArgumentError, "Error")
      :ok
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
    def incr(_, _, _, _, _), do: 1

    @impl true
    def size(_) do
      _ = Process.exit(self(), :normal)
      0
    end

    @impl true
    def flush(_) do
      Process.sleep(2000)
      0
    end

    @impl true
    def get_all(_, _, _) do
      :ok = Process.sleep(1000)
      %{}
    end

    @impl true
    def put_all(_, _, _, _, _), do: Process.exit(self(), :normal)
  end
end
