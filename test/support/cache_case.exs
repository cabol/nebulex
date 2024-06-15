defmodule Nebulex.CacheCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  import Mimic, only: [stub: 3]

  alias Nebulex.Telemetry

  @doc false
  defmacro deftests(do: block) do
    quote do
      defmacro __using__(_opts) do
        block = unquote(Macro.escape(block))

        quote do
          unquote(block)
        end
      end
    end
  end

  @doc false
  defmacro deftests(text, do: block) do
    quote do
      defmacro __using__(_opts) do
        text = unquote(text)
        block = unquote(Macro.escape(block))

        quote do
          describe unquote(text) do
            unquote(block)
          end
        end
      end
    end
  end

  @doc false
  defmacro setup_with_cache(cache, opts \\ []) do
    quote do
      setup do
        cache = unquote(cache)
        opts = unquote(opts)

        {ctx_opts, opts} = Keyword.split(opts, [:error_module, :error_reason])

        {:ok, pid} = cache.start_link(opts)

        on_exit(fn ->
          unquote(__MODULE__).safe_stop(pid)
        end)

        {:ok, [cache: cache] ++ ctx_opts}
      end
    end
  end

  @doc false
  defmacro setup_with_dynamic_cache(cache, name, opts \\ []) do
    quote do
      setup do
        cache = unquote(cache)
        name = unquote(name)
        opts = unquote(opts)

        {ctx_opts, opts} = Keyword.split(opts, [:error_module, :error_reason])

        default_dynamic_cache = cache.get_dynamic_cache()
        {:ok, pid} = cache.start_link([name: name] ++ opts)

        _ = cache.put_dynamic_cache(name)

        on_exit(fn ->
          try do
            unquote(__MODULE__).safe_stop(pid)
          after
            cache.put_dynamic_cache(default_dynamic_cache)
          end
        end)

        {:ok, [cache: cache, name: name] ++ ctx_opts}
      end
    end
  end

  @doc false
  def t_sleep(timeout) do
    if Application.get_env(:nebulex, :sleep_mock, false) do
      Nebulex.Time
      |> stub(:now, fn -> System.system_time(:millisecond) + timeout end)

      timeout
    else
      :ok = Process.sleep(timeout)

      0
    end
  end

  @doc false
  def safe_stop(pid) do
    if Process.alive?(pid), do: Supervisor.stop(pid, :normal, 5000)
  catch
    # Perhaps the `pid` has terminated already (race-condition),
    # so we don't want to crash the test
    :exit, _ -> :ok
  end

  @doc false
  def test_with_dynamic_cache(cache, opts \\ [], callback) do
    default_dynamic_cache = cache.get_dynamic_cache()

    {:ok, pid} = cache.start_link(opts)

    try do
      _ = cache.put_dynamic_cache(pid)

      callback.()
    after
      _ = cache.put_dynamic_cache(default_dynamic_cache)

      Supervisor.stop(pid)
    end
  end

  @doc false
  def wait_until(retries \\ 50, delay \\ 100, fun)

  def wait_until(1, _delay, fun), do: fun.()

  def wait_until(retries, delay, fun) when retries > 1 do
    fun.()
  rescue
    _ ->
      :ok = Process.sleep(delay)

      wait_until(retries - 1, delay, fun)
  end

  @doc false
  def cache_put(cache, lst, fun \\ & &1, opts \\ []) do
    for key <- lst do
      value = fun.(key)

      :ok = cache.put(key, value, opts)

      value
    end
  end

  @doc false
  def with_telemetry_handler(handler_id \\ :nbx_telemetry_test, events, fun) do
    :ok =
      Telemetry.attach_many(
        handler_id,
        events,
        &__MODULE__.handle_event/4,
        %{pid: self()}
      )

    fun.()
  after
    Telemetry.detach(handler_id)
  end

  @doc false
  def handle_event(event, measurements, metadata, %{pid: pid}) do
    send(pid, {event, measurements, metadata})
  end

  @doc false
  def assert_error_module(ctx, error_module) do
    expected_error_module = Map.get(ctx, :error_module, Nebulex.Error)

    assert error_module == expected_error_module
  end

  @doc false
  def assert_error_reason(ctx, error_reason) do
    expected_error_reason = Map.get(ctx, :error_reason, :error)

    assert error_reason == expected_error_reason
  end
end
