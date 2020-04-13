if Code.ensure_loaded?(Decorator.Define) do
  defmodule Nebulex.Decorators do
    @moduledoc ~S"""
    Declarative annotation-based caching via function decorators.

    For caching declaration, the abstraction provides three Elixir function
    decorators: `cacheable `, `cache_evict`, and `cache_put`, which allow
    functions to trigger cache population or cache eviction.
    Let us take a closer look at each annotation.

    > Inspired by [Spring Cache Abstraction](https://docs.spring.io/spring/docs/3.2.x/spring-framework-reference/html/cache.html).

    ## `cacheable` decorator

    As the name implies, `cacheable` is used to demarcate functions that are
    cacheable - that is, functions for whom the result is stored into the cache
    so, on subsequent invocations (with the same arguments), the value in the
    cache is returned without having to actually execute the function. In its
    simplest form, the decorator/annotation declaration requires the name of
    the cache associated with the annotated function:

        @decorate cacheable(cache: Cache)
        def get_account(id) do
          # the logic for retrieving the account ...
        end

    In the snippet above, the function `get_account/1` is associated with the
    cache named `Cache`. Each time the function is called, the cache is checked
    to see whether the invocation has been already executed and does not have
    to be repeated.

    ### Default Key Generation

    Since caches are essentially key-value stores, each invocation of a cached
    function needs to be translated into a suitable key for cache access.
    Out of the box, the caching abstraction uses a simple key-generator
    based on the following algorithm: `:erlang.phash2({module, func_name})`.

    ### Custom Key Generation Declaration

    Since caching is generic, it is quite likely the target functions have
    various signatures that cannot be simply mapped on top of the cache
    structure. This tends to become obvious when the target function has
    multiple arguments out of which only some are suitable for caching
    (while the rest are used only by the function logic). For example:

        @decorate cacheable(cache: Cache)
        def get_account(email, include_users?) do
          # the logic for retrieving the account ...
        end

    At first glance, while the boolean argument influences the way the book is
    found, it is no use for the cache.

    For such cases, the `cacheable` decorator allows the user to specify how
    the key is generated based on the function attributes.

        @decorate cacheable(cache: Cache, key: {Account, email})
        def get_account(email, include_users?) do
          # the logic for retrieving the account ...
        end

        @decorate cacheable(cache: Cache, key: {Account, user.account_id})
        def get_account_by_user(%User{} = user) do
          # the logic for retrieving the account ...
        end

    It is also possible passing options to the cache, like so:

        @decorate cacheable(cache: Cache, key: {Account, email}, opts: [ttl: 300_000])
        def get_account(email, include_users?) do
          # the logic for retrieving the account ...
        end

    See the **"Shared Options"** section below.

    ## `cache_put` decorator

    For cases where the cache needs to be updated without interfering with the
    function execution, one can use the `cache_put` decorator. That is, the
    method will always be executed and its result placed into the cache
    (according to the `cache_put` options). It supports the same options as
    `cacheable`.

        @decorate cache_put(cache: Cache, key: {Account, email})
        def update_account(%Account{} = acct, attrs) do
          # the logic for updating the account ...
        end

    Note that using `cache_put` and `cacheable` annotations on the same function
    is generally discouraged because they have different behaviors. While the
    latter causes the method execution to be skipped by using the cache, the
    former forces the execution in order to execute a cache update. This leads
    to unexpected behavior and with the exception of specific corner-cases
    (such as decorators having conditions that exclude them from each other),
    such declarations should be avoided.

    ## `cache_evict` decorator

    The cache abstraction allows not just the population of a cache store but
    also eviction. This process is useful for removing stale or unused data from
    the cache. Opposed to `cacheable`, the decorator `cache_evict` demarcates
    functions that perform cache eviction, which are functions that act as
    triggers for removing data from the cache. The `cache_evict` decorator not
    only allows a key to be specified, but also a set of keys. Besides, extra
    options like`all_entries` which indicates whether a cache-wide eviction
    needs to be performed rather than just an entry one (based on the key or
    keys):

        @decorate cache_evict(cache: Cache, key: {Account, email})
        def delete_account_by email(email) do
          # the logic for deleting the account ...
        end

        @decorate cacheable(cache: Cache, keys: [{Account, acct.id}, {Account, acct.email}])
        def delete_account(%Account{} = acct) do
          # the logic for deleting the account ...
        end

        @decorate cacheable(cache: Cache, all_entries: true)
        def delete_all_accounts do
          # the logic for deleting all the accounts ...
        end

    The option `all_entries:` comes in handy when an entire cache region needs
    to be cleared out - rather than evicting each entry (which would take a
    long time since it is inefficient), all the entries are removed in one
    operation as shown above.

    ## Putting all together

    Supposing we are using `Ecto` and we want to define some cacheable functions
    within the context `MyApp.Accounts`:

        defmodule MyApp.Accounts do
          use Nebulex.Decorators

          import Ecto.Query

          alias MyApp.Accounts.Account
          alias MyApp.{Cache, Repo}

          @ttl 3_600_000 #=> 1 hr

          @decorate cacheable(cache: Cache, key: {Account, id}, opts: [ttl: @ttl])
          def get_account!(id) do
            Repo.get!(Account, id)
          end

          @decorate cacheable(cache: Cache, key: {Account, clauses})
          def get_account_by!(clauses) do
            Repo.get_by!(Account, clauses)
          end

          @decorate cacheable(cache: Cache, match: &match_fun/1)
          def accounts_by_type(type) do
            query = from(q in Account, where: q.type == ^type)
            Repo.all(query)
          end

          defp match_fun([]), do: false
          defp match_fun(_), do: true

          @decorate cache_put(cache: Cache, key: {Account, acct.id})
          def update_account!(%Account{} = acct, attrs) do
            acct
            |> Account.changeset(attrs)
            |> Repo.update!()
          end

          @decorate cache_evict(
                      cache: Cache,
                      keys: [
                        {Account, acct.id},
                        {Account, [email: acct.email]}
                      ]
                    )
          def delete_account(%Account{} = acct) do
            Repo.delete(acct)
          end
        end

    ## Shared Options

    All three cache annotations explained previously accept the following
    options:

      * `:cache` - Defines what cache to use (required). Raises `ArgumentError`
        if the option is not present.

      * `:key` - Defines the cache access key (optional). If this option
        is not present, a default key is generated by hashing the tuple
        `{module, fun_name}`; the first element is the caller module and the
        second one the function name (`:erlang.phash2({module, fun})`).

      * `:opts` - Defines the cache options that will be passed as argument
        to the invoked cache function (optional).

      * `:match` - Defines a function `(element() -> as_boolean(term()))` that
        receives the evaluated code block and decides if the cache should be
        updated or not (optional). Caches only those elements for which `fun`
        returns a truthy value. It does not have any effect on `cache_evict`
        since values are always evicted before executing the function logic.

    See [Cache Usage Patters Guide](http://hexdocs.pm/nebulex/cache-usage-patterns.html).

    ## Pre/Post Hooks

    Since `v2.0.0`, pre/post hooks are not supported and/or handled by `Nebulex`
    itself. Hooks feature is not a common use-case and also it is something that
    can be be easily implemented on top of the Cache at the application level.

    Nevertheless, to keep backward compatibility somehow, `Nebulex` provides a
    decorator for implementing pre/post hooks very easily.

    Suppose we want to trace all cache calls (before and after they are called)
    by logging them. In this case, we need to provide a pre/post hook to log
    these calls.

    First of all, we have to create a module implementing `Nebulex.Hook`
    behaviour:

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
            Logger.debug(
              "POST: #{event.module}.#{event.name}/#{event.arity} => #{inspect(event.result)}")
          end
        end

    And then, in the Cache:

        defmodule MyApp.Cache do
          use Nebulex.Decorators
          @decorate_all hook(MyApp.LoggingHook)

          use Nebulex.Cache,
            otp_app: :my_app,
            adapter: Nebulex.Adapters.Local
        end

    Try it out:

        iex(1)> MyApp.Cache.put 1, 1
        10:19:47.736 [debug] PRE: Elixir.MyApp.Cache.put/3
        :ok
        10:19:47.736 [debug] POST: Elixir.MyApp.Cache.put/3 => :ok
        iex(2)> MyApp.Cache.get 1
        10:20:14.941 [debug] PRE: Elixir.MyApp.Cache.get/2
        1
        10:20:14.941 [debug] POST: Elixir.MyApp.Cache.get/2 => 1

    See also [Nebulex.Hook](http://hexdocs.pm/nebulex/Nebulex.Hook.html).
    """

    use Decorator.Define, cacheable: 1, cache_evict: 1, cache_put: 1, hook: 1

    @doc """
    Provides a way of annotating functions to be cached (cacheable aspect).

    The returned value by the code block is cached if it doesn't exist already
    in cache, otherwise, it is returned directly from cache and the code block
    is not executed.

    ## Options

    See the "Shared options" section at the module documentation.

    ## Examples

        defmodule MyApp.Example do
          use Nebulex.Decorators

          alias MyApp.Cache

          @decorate cacheable(cache: Cache, key: name)
          def get_by_name(name, age) do
            # your logic (maybe the loader to retrieve the value from the SoR)
          end

          @decorate cacheable(cache: Cache, key: age, opts: [ttl: 3600])
          def get_by_age(age) do
            # your logic (maybe the loader to retrieve the value from the SoR)
          end

          @decorate cacheable(cache: Cache, key: clauses, match: &match_fun/1)
          def all(clauses) do
            # your logic (maybe the loader to retrieve the value from the SoR)
          end

          defp match_fun([]), do: false
          defp match_fun(_), do: true
        end

    The **Read-through** pattern is supported by this decorator. The loader to
    retrieve the value from the system-of-record (SoR) is your function's logic
    and the rest is provided by the macro under-the-hood.
    """
    def cacheable(attrs, block, context) do
      caching_action(:cacheable, attrs, block, context)
    end

    @doc """
    Provides a way of annotating functions to be evicted; but updating the
    cached key instead of deleting it.

    The content of the cache is updated without interfering with the function
    execution. That is, the method would always be executed and the result
    cached.

    The difference between `cacheable/3` and `cache_put/3` is that `cacheable/3`
    will skip running the function if the key exists in the cache, whereas
    `cache_put/3` will actually run the function and then put the result in
    the cache.

    ## Options

    See the "Shared options" section at the module documentation.

    ## Examples

        defmodule MyApp.Example do
          use Nebulex.Decorators

          alias MyApp.Cache

          @decorate cache_put(cache: Cache, key: name)
          def update(name) do
            # your logic (maybe write data to the SoR)
          end

          @decorate cache_put(cache: Cache, opts: [ttl: 3600])
          def update_with_ttl(name) do
            # your logic (maybe write data to the SoR)
          end

          @decorate cache_put(cache: Cache, key: clauses, match: &match_fun/1)
          def update_all(clauses) do
            # your logic (maybe write data to the SoR)
          end

          defp match_fun([]), do: false
          defp match_fun(_), do: true
        end

    The **Write-through** pattern is supported by this decorator. Your function
    provides the logic to write data to the system-of-record (SoR) and the rest
    is provided by the decorator under-the-hood.
    """
    def cache_put(attrs, block, context) do
      caching_action(:cache_put, attrs, block, context)
    end

    @doc """
    Provides a way of annotating functions to be evicted (eviction aspect).

    On function's completion, the given key or keys (depends on the `:key` and
    `:keys` options) are deleted from the cache.

    ## Options

      * `:keys` - Defines the set of keys to be evicted from cache on function
        completion.

      * `:all_entries` - Defines if all entries must be removed on function
        completion. Defaults to `false`.

    See the "Shared options" section at the module documentation.

    ## Examples

        defmodule MyApp.Example do
          use Nebulex.Decorators

          alias MyApp.Cache

          @decorate cache_evict(cache: Cache, key: name)
          def evict(name) do
            # your logic (maybe write/delete data to the SoR)
          end

          @decorate cache_evict(cache: Cache, keys: [attrs.name, attrs.id])
          def evict_many(attrs) do
            # your logic (maybe write/delete data to the SoR)
          end

          @decorate cache_evict(cache: Cache, all_entries: true)
          def evict_all do
            # your logic (maybe write/delete data to the SoR)
          end
        end

    The **Write-through** pattern is supported by this decorator. Your function
    provides the logic to write data to the system-of-record (SoR) and the rest
    is provided by the decorator under-the-hood. But in contrast with `update`
    decorator, when the data is written to the SoR, the key for that value is
    deleted from cache instead of updated.
    """
    def cache_evict(attrs, block, context) do
      caching_action(:cache_evict, attrs, block, context)
    end

    @doc ~S"""
    Provides a way of annotating functions to be hooked (pre/post hooks).

    The first argument `hook` must be a module implementing the `Nebulex.Hook`
    behaviour.

    Raises `Nebulex.HookError` is any error does occurs.

    This decorator runs the following steps:

      1. The callback `c:Nebulex.Hook.handle_pre/1` is invoked; in case there is
         a pre-hook. The returned value is passed to the post- hook within the
         event's accumulator.
      2. The code block is executed, and the result is passed to the post- hook
         within the event's result.
      3. The callback `c:Nebulex.Hook.handle_post/1` is invoked. The return is
         ignored here.
      4. The evaluated code block result is returned.

    This is a very flexible way of implementing or adding pre and post hooks to
    the cache. However, tt should be used very carefully since it may affect the
    performance and/or behavior of the function.

    ## Example

        defmodule MyApp.DebugHook do
          use Nebulex.Hook

          alias Nebulex.Hook.Event

          require Logger

          ## Nebulex.Hook

          @impl true
          def handle_post(%Event{} = e) do
            Logger.debug(
              "#{e.module}.#{e.name}/#{e.arity} => #{inspect(e.result)}")
          end
        end

        defmodule MyApp.MyCache do
          use Nebulex.Decorators
          @decorate_all hook(MyApp.DebugHook)

          use Nebulex.Cache,
            otp_app: :my_app,
            adapter: Nebulex.Adapters.Local
        end

    See also `Nebulex.Hook`.
    """
    def hook(hook, block, context) do
      quote do
        hook = unquote(hook)

        event = %Nebulex.Hook.Event{
          module: unquote(context.module),
          name: unquote(context.name),
          arity: unquote(context.arity)
        }

        try do
          acc = hook.handle_pre(event)
          result = unquote(block)
          _ = hook.handle_post(%{event | result: result, acc: acc})
          result
        rescue
          e -> reraise Nebulex.HookError, [exception: e], __STACKTRACE__
        end
      end
    end

    ## Private Functions

    defp caching_action(action, attrs, block, context) do
      cache = attrs[:cache] || raise ArgumentError, "expected cache: to be given as argument"

      key_var = Keyword.get(attrs, :key)
      keys_var = Keyword.get(attrs, :keys, [])
      match_var = Keyword.get(attrs, :match)
      opts_var = Keyword.get(attrs, :opts, [])

      action_logic = action_logic(action, block, attrs)

      quote do
        cache = unquote(cache)
        key = unquote(key_var) || :erlang.phash2({unquote(context.module), unquote(context.name)})
        keys = unquote(keys_var)
        opts = unquote(opts_var)
        match = unquote(match_var) || fn _ -> true end

        unquote(action_logic)
      end
    end

    defp action_logic(:cacheable, block, _attrs) do
      quote do
        if value = cache.get(key, opts) do
          value
        else
          value = unquote(block)

          if match.(value) do
            :ok = cache.put(key, value, opts)
            value
          else
            value
          end
        end
      end
    end

    defp action_logic(:cache_put, block, _attrs) do
      quote do
        value = unquote(block)

        if match.(value) do
          :ok = cache.put(key, value, opts)
          value
        else
          value
        end
      end
    end

    defp action_logic(:cache_evict, block, attrs) do
      all_entries? = Keyword.get(attrs, :all_entries, false)

      quote do
        if unquote(all_entries?) do
          cache.flush()
        else
          Enum.each([key | keys], fn k ->
            if k, do: cache.delete(k)
          end)
        end

        unquote(block)
      end
    end
  end
end
