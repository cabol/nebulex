defmodule Nebulex.Cache do
  @moduledoc """
  Cache Main Interface.

  A Cache maps to an underlying implementation, controlled by the
  adapter. For example, Nebulex ships with a default adapter that
  implements a local generational cache.

  When used, the Cache expects the `:otp_app` and `adapter` as options.
  The `:otp_app` should point to an OTP application that has the Cache
  configuration. For example, the Cache:

      defmodule MyCache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Local
      end

  Could be configured with:

      config :my_app, MyCache,
        version_generator: MyCache.VersionGenerator,
        stats: true,
        gc_interval: 3600

  Most of the configuration that goes into the `config` is specific
  to the adapter, so check `Nebulex.Adapters.Local` documentation
  for more information. However, some configuration is shared across
  all adapters, they are:

    * `:version_generator` - this option specifies the module that
      implements the `Nebulex.Object.Version` interface. This interface
      defines only one callback `generate/1` that is invoked by
      the adapters to generate new object versions. If this option
      is not set, then the version is set to `nil` by default.

    * `:stats` - a compile-time option that specifies if cache statistics
      is enabled or not (defaults to `false`).

  ## Pre/Post hooks

  The cache can also provide its own pre/post hooks implementation; see
  `Nebulex.Hook` behaviour. By default, pre/post hooks are empty lists,
  but you can override the functions of `Nebulex.Hook` behaviour.

  Additionally, it is possible to configure the mode how the hooks are
  evaluated (synchronous, asynchronous and pipeline).

  For more information about the usage, check out `Nebulex.Hook`.

  ## Shared options

  Almost all of the Cache operations below accept the following options:

    * `:return` - Selects return type: `:value | :key | :object`.
      If `:value` (the default) is set, only object's value is returned.
      If `:key` set, only object's key is returned.
      If `:object` is set, `Nebulex.Object.t()` is returned.

    * `:version` - The version of the object on which the operation will
      take place. The version can be any term (default: `nil`).

    * `:ttl` - Time To Live (TTL) or expiration time in seconds for a key
      (default: `:infinity`) – applies only to `set/3`.

  Such cases will be explicitly documented as well as any extra option.

  ## Extended API

  Some adapters might extend the API with additional functions, therefore,
  it is important to check out adapters documentation.
  """

  @type t :: module

  @typedoc "Cache object"
  @type object :: Nebulex.Object.t()

  @typedoc "Object key"
  @type key :: any

  @typedoc "Object value"
  @type value :: any

  @typedoc "Cache entries"
  @type entries :: map | [{key, value}] | [object]

  @typedoc "Cache action options"
  @type opts :: Keyword.t()

  @typedoc "Return alternatives (value is the default)"
  @type return :: key | value | object

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Nebulex.Cache
      @behaviour Nebulex.Hook

      alias Nebulex.Cache.Stats
      alias Nebulex.Hook

      {otp_app, adapter, behaviours, config} =
        Nebulex.Cache.Supervisor.compile_config(__MODULE__, opts)

      @otp_app otp_app
      @adapter adapter
      @config config
      @before_compile adapter

      ## Config and metadata

      @doc false
      def config do
        {:ok, config} = Nebulex.Cache.Supervisor.runtime_config(__MODULE__, @otp_app, [])
        config
      end

      @doc false
      def __adapter__, do: @adapter

      ## Process lifecycle

      @doc false
      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :supervisor
        }
      end

      @doc false
      def start_link(opts \\ []) do
        Nebulex.Cache.Supervisor.start_link(__MODULE__, @otp_app, @adapter, opts)
      end

      @doc false
      def stop(pid, timeout \\ 5000) do
        Supervisor.stop(pid, :normal, timeout)
      end

      ## Object version generator

      if versioner = Keyword.get(@config, :version_generator) do
        @doc false
        def object_vsn(cached_object) do
          unquote(versioner).generate(cached_object)
        end
      else
        @doc false
        def object_vsn(_), do: nil
      end

      ## Objects

      @doc false
      def get(key, opts \\ []) do
        with_hooks(Nebulex.Cache.Object, :get, [key, opts])
      end

      @doc false
      def get!(key, opts \\ []) do
        with_hooks(Nebulex.Cache.Object, :get!, [key, opts])
      end

      @doc false
      def get_many(keys, opts \\ []) do
        with_hooks(Nebulex.Cache.Object, :get_many, [keys, opts])
      end

      @doc false
      def set(key, value, opts \\ []) do
        with_hooks(Nebulex.Cache.Object, :set, [key, value, opts])
      end

      @doc false
      def set_many(entries, opts \\ []) do
        with_hooks(Nebulex.Cache.Object, :set_many, [entries, opts])
      end

      @doc false
      def add(key, value, opts \\ []) do
        with_hooks(Nebulex.Cache.Object, :add, [key, value, opts])
      end

      @doc false
      def add!(key, value, opts \\ []) do
        with_hooks(Nebulex.Cache.Object, :add!, [key, value, opts])
      end

      @doc false
      def replace(key, value, opts \\ []) do
        with_hooks(Nebulex.Cache.Object, :replace, [key, value, opts])
      end

      @doc false
      def replace!(key, value, opts \\ []) do
        with_hooks(Nebulex.Cache.Object, :replace!, [key, value, opts])
      end

      @doc false
      def add_or_replace!(key, value, opts \\ []) do
        with_hooks(Nebulex.Cache.Object, :add_or_replace!, [key, value, opts])
      end

      @doc false
      def delete(key, opts \\ []) do
        with_hooks(Nebulex.Cache.Object, :delete, [key, opts])
      end

      @doc false
      def take(key, opts \\ []) do
        with_hooks(Nebulex.Cache.Object, :take, [key, opts])
      end

      @doc false
      def take!(key, opts \\ []) do
        with_hooks(Nebulex.Cache.Object, :take!, [key, opts])
      end

      @doc false
      def has_key?(key) do
        with_hooks(Nebulex.Cache.Object, :has_key?, [key])
      end

      @doc false
      def object_info(key, attr) do
        with_hooks(Nebulex.Cache.Object, :object_info, [key, attr])
      end

      @doc false
      def expire(key, ttl) do
        with_hooks(Nebulex.Cache.Object, :expire, [key, ttl])
      end

      @doc false
      def get_and_update(key, fun, opts \\ []) do
        with_hooks(Nebulex.Cache.Object, :get_and_update, [key, fun, opts])
      end

      @doc false
      def update(key, initial, fun, opts \\ []) do
        with_hooks(Nebulex.Cache.Object, :update, [key, initial, fun, opts])
      end

      @doc false
      def update_counter(key, incr \\ 1, opts \\ []) do
        with_hooks(Nebulex.Cache.Object, :update_counter, [key, incr, opts])
      end

      @doc false
      def size do
        with_hooks(@adapter, :size)
      end

      @doc false
      def flush do
        with_hooks(@adapter, :flush)
      end

      ## Queryable

      if Nebulex.Adapter.Queryable in behaviours do
        @doc false
        def all(query \\ :all, opts \\ []) do
          with_hooks(Nebulex.Cache.Queryable, :all, [query, opts])
        end

        @doc false
        def stream(query \\ :all, opts \\ []) do
          with_hooks(Nebulex.Cache.Queryable, :stream, [query, opts])
        end
      end

      ## Transactions

      if Nebulex.Adapter.Transaction in behaviours do
        @doc false
        def transaction(fun, opts \\ []) do
          with_hooks(Nebulex.Cache.Transaction, :transaction, [fun, opts])
        end

        @doc false
        def in_transaction? do
          with_hooks(Nebulex.Cache.Transaction, :in_transaction?)
        end
      end

      ## Hooks

      @doc false
      def pre_hooks, do: {:async, []}

      @doc false
      def post_hooks, do: {:async, []}

      defoverridable pre_hooks: 0, post_hooks: 0

      ## Helpers

      defp with_hooks(wrapper, action, args \\ []) do
        wrapper
        |> eval_pre_hooks(action, args)
        |> apply(action, [__MODULE__ | args])
        |> eval_post_hooks(action, args)
      end

      defp eval_pre_hooks(wrapper, action, args) do
        _ = Hook.eval(pre_hooks(), {__MODULE__, action, args}, nil)
        wrapper
      end

      if @config[:stats] == true do
        defp eval_post_hooks(result, action, args) do
          {mode, hooks} = post_hooks()

          Hook.eval(
            {mode, [unquote(&Stats.post_hook/2) | hooks]},
            {__MODULE__, action, args},
            result
          )
        end
      else
        defp eval_post_hooks(result, action, args) do
          Hook.eval(post_hooks(), {__MODULE__, action, args}, result)
        end
      end
    end
  end

  ## Nebulex.Adapter

  @optional_callbacks init: 1

  @doc """
  Returns the adapter tied to the cache.
  """
  @callback __adapter__ :: Nebulex.Adapter.t()

  @doc """
  Returns the adapter configuration stored in the `:otp_app` environment.

  If the `c:init/2` callback is implemented in the cache, it will be invoked.
  """
  @callback config() :: Keyword.t()

  @doc """
  Starts a supervision and return `{:ok, pid}` or just `:ok` if nothing
  needs to be done.

  Returns `{:error, {:already_started, pid}}` if the cache is already
  started or `{:error, term}` in case anything else goes wrong.

  ## Options

  See the configuration in the moduledoc for options shared between adapters,
  for adapter-specific configuration see the adapter's documentation.
  """
  @callback start_link(opts) ::
              {:ok, pid}
              | {:error, {:already_started, pid}}
              | {:error, term}

  @doc """
  A callback executed when the cache starts or when configuration is read.
  """
  @callback init(config :: Keyword.t()) :: {:ok, Keyword.t()} | :ignore

  @doc """
  Shuts down the cache represented by the given pid.
  """
  @callback stop(pid, timeout) :: :ok

  @doc """
  Gets a value or object from Cache where the key matches the
  given `key`.

  Returns `nil` if no result was found.

  ## Options

  Besides the "Shared options" section at the module documentation,
  it accepts:

    * `:on_conflict` - It may be one of `:raise` (the default), `:nothing`,
      `:override`. See the "OnConflict" section for more information.

  ## Example

      iex> MyCache.set("foo", "bar")
      "bar"

      iex>  MyCache.get("foo")
      "bar"

      iex>  MyCache.get("foo", return: :object)
      %Nebulex.Object{key: "foo", value: "bar", version: nil, expire_at: nil}

       iex> MyCache.get(:non_existent_key)
       nil

  ## OnConflict

  The `:on_conflict` option supports the following values:

    * `:raise` - raises if there is a conflicting key
    * `:nothing` - ignores the error in case of conflicts
    * `:override` - same effect as `:nothing`

  ## Examples

      # Set a value
      iex> MyCache.set(:a, 1)
      1

      # Gets with an invalid version but do nothing on conflicts.
      # Keep in mind that, although this returns successfully, the returned
      # struct does not reflect the data in the Cache. For instance, in case
      # of "on_conflict: :nothing", it returns the latest version of the
      # cached object.
      iex> %Nebulex.Object{value: 1} =
      ...>   MyCache.get(:a, return: :object, version: :invalid, on_conflict: :nothing)
      iex> MyCache.get(:a)
      1
  """
  @callback get(key, opts) :: return | nil

  @doc """
  Similar to `get/2` but raises `KeyError` if `key` is not found.

  ## Options

  See the "Shared options" section at the module documentation.

  ## Example

      MyCache.get!(:a)
  """
  @callback get!(key, opts) :: return | no_return

  @doc """
  Returns a map with the values or objects (check `:return` option) for all
  specified keys. For every key that does not hold a value or does not exist,
  that key is simply ignored. Because of this, the operation never fails.

  ## Options

  See the "Shared options" section at the module documentation.

  Note that for this function, option `:version` is ignored.

  ## Example

      iex> MyCache.set_many([a: 1, c: 3])
      :ok

      iex> MyCache.get_many([:a, :b, :c])
      %{a: 1, c: 3}
  """
  @callback get_many([key], opts) :: map

  @doc """
  Sets the given `value` under `key` into the cache.

  If `key` already holds an object, it is overwritten. Any previous
  time to live associated with the key is discarded on successful
  `set` operation.

  Returns either the value, key or the object, depending on `:return`
  option, if the action is completed successfully.

  ## Options

  Besides the "Shared options" section at the module documentation,
  it accepts:

    * `:on_conflict` - It may be one of `:raise` (the default), `:nothing`,
      `:override`. See the "OnConflict" section for more information.

  ## Example

      iex> MyCache.set("foo", "bar")
      "bar"

      iex> MyCache.set("foo", "bar", ttl: 10, return: :object)
      %Nebulex.Object{key: "foo", value: "bar", version: nil, expire_at: 1540004049}

      # if the value is nil, then it is not stored (operation is skipped)
      iex> MyCache.set("foo", nil)
      nil

  ## OnConflict

  The `:on_conflict` option supports the following values:

    * `:raise` - raises if there is a conflicting key
    * `:nothing` - ignores the error in case of conflicts
    * `:override` - the command is executed ignoring the conflict, then
      the value on the existing key is replaced with the given `value`

  ## Examples

      iex> %Nebulex.Object{version: v1} = MyCache.set(:a, 1, return: :object)
      iex> MyCache.set(:a, 2, version: v1)
      2

      # Set with the same key and wrong version but do nothing on conflicts.
      # Keep in mind in case of "on_conflict: :nothing", the returned object
      # is the current cached object, if there is one
      iex> MyCache.set(:a, 3, version: v1, on_conflict: :nothing)
      2

      # Set with the same key and wrong version but replace the current
      # value on conflicts.
      iex> MyCache.set(:a, 3, version: v1, on_conflict: :override)
      3
  """
  @callback set(key, value, opts) :: return | nil

  @doc """
  Sets the given `entries`, replacing existing ones, just as regular `set`.

  Returns `:ok` if the all entries were successfully set, otherwise
  `{:error, failed_keys}`, where `failed_keys` contains the keys that
  could not be set.

  Ideally, this operation should be atomic, so all given keys are set at once.
  But it depends purely on the adapter's implementation and the backend used
  internally by the adapter. Hence, it is recommended to checkout the
  adapter's documentation.

  ## Options

  See the "Shared options" section at the module documentation.

  Note that for this function, option `:version` is ignored.

  ## Example

      iex> MyCache.set_many(apples: 3, bananas: 1)
      :ok

      iex> MyCache.set_many(%{"apples" => 1, "bananas" => 3})
      :ok

      # set a custom list of objects
      iex> MyCache.set_many([
      ...>   %Nebulex.Object{key: :apples, value: 1},
      ...>   %Nebulex.Object{key: :bananas, value: 2, expire_at: 5}
      ...> ])
      :ok

      # for some reason `:c` couldn't be set, so we got an error
      iex> MyCache.set_many([a: 1, b: 2, c: 3], ttl: 1000)
      {:error, [:c]}
  """
  @callback set_many(entries, opts) :: :ok | {:error, failed_keys :: [key]}

  @doc """
  Sets the given `value` under `key` into the cache, only if it does not
  already exist.

  If cache doesn't contain the given `key`, then `{:ok, value}` is returned.
  If cache contains `key`, `:error` is returned.

  ## Options

  See the "Shared options" section at the module documentation.

  For `add` operation, the option `:version` is ignored.

  ## Example

      iex> MyCache.add("foo", "bar")
      {ok, "bar"}

      iex> MyCache.add("foo", "bar")
      :error

      # if the value is nil, it is not stored (operation is skipped)
      iex> MyCache.add("foo", nil)
      {ok, nil}
  """
  @callback add(key, value, opts) :: {:ok, return} | :error

  @doc """
  Similar to `add/3` but raises `Nebulex.KeyAlreadyExistsError` if the
  key already exists.

  ## Options

  See the "Shared options" section at the module documentation.

  ## Example

      MyCache.add!("foo", "bar")
  """
  @callback add!(key, value, opts) :: return | no_return

  @doc """
  Alters the object stored under `key`, but only if the object already exists
  into the cache.

  If cache contains the given `key`, then `{:ok, return}` is returned.
  If cache doesn't contain `key`, `:error` is returned.

  ## Options

  Besides the "Shared options" section at the module documentation,
  it accepts:

    * `:on_conflict` - Same as callback `set/3`.

  ## Example

      iex> MyCache.replace("foo", "bar")
      :error

      iex> MyCache.set("foo", "bar")
      "bar"

      # update only current value
      iex> MyCache.replace("foo", "bar2")
      {:ok, "bar2"}

      # update current value and TTL
      iex> MyCache.replace("foo", "bar3", ttl: 10)
      {:ok, "bar3"}
  """
  @callback replace(key, value, opts) :: {:ok, return} | :error

  @doc """
  Similar to `replace/3` but raises `KeyError` if `key` is not found.

  ## Options

  Besides the "Shared options" section at the module documentation,
  it accepts:

    * `:on_conflict` - Same as callback `set/3`.

  ## Example

      MyCache.replace!("foo", "bar")
  """
  @callback replace!(key, value, opts) :: return | no_return

  @doc """
  When the `key` already exists, the cached value is replaced by `value`,
  otherwise the object is created at fisrt time.

  Returns the replaced or created value when the function is completed
  successfully. Because this function is a combination of `replace/3`
  and `add!/3` functions, there might be a race condition between them,
  in that case the last operation `add!/3` fails with
  `Nebulex.KeyAlreadyExistsError`.

  ## Options

  Besides the "Shared options" section at the module documentation,
  it accepts:

    * `:on_conflict` - Same as callback `set/3`.

  ## Example

      MyCache.add_or_replace!("foo", "bar")
  """
  @callback add_or_replace!(key, value, opts) :: return | no_return

  @doc """
  Deletes the entry in cache for a specific `key`.

  If the `key` does not exist, returns the result according to the `:return`
  option (for `delete` defaults to `:key`) but the cache is not altered.

  ## Options

  Besides the "Shared options" section at the module documentation,
  it accepts:

    * `:on_conflict` - It may be one of `:raise` (the default), `:nothing`,
      `:override`. See the "OnConflict" section for more information.

  Note that for this function `:return` option hasn't any effect
  since it always returns the `key` either success or not.

  ## Example

      iex> MyCache.set(:a, 1)
      1

      iex> MyCache.delete(:a)
      :a

      iex> MyCache.get(:a)
      nil

      iex> MyCache.delete(:non_existent_key)
      :non_existent_key

  ## OnConflict

  The `:on_conflict` option supports the following values:

    * `:raise` - raises if there is a conflicting key
    * `:nothing` - ignores the error in case of conflicts
    * `:override` - the command is executed ignoring the conflict, then
      the value on the existing key is deleted

  ## Examples

      # Set a value
      iex> MyCache.set(:a, 1)
      1

      # Delete with an invalid version but do nothing on conflicts.
      # Keep in mind that, although this returns successfully, the returned
      # `key` does not reflect the data in the cache. For instance, in case
      # of "on_conflict: :nothing", the returned `key` isn't deleted.
      iex> MyCache.delete(:a, version: :invalid, on_conflict: :nothing)
      :a

      iex> MyCache.get(:a)
      1

      # Delete with the same invalid version but force to delete the current
      # value on conflicts (if the entry exists).
      iex> MyCache.delete(:a, version: :invalid, on_conflict: :override)
      :a

      iex> MyCache.get(:a)
      nil
  """
  @callback delete(key, opts) :: return | nil

  @doc """
  Returns and removes the object with key `key` in the cache.

  Returns `nil` if no result was found.

  ## Options

  Besides the "Shared options" section at the module documentation,
  it accepts:

    * `:on_conflict` - Same as callback `set/3`.

  ## Examples

      iex> MyCache.set(:a, 1)
      1

      iex> MyCache.take(:a)
      1

      iex> MyCache.take(:a)
      nil

      iex> :a |> MyCache.set(1, return: :key) |> MyCache.take(return: :object)
      %Nebulex.Object{key: :a, value: 1, version: nil, expire_at: nil}
  """
  @callback take(key, opts) :: return | nil

  @doc """
  Similar to `take/2` but raises `KeyError` if `key` is not found.

  ## Options

  See the "Shared options" section at the module documentation.

  ## Example

      MyCache.take!(:a)
  """
  @callback take!(key, opts) :: return | no_return

  @doc """
  Returns whether the given `key` exists in cache.

  ## Examples

      iex> MyCache.set(:a, 1)
      1

      iex> MyCache.has_key?(:a)
      true

      iex> MyCache.has_key?(:b)
      false
  """
  @callback has_key?(key) :: boolean

  @doc """
  Returns the information associated with `attr` for the given `key`,
  or returns `nil` if `key` doesn't exist.

  If `attr` is not one of the allowed values, `ArgumentError` is raised.

  The following values are allowed for `attr`:

    * `:ttl` - Returns the remaining time to live for the given `key`,
      if it has a timeout, otherwise, `:infinity` is returned.

    * `:version` - Returns the current version for the given `key`.

  ## Examples

      iex> MyCache.set(:a, 1, ttl: 5)
      1

      iex> MyCache.set(:b, 2)
      2

      iex> MyCache.object_info(:a, :ttl)
      5

      iex> MyCache.ttl(:b)
      :infinity

      iex> MyCache.object_info(:a, :version)
      nil
  """
  @callback object_info(key, attr :: :ttl | :version) :: any | nil

  @doc """
  Returns the expiry timestamp for the given `key`, if the timeout `ttl`
  (in seconds) is successfully updated.

  If `key` doesn't exist, `nil` is returned.

  ## Examples

      iex> MyCache.set(:a, 1)
      1

      iex> MyCache.expire(:a, 5)
      1540004049

      iex> MyCache.expire(:a, :infinity)
      :infinity

      iex> MyCache.ttl(:b, 5)
      nil
  """
  @callback expire(key, ttl :: timeout) :: timeout | nil

  @doc """
  Gets the object/value from `key` and updates it, all in one pass.

  `fun` is called with the current cached value under `key` (or `nil`
  if `key` hasn't been cached) and must return a two-element tuple:
  the "get" value (the retrieved value, which can be operated on before
  being returned) and the new value to be stored under `key`. `fun` may
  also return `:pop`, which means the current value shall be removed
  from Cache and returned.

  The returned value is a tuple with the "get" value returned by
  `fun` and the new updated value under `key`.

  ## Options

  Besides the "Shared options" section at the module documentation,
  it accepts:

    * `:on_conflict` - Same as callback `set/3`.

  ## Examples

      # update nonexistent key
      iex> MyCache.get_and_update(:a, fn current_value ->
      ...>   {current_value, "value!"}
      ...> end)
      {nil, "value!"}

      # update existing key
      iex> MyCache.get_and_update(:a, fn current_value ->
      ...>   {current_value, "new value!"}
      ...> end)
      {"value!", "new value!"}

      # pop/remove value if exist
      iex> MyCache.get_and_update(:a, fn _ -> :pop end)
      {"new value!", nil}

      # pop/remove nonexistent key
      iex> MyCache.get_and_update(:b, fn _ -> :pop end)
      {nil, nil}

      # update existing key but returning the object
      iex> {"hello", %Object{key: :a, value: "hello world"}} =
      ...>   :a
      ...>   |> MyCache.set!("hello", return: :key)
      ...>   |> MyCache.get_and_update(fn current_value ->
      ...>        {current_value, "hello world"}
      ...>   end, return: :object)
  """
  @callback get_and_update(key, (value -> {get, update} | :pop), opts) :: {get, update}
            when get: value, update: return

  @doc """
  Updates the cached `key` with the given function.

  If `key` is present in Cache with value `value`, `fun` is invoked with
  argument `value` and its result is used as the new value of `key`.

  If `key` is not present in Cache, `initial` is inserted as the value
  of `key`.

  ## Options

  Besides the "Shared options" section at the module documentation,
  it accepts:

    * `:on_conflict` - Same as callback `set/3`.

  ## Examples

      iex> MyCache.update(:a, 1, &(&1 * 2))
      1

      iex> MyCache.update(:a, 1, &(&1 * 2))
      2

      iex> %Nebulex.Object{value: 4} =
      ...>   MyCache.update(:a, 1, &(&1 * 2), return: :object)
  """
  @callback update(key, initial :: value, (value -> value), opts) :: return

  @doc """
  Updates (increment or decrement) the counter mapped to the given `key`.

  If `incr >= 0` then the current value is incremented by that amount,
  otherwise the current value is decremented.

  If `incr` is not a valid integer, then an `ArgumentError` exception
  is raised.

  ## Options

  See the "Shared options" section at the module documentation.

  Note that for this function, option `:version` is ignored.

  ## Examples

      iex> MyCache.update_counter(:a)
      1

      iex> MyCache.update_counter(:a, 2)
      3

      iex> MyCache.update_counter(:a, -1)
      2

      iex> %Nebulex.Object{key: :a, value: 2} =
      ...>   MyCache.update_counter(:a, 0, return: :object)
  """
  @callback update_counter(key, incr :: integer, opts) :: integer

  @doc """
  Returns the total number of cached entries.

  ## Examples

      iex> :ok = Enum.each(1..10, &MyCache.set(&1, &1))
      iex> MyCache.size()
      10

      iex> :ok = Enum.each(1..5, &MyCache.delete(&1))
      iex> MyCache.size()
      5
  """
  @callback size() :: integer

  @doc """
  Flushes the cache.

  ## Examples

      iex> :ok = Enum.each(1..5, &MyCache.set(&1, &1))
      iex> MyCache.flush()
      :ok

      iex> Enum.each(1..5, fn x ->
      ...>   nil = MyCache.get(x)
      ...> end)
  """
  @callback flush() :: :ok

  ## Nebulex.Adapter.Queryable

  @optional_callbacks all: 2, stream: 2

  @doc """
  Fetches all entries from cache matching the given `query`.

  If the `query` is `:all`, it streams all entries from cache; this is common
  for all adapters. However, the `query` may have any other value, which
  depends entirely on the adapter's implementation; check out the "Query"
  section below.

  May raise `Nebulex.QueryError` if query validation fails.

  ## Options

  See the "Shared options" section at the module documentation.

  Note that for this function, option `:version` is ignored.

  ## Example

      # set some entries
      iex> :ok = Enum.each(1..5, &MyCache.set(&1, &1 * 2))

      # fetch all (with default params)
      iex> MyCache.all()
      [1, 2, 3, 4, 5]

      # fetch all entries and return values
      iex> MyCache.all(:all, return: :value)
      [2, 4, 6, 8, 10]

      # fetch all entries and return objects
      iex> [%Nebulex.Object{} | _] = MyCache.all(:all, return: :object)

      # fetch all entries that match with the given query
      # assuming we are using Nebulex.Adapters.Local adapter
      iex> query = [{{:"$1", :"$2", :_, :_}, [{:>, :"$2", 5}], [:"$1"]}]
      iex> MyCache.all(query)
      [3, 4, 5]

  ## Query

  Query spec is defined by the adapter, hence, it is recommended to check out
  adapters documentation. For instance, the built-in `Nebulex.Adapters.Local`
  adapter supports `:all | :all_unexpired | :all_expired | :ets.match_spec()`
  as query value.

  ## Examples

      # additional built-in queries for Nebulex.Adapters.Local adapter
      iex> all_unexpired = MyCache.all(:all_unexpired)
      iex> all_expired = MyCache.all(:all_expired)

      # if we are using Nebulex.Adapters.Local adapter, the stored entry
      # is a tuple {key, value, version, expire_at}, then the match spec
      # could be something like:
      iex> spec = [{{:"$1", :"$2", :_, :_}, [{:>, :"$2", 5}], [{{:"$1", :"$2"}}]}]
      iex> MyCache.all(spec)
      [{3, 6}, {4, 8}, {5, 10}]

      # the same previous query but using Ex2ms
      iex> import Ex2ms
      Ex2ms

      iex> spec =
      ...>   fun do
      ...>     {key, value, _, _} when value > 5 -> {key, value}
      ...>   end

      iex> MyCache.all(spec)
      [{3, 6}, {4, 8}, {5, 10}]

  To learn more, check out adapters documentation.
  """
  @callback all(query :: :all | any, opts) :: [any]

  @doc """
  Similar to `all/2` but returns a lazy enumerable that emits all entries
  from the cache matching the given `query`.

  May raise `Nebulex.QueryError` if query validation fails.

  ## Options

  Besides the "Shared options" section at the module documentation,
  it accepts:

    * `:page_size` - Positive integer (>= 1) that defines the page size for
      the stream (defaults to `10`).

  ## Examples

      # set some entries
      iex> :ok = Enum.each(1..5, &MyCache.set(&1, &1 * 2))

      # stream all (with default params)
      iex> MyCache.stream() |> Enum.to_list()
      [1, 2, 3, 4, 5]

      # stream all entries and return values
      iex> MyCache.stream(:all, return: :value, page_size: 3) |> Enum.to_list()
      [2, 4, 6, 8, 10]

      # stream all entries and return objects
      iex> stream = MyCache.stream(:all, return: :object, page_size: 3)
      iex> [%Nebulex.Object{} | _] = Enum.to_list(stream)

      # additional built-in queries for Nebulex.Adapters.Local adapter
      all_unexpired_stream = MyCache.stream(:all_unexpired)
      all_expired_stream = MyCache.stream(:all_expired)

      # if we are using Nebulex.Adapters.Local adapter, the stored entry
      # is a tuple {key, value, version, expire_at}, then the match spec
      # could be something like:
      iex> spec = [{{:"$1", :"$2", :_, :_}, [{:>, :"$2", 5}], [{{:"$1", :"$2"}}]}]
      iex> MyCache.stream(spec, page_size: 3) |> Enum.to_list()
      [{3, 6}, {4, 8}, {5, 10}]

      # the same previous query but using Ex2ms
      iex> import Ex2ms
      Ex2ms

      iex> spec =
      ...>   fun do
      ...>     {key, value, _, _} when value > 5 -> {key, value}
      ...>   end

      iex> spec |> MyCache.stream(page_size: 3) |> Enum.to_list()
      [{3, 6}, {4, 8}, {5, 10}]

  To learn more, check out adapters documentation.
  """
  @callback stream(query :: :all | any, opts) :: Enum.t()

  ## Nebulex.Adapter.Transaction

  @optional_callbacks transaction: 2, in_transaction?: 0

  @doc """
  Runs the given function inside a transaction.

  A successful transaction returns the value returned by the function.

  ## Options

  See the "Shared options" section at the module documentation.

  ## Examples

      MyCache.transaction fn ->
        alice = MyCache.get(:alice)
        bob = MyCache.get(:bob)
        MyCache.set(:alice, %{alice | balance: alice.balance + 100})
        MyCache.set(:bob, %{bob | balance: bob.balance + 100})
      end

      # locking only the involved key (recommended):
      MyCache.transaction fn ->
        alice = MyCache.get(:alice)
        bob = MyCache.get(:bob)
        MyCache.set(:alice, %{alice | balance: alice.balance + 100})
        MyCache.set(:bob, %{bob | balance: bob.balance + 100})
      end, keys: [:alice, :bob]
  """
  @callback transaction(function :: fun, opts) :: any

  @doc """
  Returns `true` if the current process is inside a transaction.

  ## Examples

      MyCache.in_transaction?
      #=> false

      MyCache.transaction(fn ->
        MyCache.in_transaction? #=> true
      end)
  """
  @callback in_transaction?() :: boolean
end
