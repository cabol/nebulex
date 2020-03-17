# Pre/Post Hooks

Since `v2.0.0`, pre/post hooks are not supported and/or handled by `Nebulex`
itself. Hooks feature is not a common use-case and also it is something that
can be be easily implemented on top of the Cache at application level.

Nevertheless, to keep backwards compatibility somehow, `Nebulex` provides an
[annotation/decorator][hook_decorator] for implementing pre/post hooks very
easily.

[hook_decorator]: http://hexdocs.pm/nebulex/Nebulex.Decorators.html#hook/3

## Logging Hook Example

Suppose we want to trace all cache calls (before and after they are called)
by logging them. In this case, we need to provide a pre and post hook to log
these calls.

First of all, we have to create a module implementing `Nebulex.Hook` behaviour:

```elixir
defmodule MyApp.LoggingHook do
  use Nebulex.Hook

  alias Nebulex.Hook.Event

  require Logger

  ## Nebulex.Hook

  @impl Nebulex.Hook
  def handle_pre(%Event{} = event) do
    Logger.debug("PRE: #{event.module}.#{event.name}/#{event.arity}")
  end

  @impl Nebulex.Hook
  def handle_post(%Event{} = event) do
    Logger.debug("POST: #{event.module}.#{event.name}/#{event.arity} => #{inspect(event.result)}")
  end
end
```

And then, in our Cache:

```elixir
defmodule MyApp.Cache do
  use Nebulex.Decorators
  @decorate_all hook(MyApp.LoggingHook)

  use Nebulex.Cache,
    otp_app: :my_app,
    adapter: Nebulex.Adapters.Local
end
```

Then, if we open a console and try out:

```elixir
iex(1)> MyApp.Cache.put 1, 1

10:19:47.736 [debug] PRE: Elixir.MyApp.Cache.put/3
:ok

10:19:47.736 [debug] POST: Elixir.MyApp.Cache.put/3 => :ok

iex(2)> MyApp.Cache.get 1

10:20:14.941 [debug] PRE: Elixir.MyApp.Cache.get/2
1

10:20:14.941 [debug] POST: Elixir.MyApp.Cache.get/2 => 1
```

See how our hooks are logging all cache calls!

See also [Nebulex.Hook](http://hexdocs.pm/nebulex/Nebulex.Hook.html).
