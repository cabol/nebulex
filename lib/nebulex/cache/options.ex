defmodule Nebulex.Cache.Options do
  @moduledoc false

  alias Nebulex.{Time, Utils}

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
      type: {:custom, __MODULE__, :__validate_behaviour__, [Nebulex.Adapter, "adapter"]},
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

  # Shared option definitions (runtime)
  runtime_shared_opts = [
    timeout: [
      type: :timeout,
      required: false,
      default: :infinity,
      doc: """
      The time in **milliseconds** to wait for a command to finish
      (`:infinity` to wait indefinitely).

      > #### Timeout option {: .warning}
      >
      > Despite being a shared option accepted by almost all cache functions,
      > it is up to the adapter to support it.
      """
    ],
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
      default: %{},
      doc: """
      Extra metadata to add to the Telemetry cache command events.
      These end up in the `:extra_metadata` metadata key of these events.

      See the ["Telemetry events"](#module-telemetry-events) section
      for more information.
      """
    ]
  ]

  # Runtime common option definitions for write operations
  runtime_common_write_opts = [
    ttl: [
      type: :timeout,
      required: false,
      default: :infinity,
      doc: """
      The key's time-to-live (or expiry time) in **milliseconds**.
      """
    ]
  ]

  # Runtime option definitions for updating counter
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

  # Compilation time options schema
  @compile_opts_schema NimbleOptions.new!(compile_opts)

  # Start options schema
  @start_link_opts_schema NimbleOptions.new!(start_link_opts)

  # Shared options schema
  @runtime_shared_opts_schema NimbleOptions.new!(runtime_shared_opts)

  # Runtime common write operations schema
  @runtime_common_write_opts_schema NimbleOptions.new!(runtime_common_write_opts)

  # Update counter options schema
  @update_counter_opts_schema NimbleOptions.new!(runtime_common_write_opts ++ update_counter_opts)

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

  @spec runtime_common_write_options_docs() :: binary()
  def runtime_common_write_options_docs do
    NimbleOptions.docs(@runtime_common_write_opts_schema)
  end

  @spec update_counter_options_docs() :: binary()
  def update_counter_options_docs do
    NimbleOptions.docs(@update_counter_opts_schema)
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
      |> Keyword.take(Keyword.keys(@start_link_opts_schema.schema))
      |> NimbleOptions.validate!(@start_link_opts_schema)

    Keyword.merge(opts, start_link_opts)
  end

  @spec validate_runtime_shared_opts!(keyword()) :: keyword()
  def validate_runtime_shared_opts!(opts) do
    NimbleOptions.validate!(opts, @runtime_shared_opts_schema)
  end

  @doc false
  def __validate_name__(name)

  def __validate_name__(name) when is_atom(name) do
    {:ok, name}
  end

  def __validate_name__({:via, _reg_mod, _reg_name}) do
    {:ok, nil}
  end

  @doc false
  def __validate_behaviour__(value, behaviour, msg) when is_atom(value) do
    with {:module, module} <- Code.ensure_compiled(value),
         behaviours = Utils.module_behaviours(module),
         true <- behaviour in behaviours do
      {:ok, module}
    else
      {:error, _} ->
        msg =
          "#{msg} #{inspect(value)} was not compiled, " <>
            "ensure it is correct and it is included as a project dependency"

        {:error, msg}

      false ->
        msg =
          "expected the #{msg} module given to Nebulex.Cache " <>
            "to list #{inspect(behaviour)} as a behaviour"

        {:error, msg}
    end
  end

  def __validate_behaviour__(value, _behaviour, _msg) do
    {:error, "expected a module, got: #{inspect(value)}"}
  end

  ## Extras

  @spec pop_and_validate_timeout(keyword(), any()) :: {timeout(), keyword()}
  def pop_and_validate_timeout(opts, key) do
    case Keyword.pop(opts, key) do
      {nil, opts} ->
        {:infinity, opts}

      {ttl, opts} ->
        if not Time.timeout?(ttl) do
          raise ArgumentError,
                "invalid value for #{inspect(key)} option: expected " <>
                  "non-negative integer or :infinity, got: #{inspect(ttl)}"
        end

        {ttl, opts}
    end
  end

  @spec pop_and_validate_integer(keyword(), any()) :: {integer(), keyword()}
  def pop_and_validate_integer(opts, key) do
    case Keyword.pop(opts, key) do
      {nil, opts} ->
        {0, opts}

      {val, opts} when is_integer(val) ->
        {val, opts}

      {val, _opts} ->
        raise ArgumentError,
              "invalid value for #{inspect(key)} option: expected integer, " <>
                "got: #{inspect(val)}"
    end
  end
end
