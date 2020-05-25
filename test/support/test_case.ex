defmodule Nebulex.TestCase do
  @moduledoc false

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
            if Process.alive?(pid), do: Supervisor.stop(pid)
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
  def with_dynamic_cache(cache, opts \\ [], callback) do
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
end
