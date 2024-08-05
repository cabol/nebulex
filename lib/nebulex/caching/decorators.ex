if Code.ensure_loaded?(Decorator.Define) do
  defmodule Nebulex.Caching.Decorators do
    @moduledoc """
    Declarative annotation-based caching via function
    [decorators](https://github.com/arjan/decorator).

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
    based on the following algorithm:

      * If no params are given, return `0`.
      * If only one param is given, return that param as key.
      * If more than one param is given, return a key computed from the hashes
        of all parameters (`:erlang.phash2(args)`).

    > **IMPORTANT:** Since Nebulex v2.1.0, the default key generation implements
      the algorithm described above, breaking backward compatibility with older
      versions. Therefore, you may need to change your code in case of using the
      default key generation.

    The default key generator is provided by the cache via the callback
    `c:Nebulex.Cache.__default_key_generator__/0` and it is applied only
    if the option `key:` or `keys:` is not configured. Defaults to
    `Nebulex.Caching.SimpleKeyGenerator`. You can change the default
    key generator at compile time with the option `:default_key_generator`.
    For example, one can define a cache with a default key generator as:

        defmodule MyApp.Cache do
          use Nebulex.Cache,
            otp_app: :my_app,
            adapter: Nebulex.Adapters.Local,
            default_key_generator: __MODULE__

          @behaviour Nebulex.Caching.KeyGenerator

          @impl true
          def generate(mod, fun, args), do: :erlang.phash2({mod, fun, args})
        end

    The key generator module must implement the `Nebulex.Caching.KeyGenerator`
    behaviour.

    > **IMPORTANT:** There are some caveats to keep in mind when using
      the key generator, therefore, it is highly recommended to review
      `Nebulex.Caching.KeyGenerator` behaviour documentation before.

    Also, you can provide a different key generator at any time
    (overriding the default one) when using any caching annotation
    through the option `:key_generator`. For example:

        # With a module implementing the key-generator behaviour
        @decorate cache_put(cache: Cache, key_generator: CustomKeyGenerator)
        def update_account(account) do
          # the logic for updating the given entity ...
        end

        # With the shorthand tuple {module, args}
        @decorate cache_put(
                    cache: Cache,
                    key_generator: {CustomKeyGenerator, [account.name]}
                  )
        def update_account2(account) do
          # the logic for updating the given entity ...
        end

        # With a MFA tuple
        @decorate cache_put(
                    cache: Cache,
                    key_generator: {AnotherModule, :genkey, [account.id]}
                  )
        def update_account3(account) do
          # the logic for updating the given entity ...
        end

    > The `:key_generator` option is available for all caching annotations.

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

    At first glance, while the boolean argument influences the way the account
    is found, it is no use for the cache.

    For such cases, the `cacheable` decorator allows the user to specify the
    key explicitly based on the function attributes.

        @decorate cacheable(cache: Cache, key: {Account, email})
        def get_account(email, include_users?) do
          # the logic for retrieving the account ...
        end

        @decorate cacheable(cache: Cache, key: {Account, user.account_id})
        def get_user_account(%User{} = user) do
          # the logic for retrieving the account ...
        end

    It is also possible passing options to the cache, like so:

        @decorate cacheable(
                    cache: Cache,
                    key: {Account, email},
                    opts: [ttl: 300_000]
                  )
        def get_account(email, include_users?) do
          # the logic for retrieving the account ...
        end

    See the **"Shared Options"** section below.

    ### Functions with multiple clauses

    Since [decorator lib](https://github.com/arjan/decorator#functions-with-multiple-clauses)
    is used, it is important to be aware of its recommendations, warns,
    limitations, and so on. In this case, for functions with multiple clauses
    the general advice is to create an empty function head, and call the
    decorator on that head, like so:

        @decorate cacheable(cache: Cache, key: email)
        def get_account(email \\\\ nil)

        def get_account(nil), do: nil

        def get_account(email) do
          # the logic for retrieving the account ...
        end

    ## `cache_put` decorator

    For cases where the cache needs to be updated without interfering with the
    function execution, one can use the `cache_put` decorator. That is, the
    method will always be executed and its result placed into the cache
    (according to the `cache_put` options). It supports the same options as
    `cacheable`.

        @decorate cache_put(cache: Cache, key: {Account, acct.email})
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
        def delete_account_by_email(email) do
          # the logic for deleting the account ...
        end

        @decorate cacheable(
                    cache: Cache,
                    keys: [{Account, acct.id}, {Account, acct.email}]
                  )
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

    ## Shared Options

    All three cache annotations explained previously accept the following
    options:

      * `:cache` - Defines what cache to use (required). Raises `ArgumentError`
        if the option is not present. It can be also a MFA tuple to resolve the
        cache dynamically in runtime by calling it. See "The :cache option"
        section below for more information.

      * `:key` - Defines the cache access key (optional). It overrides the
        `:key_generator` option. If this option is not present, a default
        key is generated by the configured or default key generator.

      * `:opts` - Defines the cache options that will be passed as argument
        to the invoked cache function (optional).

      * `:match` - Match function `t:match_fun/0`. This function is for matching
        and deciding whether the code-block evaluation result (which is received
        as an argument) is cached or not. The function should return:

          * `true` - the code-block evaluation result is cached as it is
            (the default).
          * `{true, value}` - `value` is cached. This is useful to set what
            exactly must be cached.
          * `{true, value, opts}` - `value` is cached with the options given by
            `opts`. This return allows us to set the value to be cached, as well
            as the runtime options for storing it (e.g.: the `ttl`).
          * `false` - Nothing is cached.

        The default match function looks like this:

        ```elixir
        fn
          {:error, _} -> false
          :error -> false
          nil -> false
          _ -> true
        end
        ```

        By default, if the code-block evaluation returns any of the following
        terms/values `nil`, `:error`, `{:error, term}`, the default match
        function returns `false` (the returned result is not cached),
        otherwise, `true` is returned (the returned result is cached).

      * `:key_generator` - The custom key-generator to be used (optional).
        If present, this option overrides the default key generator provided
        by the cache, and it is applied only if the option `key:` or `keys:`
        is not present. In other words, the option `key:` or `keys:` overrides
        the `:key_generator` option. See "The `:key_generator` option" section
        below for more information about the possible values.

      * `:on_error` - It may be one of `:raise` (the default) or `:nothing`.
        The decorators/annotations call the cache under the hood, hence,
        by default, any error or exception at executing a cache command
        is propagated. When this option is set to `:nothing`, any error
        or exception executing a cache command is ignored and the annotated
        function is executed normally.

    ### The `:cache` option

    The cache option can be the de defined cache module or an MFA tuple to
    resolve the cache dynamically in runtime. When it is an MFA tuple, the
    MFA is invoked passing the calling module, function name, and arguments
    by default, and the MFA arguments are passed as extra arguments.
    For example:

        @decorate cacheable(cache: {MyApp.Cache, :cache, []}, key: var)
        def some_function(var) do
          # Some logic ...
        end

    The annotated function above will call `MyApp.Cache.cache(mod, fun, args)`
    to resolve the cache in runtime, where `mod` is the calling module, `fun`
    the calling function name, and `args` the calling arguments.

    Also, we can define the function passing some extra arguments, like so:

        @decorate cacheable(cache: {MyApp.Cache, :cache, ["extra"]}, key: var)
        def some_function(var) do
          # Some logic ...
        end

    In this case, the MFA will be invoked by adding the extra arguments, like:
    `MyApp.Cache.cache(mod, fun, args, "extra")`.

    ### The `:key_generator` option

    The possible values for the `:key_generator` are:

      * A module implementing the `Nebulex.Caching.KeyGenerator` behaviour.

      * A MFA tuple `{module, function, args}` for a function to call to
        generate the key before the cache is invoked. A shorthand value of
        `{module, args}` is equivalent to
        `{module, :generate, [calling_module, calling_function_name, args]}`.

    ## Putting all together

    Supposing we are using `Ecto` and we want to define some cacheable functions
    within the context `MyApp.Accounts`:

        # The config
        config :my_app, MyApp.Cache,
          gc_interval: 86_400_000, #=> 1 day
          backend: :shards

        # The Cache
        defmodule MyApp.Cache do
          use Nebulex.Cache,
            otp_app: :my_app,
            adapter: Nebulex.Adapters.Local
        end

        # Some Ecto schema
        defmodule MyApp.Accounts.User do
          use Ecto.Schema

          schema "users" do
            field(:username, :string)
            field(:password, :string)
            field(:role, :string)
          end

          def changeset(user, attrs) do
            user
            |> cast(attrs, [:username, :password, :role])
            |> validate_required([:username, :password, :role])
          end
        end

        # Accounts context
        defmodule MyApp.Accounts do
          use Nebulex.Caching

          alias MyApp.Accounts.User
          alias MyApp.{Cache, Repo}

          @ttl :timer.hours(1)

          @decorate cacheable(cache: Cache, key: {User, id}, opts: [ttl: @ttl])
          def get_user!(id) do
            Repo.get!(User, id)
          end

          @decorate cacheable(
                      cache: Cache,
                      key: {User, username},
                      opts: [ttl: @ttl]
                    )
          def get_user_by_username(username) do
            Repo.get_by(User, [username: username])
          end

          @decorate cache_put(
                      cache: Cache,
                      keys: [{User, usr.id}, {User, usr.username}],
                      match: &match_update/1
                    )
          def update_user(%User{} = usr, attrs) do
            usr
            |> User.changeset(attrs)
            |> Repo.update()
          end

          defp match_update({:ok, usr}), do: {true, usr}
          defp match_update({:error, _}), do: false

          @decorate cache_evict(
                      cache: Cache,
                      keys: [{User, usr.id}, {User, usr.username}]
                    )
          def delete_user(%User{} = usr) do
            Repo.delete(usr)
          end

          def create_user(attrs \\\\ %{}) do
            %User{}
            |> User.changeset(attrs)
            |> Repo.insert()
          end
        end

    See [Cache Usage Patterns Guide](http://hexdocs.pm/nebulex/cache-usage-patterns.html).
    """

    use Decorator.Define, cacheable: 1, cache_evict: 1, cache_put: 1

    import Nebulex.Helpers
    import Record

    ## Types

    # Key reference spec
    defrecordp(:keyref, :"$nbx_cache_keyref", cache: nil, key: nil)

    @typedoc "Type spec for a key reference"
    @type keyref :: record(:keyref, cache: Nebulex.Cache.t(), key: any)

    @typedoc "Type for :on_error option"
    @type on_error_opt :: :raise | :nothing

    @typedoc "Match function type"
    @type match_fun :: (any -> boolean | {true, any} | {true, any, Keyword.t()})

    @typedoc "Type spec for the option :references"
    @type references :: (any -> any) | nil | any

    ## API

    @doc """
    Provides a way of annotating functions to be cached (cacheable aspect).

    The returned value by the code block is cached if it doesn't exist already
    in cache, otherwise, it is returned directly from cache and the code block
    is not executed.

    ## Options

      * `:references` - (Optional) (`t:references/0`) Indicates the key given
        by the option `:key` references another key given by the option
        `:references`. In other words, when it is present, this option tells
        the `cacheable` decorator to store the function's block result under
        the referenced key given by the option `:references`, and the referenced
        key under the key given by the option `:key`. The value could be:

        * `nil` - (Default) It is ignored (no key references).
        * `(term -> keyref | term)` - An anonymous function receiving the
          result of the function's code block evaluation and must return the
          referenced key. There is also a special type of return in case you
          want to reference a key located in an external/different cache than
          the one defined with the options `:key` or `:key_generator`. In this
          scenario, you must return a special type `t:keyref/0`, which can be
          build with the macro [`keyref/2`](`Nebulex.Caching.keyref/2`).
          See the "External referenced keys" section below.
        * `any` - It could be an explicit term or value, for example, a fixed
          value or a function argument.

        See the "Referenced keys" section for more information.

    See the "Shared options" section at the module documentation.

    ## Examples

        defmodule MyApp.Example do
          use Nebulex.Caching

          alias MyApp.Cache

          @ttl :timer.hours(1)

          @decorate cacheable(cache: Cache, key: id, opts: [ttl: @ttl])
          def get_by_id(id) do
            # your logic (maybe the loader to retrieve the value from the SoR)
          end

          @decorate cacheable(cache: Cache, key: email, references: & &1.id)
          def get_by_email(email) do
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

    ## Referenced keys

    Referenced keys are particularly useful when you have multiple different
    keys keeping the same value. For example, let's imagine we have an schema
    `User` with more than one unique field, like `:id`, `:email`, and `:token`.
    We may have a module with functions retrieving the user account by any of
    those fields, like so:

        defmodule MyApp.UserAccounts do
          use Nebulex.Caching

          alias MyApp.Cache

          @decorate cacheable(cache: Cache, key: id)
          def get_user_account(id) do
            # your logic ...
          end

          @decorate cacheable(cache: Cache, key: email)
          def get_user_account_by_email(email) do
            # your logic ...
          end

          @decorate cacheable(cache: Cache, key: token)
          def get_user_account_by_token(token) do
            # your logic ...
          end

          @decorate cache_evict(
                      cache: Cache,
                      keys: [user.id, user.email, user.token]
                    )
          def update_user_account(user) do
            # your logic ...
          end
        end

    As you notice, all the three functions will end up storing the same user
    record under a different key. This is not very efficient in terms of
    memory space, is it? Besides, when the user record is updated, we have
    to invalidate the previously cached entries, which means, we have to
    specify in the `cache_evict` decorator all the different keys the user
    account has ben cached under.

    By means of the referenced keys, we can address it in a better and simpler
    way. The module will look like this:

        defmodule MyApp.UserAccounts do
          use Nebulex.Caching

          alias MyApp.Cache

          @decorate cacheable(cache: Cache, key: id)
          def get_user_account(id) do
            # your logic ...
          end

          @decorate cacheable(cache: Cache, key: email, references: & &1.id)
          def get_user_account_by_email(email) do
            # your logic ...
          end

          @decorate cacheable(cache: Cache, key: token, references: & &1.id)
          def get_user_account_by_token(token) do
            # your logic ...
          end

          @decorate cache_evict(cache: Cache, key: user.id)
          def update_user_account(user) do
            # your logic ...
          end
        end

    With the option `:references` we are indicating to the `cacheable` decorator
    to store the user id (`& &1.id` - assuming the function returns an user
    record) under the key `email` and the key `token`, and the user record
    itself under the user id, which is the referenced key. This time, instead of
    storing the same object three times, it will be stored only once under the
    user id, and the other entries will just keep a reference to it. When the
    functions `get_user_account_by_email/1` or `get_user_account_by_token/1`
    are executed, the decorator will automatically handle it; under-the-hood,
    it will fetch the referenced key given by `email` or `token` first, and
    then get the user record under the referenced key.

    On the other hand, in the eviction function `update_user_account/1`, since
    the user record is stored only once under the user's ID, we could set the
    option `:key` to the user's ID, without specifying multiple keys like in the
    previous case. However, there is a caveat: _"the `cache_evict` decorator
    doesn't evict the references automatically"_. See the
    ["CAVEATS"](#cacheable/3-caveats) section below.

    ### External referenced keys

    Previously, we saw how to work with referenced keys but on the same cache,
    like "internal references." Despite this being the typical case scenario,
    there could be situations where you may want to reference a key stored in a
    different or external cache. Why would I want to reference a key located in
    a separate cache? There may be multiple reasons, but let's give a few
    examples.

      * One example is when you have a Redis cache; in such case, you likely
        want to optimize the calls to Redis as much as possible. Therefore, you
        should store the referenced keys in a local cache and the values in
        Redis. This way, we only hit Redis to access the keys with the actual
        values, and the decorator resolves the referenced keys locally.

      * Another example is for keeping the cache key references isolated,
        preferably locally. Then, apply a different eviction (or garbage
        collection) policy for the references; one may want to expire the
        references more often to avoid having dangling keys since the
        `cache_evict` decorator doesn't remove the references automatically,
        just the defined key (or keys). See the
        ["CAVEATS"](#cacheable/3-caveats) section below.

    Let us modify the previous _"user accounts"_ example based on the Redis
    scenario:

        defmodule MyApp.UserAccounts do
          use Nebulex.Caching

          alias MyApp.{LocalCache, RedisCache}

          @decorate cacheable(cache: RedisCache, key: id)
          def get_user_account(id) do
            # your logic ...
          end

          @decorate cacheable(
                      cache: LocalCache,
                      key: email,
                      references: &keyref(RedisCache, &1.id)
                    )
          def get_user_account_by_email(email) do
            # your logic ...
          end

          @decorate cacheable(
                      cache: LocalCache,
                      key: token,
                      references: &keyref(RedisCache, &1.id)
                    )
          def get_user_account_by_token(token) do
            # your logic ...
          end

          @decorate cache_evict(cache: RedisCache, key: user.id)
          def update_user_account(user) do
            # your logic ...
          end
        end

    The functions `get_user_account/1` and `update_user_account/2` use
    `RedisCache` to store the real value in Redis while
    `get_user_account_by_email/1` and `get_user_account_by_token/1` use
    `LocalCache` to store the referenced keys. Then, with the option
    `references: &keyref(RedisCache, &1.id)` we are telling the `cacheable`
    decorator the referenced key given by `&1.id` is located in the cache
    `RedisCache`; underneath, the macro [`keyref/2`](`Nebulex.Caching.keyref/2`)
    builds the special return type for the external cache reference.

    ### CAVEATS

    * When the `cache_evict` decorator annotates a key (or keys) to evict, the
      decorator removes only the entry associated with that key. Therefore, if
      the key has references, those are not automatically removed, which means
      dangling keys. However, there are multiple ways to address dangling keys
      (or references):

      * The first (and the simplest) sets a TTL to the reference. For example:
        `cacheable(key: name, references: & &1.id, opts: [ttl: @ttl])`. You can
        also specify a different TTL for the referenced key:
        `references: &keyref(&1.id, ttl: @another_ttl)`.

      * The second alternative, perhaps the most recommended, is having a
        separate cache to keep the references (e.g., a cache using the local
        adapter). This way, you could provide a different eviction or GC
        configuration to run the GC more often and keep the references cache
        clean. See
        ["External referenced keys"](#cacheable/3-external-referenced-keys).

      * The third alternative uses the `:keys` option for specifying a key and
        its references. For example, if you have
        `@decorate cacheable(key: email, references: & &1.id)`, the eviction
        may look like this `@decorate cache_evict(keys: [user.id, user.email])`.
        This one is perhaps the least ideal option because it is cumbersome;
        you have to know and specify the key and all its references, and at the
        same time, you will need to have access to the key and references in the
        arguments, which sometimes is not possible because you may receive only
        the ID, but not the email.

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

      * `:keys` - The set of cached keys to be updated with the returned value
        on function completion. It overrides `:key` and `:key_generator`
        options.

    See the "Shared options" section at the module documentation.

    ## Examples

        defmodule MyApp.Example do
          use Nebulex.Caching

          alias MyApp.Cache

          @ttl :timer.hours(1)

          @decorate cache_put(cache: Cache, key: id, opts: [ttl: @ttl])
          def update!(id, attrs \\\\ %{}) do
            # your logic (maybe write data to the SoR)
          end

          @decorate cache_put(
                      cache: Cache,
                      key: id,
                      match: &match_fun/1,
                      opts: [ttl: @ttl]
                    )
          def update(id, attrs \\\\ %{}) do
            # your logic (maybe write data to the SoR)
          end

          @decorate cache_put(
                      cache: Cache,
                      keys: [object.name, object.id],
                      match: &match_fun/1,
                      opts: [ttl: @ttl]
                    )
          def update_object(object) do
            # your logic (maybe write data to the SoR)
          end

          defp match_fun({:ok, updated}), do: {true, updated}
          defp match_fun({:error, _}), do: false
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
        completion. It overrides `:key` and `:key_generator` options.

      * `:all_entries` - Defines if all entries must be removed on function
        completion. Defaults to `false`.

      * `:before_invocation` - Boolean to indicate whether the eviction should
        occur after (the default) or before the function executes. The former
        provides the same semantics as the rest of the annotations; once the
        function completes successfully, an action (in this case eviction)
        on the cache is executed. If the function does not execute (as it might
        be cached) or an exception is raised, the eviction does not occur.
        The latter (`before_invocation: true`) causes the eviction to occur
        always, before the function is invoked; this is useful in cases where
        the eviction does not need to be tied to the function outcome.

    See the "Shared options" section at the module documentation.

    ## Examples

        defmodule MyApp.Example do
          use Nebulex.Caching

          alias MyApp.Cache

          @decorate cache_evict(cache: Cache, key: id)
          def delete(id) do
            # your logic (maybe write/delete data to the SoR)
          end

          @decorate cache_evict(cache: Cache, keys: [object.name, object.id])
          def delete_object(object) do
            # your logic (maybe write/delete data to the SoR)
          end

          @decorate cache_evict(cache: Cache, all_entries: true)
          def delete_all do
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

    @doc """
    A convenience function for building a cache key reference when using the
    `cacheable` decorator. If you want to build an external reference, which is,
    referencing a `key` stored in an external cache, you have to provide the
    `cache` where the `key` is located to. The `cache` argument is optional,
    and by default is `nil`, which means, the referenced `key` is in the same
    cache provided via `:key` or `:key_generator` options (internal reference).

    **NOTE:** In case you need to build a reference, consider using the macro
    `Nebulex.Caching.keyref/2` instead.

    See `cacheable/3` decorator for more information about external references.

    ## Examples

        iex> Nebulex.Caching.Decorators.build_keyref("my-key")
        {:"$nbx_cache_keyref", nil, "my-key"}
        iex> Nebulex.Caching.Decorators.build_keyref(MyCache, "my-key")
        {:"$nbx_cache_keyref", MyCache, "my-key"}

    """
    @spec build_keyref(Nebulex.Cache.t(), term) :: keyref()
    def build_keyref(cache \\ nil, key) do
      keyref(cache: cache, key: key)
    end

    ## Private Functions

    defp caching_action(action, attrs, block, context) do
      cache = attrs[:cache] || raise ArgumentError, "expected cache: to be given as argument"
      opts_var = attrs[:opts] || []
      on_error_var = on_error_opt(attrs)
      match_var = attrs[:match] || default_match_fun()

      args =
        context.args
        |> Enum.reduce([], &walk/2)
        |> Enum.reverse()

      cache_block = cache_block(cache, args, context)
      keygen_block = keygen_block(attrs, args, context)
      action_block = action_block(action, block, attrs, keygen_block)

      quote do
        cache = unquote(cache_block)
        opts = unquote(opts_var)
        match = unquote(match_var)
        on_error = unquote(on_error_var)

        unquote(action_block)
      end
    end

    defp default_match_fun do
      quote do
        fn
          {:error, _} -> false
          :error -> false
          nil -> false
          _ -> true
        end
      end
    end

    defp walk({:\\, _, [ast, _]}, acc) do
      walk(ast, acc)
    end

    defp walk({:=, _, [_, ast]}, acc) do
      walk(ast, acc)
    end

    defp walk({var, _meta, context} = ast, acc) when is_atom(var) and is_atom(context) do
      if match?("_" <> _, "#{var}") or Macro.special_form?(var, 0) do
        acc
      else
        [ast | acc]
      end
    end

    defp walk(_ast, acc) do
      acc
    end

    # MFA cache: `{module, function, args}`
    defp cache_block({:{}, _, [mod, fun, cache_args]}, args, ctx) do
      quote do
        unquote(mod).unquote(fun)(
          unquote(ctx.module),
          unquote(ctx.name),
          unquote(args),
          unquote_splicing(cache_args)
        )
      end
    end

    # Module implementing the cache behaviour (default)
    defp cache_block({_, _, _} = cache, _args, _ctx) do
      quote(do: unquote(cache))
    end

    defp keygen_block(attrs, args, ctx) do
      cond do
        key = Keyword.get(attrs, :key) ->
          quote(do: unquote(key))

        keygen = Keyword.get(attrs, :key_generator) ->
          keygen_call(keygen, ctx, args)

        true ->
          quote do
            cache.__default_key_generator__().generate(
              unquote(ctx.module),
              unquote(ctx.name),
              unquote(args)
            )
          end
      end
    end

    # MFA key-generator: `{module, function, args}`
    defp keygen_call({:{}, _, [mod, fun, keygen_args]}, _ctx, _args) do
      quote do
        unquote(mod).unquote(fun)(unquote_splicing(keygen_args))
      end
    end

    # Key-generator tuple `{module, args}`, where the `module` implements
    # the key-generator behaviour
    defp keygen_call({{_, _, _} = mod, keygen_args}, ctx, _args) when is_list(keygen_args) do
      quote do
        unquote(mod).generate(unquote(ctx.module), unquote(ctx.name), unquote(keygen_args))
      end
    end

    # Key-generator module implementing the behaviour
    defp keygen_call({_, _, _} = keygen, ctx, args) do
      quote do
        unquote(keygen).generate(unquote(ctx.module), unquote(ctx.name), unquote(args))
      end
    end

    defp action_block(:cacheable, block, attrs, keygen) do
      references = Keyword.get(attrs, :references)

      quote do
        unquote(__MODULE__).eval_cacheable(
          cache,
          unquote(keygen),
          unquote(references),
          opts,
          on_error,
          match,
          fn -> unquote(block) end
        )
      end
    end

    defp action_block(:cache_put, block, attrs, keygen) do
      keys = get_keys(attrs)

      key =
        if is_list(keys) and length(keys) > 0,
          do: {:"$keys", keys},
          else: keygen

      quote do
        result = unquote(block)

        unquote(__MODULE__).run_cmd(
          unquote(__MODULE__),
          :eval_match,
          [result, match, cache, unquote(key), opts],
          on_error,
          result
        )

        result
      end
    end

    defp action_block(:cache_evict, block, attrs, keygen) do
      before_invocation? = attrs[:before_invocation] || false

      eviction = eviction_block(attrs, keygen)

      if before_invocation? == true do
        quote do
          unquote(eviction)
          unquote(block)
        end
      else
        quote do
          result = unquote(block)

          unquote(eviction)

          result
        end
      end
    end

    defp eviction_block(attrs, keygen) do
      keys = get_keys(attrs)
      all_entries? = attrs[:all_entries] || false

      cond do
        all_entries? == true ->
          quote(do: unquote(__MODULE__).run_cmd(cache, :delete_all, [], on_error, 0))

        is_list(keys) and length(keys) > 0 ->
          delete_keys_block(keys)

        true ->
          quote(do: unquote(__MODULE__).run_cmd(cache, :delete, [unquote(keygen)], on_error, :ok))
      end
    end

    defp delete_keys_block(keys) do
      quote do
        Enum.each(unquote(keys), &unquote(__MODULE__).run_cmd(cache, :delete, [&1], on_error, :ok))
      end
    end

    defp get_keys(attrs) do
      get_option(
        attrs,
        :keys,
        "a list with at least one element",
        &((is_list(&1) and length(&1) > 0) or is_nil(&1))
      )
    end

    defp on_error_opt(attrs) do
      get_option(
        attrs,
        :on_error,
        ":raise or :nothing",
        &(&1 in [:raise, :nothing]),
        :raise
      )
    end

    ## Helpers

    @doc """
    Convenience function for evaluating the `cacheable` decorator in runtime.

    **NOTE:** For internal purposes only.
    """
    @spec eval_cacheable(
            module,
            term,
            references,
            Keyword.t(),
            on_error_opt,
            match_fun,
            (-> term)
          ) :: term
    def eval_cacheable(cache, key, references, opts, on_error, match, block)

    def eval_cacheable(cache, key, nil, opts, on_error, match, block) do
      with nil <- run_cmd(cache, :get, [key, opts], on_error) do
        result = block.()

        run_cmd(
          __MODULE__,
          :eval_match,
          [result, match, cache, key, opts],
          on_error,
          result
        )

        result
      end
    end

    def eval_cacheable(cache, key, references, opts, on_error, match, block) do
      case run_cmd(cache, :get, [key, opts], on_error) do
        nil ->
          result = block.()
          ref_key = eval_cacheable_ref(references, result)

          with true <-
                 run_cmd(
                   __MODULE__,
                   :eval_match,
                   [result, match, cache, ref_key, opts],
                   on_error,
                   result
                 ) do
            :ok = cache_put(cache, key, ref_key, opts)
          end

          result

        keyref(cache: ref_cache, key: ref_key) ->
          cache = ref_cache || cache

          with nil <- run_cmd(cache, :get, [ref_key, opts], on_error) do
            result = block.()

            run_cmd(
              __MODULE__,
              :eval_match,
              [result, match, cache, ref_key, opts],
              on_error,
              result
            )

            result
          end

        val ->
          val
      end
    end

    defp eval_cacheable_ref(references, result) do
      with ref_fun when is_function(ref_fun, 1) <- references do
        ref_fun.(result)
      end
      |> case do
        keyref() = ref -> ref
        ref_key -> keyref(key: ref_key)
      end
    end

    @doc """
    Convenience function for evaluating the `:match` function in runtime.

    **NOTE:** For internal purposes only.

    **NOTE:** Workaround to avoid dialyzer warnings when using declarative
    annotation-based caching via decorators.
    """
    @spec eval_match(term, match_fun, module, term, Keyword.t()) :: boolean
    def eval_match(result, match, cache, key, opts)

    def eval_match(result, match, cache, keyref(cache: nil, key: key), opts) do
      eval_match(result, match, cache, key, opts)
    end

    def eval_match(result, match, _cache, keyref(cache: ref_cache, key: key), opts) do
      eval_match(result, match, ref_cache, key, opts)
    end

    def eval_match(result, match, cache, key, opts) do
      case match.(result) do
        {true, value} ->
          :ok = cache_put(cache, key, value, opts)

          true

        {true, value, match_opts} ->
          :ok = cache_put(cache, key, value, Keyword.merge(opts, match_opts))

          true

        true ->
          :ok = cache_put(cache, key, result, opts)

          true

        false ->
          false
      end
    end

    @doc """
    Convenience function for cache_put annotation.

    **NOTE:** For internal purposes only.
    """
    @spec cache_put(module, {:"$keys", term} | term, term, Keyword.t()) :: :ok
    def cache_put(cache, key, value, opts)

    def cache_put(cache, {:"$keys", keys}, value, opts) do
      entries = for k <- keys, do: {k, value}

      cache.put_all(entries, opts)
    end

    def cache_put(cache, key, value, opts) do
      cache.put(key, value, opts)
    end

    @doc """
    Convenience function for ignoring cache errors when `:on_error` option
    is set to `:nothing`

    **NOTE:** For internal purposes only.
    """
    @spec run_cmd(module, atom, [term], on_error_opt, term) :: term
    def run_cmd(mod, fun, args, on_error, default \\ nil)

    def run_cmd(mod, fun, args, :raise, _default) do
      apply(mod, fun, args)
    end

    def run_cmd(mod, fun, args, :nothing, default) do
      apply(mod, fun, args)
    rescue
      _e -> default
    end
  end
end
