defmodule Nebulex.Hook do
  @moduledoc ~S"""
  This module specifies the behaviour for pre/post hooks callbacks.
  These functions are defined in order to intercept any cache operation
  and be able to execute a set of actions before and/or after the operation
  takes place.

  ## Execution modes

  It is possible to setup the mode how the hooks are evaluated. The
  `pre_hooks/0` and `post_hooks/0` callbacks must return a tuple
  `{mode, hook_funs}`, where the first element `mode` is the one
  that defines the execution mode. The available modes are:

    * `:async` - (the default) all hooks are evaluated asynchronously
      (in parallel) and their results are ignored.

    * `:sync` - hooks are evaluated synchronously (sequentially) and their
      results are ignored.

    * `:pipe` - similar to `:sync` but each hook result is passed to the
      next one and so on, until the last hook evaluation is returned.

  ## Example

      defmodule MyApp.MyCache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Local

        def pre_hooks do
          {:async, [... your pre hook functions ...]}
        end

        def post_hooks do
          {:pipe, [... your post hook functions ...]}
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
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Local

        def pre_hooks do
          pre_hook =
            fn
              (result, {_, :get, _} = call) ->
                # do your stuff ...
              (result, _) ->
                result
            end

          {:async, [pre_hook]}
        end
      end
  """
  @callback pre_hooks() :: {mode, [hook_fun]}

  @doc """
  Returns a list of hook functions that will be executed after invoke the
  cache action.

  ## Examples

      defmodule MyCache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Local

        def post_hooks do
          {:pipe, [&post_hook/2]}
        end

        def post_hook(result, {_, :set, _} = call) do
          send(:hooked_cache, call)
        end

        def post_hook(_, _) do
          :noop
        end
      end
  """
  @callback post_hooks() :: {mode, [hook_fun]}

  @doc """
  Evaluates the `hooks` according to the given execution `mode`.
  """
  @spec eval({mode, hooks :: [hook_fun]}, command, result :: any) :: any
  def eval({_mode, []}, _command, result), do: result

  def eval({mode, hooks}, {_cache, _action, _args} = command, result) do
    Enum.reduce(hooks, result, fn
      hook, acc when is_function(hook, 2) and mode == :pipe ->
        hook.(acc, command)

      hook, ^result when is_function(hook, 2) and mode == :sync ->
        _ = hook.(result, command)
        result

      hook, ^result when is_function(hook, 2) ->
        _ = Task.start_link(:erlang, :apply, [hook, [result, command]])
        result

      _, acc when mode == :pipe ->
        acc

      _, _ ->
        result
    end)
  end
end
