if Code.ensure_loaded?(Decorator.Define) do
  defmodule Nebulex.Caching.Decorators do
    @moduledoc """
    Declarative decorator-based caching, inspired by
    [Spring Cache Abstraction][spring-cache].

    > *[`decorator`][decorator-lib] library is used underneath.*

    [spring-cache]: https://docs.spring.io/spring/docs/3.2.x/spring-framework-reference/html/cache.html
    [decorator-lib]: https://github.com/arjan/decorator

    For caching declaration, the abstraction provides three Elixir function
    decorators: `cacheable `, `cache_evict`, and `cache_put`, which allow
    functions to trigger cache population or cache eviction.
    Let us take a closer look at each decorator.

    ## `cacheable` decorator

    As the name implies, `cacheable` is used to delimit functions that are
    cacheable - that is, functions for whom the result is stored in the cache
    so that on subsequent invocations (with the same arguments), the value is
    returned from the cache without having to execute the function. In its
    simplest form, the decorator declaration requires the cache associated with
    the decorated function if the [default cache](#module-default-cache) is not
    configured (see ["Cache configuration"](#module-cache-configuration)):

        @decorate cacheable(cache: Cache)
        def find_book(isbn) do
          # the logic for retrieving the book ...
        end

    In the snippet above, the function `get_account/1` is associated with the
    cache named `Cache`. Each time the function is called, the cache is checked
    to see whether the invocation has been already executed and does not have
    to be repeated.

    See `cacheable/3` for more information.

    ## `cache_put` decorator

    For cases where the cache needs to be updated without interfering with the
    function execution, one can use the `cache_put` decorator. That is, the
    function will always be executed and its result placed into the cache
    (according to the `cache_put` options). It supports the same options as
    `cacheable` and should be used for cache population or update rather than
    function flow optimization.

        @decorate cache_put(cache: Cache)
        def update_book(isbn) do
          # the logic for retrieving the book and then updating it ...
        end

    Note that using `cache_put` and `cacheable` decorators on the same function
    is generally discouraged because they have different behaviors. While the
    latter causes the function execution to be skipped by using the cache, the
    former forces the execution in order to execute a cache update. This leads
    to unexpected behavior and with the exception of specific corner-cases
    (such as decorators having conditions that exclude them from each other),
    such declarations should be avoided.

    See `cache_put/3` for more information.

    ## `cache_evict` decorator

    The cache abstraction allows not just the population of a cache store but
    also eviction. This process is useful for removing stale or unused data from
    the cache. Opposed to `cacheable`, the decorator `cache_evict` demarcates
    functions that perform cache eviction, which are functions that act as
    triggers for removing data from the cache. Just like its sibling,
    `cache_evict` requires specifying the cache that will be affected by the
    action, allows to provide a key or a list of keys to be evicted, but in
    addition, features an extra option `:all_entries` which indicates whether
    a cache-wide eviction needs to be performed rather than just one or a few
    entries (based on `:key` or `:keys` option):

        @decorate cache_evict(cache: Cache, all_entries: true)
        def load_books(file_stream) do
          # the logic for loading books ...
        end

    The option `:all_entries` comes in handy when an entire cache region needs
    to be cleared out - rather than evicting each entry (which would take a
    long time since it is inefficient), all the entries are removed in one
    operation as shown above.

    One can also indicate whether the eviction should occur after (the default)
    or before the function executes through the `:before_invocation` attribute.
    The former provides the same semantics as the rest of the decorators; once
    the method completes successfully, an action (in this case, eviction) on the
    cache is executed. If the function does not execute (as it might be cached)
    or an exception is raised, the eviction does not occur. The latter
    (`before_invocation: true`) causes the eviction to occur always before the
    method is invoked. This is useful in cases where the eviction does not need
    to be tied to the function execution outcome.

    See `cache_evict/3` for more information.

    ## Shared Options

    All three cache decorators explained previously accept the following
    options:

    #{Nebulex.Caching.Options.shared_options_docs()}

    ## Cache configuration

    As documented in the options above, the `:cache` option configures the cache
    for the decorated function (in the decorator declaration). However, there
    are three possible values, such as documented in the `t:cache/0` type.
    Let's go over these cache value alternatives in detail.

    ### Cache module

    The first cache value option is an existing cache module; this is the most
    common value. For example:

        @decorate cacheable(cache: MyApp.Cache)
        def find_book(isbn) do
          # the logic for retrieving the book ...
        end

    ### Dynamic cache

    In case one is using a dynamic cache:

        @decorate cacheable(cache: dynamic_cache(MyApp.Cache, :books))
        def find_book(isbn) do
          # the logic for retrieving the book ...
        end

    > See ["Dynamic caches"][dynamic-caches] for more information.

    [dynamic-caches]: https://hexdocs.pm/nebulex/Nebulex.Cache.html#module-dynamic-caches

    ### Anonymous function

    Finally, it is also possible to configure an anonymous function to resolve
    the cache value in runtime. The function receives the
    [decorator context](`t:context/0`) as an argument and must return either
    a cache module or a dynamic cache.

        @decorate cacheable(cache: &MyApp.Resolver.resolve_cache/1)
        def find_book(isbn) do
          # the logic for retrieving the book ...
        end

    Where `resolve_cache` function may look like this:

        defmodule MyApp.Resolver do
          alias Nebulex.Caching.Decorators.Context

          def resolve_cache(%Context{} = context) do
            # the logic for generating the cache value
          end
        end

    ## Default cache

    While option `:cache` is handy for specifying the decorated function's
    cache, it may be cumbersome when there is a module with several decorated
    functions, and all use the same cache. In that case, we must set the
    `:cache` option with the same value in all the decorated functions.
    Fortunately, the `:cache` option can be configured globally for all
    decorated functions in a module when defining the caching usage via
    `use Nebulex.Caching`. For example:

        defmodule MyApp.Books do
          use Nebulex.Caching, cache: MyApp.Cache

          @decorate cacheable()
          def get_book(isbn) do
            # the logic for retrieving a book ...
          end

          @decorate cacheable(cache: MyApp.BestSellersCache)
          def best_sellers do
            # the logic for retrieving best seller books ...
          end

          ...
        end

    In the snippet above, the function `get_book/1` is associated with the
    cache `MyApp.Cache` by default since option `:cache` is not provided in
    the decorator. In other words, when the `:cache` option is configured
    globally (when defining the caching usage via `use Nebulex.Caching`),
    it is not required in the decorator declaration. However, one can always
    override the global or default cache in the decorator declaration by
    providing the option `:cache`, as is shown in the `best_sellers/0`
    function, which is associated with a different cache.

    To conclude, it is crucial to know the decorator must be associated with
    a cache, either a global or default cache defined at the caching usage
    definition (e.g., `use Nebulex.Caching, cache: MyCache`) or a specific
    one configured in the decorator declaration.

    ## Key Generation

    Since caches are essentially key-value stores, each invocation of a cached
    function needs to be translated into a suitable key for cache access. The
    key can be generated using a default key generator (which is configurable)
    or through decorator options `:key` or `:keys`. Let us take a closer look
    at each approach:

    ### Default Key Generation

    Out of the box, the caching abstraction uses a simple key generator
    strategy given by `Nebulex.Caching.Decorators.generate_key/1`, which is
    based on the following algorithm:

      * If no arguments are given, return `0`.
      * If only one argument is given, return that param as key.
      * If more than one argument is given, return a key computed
        from the hash of all arguments (`:erlang.phash2(args)`).

    One could provide a different key generator via option
    `:default_key_generator`. Once it is configured, the generator will be used
    for each declaration that does not specify its own key generation strategy.
    See ["Custom Key Generation"](#module-custom-key-generation-declaration)
    section down below.

    The following example shows how to configure a custom default key generator:

        defmodule MyApp.Keygen do
          def generate(context) do
            # your key generation logic ...
          end
        end

        defmodule MyApp.Books do
          use Nebulex.Caching,
            cache: MyApp.Cache
            default_key_generator: &MyApp.Keygen.generate/1

          ...
        end

    The function given to `:default_key_generator` must follow the format
    `&Mod.fun/arity`.

    ### Custom Key Generation Declaration

    Since caching is generic, it is quite likely the target functions have
    various signatures that cannot be simply mapped on top of the cache
    structure. This tends to become obvious when the target function has
    multiple arguments out of which only some are suitable for caching
    (while the rest are used only by the function logic). For example:

        @decorate cacheable(cache: Cache)
        def find_book(isbn, check_warehouse?, include_used?) do
          # the logic for retrieving the book ...
        end

    At first glance, while the two `boolean` arguments influence the way the
    book is found, they are not used for the cache. Furthermore, what if only
    one of the two is important while the other is not?

    For such cases, the `cacheable` decorator allows the user to specify how
    the key is generated through the `:key` option (the same applies to all
    decorators). The developer can pick the arguments of interest (or their
    nested properties), perform operations or even invoke arbitrary functions
    without having to write any code or implement any interface. This is the
    recommended approach over the default generator since functions tend to be
    quite different in signatures as the code base grows; while the default
    strategy might work for some functions, it rarely does for all functions.

    The following are some examples of generating keys:

        @decorate cacheable(cache: Cache, key: isbn)
        def find_book(isbn, check_warehouse?, include_used?) do
          # the logic for retrieving the book ...
        end

        @decorate cacheable(cache: Cache, key: isbn.raw_number)
        def find_book(isbn, check_warehouse?, include_used?) do
          # the logic for retrieving the book ...
        end

    It is also possible to use an anonymous function to generate the key.
    The function receives the [decorator's context](`t:context/0`)
    as an argument. For example:

        @decorate cacheable(cache: Cache, key: &{&1.function_name, hd(&1.args)})
        def find_book(isbn, check_warehouse?, include_used?) do
          # the logic for retrieving the book ...
        end

    The key can be also the tuple `{:in, keys}` where `keys` is a list with the
    keys to cache, evict, or update. For example:

        @decorate cache_evict(cache: Cache, key: {:in, [isbn.id, isbn.raw_number]})
        def remove_book(isbn) do
          # the logic for removing the book ...
        end

    The tuple `{:in, [isbn.id, isbn.raw_number]}` instructs the `cache_evict`
    decorator to remove the keys `isbn.id` and `isbn.raw_number` from the
    cache.

    > #### `key: {:in, [...]}` {: .info}
    >
    > The `:key` option only admits the value `{:in, [...]}` for
    > [`cache_evict`](`cache_evict/3`) and [`cache_put`](`cache_put/3`)
    > decorators only. When you need to cache the same value under different
    > keys, you usually decorate multiple functions, like so:
    >
    > ```elixir
    > @decorate cacheable(key: id)
    > def get_user(id)
    >
    > @decorate cacheable(key: email)
    > def get_user_by_email(email)
    > ```
    >
    > See [`cacheable`](`cacheable/3`) decorator for more information.

    ### Custom options

    One can also provide options for the cache commands executed underneath,
    like so:

        @decorate cacheable(cache: Cache, key: isbn, opts: [ttl: :timer.hours(1)])
        def find_book(isbn, check_warehouse?, include_used?) do
          # the logic for retrieving the book ...
        end

    In that case, `opts: [ttl: :timer.hours(1)]` specifies the TTL for the
    cached value.

    See the ["Shared Options"](#module-shared-options) section
    for more information.

    ## Examples

    Supposing an app uses Ecto, and there is a context for accessing books
    `MyApp.Books`, we may decorate some functions as follows:

        # The cache config
        config :my_app, MyApp.Cache,
          gc_interval: 86_400_000, #=> 1 day
          max_size: 1_000_000 #=> Max 1M books

        # The Cache
        defmodule MyApp.Cache do
          use Nebulex.Cache,
            otp_app: :my_app,
            adapter: Nebulex.Adapters.Local
        end

        # Book schema
        defmodule MyApp.Books.Book do
          use Ecto.Schema

          schema "books" do
            field(:isbn, :string)
            field(:title, :string)
            field(:author, :string)
            # The rest of the fields omitted
          end

          def changeset(book, attrs) do
            book
            |> cast(attrs, [:isbn, :title, :author])
            |> validate_required([:isbn, :title, :author])
          end
        end

        # Books context
        defmodule MyApp.Books do
          use Nebulex.Caching, cache: MyApp.Cache

          alias MyApp.Repo
          alias MyApp.Books.Book

          @decorate cacheable(key: id)
          def get_book(id) do
            Repo.get(Book, id)
          end

          @decorate cacheable(key: isbn)
          def get_book_by_isbn(isbn) do
            Repo.get_by(Book, [isbn: isbn])
          end

          @decorate cache_put(
                      key: {:in, [book.id, book.isbn]},
                      match: &__MODULE__.match_fun/1
                    )
          def update_book(%Book{} = book, attrs) do
            book
            |> Book.changeset(attrs)
            |> Repo.update()
          end

          def match_fun({:ok, usr}), do: {true, usr}
          def match_fun({:error, _}), do: false

          @decorate cache_evict(key: {:in, [book.id, book.isbn]})
          def delete_book(%Book{} = book) do
            Repo.delete(book)
          end

          def create_book(attrs \\\\ %{}) do
            %Book{}
            |> Book.changeset(attrs)
            |> Repo.insert()
          end
        end

    ## Functions with multiple clauses

    Since [`decorator`](https://github.com/arjan/decorator#functions-with-multiple-clauses)
    library is used, it is important to be aware of its recommendations,
    caveats, limitations, and so on. For instance, for functions with multiple
    clauses the general advice is to create an empty function head, and call
    the decorator on that head, like so:

        @decorate cacheable(cache: Cache)
        def get_user(id \\\\ nil)

        def get_user(nil), do: nil

        def get_user(id) do
          # your logic ...
        end

    However, the previous example works because we are not using the function
    attributes for defining a custom key via the `:key` option. If we add
    `key: id` for instance, we will get errors and/or warnings, since the
    decorator is expecting the attribute `id` to be present, but it is not
    in the first function clause. In other words, when we take this approach,
    is like the decorator was applied to all function clauses separately.
    To overcome this issue, the arguments used in the decorator must be
    present in the function clauses, which could be achieved in different
    ways. A simple way would be to decorate a wrapper function with the
    arguments the decorator use and do the pattern-matching in a separate
    function.

        @decorate cacheable(cache: Cache, key: id)
        def get_user(id \\\\ nil) do
          do_get_user(id)
        end

        defp do_get_user(nil), do: nil

        defp do_get_user(id) do
          # your logic ...
        end

    Alternatively, you could decorate only the function clause needing the
    caching.

        def get_user(nil), do: nil

        @decorate cacheable(cache: Cache, key: id)
        def get_user(id) do
          # your logic ...
        end

    ## Further readings

      * [Cache Usage Patterns Guide](http://hexdocs.pm/nebulex/cache-usage-patterns.html).

    """

    defmodule Context do
      @moduledoc """
      Decorator context.
      """

      @typedoc """
      Decorator context type.

      The decorator context defines the following keys:

        * `:decorator` - Decorator's name.
        * `:module` - The invoked module.
        * `:function_name` - The invoked function name
        * `:arity` - The arity of the invoked function.
        * `:args` - The arguments that are given to the invoked function.

      ## Caveats about the `:args`

      The following are some caveats about the context's `:args`
      to keep in mind:

        * Only arguments explicitly assigned to a variable will be included.
        * Ignored or underscored arguments will be ignored.
        * Pattern-matching expressions without a variable assignment will be
          ignored. Therefore, if there is a pattern-matching and you want to
          include its value, it has to be explicitly assigned to a variable.

      For example, suppose you have a module with a decorated function:

          defmodule MyApp.SomeModule do
            use Nebulex.Caching

            alias MyApp.Cache

            @decorate cacheable(cache: Cache, key: &__MODULE__.key_generator/1)
            def get_something(x, _y, _, {_, _}, [_, _], %{a: a}, %{} = z) do
              # Function's logic
            end

            def key_generator(context) do
              # Key generation logic
            end
          end

      The generator will be invoked like so:

          key_generator(%Nebulex.Caching.Decorators.Context{
            decorator: :cacheable,
            module: MyApp.SomeModule,
            function_name: :get_something,
            arity: 7,
            args: [x, z]
          })

      As you may notice, only the arguments `x` and `z` are included in the
      context args when calling the `key_generator/1` function.
      """
      @type t() :: %__MODULE__{
              decorator: :cacheable | :cache_evict | :cache_put,
              module: module(),
              function_name: atom(),
              arity: non_neg_integer(),
              args: [any()]
            }

      # Context struct
      defstruct decorator: nil, module: nil, function_name: nil, arity: 0, args: []
    end

    # Decorator definitions
    use Decorator.Define,
      cacheable: 0,
      cacheable: 1,
      cache_evict: 0,
      cache_evict: 1,
      cache_put: 0,
      cache_put: 1

    import Nebulex.Utils, only: [get_option: 5]
    import Record

    ## Records

    # Dynamic cache spec
    defrecordp(:dynamic_cache, :"$nbx_dynamic_cache_spec", cache: nil, name: nil)

    # Key reference spec
    defrecordp(:keyref, :"$nbx_keyref_spec", cache: nil, key: nil, ttl: nil)

    ## Types

    @typedoc "Proxy type to the decorator context"
    @type context() :: Context.t()

    @typedoc "Type spec for a dynamic cache definition"
    @type dynamic_cache() :: record(:dynamic_cache, cache: module(), name: atom() | pid())

    @typedoc "The type for the cache value"
    @type cache_value() :: module() | dynamic_cache()

    @typedoc """
    The type for the `:cache` option value.

    When defining the `:cache` option on the decorated function,
    the value can be:

      * The defined cache module.
      * A dynamic cache spec created with the macro
        [`dynamic_cache/2`](`Nebulex.Caching.dynamic_cache/2`).
      * An anonymous function to call to resolve the cache value in runtime.
        The function receives the decorator context as an argument and must
        return either a cache module or a dynamic cache.

    """
    @type cache() :: cache_value() | (context() -> cache_value())

    @typedoc """
    The type for the `:key` option value.

    When defining the `:key` option on the decorated function,
    the value can be:

      * An anonymous function to call to generate the key in runtime.
        The function receives the decorator context as an argument
        and must return the key for caching.
      * The tuple `{:in, keys}`, where `keys` is a list with the keys to evict
        or update. This option is allowed for `cache_evict` and `cache_put`
        decorators only.
      * Any term.

    """
    @type key() :: (context() -> any()) | {:in, [any()]} | any()

    @typedoc "Type for on_error action"
    @type on_error() :: :nothing | :raise

    @typedoc "Type for the match function return"
    @type match_return() :: boolean() | {true, any()} | {true, any(), keyword()}

    @typedoc "Type for match function"
    @type match() ::
            (result :: any() -> match_return())
            | (result :: any(), context() -> match_return())

    @typedoc "Type for a key reference spec"
    @type keyref_spec() ::
            record(:keyref, cache: Nebulex.Cache.t(), key: any(), ttl: timeout() | nil)

    @typedoc "Type for a key reference"
    @type keyref() :: keyref_spec() | any()

    @typedoc """
    Type spec for the option `:references`.

    When defining the `:references` option on the decorated function,
    the value can be:

      * A reserved tuple that the type `t:keyref/0` defines. It must be created
        using the macro [`keyref/2`](`Nebulex.Caching.keyref/2`).
      * An anonymous function expects the result of the decorated function
        evaluation as an argument. Alternatively, the decorator context can be
        received as a second argument. It must return the referenced key, which
        could be `t:keyref/0` or any term.
      * `nil` means there are no key references (ignored).
      * Any term.

    See `cacheable/3` decorator for more information.
    """
    @type references() ::
            nil
            | keyref()
            | (result :: any() -> keyref() | any())
            | (result :: any(), context() -> keyref() | any())

    # Decorator context key
    @decorator_context_key {__MODULE__, :decorator_context}

    ## Decorator API

    @doc """
    As the name implies, the `cacheable` decorator indicates storing in cache
    the result of invoking a function.

    Each time a decorated function is invoked, the caching behavior will be
    applied, checking whether the function has already been invoked for the
    given arguments. A default algorithm uses the function arguments to compute
    the key. Still, a custom key can be provided through the `:key` option,
    or a custom key-generator implementation can replace the default one
    (See ["Key Generation"](#module-key-generation) section in the module
    documentation).

    If no value is found in the cache for the computed key, the target function
    will be invoked, and the returned value will be stored in the associated
    cache. Note that what is cached can be handled with the `:match` option.

    ## Options

    #{Nebulex.Caching.Options.cacheable_options_docs()}

    See the ["Shared options"](#module-shared-options) section in the module
    documentation for more options.

    ## Examples

        defmodule MyApp.Example do
          use Nebulex.Caching, cache: MyApp.Cache

          @ttl :timer.hours(1)

          @decorate cacheable(key: id, opts: [ttl: @ttl])
          def get_by_id(id) do
            # your logic (maybe the loader to retrieve the value from the SoR)
          end

          @decorate cacheable(key: email, references: & &1.id)
          def get_by_email(email) do
            # your logic (maybe the loader to retrieve the value from the SoR)
          end

          @decorate cacheable(key: clauses, match: &match_fun/1)
          def all(clauses) do
            # your logic (maybe the loader to retrieve the value from the SoR)
          end

          defp match_fun([]), do: false
          defp match_fun(_), do: true
        end

    > #### **Read-through** pattern {: .info}
    >
    > This decorator supports the **Read-through** pattern. The loader to
    > retrieve the value from the system of record (SoR) is your function's
    > logic, and the macro under the hood provides the rest.

    ## Referenced keys

    Referenced keys are handy when multiple keys keep the same value. For
    example, let's imagine we have a schema `User` with multiple unique fields,
    like `:id`, `:email`, and `:token`. We may have a module with functions
    retrieving the user account by any of those fields, like so:

        defmodule MyApp.UserAccounts do
          use Nebulex.Caching, cache: MyApp.Cache

          @decorate cacheable(key: id)
          def get_user_account(id) do
            # your logic ...
          end

          @decorate cacheable(key: email)
          def get_user_account_by_email(email) do
            # your logic ...
          end

          @decorate cacheable(key: token)
          def get_user_account_by_token(token) do
            # your logic ...
          end

          @decorate cache_evict(key: {:in, [user.id, user.email, user.token]})
          def update_user_account(user, attrs) do
            # your logic ...
          end
        end

    As you notice, all three functions will store the same user record under a
    different key. It could be more efficient in terms of memory space. Besides,
    when the user record is updated, we have to invalidate the previously cached
    entries, which means we have to specify in the `cache_evict` decorator all
    the different keys associated with the cached user account.

    Using the referenced keys, we can address it better and more simply.
    The module will look like this:

        defmodule MyApp.UserAccounts do
          use Nebulex.Caching, cache: MyApp.Cache

          @decorate cacheable(key: id)
          def get_user_account(id) do
            # your logic ...
          end

          @decorate cacheable(key: email, references: & &1.id)
          def get_user_account_by_email(email) do
            # your logic ...
          end

          @decorate cacheable(key: token, references: & &1.id)
          def get_user_account_by_token(token) do
            # your logic ...
          end

          @decorate cache_evict(key: user.id)
          def update_user_account(user, attrs) do
            # your logic ...
          end
        end

    With the option `:references`, we are indicating to the `cacheable`
    decorator to store the user id (`& &1.id` - assuming the function returns a
    user record) under the key `email` and the key `token`, and the user record
    itself under the user id, which is the referenced key. This time, instead of
    storing the same object three times, the decorator will cache it only once
    under the user ID, and the other entries will keep a reference to it. When
    the functions `get_user_account_by_email/1` or `get_user_account_by_token/1`
    are executed, the decorator will automatically handle it; under the hood,
    it will fetch the referenced key given by `email` or `token` first, and
    then get the user record under the referenced key.

    On the other hand, in the eviction function `update_user_account/1`, since
    the user record is stored only once under the user's ID, we could set the
    option `:key` to the user's ID, without specifying multiple keys like in the
    previous case. However, there is a caveat: _"the `cache_evict` decorator
    doesn't evict the references automatically"_. See the
    ["CAVEATS"](#cacheable/3-caveats) section below.

    ### The `match` function on references

    The `cacheable` decorator also evaluates the `:match` option's function on
    cache key references to ensure consistency and correctness. Let's give an
    example to understand what this is about.

    Using the previous _"user accounts"_ example, here is the first call to
    fetch a user by email:

        iex> user = MyApp.UserAccounts.get_user_account_by_email("me@test.com")
        #=> %MyApp.UserAccounts.User{id: 1, email: "me@test.com", ...}

    The user is now available in the cache for subsequent calls. Now, let's
    suppose we update the user's email by calling:

        iex> MyApp.UserAccounts.update_user_account(user, %{
        ...>   email: "updated@test.com", ...
        ...> })
        #=> %MyApp.UserAccounts.User{id: 1, email: "updated@test.com", ...}

    The `update_user_account` function should have removed the user schema
    associated with the `user.id` key (decorated with `cache_evict`) but not
    its references. Therefore, if we call `get_user_account_by_email` again:

        iex> user = MyApp.UserAccounts.get_user_account_by_email("me@test.com")
        #=> %MyApp.UserAccounts.User{id: 1, email: "updated@test.com", ...}

    And here, we have an inconsistency because we are requesting a user with
    the email `"me@test.com"` and we got a user with a different email
    `"updated@test.com"` (the updated one). How can we avoid this? The answer
    is to leverage the match function to ensure consistency and correctness.
    Let's provide a match function that helps us with it.

        @decorate cacheable(
                    key: email,
                    references: & &1.id,
                    match: &match(&1, email)
                  )
        def get_user_account_by_email(email) do
          # your logic ...
        end

        defp match(%{email: email}, email), do: true
        defp match(_, _), do: false

    With the solution above, the `cacheable` decorator only caches the user's
    value if the email matches the one in the arguments. Otherwise, nothing is
    cached, and the decorator evaluates the function's block. Previously, the
    decorator was caching the user regardless of the requested email value.
    With this fix, if we try the previous call:

        iex> MyApp.UserAccounts.get_user_account_by_email("me@test.com")
        #=> nil

    Since there is an email mismatch in the previous call, the decorator removes
    the mismatch reference from the cache (eliminating the inconsistency) and
    executes the function body, assuming it uses `MyApp.Repo.get_by/2`, `nil`
    is returned because there is no such user in the database.

    > #### `:match` option {: .info}
    >
    > The `:match` option can and should be used when using references to allow
    > the decorator to remove inconsistent cache key references automatically.

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
    `LocalCache` to store the cache key references. Then, with the option
    `references: &keyref(RedisCache, &1.id)` we are telling the `cacheable`
    decorator the referenced key given by `&1.id` is located in the cache
    `RedisCache`; underneath, the macro [`keyref/2`](`Nebulex.Caching.keyref/2`)
    builds the particular return type for the external cache reference.

    ### Caveats about references

    * When the `cache_evict` decorator annotates a key (or keys) to evict, the
      decorator removes only the entry associated with that key. Therefore, if
      the key has references, those are not automatically removed, which means
      dangling keys. However, there are multiple ways to address dangling keys
      (or references):

      * The first one (perhaps the simplest one) sets a TTL to the reference.
        For example:

        ```elixir
        @decorate cacheable(key: email, references: & &1.id, opts: [ttl: @ttl])
        def get_user_by_email(email) do
          # get the user from the database ...
        end
        ```

        You could also specify a different TTL for the referenced key:

        ```elixir
        @decorate cacheable(
                    key: email,
                    references: &keyref(&1.id, ttl: @another_ttl),
                    opts: [ttl: @ttl]
                  )
        def get_user_by_email(email) do
          # get the user from the database ...
        end
        ```

      * The second alternative, perhaps the recommended, is having a separate
        cache to keep the references (e.g., a cache using the local adapter).
        This way, you could provide a different eviction or GC configuration
        to run the GC more often and keep the references cache clean. See
        ["External referenced keys"](#cacheable/3-external-referenced-keys).

      * The third alternative uses the `key: {:in, keys}` to specify a key and
        its references. For example, if you have:

        ```elixir
        @decorate cacheable(key: email, references: & &1.id)
        def get_user_by_email(email) do
          # get the user from the database ...
        end
        ```

        The eviction may look like this:

        ```elixir
        @decorate cache_evict(key: {:in, [user.id, user.email]})
        def delete_user(user) do
          # delete the user from the database ...
        end
        ```

        This one is perhaps the least ideal option because it is cumbersome;
        you have to know and specify the key and all its references, and at the
        same time, you will need to have access to the key and references in the
        arguments, which sometimes is not possible because you may receive only
        the ID, but not the email.

    """
    @doc group: "Decorator API"
    def cacheable(attrs \\ [], block, context) do
      caching_action(:cacheable, attrs, block, context)
    end

    @doc """
    Decorator indicating that a function triggers a
    [cache put](`c:Nebulex.Cache.put/3`) operation.

    In contrast to the [`cacheable`](`cacheable/3`) decorator, this decorator
    does not cause the decorated function to be skipped. Instead, it always
    causes the function to be invoked and its result to be stored in the
    associated cache if the condition given by the `:match` option matches
    accordingly.

    ## Options

    See the ["Shared options"](#module-shared-options) section in the module
    documentation for more options.

    ## Examples

        defmodule MyApp.Example do
          use Nebulex.Caching, cache: MyApp.Cache

          @ttl :timer.hours(1)

          @decorate cache_put(key: id, opts: [ttl: @ttl])
          def update!(id, attrs \\\\ %{}) do
            # your logic (maybe write data to the SoR)
          end

          @decorate cache_put(
                      key: id,
                      match: &__MODULE__.match_fun/1,
                      opts: [ttl: @ttl]
                    )
          def update(id, attrs \\\\ %{}) do
            # your logic (maybe write data to the SoR)
          end

          @decorate cache_put(
                      key: {:in, [object.name, object.id]},
                      match: &__MODULE__.match_fun/1,
                      opts: [ttl: @ttl]
                    )
          def update_object(object) do
            # your logic (maybe write data to the SoR)
          end

          def match_fun({:ok, updated}), do: {true, updated}
          def match_fun({:error, _}), do: false
        end

    > #### **Write-through** pattern {: .info}
    >
    > This decorator supports the **Write-through** pattern. Your function
    > provides the logic to write data to the system of record (SoR), and the
    > decorator under the hood provides the rest.
    """
    @doc group: "Decorator API"
    def cache_put(attrs \\ [], block, context) do
      caching_action(:cache_put, attrs, block, context)
    end

    @doc """
    Decorator indicating that a function triggers a cache evict operation
    (`delete` or `delete_all`).

    ## Options

    #{Nebulex.Caching.Options.cache_evict_options_docs()}

    See the ["Shared options"](#module-shared-options) section in the module
    documentation for more options.

    ## Examples

        defmodule MyApp.Example do
          use Nebulex.Caching, cache: MyApp.Cache

          @decorate cache_evict(key: id)
          def delete(id) do
            # your logic (maybe write/delete data to the SoR)
          end

          @decorate cache_evict(key: {:in, [object.name, object.id]})
          def delete_object(object) do
            # your logic (maybe write/delete data to the SoR)
          end

          @decorate cache_evict(all_entries: true)
          def delete_all do
            # your logic (maybe write/delete data to the SoR)
          end
        end

    > #### **Write-through** pattern {: .info}
    >
    > This decorator supports the **Write-through** pattern. Your function
    > provides the logic to write data to the system of record (SoR), and the
    > decorator under the hood provides the rest. But in contrast with the
    > `update` decorator, the data is deleted from the cache instead of updated.
    """
    @doc group: "Decorator API"
    def cache_evict(attrs \\ [], block, context) do
      caching_action(:cache_evict, attrs, block, context)
    end

    ## Decorator helpers

    @doc """
    A helper function to create a reserved tuple for a dynamic cache.

    The first argument, `cache`, specifies the defined cache module,
    and the second argument, `name`, is the actual name of the cache.

    When creating a dynamic cache tuple form, use the macro
    `Nebulex.Caching.dynamic_cache/2` instead.

    ## Example

        defmodule MyApp.Books do
          use Nebulex.Caching

          @decorate cacheable(cache: dynamic_cache(MyApp.Cache, :books))
          def find_book(isbn) do
            # your logic ...
          end
        end

    """
    @doc group: "Decorator Helpers"
    @spec dynamic_cache_spec(module(), atom() | pid()) :: dynamic_cache()
    def dynamic_cache_spec(cache, name) do
      dynamic_cache(cache: cache, name: name)
    end

    @doc """
    A helper function to create a reserved tuple for a reference.

    ## Arguments

      * `cache` - The cache where the referenced key is stored. If it is `nil`,
        the referenced key is looked up in the same cache provided via the
        `:cache` option.
      * `key` - The referenced key.
      * `ttl` - The TTL for the referenced key. If configured, it overrides the
        TTL given in the decorator's option `:opts`.

    When creating a reference tuple form, use the macro
    `Nebulex.Caching.keyref/2` instead.

    See the ["Referenced keys"](#cacheable/3-referenced-keys) section in the
    `cacheable` decorator for more information.
    """
    @doc group: "Decorator Helpers"
    @spec keyref_spec(cache() | nil, any(), timeout() | nil) :: keyref_spec()
    def keyref_spec(cache, key, ttl) do
      keyref(cache: cache, key: key, ttl: ttl)
    end

    @doc """
    Default match function.
    """
    @doc group: "Decorator Helpers"
    @spec default_match(any()) :: boolean()
    def default_match(result)

    def default_match({:error, _}), do: false
    def default_match(:error), do: false
    def default_match(_other), do: true

    @doc """
    Default key generation function.
    """
    @doc group: "Decorator Helpers"
    @spec generate_key(context()) :: any()
    def generate_key(context)

    def generate_key(%{args: []}), do: 0
    def generate_key(%{args: [arg]}), do: arg
    def generate_key(%{args: args}), do: :erlang.phash2(args)

    ## Private functions for decorators

    defp caching_action(decorator, attrs, block, context) do
      # Get options defined via the __using__ macro
      use_opts = Module.get_attribute(context.module, :__use_caching_opts__, [])

      # Build decorator context
      context = decorator_context(decorator, context)

      # Resolve the cache to use
      cache_var = get_cache(attrs, use_opts)

      # Build key generation block
      keygen_block = keygen_block(decorator, attrs, use_opts)

      # Get the options to be given to the cache commands
      opts_var = Keyword.get_lazy(attrs, :opts, fn -> Keyword.fetch!(use_opts, :opts) end)

      # Build the action block
      action_block =
        action_block(
          decorator,
          block,
          attrs,
          keygen_block,
          on_error_opt(attrs, fn -> Keyword.fetch!(use_opts, :on_error) end),
          Keyword.get_lazy(attrs, :match, fn ->
            Keyword.get(use_opts, :match, &__MODULE__.default_match/1)
          end)
        )

      quote do
        # Set common vars
        cache = unquote(cache_var)
        opts = unquote(opts_var)

        # Set the decorator context
        _ = Process.put(unquote(@decorator_context_key), unquote(context))

        try do
          # Execute the decorated function's code block
          unquote(action_block)
        after
          # Reset decorator context
          Process.delete(unquote(@decorator_context_key))
        end
      end
    end

    defp get_cache(attrs, use_opts) do
      with :error <- Keyword.fetch(attrs, :cache),
           :error <- Keyword.fetch(use_opts, :cache) do
        opts =
          use_opts
          |> Keyword.merge(attrs)
          |> Keyword.keys()

        raise ArgumentError, "required :cache option not found, received options: #{inspect(opts)}"
      else
        {:ok, cache} -> cache
      end
    end

    defp decorator_context(decorator, context) do
      # Sanitize context args
      args =
        context.args
        |> Enum.reduce([], &sanitize_arg/2)
        |> Enum.reverse()

      quote do
        var!(ctx_args, __MODULE__) = unquote(args)

        %Context{
          decorator: unquote(decorator),
          module: unquote(context.module),
          function_name: unquote(context.name),
          arity: unquote(context.arity),
          args: var!(ctx_args, __MODULE__)
        }
      end
    end

    defp sanitize_arg({:\\, _, [ast, _]}, acc) do
      sanitize_arg(ast, acc)
    end

    defp sanitize_arg({:=, _, [_, ast]}, acc) do
      sanitize_arg(ast, acc)
    end

    defp sanitize_arg({var, _meta, context} = ast, acc) when is_atom(var) and is_atom(context) do
      if match?("_" <> _, "#{var}") or Macro.special_form?(var, 0) do
        acc
      else
        [ast | acc]
      end
    end

    defp sanitize_arg(_ast, acc) do
      acc
    end

    defp keygen_block(decorator, attrs, use_opts) do
      case {Keyword.fetch(attrs, :key), decorator} do
        {{:ok, {:in, _keys}}, :cacheable} ->
          raise ArgumentError,
                "invalid value for :key option: {:in, [...]} is not " <>
                  "supported for cacheable decorator"

        {{:ok, {:in, keys} = key}, _} when is_list(keys) and length(keys) > 0 ->
          quote(do: unquote(key))

        {{:ok, {:in, keys}}, _} ->
          raise ArgumentError,
                "invalid value for :key option: {:in, keys} expects keys " <>
                  "to be a non empty list, got: #{inspect(keys)}"

        {{:ok, key}, _} ->
          quote(do: unquote(key))

        {:error, _} ->
          generator = Keyword.get(use_opts, :default_key_generator, &__MODULE__.generate_key/1)

          quote(do: unquote(generator))
      end
    end

    defp action_block(:cacheable, block, attrs, keygen, on_error, match) do
      references = Keyword.get(attrs, :references)

      quote do
        unquote(__MODULE__).eval_cacheable(
          cache,
          unquote(keygen),
          unquote(references),
          opts,
          unquote(match),
          unquote(on_error),
          fn -> unquote(block) end
        )
      end
    end

    defp action_block(:cache_put, block, _attrs, keygen, on_error, match) do
      quote do
        result = unquote(block)

        unquote(__MODULE__).eval_cache_put(
          cache,
          unquote(keygen),
          result,
          opts,
          unquote(on_error),
          unquote(match)
        )

        result
      end
    end

    defp action_block(:cache_evict, block, attrs, keygen, on_error, _match) do
      before_invocation? = get_boolean(attrs, :before_invocation)
      all_entries? = get_boolean(attrs, :all_entries)

      quote do
        unquote(__MODULE__).eval_cache_evict(
          cache,
          unquote(keygen),
          unquote(before_invocation?),
          unquote(all_entries?),
          unquote(on_error),
          fn -> unquote(block) end
        )
      end
    end

    defp on_error_opt(attrs, default) do
      get_option(attrs, :on_error, ":raise or :nothing", &(&1 in [:raise, :nothing]), default)
    end

    defp get_boolean(attrs, key) do
      get_option(attrs, key, "a boolean", &Kernel.is_boolean/1, false)
    end

    ## Internal API

    @doc """
    Convenience function for wrapping and/or encapsulating
    the **cacheable** decorator logic.

    **NOTE:** Internal purposes only.
    """
    @doc group: "Internal API"
    @spec eval_cacheable(any(), any(), references(), keyword(), match(), on_error(), fun()) :: any()
    def eval_cacheable(cache, key, references, opts, match, on_error, block_fun) do
      context = Process.get(@decorator_context_key)
      cache = eval_cache(cache, context)
      key = eval_key(cache, key, context)

      do_eval_cacheable(cache, key, references, opts, match, on_error, block_fun)
    end

    defp do_eval_cacheable(cache, key, nil, opts, match, on_error, block_fun) do
      do_apply(cache, :fetch, [key, opts])
      |> handle_cacheable(
        on_error,
        block_fun,
        &__MODULE__.eval_cache_put(cache, key, &1, opts, on_error, match)
      )
    end

    defp do_eval_cacheable(
           ref_cache,
           ref_key,
           {:"$nbx_parent_keyref", keyref(cache: cache, key: key)},
           opts,
           match,
           on_error,
           block_fun
         ) do
      do_apply(ref_cache, :fetch, [ref_key, opts])
      |> handle_cacheable(
        on_error,
        block_fun,
        fn value ->
          with false <- do_eval_cache_put(ref_cache, ref_key, value, opts, on_error, match) do
            # The match returned `false`, remove the reference's parent key
            _ = do_apply(cache, :delete, [key])

            false
          end
        end,
        fn value ->
          case eval_function(match, value) do
            false ->
              # Remove the reference's parent key
              _ = do_apply(cache, :delete, [key])

              block_fun.()

            _else ->
              value
          end
        end
      )
    end

    defp do_eval_cacheable(cache, key, references, opts, match, on_error, block_fun) do
      case do_apply(cache, :fetch, [key, opts]) do
        {:ok, keyref(cache: ref_cache, key: ref_key)} ->
          eval_cacheable(
            ref_cache || cache,
            ref_key,
            {:"$nbx_parent_keyref", keyref(cache: cache, key: key)},
            opts,
            match,
            on_error,
            block_fun
          )

        other ->
          handle_cacheable(other, on_error, block_fun, fn result ->
            reference = eval_cacheable_ref(references, result)

            with true <- eval_cache_put(cache, reference, result, opts, on_error, match) do
              :ok = cache_put(cache, key, reference, opts)
            end
          end)
      end
    end

    defp eval_cacheable_ref(references, result) do
      case eval_function(references, result) do
        keyref() = ref -> ref
        referenced_key -> keyref(key: referenced_key)
      end
    end

    # Handle fetch result
    defp handle_cacheable(result, on_error, block_fn, key_err_fn, on_ok \\ nil)

    defp handle_cacheable({:ok, value}, _on_error, _block_fn, _key_err_fn, nil) do
      value
    end

    defp handle_cacheable({:ok, value}, _on_error, _block_fn, _key_err_fn, on_ok) do
      on_ok.(value)
    end

    defp handle_cacheable({:error, %Nebulex.KeyError{}}, _on_error, block_fn, key_err_fn, _on_ok) do
      block_fn.()
      |> tap(key_err_fn)
    end

    defp handle_cacheable({:error, _}, :nothing, block_fn, _key_err_fn, _on_ok) do
      block_fn.()
    end

    defp handle_cacheable({:error, reason}, :raise, _block_fn, _key_err_fn, _on_ok) do
      raise reason
    end

    @doc """
    Convenience function for wrapping and/or encapsulating
    the **cache_evict** decorator logic.

    **NOTE:** Internal purposes only.
    """
    @doc group: "Internal API"
    @spec eval_cache_evict(any(), any(), boolean(), boolean(), on_error(), fun()) :: any()
    def eval_cache_evict(cache, key, before_invocation?, all_entries?, on_error, block_fun) do
      context = Process.get(@decorator_context_key)
      cache = eval_cache(cache, context)
      key = eval_key(cache, key, context)

      do_eval_cache_evict(cache, key, before_invocation?, all_entries?, on_error, block_fun)
    end

    defp do_eval_cache_evict(cache, key, true, all_entries?, on_error, block_fun) do
      _ = do_evict(all_entries?, cache, key, on_error)

      block_fun.()
    end

    defp do_eval_cache_evict(cache, key, false, all_entries?, on_error, block_fun) do
      result = block_fun.()

      _ = do_evict(all_entries?, cache, key, on_error)

      result
    end

    defp do_evict(true, cache, _key, on_error) do
      run_cmd(cache, :delete_all, [], on_error)
    end

    defp do_evict(false, cache, {:in, keys}, on_error) do
      run_cmd(cache, :delete_all, [[in: keys]], on_error)
    end

    defp do_evict(false, cache, key, on_error) do
      run_cmd(cache, :delete, [key, []], on_error)
    end

    @doc """
    Convenience function for wrapping and/or encapsulating
    the **cache_put** decorator logic.

    **NOTE:** Internal purposes only.
    """
    @doc group: "Internal API"
    @spec eval_cache_put(any(), any(), any(), keyword(), on_error(), match()) :: any()
    def eval_cache_put(cache, key, value, opts, on_error, match) do
      context = Process.get(@decorator_context_key)
      cache = eval_cache(cache, context)
      key = eval_key(cache, key, context)

      do_eval_cache_put(cache, key, value, opts, on_error, match)
    end

    defp do_eval_cache_put(
           cache,
           keyref(cache: ref_cache, key: ref_key, ttl: ttl),
           value,
           opts,
           on_error,
           match
         ) do
      opts = if ttl, do: Keyword.put(opts, :ttl, ttl), else: opts

      eval_cache_put(ref_cache || cache, ref_key, value, opts, on_error, match)
    end

    defp do_eval_cache_put(cache, key, value, opts, on_error, match) do
      case eval_function(match, value) do
        {true, cache_value} ->
          _ = run_cmd(__MODULE__, :cache_put, [cache, key, cache_value, opts], on_error)

          true

        {true, cache_value, new_opts} ->
          _ =
            run_cmd(
              __MODULE__,
              :cache_put,
              [cache, key, cache_value, Keyword.merge(opts, new_opts)],
              on_error
            )

          true

        true ->
          _ = run_cmd(__MODULE__, :cache_put, [cache, key, value, opts], on_error)

          true

        false ->
          false
      end
    end

    @doc """
    Convenience function for the `cache_put` decorator.

    **NOTE:** Internal purposes only.
    """
    @doc group: "Internal API"
    @spec cache_put(cache_value(), {:in, [any()]} | any(), any(), keyword()) :: :ok
    def cache_put(cache, key, value, opts)

    def cache_put(cache, {:in, keys}, value, opts) do
      do_apply(cache, :put_all, [Enum.map(keys, &{&1, value}), opts])
    end

    def cache_put(cache, key, value, opts) do
      do_apply(cache, :put, [key, value, opts])
    end

    @doc """
    Convenience function for evaluating the `cache` argument.

    **NOTE:** Internal purposes only.
    """
    @doc group: "Internal API"
    @spec eval_cache(any(), context()) :: cache_value()
    def eval_cache(cache, ctx)

    def eval_cache(cache, _ctx) when is_atom(cache), do: cache
    def eval_cache(dynamic_cache() = cache, _ctx), do: cache
    def eval_cache(cache, ctx) when is_function(cache, 1), do: cache.(ctx)
    def eval_cache(cache, _ctx), do: raise_invalid_cache(cache)

    @doc """
    Convenience function for evaluating the `key` argument.

    **NOTE:** Internal purposes only.
    """
    @doc group: "Internal API"
    @spec eval_key(any(), any(), context()) :: any()
    def eval_key(cache, key, ctx)

    def eval_key(_cache, key, ctx) when is_function(key, 1) do
      key.(ctx)
    end

    def eval_key(_cache, key, _ctx) do
      key
    end

    @doc """
    Convenience function for running a cache command.

    **NOTE:** Internal purposes only.
    """
    @doc group: "Internal API"
    @spec run_cmd(module(), atom(), [any()], on_error()) :: any()
    def run_cmd(cache, fun, args, on_error)

    def run_cmd(cache, fun, args, :nothing) do
      do_apply(cache, fun, args)
    end

    def run_cmd(cache, fun, args, :raise) do
      with {:error, reason} <- do_apply(cache, fun, args) do
        raise reason
      end
    end

    ## Private functions

    defp eval_function(fun, arg) when is_function(fun, 1) do
      fun.(arg)
    end

    defp eval_function(fun, arg) when is_function(fun, 2) do
      fun.(arg, Process.get(@decorator_context_key))
    end

    defp eval_function(other, _arg) do
      other
    end

    defp do_apply(dynamic_cache(cache: cache, name: name), fun, args) do
      apply(cache, fun, [name | args])
    end

    defp do_apply(mod, fun, args) do
      apply(mod, fun, args)
    end

    @compile {:inline, raise_invalid_cache: 1}
    @spec raise_invalid_cache(any()) :: no_return()
    defp raise_invalid_cache(cache) do
      raise ArgumentError,
            "invalid value for :cache option: expected " <>
              "t:Nebulex.Caching.Decorators.cache/0, got: #{inspect(cache)}"
    end
  end
end
