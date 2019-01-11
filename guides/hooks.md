# Pre/Post Hooks

Pre/Post hooks are functions that you define and that you direct to execute
before or after particular methods. Hooks mechanism is very powerful but
dangerous at the same time, so you have to be careful.

When we define a cache, we are able to override `pre_hooks/0` and `post_hooks/0`
functions by providing ours; these callbacks are defined by `c:Nebulex.Cache.Hook`
behaviour. Let's check out the example just below in order to understand better
how it works.

## Logging Hooks Example

Suppose we want to trace all cache calls (before and after they are called)
by logging them. In this case, we need to provide a pre and post hook to log
these calls.

Supposing you have an app already and it is also setup, your cache might looks
like this:

```elixir
defmodule MyApp.Cache do
  use Nebulex.Cache,
    otp_app: :my_app,
    adapter: Nebulex.Adapters.Local

  require Logger

  def pre_hooks do
    log =
      fn result, call ->
        Logger.debug "PRE: #{inspect call} ==> #{inspect result}"
      end

    {:async, [log]}
  end

  def post_hooks do
    log =
      fn result, call ->
        Logger.debug "POST: #{inspect call} ==> #{inspect result}"
      end

    {:pipe, [log]}
  end
end
```

See how the `pre_hooks/0` and `post_hooks/0` are overridden providing our own
pre/post hooks for tracing/logging purposes.

Then, if we open a console and try out:

```elixir
iex(1)> MyApp.Cache.set 1, 1

10:19:47.736 [debug] PRE: {MyApp.Cache, :set, [1, 1, []]}
1

10:19:47.736 [debug] POST: {MyApp.Cache, :set, [1, 1, []]} ==> 1

iex(2)> MyApp.Cache.get 1

10:20:14.941 [debug] PRE: {MyApp.Cache, :get, [1, []]}
1

10:20:14.941 [debug] POST: {MyApp.Cache, :get, [1, []]} ==> 1
```

See how our hooks are logging all cache calls!

## Configuration

It is possible to setup the mode how the hooks are evaluated. The available
modes are:

  * `:async` - all hooks are evaluated asynchronously (in parallel) and their
    results are ignored.

  * `:sync` - hooks are evaluated synchronously (sequentially) and their
    results are ignored.

  * `:pipe` - similar to `:sync` but each hook result is passed to the
    next one and so on, until the last hook evaluation is returned.

You have to be careful with `:pipe` option, because the result of the hook is
passed to the next one and so on, and the final result will be the result of
the last hook. So, as you can see, the result can be manipulated, but this
behaviour only affects the post hooks, because the result of pre hooks is
ignored – the result is piped between pre hooks, but the final result never
arrives to the cache action.
