defmodule Nebulex.CacheCase do
  @moduledoc false

  @doc false
  defmacro deftests(do: block) do
    quote do
      defmacro __using__(opts) do
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
      defmacro __using__(opts) do
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

        {:ok, pid} = cache.start_link(opts)

        on_exit(fn ->
          try do
            :ok = Process.sleep(20)
            if Process.alive?(pid), do: Supervisor.stop(pid, :normal, 5000)
          catch
            :exit, _ -> :noop
          end
        end)

        {:ok, cache: cache}
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

        default_dynamic_cache = cache.get_dynamic_cache()
        {:ok, pid} = cache.start_link([name: name] ++ opts)
        _ = cache.put_dynamic_cache(name)

        on_exit(fn ->
          try do
            :ok = Process.sleep(20)
            if Process.alive?(pid), do: Supervisor.stop(pid, :normal, 5000)
          catch
            :exit, _ -> :noop
          after
            cache.put_dynamic_cache(default_dynamic_cache)
          end
        end)

        {:ok, cache: cache, name: name}
      end
    end
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
      :telemetry.attach_many(
        handler_id,
        events,
        &__MODULE__.handle_event/4,
        %{pid: self()}
      )

    fun.()
  after
    :telemetry.detach(handler_id)
  end

  @doc false
  def handle_event(event, measurements, metadata, %{pid: pid}) do
    send(pid, {event, measurements, metadata})
  end
end
