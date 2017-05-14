defmodule Nebulex.Adapters.Multilevel do
  @moduledoc """
  Adapter module for Multi-level Cache.

  This is just a simple layer on top of local or distributed cache
  implementations that enables to have a cache hierarchy by levels.
  Multi-level caches generally operate by checking the fastest,
  level 1 (L1) cache first; if it hits, the adapter proceeds at
  high speed. If that smaller cache misses, the next fastest cache
  (level 2, L2) is checked, and so on, before accessing external
  memory (that can be the latest level).

  Beware that the only added value function here is `get/3`, the other
  functions works more like a bypass functions.

  ## Options

  These options should be set in the config file and require
  recompilation in order to make an effect.

    * `:adapter` - The adapter name, in this case, `Nebulex.Adapters.Multilevel`

    * `:cache_model` - Specifies the cache model: `:inclusive` or `:exclusive`;
      defaults to `:inclusive`. In an inclusive cache, the same data can be
      present in all caches/levels. In an exclusive cache, data can be present
      in only one cache/level and a key cannot be found in the rest of caches
      at the same time. This option affects get operation only.

    * `:levels` - The list of caches where each cache corresponds to a level.
      The order of the caches in the list defines the the order of the levels
      as well, for example, the first cache in the list will be the L1 cache
      (level 1) and so on; the Nth elemnt will be the LN cache. This option
      is mandatory, if it is not set or empty, an exception will be raised.

    * `:fallback` - Defines a fallback function when a key is not present
      in any cache level. Function is defined as: `(key -> value)`.

  The `:fallback` can be defined in two ways: at compile-time and at run-time.
  At compile-time, in the cache config, set the module that implements the
  function:

      config :my_app, MyApp.MultilevelCache,
        fallback: &MyMapp.AnyModule/1

  And at run-time, passing the function as an option within the `opts` argument
  (only valid for `get` function):

      MultilevelCache.get("foo", fallback: fn(key) -> key * 2 end)

  ## Example

  `Nebulex.Cache` is the wrapper around the Cache. We can define the
  multi-level cache as follows:

      defmodule MyApp.MultilevelCache do
        use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Multilevel

        defmodule L1 do
          use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Local
        end

        defmodule L2 do
          use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Dist
        end

        def fallback(_key) do
          # maybe fetch the data from Database
          nil
        end
      end

      defmodule MyApp.LocalCache do
        use Nebulex.Cache, otp_app: :my_app, adapter: Nebulex.Adapters.Local
      end

  Where the configuration for the Cache must be in your application
  environment, usually defined in your `config/config.exs`:

      config :my_app, MyApp.MultilevelCache,
        levels: [
          MyApp.MultilevelCache.L1,
          MyApp.MultilevelCache.L2
        ],
        fallback: &MyApp.MultilevelCache.fallback/1

      config :my_app, MyApp.MultilevelCache.L1,
        n_shards: 2,
        gc_interval: 3600

      config :my_app, MyApp.MultilevelCache.L2,
        local: MyApp.LocalCache

      config :my_app, MyApp.LocalCache,
        n_shards: 2,
        gc_interval: 3600

  ## Extended API

  This adapter provides some additional functions to the `Nebulex.Cache` API.

  ### `__levels__`

  This function returns the configured level list.

      MyCache.__levels__

  ### `__model__`

  This function returns the multi-level cache model.

      MyCache.__model__

  ### `__fallback__`

  This function returns the default fallback function.

      MyCache.__fallback__

  ## Limitations

  Because this adapter reuses other existing/configured adapters, it inherits
  all their limitations too. Therefore, it is highly recommended to check the
  documentation of the used adapters.
  """

  # Provide Cache Implementation
  @behaviour Nebulex.Adapter

  alias Nebulex.Object

  ## Adapter Impl

  @doc false
  defmacro __before_compile__(env) do
    otp_app = Module.get_attribute(env.module, :otp_app)
    config = Module.get_attribute(env.module, :config)
    cache_model = Keyword.get(config, :cache_model, :inclusive)
    fallback = Keyword.get(config, :fallback)
    levels = Keyword.get(config, :levels)

    unless levels do
      raise ArgumentError,
        "missing :levels configuration in config " <>
        "#{inspect otp_app}, #{inspect env.module}"
    end

    unless is_list(levels) && length(levels) > 0 do
      raise ArgumentError,
        ":levels configuration in config must have at least one level, " <>
        "got: #{inspect levels}"
    end

    quote do
      def __levels__, do: unquote(levels)

      def __model__, do: unquote(cache_model)

      def __fallback__, do: unquote(fallback)
    end
  end

  ## Adapter Impl

  @doc false
  def children(_cache, _opts), do: []

  @doc false
  def get(cache, key, opts \\ []) do
    cache.__levels__
    |> Enum.reduce_while({nil, []}, fn(current, {_, prev}) ->
      if object = current.get(key, Keyword.put(opts, :return, :object)) do
        {:halt, {object, [current | prev]}}
      else
        {:cont, {nil, [current | prev]}}
      end
    end)
    |> maybe_fallback(cache, key, opts)
    |> maybe_replicate_data(cache)
    |> validate_return(opts)
  end

  @doc false
  def set(cache, key, value, opts \\ []) do
    eval(cache, :set, [key, value, opts], opts)
  end

  @doc false
  def delete(cache, key, opts \\ []) do
    eval(cache, :delete, [key, opts], opts)
  end

  @doc false
  def has_key?(cache, key) do
    eval_while(cache, :has_key?, [key], false)
  end

  @doc false
  def pop(cache, key, opts \\ []) do
    eval_while(cache, :pop, [key, opts])
  end

  @doc false
  def get_and_update(cache, key, fun, opts \\ []) when is_function(fun, 1) do
    eval(cache, :get_and_update, [key, fun, opts], opts)
  end

  @doc false
  def update(cache, key, initial, fun, opts \\ []) do
    eval(cache, :update, [key, initial, fun, opts], opts)
  end

  @doc false
  def transaction(cache, key, fun) do
    eval(cache, :transaction, [key, fun])
  end

  ## Helpers

  defp eval(ml_cache, fun, args, opts \\ []) do
    [l1 | next] = case opts[:level] do
      nil   -> [hd(ml_cache.__levels__)]
      :all  -> ml_cache.__levels__
      level -> [:lists.nth(level, ml_cache.__levels__)]
    end
    Enum.reduce(next, apply(l1, fun, args), fn(cache, acc) ->
      ^acc = apply(cache, fun, args)
    end)
  end

  defp eval_while(ml_cache, fun, args, init \\ nil) do
    Enum.reduce_while(ml_cache.__levels__, init, fn(cache, acc) ->
      if return = apply(cache, fun, args) do
        {:halt, return}
      else
        {:cont, acc}
      end
    end)
  end

  defp maybe_fallback({nil, levels}, cache, key, opts) do
    object = if fallback = opts[:fallback] || cache. __fallback__,
      do: Object.new(key, fallback.(key)),
      else: nil
    {object, levels}
  end
  defp maybe_fallback(return, _, _, _), do: return

  defp maybe_replicate_data({nil, _}, _),
    do: nil
  defp maybe_replicate_data({object, levels}, cache) do
    cache.__model__
    |> case do
      :exclusive -> []
      :inclusive -> levels
    end
    |> Enum.reduce(object, &(&1.set(&2.key, &2.value, return: :object)))
  end

  defp validate_return(nil, _),
    do: nil
  defp validate_return(object, opts) do
    case Keyword.get(opts, :return, :value) do
      :object -> object
      :value  -> object.value
      :key    -> object.key
    end
  end
end
