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

    Continue checking **`Nebulex.Caching.Decorators`** to learn more about the
    caching decorators and their usage.

    ## Compilation time options

    The following are the available compilation time options when defining
    the caching usage via `use Nebulex.Caching`:

    #{Nebulex.Caching.Options.caching_options_docs()}

    > #### `use Nebulex.Caching, opts` {: .info}
    >
    > These options apply to all decorated functions in a module, but each
    > decorator declaration can overwrite them. They act as a global or default
    > configuration for the decorators. For example, if the cache is the same
    > for all decorated functions in a module, one can configure it globally
    > like this: `use Nebulex.Caching, cache: MyCache`. Therefore, the decorator
    > declaration doesn't require the `:cache` option.
    """

    alias Nebulex.Caching.{Decorators, Options}

    @doc false
    defmacro __using__(opts \\ []) do
      quote bind_quoted: [opts: opts] do
        # Validate options
        opts =
          opts
          |> Macro.escape()
          |> Options.validate_caching_opts!()

        # Set the __using__ macro options so they can be used in the decorators
        :ok = Module.put_attribute(__MODULE__, :__caching_opts__, opts)

        use Nebulex.Caching.Decorators

        import Nebulex.Caching
      end
    end

    @doc """
    Creates a dynamic cache tuple form to use in the decorated function
    (wrapper macro for `Nebulex.Caching.Decorators.dynamic_cache_spec/2`).

    The first argument, `cache`, specifies the defined cache module,
    and the second argument, `name`, is the actual name of the cache.

    > #### Using `dynamic_cache` {: .info}
    >
    > This macro is automatically imported and then available when using
    > `use Nebulex.Caching`.

    ## Example

        defmodule MyApp.Users do
          use Nebulex.Caching

          @decorate cacheable(cache: dynamic_cache(MyApp.Cache, :users))
          def get_user(id) do
            # your logic ...
          end
        end

    See the **"`:cache` option"** section in the `Nebulex.Caching.Decorators`
    module documentation for more information.
    """
    defmacro dynamic_cache(cache, name) do
      quote do
        Decorators.dynamic_cache_spec(unquote(cache), unquote(name))
      end
    end

    @doc """
    Creates a reference tuple form to use in the decorated function
    (wrapper macro for `Nebulex.Caching.Decorators.keyref_spec/3`).

    > #### Using `keyref` {: .info}
    >
    > This macro is automatically imported and then available when using
    > `use Nebulex.Caching`.

    ## Options

      * `:cache` - The cache where the referenced key is stored.

      * `:ttl` - The TTL for the referenced key. If configured, it overrides
        the TTL given in the decorator's option `:opts`.

    See `Nebulex.Caching.Decorators.cacheable/3` decorator
    for more information.
    """
    defmacro keyref(key, opts \\ []) do
      cache = Keyword.get(opts, :cache)
      ttl = Keyword.get(opts, :ttl)

      quote do
        Decorators.keyref_spec(unquote(cache), unquote(key), unquote(ttl))
      end
    end
  end
end
