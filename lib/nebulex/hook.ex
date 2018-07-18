defmodule Nebulex.Hook do
  @moduledoc """
  This module specifies the behaviour for pre/post hooks callbacks.
  These functions are defined in order to intercept any cache operation
  and be able to execute a set of actions before and/or after the operation
  takes place.

  ## Execution modes

  It is possible to configure the `mode` how the hooks are evaluated, using the
  compile-time options `:pre_hooks_mode` and `:post_hooks_mode`. The
  available modes are:

    * `:async` - (the default) all hooks are evaluated asynchronously
      (in parallel) and their results are ignored.

    * `:sync` - hooks are evaluated synchronously (sequentially) and their
      results are ignored.

    * `:pipe` - similar to `:sync` but each hook result is passed to the
      next one and so on, until the last hook evaluation is returned.

  ## Example

      config :my_app, MyApp.MyCache,
        adapter: Nebulex.Adapters.Local,
        n_shards: 2,
        pre_hooks_mode: :async,
        post_hooks_mode: :pipe

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

  @typedoc "Defines a cache command"
  @type command :: {Nebulex.Cache.t(), action :: atom, args :: [any]}

  @typedoc "Defines the hook callback function"
  @type hook_fun :: (result :: any, command -> any)

  @typedoc "Hook execution mode"
  @type mode :: :async | :sync | :pipe

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

        def post_hook(result, {_, :set, _} = call) do
          send(:hooked_cache, call)
        end

        def post_hook(_, _) do
          :noop
        end
      end
  """
  @callback post_hooks() :: [hook_fun]

  @doc """
  Evaluates the `hooks` according to the given execution `mode`.
  """
  @spec eval(hooks :: [hook_fun], mode, command, result :: any) :: any
  def eval([], _mode, _command, result), do: result

  def eval(hooks, mode, {_cache, _action, _args} = command, result) do
    Enum.reduce(hooks, result, fn
      (hook, acc) when is_function(hook, 2) and mode == :pipe ->
        hook.(acc, command)

      (hook, ^result) when is_function(hook, 2) and mode == :sync ->
        _ = hook.(result, command)
        result

      (hook, ^result) when is_function(hook, 2) ->
        _ = Task.start_link(:erlang, :apply, [hook, [result, command]])
        result

      (_, acc) when mode == :pipe ->
        acc

      (_, _) ->
        result
    end)
  end
end
