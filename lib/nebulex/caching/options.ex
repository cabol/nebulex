defmodule Nebulex.Caching.Options do
  @moduledoc false

  # Options given to the __using__ macro
  use_caching_opts = [
    default_key_generator: [
      type: {:custom, __MODULE__, :__validate_keygen__, []},
      type_doc: "`t:Nebulex.Caching.Decorators.key/0`",
      required: false,
      doc: """
      Defines the default key generation function for all decorated functions
      in the module. It can be overridden at the decorator level via `:key`
      option.

      The function must be provided in the format `&Mod.fun/arity`.

      The default value is `&Nebulex.Caching.Decorators.generate_key/1`.
      """
    ],
    cache: [
      type: :atom,
      required: false,
      doc: """
      Defines the cache for all decorated functions in the module.
      It can be overridden at the decorator level.
      """
    ],
    on_error: [
      type: {:in, [:nothing, :raise]},
      type_doc: "`t:Nebulex.Caching.Decorators.on_error/0`",
      required: false,
      default: :nothing,
      doc: """
      Whether to raise an exception or do nothing when there is a cache error.
      It applies to all decorated functions in the module. It can be overridden
      at the decorator level.
      """
    ],
    match: [
      type: {:custom, __MODULE__, :__validate_match__, []},
      type_doc: "`t:Nebulex.Caching.Decorators.match/0`",
      required: false,
      doc: """
      The match function for all decorated functions in the module. It can be
      overridden at the decorator level.

      The function must be provided in the format `&Mod.fun/arity`.

      The default value is `&Nebulex.Caching.Decorators.default_match/1`.
      """
    ],
    opts: [
      type: :keyword_list,
      required: false,
      default: [],
      doc: """
      The options to use globally for all decorated functions in the module when
      invoking cache commands.
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

      The `:key` option admits the following values:

        * An anonymous function to call to generate the key in runtime.
          The function receives the decorator context as an argument
          and must return the key for caching.
        * The tuple `{:in, keys}`, where `keys` is a list with the keys to
          evict or update. This option is allowed for `cache_evict` and
          `cache_put` decorators only.
        * Any term.

      See ["Key Generation"](#module-key-generation) section
      for more information.
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
      def default_match({:error, _}), do: false
      def default_match(:error), do: false
      def default_match(_other), do: true
      ```

      By default, if the evaluation of the decorated function returns any of the
      following terms/values `:error` or `{:error, term}`, the default match
      function returns `false` (cache nothing). Otherwise, `true` is returned
      (the value is cached). Remember that the default match function may store
      a `nil` value if the decorated function returns it. If you don't want to
      cache `nil` values or, in general, desire a different behavior, you should
      provide another match function to meet your requirements.

      If configured, it overrides the global value (if any) defined when using
      `use Nebulex.Caching, match: &MyApp.match/1`.

      The default value is `&Nebulex.Caching.Decorators.default_match/1`.
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

      If configured, it overrides the global value (if any) defined when using
      `use Nebulex.Caching, on_error: ...`.
      """
    ],
    opts: [
      type: :keyword_list,
      required: false,
      default: [],
      doc: """
      The options used by the decorator when invoking cache commands.
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

  # cache_evict options
  cache_evict_opts = [
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

  # `use` options schema
  @use_opts_schema NimbleOptions.new!(use_caching_opts)

  # shared options schema
  @shared_opts_schema NimbleOptions.new!(shared_opts)

  # `cacheable` options schema
  @cacheable_opts_schema NimbleOptions.new!(cacheable_opts)

  # `cache_evict` options schema
  @cache_evict_opts_schema NimbleOptions.new!(cache_evict_opts)

  ## Docs API

  # coveralls-ignore-start

  @spec use_options_docs() :: binary()
  def use_options_docs do
    NimbleOptions.docs(@use_opts_schema)
  end

  @spec shared_options_docs() :: binary()
  def shared_options_docs do
    NimbleOptions.docs(@shared_opts_schema)
  end

  @spec cacheable_options_docs() :: binary()
  def cacheable_options_docs do
    NimbleOptions.docs(@cacheable_opts_schema)
  end

  @spec cache_evict_options_docs() :: binary()
  def cache_evict_options_docs do
    NimbleOptions.docs(@cache_evict_opts_schema)
  end

  # coveralls-ignore-stop

  ## Validation API

  @spec validate_use_opts!(keyword()) :: keyword()
  def validate_use_opts!(opts) do
    NimbleOptions.validate!(opts, @use_opts_schema)
  end

  ## Helpers

  # sobelow_skip ["RCE.CodeModule"]
  @doc false
  def __validate_keygen__(keygen) do
    {value, _binding} = Code.eval_quoted(keygen)

    if is_function(value, 1) do
      {:ok, value}
    else
      {:error, "expected function of arity 1, got: #{inspect(value)}"}
    end
  end

  # sobelow_skip ["RCE.CodeModule"]
  @doc false
  def __validate_match__(match) do
    {value, _binding} = Code.eval_quoted(match)

    if is_function(value, 1) or is_function(value, 2) do
      {:ok, value}
    else
      {:error, "expected function of arity 1 or 2, got: #{inspect(value)}"}
    end
  end
end
