if Code.ensure_loaded?(Decorator.Define) do
  defmodule Nebulex.Caching do
    @moduledoc """
    At its core, the abstraction applies caching to Elixir functions, reducing
    thus the number of executions based on the information available in the
    cache. That is, each time a targeted function is invoked, the abstraction
    will apply a caching behavior checking whether the function has been already
    executed and its result cached for the given arguments. If it has, then the
    cached result is returned without having to execute the actual function;
    if it has not, then function is executed, the result cached and returned
    to the user so that, the next time the method is invoked, the cached result
    is returned. This way, expensive functions (whether CPU or IO bound) can be
    executed only once for a given set of parameters and the result reused
    without having to actually execute the function again. The caching logic
    is applied transparently without any interference to the invoker.

    See **`Nebulex.Caching.Decorators`** for more information about
    **"Declarative annotation-based caching"**.
    """

    @doc false
    defmacro __using__(_opts) do
      quote do
        use Nebulex.Caching.Decorators
        import Nebulex.Caching
      end
    end

    alias Nebulex.Caching.Decorators

    @doc """
    A wrapper macro for `Nebulex.Caching.Decorators.build_keyref/2`.

    This macro is imported automatically with `use Nebulex.Caching`,
    which means you don't need to do any additional `alias` or `import`.

    See `cacheable/3` decorator for more information about its usage.
    """
    defmacro keyref(cache \\ nil, key) do
      quote do
        Decorators.build_keyref(unquote(cache), unquote(key))
      end
    end
  end
end
