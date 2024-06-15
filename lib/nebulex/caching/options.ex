defmodule Nebulex.Caching.Options do
  @moduledoc false

  # Options given to the __using__ macro
  caching_opts = [
    cache: [
      type: :atom,
      required: false,
      doc: """
      Defines the cache all decorated functions in the module will use
      by default. It can be overridden on each decorated function since
      the `:cache` option is also available at the decorator level
      (see ["Shared Options"](#module-shared-options)).

      See ["Default cache"](#module-default-cache) section
      for more information.
      """
    ],
    on_error: [
      type: {:in, [:nothing, :raise]},
      type_doc: "`t:on_error/0`",
      required: false,
      default: :nothing,
      doc: """
      Same as `:on_error` in the ["Shared Options"](#module-shared-options),
      but applies to all decorated functions in a module as default.
      """
    ],
    default_key_generator: [
      type:
        {:custom, Nebulex.Cache.Options, :__validate_behaviour__,
         [Nebulex.Caching.KeyGenerator, Nebulex.Caching]},
      type_doc: "`t:module/0`",
      required: false,
      default: Nebulex.Caching.SimpleKeyGenerator,
      doc: """
      The default key-generator module the caching decorators will use.
      """
    ]
  ]

  # Shared decorator options
  shared_opts = [
    cache: [
      type: :any,
      type_doc: "`t:cache/0`",
      required: true,
      doc: """
      The cache to use (see `t:cache/0` for possible values). If configured,
      it overrides the [default or global cache](#module-default-cache).
      The decorator uses the given `cache`. If configured, it overrides the
      [default or global cache](#module-default-cache). See `t:cache/0` for
      possible values.

      Raises an exception if the `:cache` option is not provided in the
      decorator declaration and is not configured when defining the
      caching usage via `use Nebulex.Caching` either.

      See ["Cache configuration"](#module-cache-configuration) section
      for more information.
      """
    ],
    key: [
      type: :any,
      type_doc: "`t:key/0`",
      required: false,
      doc: """
      The cache access key the decorator will use when running the decorated
      function. The default key generator generates a default key when the
      option is unavailable.

      See ["Key Generation"](#module-key-generation) section
      for more information.
      """
    ],
    opts: [
      type: :keyword_list,
      required: false,
      default: [],
      doc: """
      The options used by the decorator when invoking cache commands.
      """
    ],
    match: [
      type: {:or, [fun: 1, fun: 2]},
      type_doc: "`t:match/0`",
      required: false,
      doc: """
      Anonymous function to decide whether or not the result (provided as a
      first argument) of evaluating the decorated function is cached.
      Optionally, the match function can receive the decorator context as a
      second argument. The match function can return:

        * `true` - The value returned by the decorated function invocation is
          cached. (the default).
        * `{true, value}` - `value` is cached. It is helpful to customize what
          exactly must be cached.
        * `{true, value, opts}` - The `value` is cached with the provided
          options `opts`. It is helpful to customize what must be cached and the
          runtime options for storing it. (e.g., `{true, value, [ttl: @ttl]}`).
        * `false` - Cache nothing.

      The default match function looks like this:

      ```elixir
      fn
        {:error, _} -> false
        :error -> false
        _ -> true
      end
      ```

      By default, if the evaluation of the decorated function returns any of the
      following terms/values `:error` or `{:error, term}`, the default match
      function returns `false` (cache nothing). Otherwise, `true` is returned
      (the value is cached). Remember that the default match function may store
      a `nil` value if the decorated function returns it. If you don't want to
      cache `nil` values or, in general, desire a different behavior, you should
      provide another match function to meet your requirements.
      """
    ],
    on_error: [
      type: {:in, [:nothing, :raise]},
      type_doc: "`t:on_error/0`",
      required: false,
      default: :nothing,
      doc: """
      The decorators perform cache commands under the hood. With the option
      `:on_error`, we can tell the decorator what to do in case of an error
      or exception. The option supports the following values:

        * `:nothing` - ignores the error.
        * `:raise` - raises if there is an error.

      If configured, it overrides the global or default value
      (e.g., `use Nebulex.Caching, on_error: ...`).
      """
    ]
  ]

  # cacheable options
  cacheable_opts = [
    references: [
      type: {:or, [{:fun, 1}, {:fun, 2}, nil, :any]},
      type_doc: "`t:references/0`",
      required: false,
      default: nil,
      doc: """
      Indicates the key given by the option `:key` references another key
      provided by the option `:references`. In other words, when present,
      this option tells the `cacheable` decorator to store the decorated
      function's block result under the referenced key given by the option
      `:references` and the referenced key under the key provided by the
      option `:key`.

      See the ["Referenced keys"](#cacheable/3-referenced-keys) section below
      for more information.
      """
    ]
  ]

  # cache_put options
  cache_put_opts = [
    keys: [
      type: {:list, :any},
      required: false,
      doc: """
      The list of keys the decorator will use to cache the decorated function's
      result; each key holds a copy of the result. When present, it overrides
      the `:key` option.
      """
    ]
  ]

  # cache_evict options
  cache_evict_opts = [
    keys: [
      type: {:list, :any},
      required: false,
      doc: """
      The list of keys the decorator will remove after or before the decorated
      function's execution. When present, it overrides the `:key` option.
      """
    ],
    all_entries: [
      type: :boolean,
      required: false,
      default: false,
      doc: """
      Defines whether or not the decorator must remove all the entries inside
      the cache.
      """
    ],
    before_invocation: [
      type: :boolean,
      required: false,
      default: false,
      doc: """
      Defines whether or not the decorator should run before invoking the
      decorated function.
      """
    ]
  ]

  # caching options schema
  @caching_opts_schema NimbleOptions.new!(caching_opts)

  # shared options schema
  @shared_opts_schema NimbleOptions.new!(shared_opts)

  # cacheable options schema
  @cacheable_opts_schema NimbleOptions.new!(cacheable_opts)

  # cache_put options schema
  @cache_put_opts_schema NimbleOptions.new!(cache_put_opts)

  # cache_evict options schema
  @cache_evict_opts_schema NimbleOptions.new!(cache_evict_opts)

  ## Docs API

  # coveralls-ignore-start

  @spec caching_options_docs() :: binary()
  def caching_options_docs do
    NimbleOptions.docs(@caching_opts_schema)
  end

  @spec shared_options_docs() :: binary()
  def shared_options_docs do
    NimbleOptions.docs(@shared_opts_schema)
  end

  @spec cacheable_options_docs() :: binary()
  def cacheable_options_docs do
    NimbleOptions.docs(@cacheable_opts_schema)
  end

  @spec cache_put_options_docs() :: binary()
  def cache_put_options_docs do
    NimbleOptions.docs(@cache_put_opts_schema)
  end

  @spec cache_evict_options_docs() :: binary()
  def cache_evict_options_docs do
    NimbleOptions.docs(@cache_evict_opts_schema)
  end

  # coveralls-ignore-stop

  ## Validation API

  @spec validate_caching_opts!(keyword()) :: keyword()
  def validate_caching_opts!(opts) do
    NimbleOptions.validate!(opts, @caching_opts_schema)
  end
end
