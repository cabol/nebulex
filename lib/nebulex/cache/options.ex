defmodule Nebulex.Cache.Options do
  @moduledoc false

  import Nebulex.Utils, only: [is_timeout: 1, module_behaviours: 1]

  # Compilation time option definitions
  compile_opts = [
    otp_app: [
      type: :atom,
      required: true,
      doc: """
      The OTP application the cache configuration is under.
      """
    ],
    adapter: [
      type: {:custom, __MODULE__, :__validate_behaviour__, [Nebulex.Adapter, Nebulex.Cache]},
      type_doc: "`t:module/0`",
      required: true,
      doc: """
      The cache adapter module.
      """
    ],
    default_dynamic_cache: [
      type: :atom,
      required: false,
      doc: """
      Default dynamic cache for executing cache commands. Set to the
      defined cache module by default. For example, when you call
      `MyApp.Cache.start_link/1`, it will start a cache with the name
      `MyApp.Cache`.

      See the ["Dynamic caches"](#module-dynamic-caches) section
      for more information.
      """
    ],
    adapter_opts: [
      type: :keyword_list,
      required: false,
      default: [],
      doc: """
      Specifies a list of options passed to the adapter in compilation time.
      """
    ]
  ]

  # Start option definitions (runtime)
  start_link_opts = [
    name: [
      type: {:custom, __MODULE__, :__validate_name__, []},
      type_doc: "`t:atom/0` | `{:via, reg_mod :: module(), via_name :: any()}`",
      required: false,
      doc: """
      The name of the supervisor process the cache is started under.
      Set to the defined cache module by default. For example, when
      you call `MyApp.Cache.start_link/1`, a cache named `MyApp.Cache`
      is started.
      """
    ],
    telemetry: [
      type: :boolean,
      required: false,
      default: true,
      doc: """
      A flag to determine whether to emit the Telemetry cache command events.
      """
    ],
    telemetry_prefix: [
      type: {:list, :atom},
      required: false,
      default: [:nebulex, :cache],
      doc: """
      Nebulex emits cache events using the [Telemetry](`:telemetry`) library.
      See the ["Telemetry events"](#module-telemetry-events) section to see
      which events are emitted by Nebulex out-of-box.

      Note that if you have multiple caches (or dynamic caches), since the
      `:adapter_meta` property is available within the event metadata, you can
      use the `:cache` or `:name` properties (or both) to distinguish between
      caches. Alternatively, you can use different `:telemetry_prefix` values.
      """
    ],
    bypass_mode: [
      type: :boolean,
      required: false,
      default: false,
      doc: """
      If `true`, the cache calls are skipped by overwriting the configured
      adapter with `Nebulex.Adapters.Nil` when the cache starts. This option
      is handy for tests if you want to disable or bypass the cache while
      running the tests.
      """
    ]
  ]

  # Telemetry options (runtime)
  telemetry_opts = [
    telemetry_event: [
      type: {:list, :atom},
      required: false,
      doc: """
      The telemetry event name to dispatch the event under. Defaults to what
      is configured in the `:telemetry_prefix` option. See the
      ["Telemetry events"](#module-telemetry-events) section
      for more information.
      """
    ],
    telemetry_metadata: [
      type: {:map, :any, :any},
      required: false,
      doc: """
      Extra metadata to add to the Telemetry cache command events.
      These end up in the `:extra_metadata` metadata key of these events.

      See the ["Telemetry events"](#module-telemetry-events) section
      for more information.
      """
    ]
  ]

  # Runtime shared options
  runtime_shared_opts = [
    timeout: [
      type: :timeout,
      required: false,
      doc: """
      The time in **milliseconds** to wait for a command to finish
      (`:infinity` to wait indefinitely). The default value is `5000`.
      However, it may change depending on the adapter.

      > #### Timeout option {: .warning}
      >
      > Despite being a shared option accepted by almost all cache functions,
      > it is up to the adapter to support it.
      """
    ]
  ]

  # Runtime shared options for write operations
  write_opts = [
    ttl: [
      type: :timeout,
      required: false,
      default: :infinity,
      doc: """
      The key's time-to-live (or expiry time) in **milliseconds**
      (`:infinity` to store indefinitely).
      """
    ]
  ]

  # Extra TTL options
  ttl_opts = [
    keep_ttl: [
      type: :boolean,
      required: false,
      default: false,
      doc: """
      Indicates whether to retain the time to live associated with the key.
      Otherwise, the value in the `:ttl` option overwrites the existing one.
      """
    ]
  ]

  # Runtime options for updating counter
  update_counter_opts = [
    default: [
      type: :integer,
      required: false,
      default: 0,
      doc: """
      If the key is not present in the cache, the default value is inserted as
      the key's initial value before it is incremented.
      """
    ]
  ]

  # Stream options
  stream_opts = [
    max_entries: [
      type: :pos_integer,
      required: false,
      default: 100,
      doc: """
      The number of entries to load from the cache as we stream
      """
    ]
  ]

  # Compilation time options schema
  @compile_opts_schema NimbleOptions.new!(compile_opts)

  # Compilation time options
  @compile_opts Keyword.keys(@compile_opts_schema.schema)

  # Start options schema
  @start_link_opts_schema NimbleOptions.new!(start_link_opts)

  # Start options
  @start_link_opts Keyword.keys(@start_link_opts_schema.schema)

  # Telemetry options schema
  @telemetry_opts_schema NimbleOptions.new!(telemetry_opts)

  # Shared options schema
  @runtime_shared_opts_schema NimbleOptions.new!(runtime_shared_opts ++ telemetry_opts)

  # Shared options
  @runtime_shared_opts Keyword.keys(@runtime_shared_opts_schema.schema)

  # Runtime common write operations schema
  @write_opts_schema NimbleOptions.new!(write_opts)

  # Runtime PUT options schema
  @put_opts_schema NimbleOptions.new!(write_opts ++ ttl_opts)

  # Runtime REPLACE options schema
  @replace_opts_schema NimbleOptions.new!(
                         write_opts ++ put_in(ttl_opts, [:keep_ttl, :default], true)
                       )

  # Update counter options schema
  @update_counter_opts_schema NimbleOptions.new!(write_opts ++ update_counter_opts)

  # Stream options schema
  @stream_opts_schema NimbleOptions.new!(stream_opts)

  ## Convenience functions

  # Inline common instructions
  @compile {:inline, __compile_opts__: 0, __start_opts__: 0, __runtime_shared_opts__: 0}

  @doc """
  Returns the schema for the compilation time options.

  ## Example

      iex> keys = Nebulex.Cache.Options.__compile_opts__()
      iex> is_list(keys)
      true

  """
  @spec __compile_opts__() :: [atom()]
  def __compile_opts__, do: @compile_opts

  @doc """
  Returns the schema for the start options.

  ## Example

      iex> keys = Nebulex.Cache.Options.__start_opts__()
      iex> is_list(keys)
      true

  """
  @spec __start_opts__() :: [atom()]
  def __start_opts__, do: @start_link_opts

  @doc """
  Returns the schema for the runtime shared options.

  ## Example

      iex> keys = Nebulex.Cache.Options.__runtime_shared_opts__()
      iex> is_list(keys)
      true

  """
  @spec __runtime_shared_opts__() :: [atom()]
  def __runtime_shared_opts__, do: @runtime_shared_opts

  ## Docs API

  # coveralls-ignore-start

  @spec compile_options_docs() :: binary()
  def compile_options_docs do
    NimbleOptions.docs(@compile_opts_schema)
  end

  @spec start_link_options_docs() :: binary()
  def start_link_options_docs do
    NimbleOptions.docs(@start_link_opts_schema)
  end

  @spec runtime_shared_options_docs() :: binary()
  def runtime_shared_options_docs do
    NimbleOptions.docs(@runtime_shared_opts_schema)
  end

  @spec write_options_docs() :: binary()
  def write_options_docs do
    NimbleOptions.docs(@write_opts_schema)
  end

  @spec put_options_docs() :: binary()
  def put_options_docs do
    NimbleOptions.docs(@put_opts_schema)
  end

  @spec replace_options_docs() :: binary()
  def replace_options_docs do
    NimbleOptions.docs(@replace_opts_schema)
  end

  @spec update_counter_options_docs() :: binary()
  def update_counter_options_docs do
    NimbleOptions.docs(@update_counter_opts_schema)
  end

  @spec stream_options_docs() :: binary()
  def stream_options_docs do
    NimbleOptions.docs(@stream_opts_schema)
  end

  # coveralls-ignore-stop

  ## Validation API

  @spec validate_compile_opts!(keyword()) :: keyword()
  def validate_compile_opts!(opts) do
    NimbleOptions.validate!(opts, @compile_opts_schema)
  end

  @spec validate_start_opts!(keyword()) :: keyword()
  def validate_start_opts!(opts) do
    start_link_opts =
      opts
      |> Keyword.take(__start_opts__())
      |> NimbleOptions.validate!(@start_link_opts_schema)

    Keyword.merge(opts, start_link_opts)
  end

  @spec validate_telemetry_opts!(keyword()) :: keyword()
  def validate_telemetry_opts!(opts) do
    _ignore =
      opts
      |> Keyword.take([:telemetry_event, :telemetry_metadata])
      |> NimbleOptions.validate!(@telemetry_opts_schema)

    opts
  end

  @spec validate_stream_opts!(keyword()) :: keyword()
  def validate_stream_opts!(opts) do
    stream_opts =
      opts
      |> Keyword.take([:max_entries])
      |> NimbleOptions.validate!(@stream_opts_schema)

    Keyword.merge(opts, stream_opts)
  end

  ## Validation helpers

  @spec __validate_name__(atom() | {:via, reg_mod :: module(), via_name :: any()}) :: {:ok, atom()}
  def __validate_name__(name)

  def __validate_name__(name) when is_atom(name) do
    {:ok, name}
  end

  def __validate_name__({:via, reg_mod, _via_name}) when is_atom(reg_mod) do
    {:ok, nil}
  end

  @spec __validate_behaviour__(any(), module(), atom() | binary()) ::
          {:ok, module()} | {:error, binary()}
  def __validate_behaviour__(value, behaviour, target)

  def __validate_behaviour__(value, behaviour, target) when is_atom(target) do
    __validate_behaviour__(value, behaviour, inspect(target))
  end

  def __validate_behaviour__(value, behaviour, target)
      when is_atom(value) and is_atom(behaviour) and is_binary(target) do
    with {:module, module} <- Code.ensure_compiled(value),
         behaviours = module_behaviours(module),
         true <- behaviour in behaviours do
      {:ok, module}
    else
      {:error, _} ->
        msg =
          "the module #{inspect(value)} was not compiled, " <>
            "ensure it is correct and it is included as a project dependency"

        {:error, msg}

      false ->
        msg =
          "#{target} expects the option value #{inspect(value)} " <>
            "to list #{inspect(behaviour)} as a behaviour"

        {:error, msg}
    end
  end

  def __validate_behaviour__(value, behaviour, target)
      when is_atom(behaviour) and is_binary(target) do
    {:error, "expected a module, got: #{inspect(value)}"}
  end

  ## Extras

  @doc """
  This function behaves like `Keyword.pop_first/3`, but raises in case the value
  is not a valid timeout.

  ## Examples

      iex> Nebulex.Cache.Options.pop_and_validate_timeout!([], :timeout)
      {:infinity, []}

      iex> Nebulex.Cache.Options.pop_and_validate_timeout!([t: 1000], :t)
      {1000, []}

      iex> Nebulex.Cache.Options.pop_and_validate_timeout!([t: :infinity], :t)
      {:infinity, []}

      iex> Nebulex.Cache.Options.pop_and_validate_timeout!([k: 1], :t, 1000)
      {1000, [k: 1]}

      iex> Nebulex.Cache.Options.pop_and_validate_timeout!([t: -1], :t)
      ** (NimbleOptions.ValidationError) invalid value for :t option: expected non-negative integer or :infinity, got: -1

      iex> Nebulex.Cache.Options.pop_and_validate_timeout!([t: nil], :t)
      ** (NimbleOptions.ValidationError) invalid value for :t option: expected non-negative integer or :infinity, got: nil

      iex> Nebulex.Cache.Options.pop_and_validate_timeout!([k: 1], :t, :x)
      ** (NimbleOptions.ValidationError) invalid value for :t option: expected non-negative integer or :infinity, got: :x

      iex> Nebulex.Cache.Options.pop_and_validate_timeout!([k: 1], :t, nil)
      ** (NimbleOptions.ValidationError) invalid value for :t option: expected non-negative integer or :infinity, got: nil

  """
  @spec pop_and_validate_timeout!(keyword(), any(), timeout()) :: {timeout(), keyword()}
  def pop_and_validate_timeout!(opts, key, default \\ :infinity) do
    case Keyword.pop_first(opts, key, default) do
      {value, opts} when is_timeout(value) ->
        {value, opts}

      {value, _opts} ->
        raise NimbleOptions.ValidationError,
          message:
            "invalid value for #{inspect(key)} option: expected " <>
              "non-negative integer or :infinity, got: #{inspect(value)}"
    end
  end

  @doc """
  This function behaves like `Keyword.pop_first/3`, but raises in case the value
  is not a valid integer.

  ## Examples

      iex> Nebulex.Cache.Options.pop_and_validate_integer!([], :int)
      {0, []}

      iex> Nebulex.Cache.Options.pop_and_validate_integer!([int: 1], :int)
      {1, []}

      iex> Nebulex.Cache.Options.pop_and_validate_integer!([k: 1], :int, 1)
      {1, [k: 1]}

      iex> Nebulex.Cache.Options.pop_and_validate_integer!([int: nil], :int)
      ** (NimbleOptions.ValidationError) invalid value for :int option: expected integer, got: nil

      iex> Nebulex.Cache.Options.pop_and_validate_integer!([k: 1], :int, :x)
      ** (NimbleOptions.ValidationError) invalid value for :int option: expected integer, got: :x

      iex> Nebulex.Cache.Options.pop_and_validate_integer!([k: 1], :int, nil)
      ** (NimbleOptions.ValidationError) invalid value for :int option: expected integer, got: nil

  """
  @spec pop_and_validate_integer!(keyword(), any(), integer()) :: {integer(), keyword()}
  def pop_and_validate_integer!(opts, key, default \\ 0) do
    case Keyword.pop_first(opts, key, default) do
      {value, opts} when is_integer(value) ->
        {value, opts}

      {value, _opts} ->
        raise NimbleOptions.ValidationError,
          message:
            "invalid value for #{inspect(key)} option: expected integer, " <>
              "got: #{inspect(value)}"
    end
  end

  @doc """
  This function behaves like `Keyword.pop_first/3`, but raises in case the value
  is not a boolean.

  ## Examples

      iex> Nebulex.Cache.Options.pop_and_validate_boolean!([], :bool)
      {false, []}

      iex> Nebulex.Cache.Options.pop_and_validate_boolean!([bool: true], :bool)
      {true, []}

      iex> Nebulex.Cache.Options.pop_and_validate_boolean!([k: 1], :bool, true)
      {true, [k: 1]}

      iex> Nebulex.Cache.Options.pop_and_validate_boolean!([bool: nil], :bool)
      ** (NimbleOptions.ValidationError) invalid value for :bool option: expected boolean, got: nil

      iex> Nebulex.Cache.Options.pop_and_validate_boolean!([k: 1], :bool, :x)
      ** (NimbleOptions.ValidationError) invalid value for :bool option: expected boolean, got: :x

      iex> Nebulex.Cache.Options.pop_and_validate_boolean!([k: 1], :bool, nil)
      ** (NimbleOptions.ValidationError) invalid value for :bool option: expected boolean, got: nil

  """
  @spec pop_and_validate_boolean!(keyword(), any(), boolean()) :: {boolean(), keyword()}
  def pop_and_validate_boolean!(opts, key, default \\ false) do
    case Keyword.pop_first(opts, key, default) do
      {value, opts} when is_boolean(value) ->
        {value, opts}

      {value, _opts} ->
        raise NimbleOptions.ValidationError,
          message:
            "invalid value for #{inspect(key)} option: expected boolean, " <>
              "got: #{inspect(value)}"
    end
  end
end
