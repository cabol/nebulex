if Code.ensure_loaded?(Decorator.Define) do
  defmodule Nebulex.Hook do
    @moduledoc """
    Pre/Post Hooks

    Since `v2.0.0`, pre/post hooks are not supported and/or handled by `Nebulex`
    itself. Hooks feature is not a common use-case and also it is something that
    can be be easily implemented on top of the Cache at the application level.

    Nevertheless, to keep backward compatibility somehow, `Nebulex` provides the
    next decorators for implementing pre/post hooks very easily.

    ## `before` decorator

    The `before` decorator is declared for performing a hook action or callback
    before the annotated function is executed.

        @decorate before(fn %Nebulex.Hook{} = hook -> inspect(hook) end)
        def some_fun(var) do
          # logic ...
        end

    ## `after_return` decorator

    The `after_return` decorator is declared for performing a hook action or
    callback after the annotated function is executed and its return is passed
    through the `return:` attribute.

        @decorate after_return(&inspect(&1.return))
        def some_fun(var) do
          # logic ...
        end

    ## `around` decorator

    The final kind of hook is `around` decorator. The `around` decorator runs
    "around" the annotated function execution. It has the opportunity to do
    work both **before** and **after** the function executes. This means the
    given hook function is invoked twice, before and after the code-block is
    evaluated.

        @decorate around(&inspect(&1.step))
        def some_fun(var) do
          # logic ...
        end

    ## Putting all together

    Suppose we want to track all cache calls (before and after they are called)
    by logging them (including the execution time). In this case, we need to
    provide a pre/post hook to log these calls.

    First of all, we have to create a module implementing the hook function:

        defmodule MyApp.Tracker do
          use GenServer

          alias Nebulex.Hook

          require Logger

          @actions [:get, :put]

          ## API

          def start_link(opts \\\\ []) do
            GenServer.start_link(__MODULE__, opts, name: __MODULE__)
          end

          def track(%Hook{step: :before, name: name}) when name in @actions do
            System.system_time(:microsecond)
          end

          def track(%Hook{step: :after_return, name: name} = event) when name in @actions do
            GenServer.cast(__MODULE__, {:track, event})
          end

          def track(hook), do: hook

          ## GenServer Callbacks

          @impl true
          def init(_opts) do
            {:ok, %{}}
          end

          @impl true
          def handle_cast({:track, %Hook{acc: start} = hook}, state) do
            diff = System.system_time(:microsecond) - start
            Logger.info("#=> #\{hook.module}.#\{hook.name}/#\{hook.arity}, Duration: #\{diff}")
            {:noreply, state}
          end
        end

    And then, in the Cache:

        defmodule MyApp.Cache do
          use Nebulex.Hook
          @decorate_all around(&MyApp.Tracker.track/1)

          use Nebulex.Cache,
            otp_app: :my_app,
            adapter: Nebulex.Adapters.Local
        end

    Try it out:

        iex> MyApp.Cache.put 1, 1
        10:19:47.736 [info] Elixir.MyApp.Cache.put/3, Duration: 27
        iex> MyApp.Cache.get 1
        10:20:14.941 [info] Elixir.MyApp.Cache.get/2, Duration: 11

    """

    use Decorator.Define, before: 1, after_return: 1, around: 1

    @enforce_keys [:step, :module, :name, :arity]
    defstruct [:step, :module, :name, :arity, :return, :acc]

    @type t :: %__MODULE__{
            step: :before | :after_return,
            module: Nebulex.Cache.t(),
            name: atom,
            arity: non_neg_integer,
            return: term,
            acc: term
          }

    @type hook_fun :: (t -> term)

    alias Nebulex.Hook

    @doc """
    Before decorator.

    Intercepts any call to the annotated function and calls the given `fun`
    before the logic is executed.

    ## Example

        defmodule MyApp.Example do
          use Nebulex.Hook

          @decorate before(&inspect(&1))
          def some_fun(var) do
            # logic ...
          end
        end

    """
    @spec before(hook_fun, term, map) :: term
    def before(fun, block, context) do
      with_hook([:before], fun, block, context)
    end

    @doc """
    After-return decorator.

    Intercepts any call to the annotated function and calls the given `fun`
    after the logic is executed, and the returned result is passed through
    the `return:` attribute.

    ## Example

        defmodule MyApp.Example do
          use Nebulex.Hook

          @decorate after_return(&inspect(&1))
          def some_fun(var) do
            # logic ...
          end
        end

    """
    @spec after_return(hook_fun, term, map) :: term
    def after_return(fun, block, context) do
      with_hook([:after_return], fun, block, context)
    end

    @doc """
    Around decorator.

    Intercepts any call to the annotated function and calls the given `fun`
    before and after the logic is executed. The result of the first call to
    the hook function is passed through the `acc:` attribute, so it can be
    used in the next call (after return). Finally, as the `after_return`
    decorator, the returned code-block evaluation is passed through the
    `return:` attribute.

    ## Example

        defmodule MyApp.Profiling do
          alias Nebulex.Hook

          def prof(%Hook{step: :before}) do
            System.system_time(:microsecond)
          end

          def prof(%Hook{step: :after_return, acc: start} = hook) do
            :telemetry.execute(
              [:my_app, :profiling],
              %{duration: System.system_time(:microsecond) - start},
              %{module: hook.module, name: hook.name}
            )
          end
        end

        defmodule MyApp.Example do
          use Nebulex.Hook

          @decorate around(&MyApp.Profiling.prof/1)
          def some_fun(var) do
            # logic ...
          end
        end

    """
    @spec around(hook_fun, term, map) :: term
    def around(fun, block, context) do
      with_hook([:before, :after_return], fun, block, context)
    end

    defp with_hook(hooks, fun, block, context) do
      quote do
        hooks = unquote(hooks)
        fun = unquote(fun)

        hook = %Nebulex.Hook{
          step: :before,
          module: unquote(context.module),
          name: unquote(context.name),
          arity: unquote(context.arity)
        }

        # eval before
        acc =
          if :before in hooks do
            Hook.eval_hook(:before, fun, hook)
          end

        # eval code-block
        return = unquote(block)

        # eval after_return
        if :after_return in hooks do
          Hook.eval_hook(
            :after_return,
            fun,
            %{hook | step: :after_return, return: return, acc: acc}
          )
        end

        return
      end
    end

    @doc """
    This function is for internal purposes.
    """
    @spec eval_hook(:before | :after_return, hook_fun, t) :: term
    def eval_hook(step, fun, hook) do
      fun.(hook)
    rescue
      e ->
        msg = "hook execution failed on step #{inspect(step)} with error #{inspect(e)}"
        reraise RuntimeError, msg, __STACKTRACE__
    end
  end
end
