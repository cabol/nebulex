defmodule Nebulex.Cache.Hook do
  @moduledoc """
  Specifies pre/post hooks callbacks. These are functions that you define
  and that you direct to execute before or after particular cache action.

  ## Execution strategies

  It is possible to configure the strategy how the hooks are evaluated,
  the available strategies are:

    * `:async` - (the default) all hooks are evaluated asynchronously
      (in parallel) and their results are ignored.

    * `:sync` - hooks are evaluated synchronously (sequentially) and their
      results are ignored.

    * `:pipe` - similar to `:sync` but each hook result is passed to the
      next one and so on, until the last hook evaluation is returned.

  These strategy values applies to the compile-time options
  `:pre_hooks_strategy` and `:post_hooks_strategy`.

  ## Example

      config :my_app, MyApp.MyCache,
        adapter: Nebulex.Adapters.Local,
        n_shards: 2,
        pre_hooks_strategy: :async,
        post_hooks_strategy: :pipe

      defmodule MyApp.MyCache do
        use Nebulex.Cache, adapter: Nebulex.Adapters.Local

        def pre_hooks do
          [... your pre hook functions ...]
        end

        def post_hooks do
          [... your post hook functions ...]
        end
      end
  """

  @type hook_fun :: (result :: any, {Nebulex.Cache.t, action :: atom, args :: [any]} -> any)

  @doc """
  Returns a list of hook functions that will be executed before invoke the
  cache action.

  ## Examples

      defmodule MyCache do
        use Nebulex.Cache, adapter: Nebulex.Adapters.Local

        def pre_hooks do
          pre_hook =
            fn
              (result, {_, :get, _} = call) ->
                # do your stuff ...
              (result, _) ->
                result
            end
          [pre_hook]
        end
      end
  """
  @callback pre_hooks() :: [hook_fun]

  @doc """
  Returns a list of hook functions that will be executed after invoke the
  cache action.

  ## Examples

      defmodule MyCache do
        use Nebulex.Cache, adapter: Nebulex.Adapters.Local

        def post_hooks do
          [&post_hook/2]
        end

        def post_hook(result, {_, :set, _} = call),
          do: send(:hooked_cache, call)
        def post_hook(_, _),
          do: :noop
      end
  """
  @callback post_hooks() :: [hook_fun]
end
