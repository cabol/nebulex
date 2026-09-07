defmodule Nebulex.Adapter.CompositeKV do
  @moduledoc """
  Specifies the adapter Composite KV API.

  Composite operations combine a read and a write on the same key in one
  call and receive a function as an argument. This behaviour covers
  `c:get_and_update/6`, `c:update/7`, `c:fetch_or_store/6`, and
  `c:get_or_store/6`.

  By default, Nebulex builds these operations on top of the
  `Nebulex.Adapter.KV` primitives (`fetch`, `put`, and `delete`), and the
  given function runs in the calling process, on the local node. Because
  they are composite, the default implementation is **not atomic**. See the
  ["Composite operations"](`Nebulex.Cache#module-composite-operations`)
  section in `Nebulex.Cache` for more information.

  This behaviour is optional, like `Nebulex.Adapter.Queryable`: the cache
  module exposes the composite functions only when the adapter implements
  it. Adapters may also override the default implementation to change the
  execution model (e.g., run the function on the node owning the key) or the
  atomicity guarantees.

  ## Default implementation

  `use Nebulex.Adapter.CompositeKV` attaches the behaviour to the adapter
  and provides the default implementation (the functions in this module).
  All callbacks are overridable, so an adapter can override only some of
  them:

      defmodule MyAdapter do
        @behaviour Nebulex.Adapter
        @behaviour Nebulex.Adapter.KV

        use Nebulex.Adapter.CompositeKV

        # Override `get_and_update/6` and `update/7`; the other callbacks
        # fall back to the default implementation.
        @impl true
        def get_and_update(adapter_meta, key, fun, ttl, keep_ttl?, opts) do
          # Adapter-specific implementation ...
        end

        @impl true
        def update(adapter_meta, key, initial, fun, ttl, keep_ttl?, opts) do
          # Adapter-specific implementation ...
        end

        ...
      end

  > #### Callback arities {: .info}
  >
  > `c:update/7` takes an extra `initial` argument, so it is the only
  > callback of the four with arity 7; `c:get_and_update/6`,
  > `c:fetch_or_store/6`, and `c:get_or_store/6` all take 6 arguments.
  > Annotate every override with `@impl true`: an override defined with the
  > wrong arity, or with a mistyped name, silently keeps the default
  > implementation, and `@impl true` makes the compiler report it.

  The default implementation executes the primitive commands through
  `Nebulex.Adapter.run_command/4`, so their Telemetry command events (and
  therefore the cache entry events and stats built on top of them) are
  still emitted.

  ## Telemetry

  Each composite operation is a cache command itself: a Telemetry span with
  `command: :get_and_update`, `command: :update`, `command: :fetch_or_store`,
  or `command: :get_or_store` is emitted. The shared `:telemetry`,
  `:telemetry_event`, and `:telemetry_metadata` options apply to that
  command span and are forwarded to the primitive commands executed by the
  default implementation, so they behave as one unit.
  """

  import Nebulex.Utils, only: [wrap_error: 2]

  alias Nebulex.Adapter

  @typedoc "Proxy type to the adapter meta"
  @type adapter_meta() :: Nebulex.Adapter.adapter_meta()

  @typedoc "Proxy type to the cache key"
  @type key() :: Nebulex.Cache.key()

  @typedoc "Proxy type to the cache value"
  @type value() :: Nebulex.Cache.value()

  @typedoc "Proxy type to the cache options"
  @type opts() :: Nebulex.Cache.opts()

  @typedoc "TTL for a cache entry"
  @type ttl() :: timeout()

  @typedoc "Keep TTL flag"
  @type keep_ttl() :: boolean()

  @typedoc "Proxy type to the get and update function"
  @type get_and_update_fun() :: Nebulex.Cache.get_and_update_fun()

  @typedoc "Proxy type to the update function"
  @type update_fun() :: Nebulex.Cache.update_fun()

  @typedoc "Proxy type to the fetch or store function"
  @type fetch_or_store_fun() :: Nebulex.Cache.fetch_or_store_fun()

  @typedoc "Proxy type to the get or store function"
  @type get_or_store_fun() :: Nebulex.Cache.get_or_store_fun()

  @doc """
  Gets the value for `key` and updates it using the given function.

  `fun` is called with the current cached value under `key` (or `nil` if
  `key` hasn't been cached) and must return a two-element tuple: the current
  value (which can be operated on before being returned) and the new value
  to be stored under `key`. `fun` may also return `:pop`, which means the
  current value shall be removed from the cache and returned.

  The `ttl` and `keep_ttl` arguments apply to the write, as in
  `c:Nebulex.Adapter.KV.put/7`.

  Returns `{:ok, {current_value, new_value}}` if successful;
  `{:error, reason}` otherwise.

  See `c:Nebulex.Cache.get_and_update/3`.
  """
  @callback get_and_update(
              adapter_meta(),
              key(),
              get_and_update_fun(),
              ttl(),
              keep_ttl(),
              opts()
            ) :: Nebulex.Cache.ok_error_tuple({value(), value()})

  @doc """
  Updates the cached `key` with the given function.

  If `key` is present in the cache, `fun` is invoked with the current value
  and its result is stored under `key`. If `key` is not present, `initial`
  is stored under `key` and `fun` is not invoked.

  The `ttl` and `keep_ttl` arguments apply to the write, as in
  `c:Nebulex.Adapter.KV.put/7`.

  Returns `{:ok, value}` with the stored value if successful;
  `{:error, reason}` otherwise.

  See `c:Nebulex.Cache.update/4`.
  """
  @callback update(
              adapter_meta(),
              key(),
              initial :: value(),
              update_fun(),
              ttl(),
              keep_ttl(),
              opts()
            ) :: Nebulex.Cache.ok_error_tuple(value())

  @doc """
  Fetches the value for `key` or, on a cache miss, evaluates `fun` and
  stores its result.

  `fun` must return `{:ok, value}`, in which case `value` is stored under
  `key` and returned, or `{:error, reason}`, in which case nothing is
  stored and the error is returned.

  The `ttl` and `keep_ttl` arguments apply to the write, as in
  `c:Nebulex.Adapter.KV.put/7`.

  Returns `{:ok, value}` if successful; `{:error, reason}` otherwise.

  See `c:Nebulex.Cache.fetch_or_store/3`.
  """
  @callback fetch_or_store(
              adapter_meta(),
              key(),
              fetch_or_store_fun(),
              ttl(),
              keep_ttl(),
              opts()
            ) :: Nebulex.Cache.ok_error_tuple(value())

  @doc """
  Gets the value for `key` or, on a cache miss, evaluates `fun` and stores
  whatever it returns.

  The `ttl` and `keep_ttl` arguments apply to the write, as in
  `c:Nebulex.Adapter.KV.put/7`.

  Returns `{:ok, value}` if successful; `{:error, reason}` otherwise.

  See `c:Nebulex.Cache.get_or_store/3`.
  """
  @callback get_or_store(
              adapter_meta(),
              key(),
              get_or_store_fun(),
              ttl(),
              keep_ttl(),
              opts()
            ) :: Nebulex.Cache.ok_error_tuple(value())

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Nebulex.Adapter.CompositeKV

      @impl true
      defdelegate get_and_update(adapter_meta, key, fun, ttl, keep_ttl?, opts),
        to: unquote(__MODULE__)

      @impl true
      defdelegate update(adapter_meta, key, initial, fun, ttl, keep_ttl?, opts),
        to: unquote(__MODULE__)

      @impl true
      defdelegate fetch_or_store(adapter_meta, key, fun, ttl, keep_ttl?, opts),
        to: unquote(__MODULE__)

      @impl true
      defdelegate get_or_store(adapter_meta, key, fun, ttl, keep_ttl?, opts),
        to: unquote(__MODULE__)

      defoverridable get_and_update: 6, update: 7, fetch_or_store: 6, get_or_store: 6
    end
  end

  ## Default implementation

  @doc """
  Default implementation for `c:get_and_update/6`.
  """
  @spec get_and_update(adapter_meta(), key(), get_and_update_fun(), ttl(), keep_ttl(), opts()) ::
          Nebulex.Cache.ok_error_tuple({value(), value()})
  def get_and_update(adapter_meta, key, fun, ttl, keep_ttl?, opts) do
    with {:ok, current} <- fetch_or_nil(adapter_meta, key, opts) do
      eval_get_and_update_fun(fun.(current), current, adapter_meta, key, ttl, keep_ttl?, opts)
    end
  end

  @doc """
  Default implementation for `c:update/7`.
  """
  @spec update(adapter_meta(), key(), value(), update_fun(), ttl(), keep_ttl(), opts()) ::
          Nebulex.Cache.ok_error_tuple(value())
  def update(adapter_meta, key, initial, fun, ttl, keep_ttl?, opts) do
    with {:ok, value} <- eval_update_fun(adapter_meta, key, initial, fun, opts) do
      put(adapter_meta, key, value, ttl, keep_ttl?, opts)
    end
  end

  @doc """
  Default implementation for `c:fetch_or_store/6`.
  """
  @spec fetch_or_store(
          adapter_meta(),
          key(),
          fetch_or_store_fun(),
          ttl(),
          keep_ttl(),
          opts()
        ) :: Nebulex.Cache.ok_error_tuple(value())
  def fetch_or_store(adapter_meta, key, fun, ttl, keep_ttl?, opts) do
    with {:error, %Nebulex.KeyError{key: ^key}} <- run(adapter_meta, :fetch, [key], opts) do
      eval_fetch_or_store_fun(fun.(), adapter_meta, key, ttl, keep_ttl?, opts)
    end
  end

  @doc """
  Default implementation for `c:get_or_store/6`.
  """
  @spec get_or_store(
          adapter_meta(),
          key(),
          get_or_store_fun(),
          ttl(),
          keep_ttl(),
          opts()
        ) :: Nebulex.Cache.ok_error_tuple(value())
  def get_or_store(adapter_meta, key, fun, ttl, keep_ttl?, opts) do
    with {:error, %Nebulex.KeyError{key: ^key}} <- run(adapter_meta, :fetch, [key], opts) do
      put(adapter_meta, key, fun.(), ttl, keep_ttl?, opts)
    end
  end

  ## Private functions

  defp fetch_or_nil(adapter_meta, key, opts) do
    with {:error, %Nebulex.KeyError{key: ^key}} <- run(adapter_meta, :fetch, [key], opts) do
      {:ok, nil}
    end
  end

  defp eval_get_and_update_fun({get, nil}, _current, _adapter_meta, _key, _ttl, _keep_ttl?, _opts) do
    {:ok, {get, get}}
  end

  defp eval_get_and_update_fun({get, update}, _current, adapter_meta, key, ttl, keep_ttl?, opts) do
    with {:ok, true} <- run(adapter_meta, :put, [key, update, :put, ttl, keep_ttl?], opts) do
      {:ok, {get, update}}
    end
  end

  defp eval_get_and_update_fun(:pop, nil, _adapter_meta, _key, _ttl, _keep_ttl?, _opts) do
    {:ok, {nil, nil}}
  end

  defp eval_get_and_update_fun(:pop, current, adapter_meta, key, _ttl, _keep_ttl?, opts) do
    with :ok <- run(adapter_meta, :delete, [key], opts) do
      {:ok, {current, nil}}
    end
  end

  defp eval_get_and_update_fun(other, _current, _adapter_meta, _key, _ttl, _keep_ttl?, _opts) do
    raise ArgumentError,
          "the given function must return a two-element tuple or :pop," <>
            " got: #{inspect(other)}"
  end

  defp eval_update_fun(adapter_meta, key, initial, fun, opts) do
    case run(adapter_meta, :fetch, [key], opts) do
      {:ok, value} -> {:ok, fun.(value)}
      {:error, %Nebulex.KeyError{key: ^key}} -> {:ok, initial}
      {:error, _} = error -> error
    end
  end

  defp eval_fetch_or_store_fun({:ok, value}, adapter_meta, key, ttl, keep_ttl?, opts) do
    put(adapter_meta, key, value, ttl, keep_ttl?, opts)
  end

  defp eval_fetch_or_store_fun({:error, reason}, _adapter_meta, key, _ttl, _keep_ttl?, _opts) do
    wrap_error Nebulex.Error, reason: reason, command: :fetch_or_store, key: key
  end

  defp eval_fetch_or_store_fun(other, _adapter_meta, _key, _ttl, _keep_ttl?, _opts) do
    raise "the supplied lambda function must return {:ok, value} " <>
            "or {:error, reason}, got: #{inspect(other)}"
  end

  defp put(adapter_meta, key, value, ttl, keep_ttl?, opts) do
    with {:ok, true} <- run(adapter_meta, :put, [key, value, :put, ttl, keep_ttl?], opts) do
      {:ok, value}
    end
  end

  defp run(adapter_meta, command, args, opts) do
    adapter_meta
    |> Adapter.run_command(command, args, opts)
    |> Adapter.handle_command_response()
  end
end
