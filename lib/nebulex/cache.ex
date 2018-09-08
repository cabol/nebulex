defmodule Nebulex.Cache do
  @moduledoc """
  Cache Main Interface.

  A Cache maps to an underlying implementation, controlled by the
  adapter. For example, Nebulex ships with a default adapter that
  implements a local generational cache.

  When used, the Cache expects the `:otp_app` as option.
  The `:otp_app` should point to an OTP application that has
  the Cache configuration. For example, the Cache:

      defmodule MyCache do
        use Nebulex.Cache, otp_app: :my_app
      end

  Could be configured with:

      config :my_app, MyCache,
        adapter: Nebulex.Adapters.Local,
        n_shards: 2

  Most of the configuration that goes into the `config` is specific
  to the adapter, so check `Nebulex.Adapters.Local` documentation
  for more information. However, some configuration is shared across
  all adapters, they are:

    * `:adapter` - a compile-time option that specifies the adapter itself.
      As a compile-time option, it may also be given as an option to
      `use Nebulex.Cache`.

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

    * `:return` - Selects return type. When `:value` (the default), returns
      the object `value`. When `:object`, returns the `Nebulex.Object.t()`.

    * `:version` - The version of the object on which the operation will
      take place. The version can be any term (default: `nil`).

    * `:ttl` - Time To Live (TTL) or expiration time in seconds for a key
      (default: `:infinity`) – applies only to `set/3`.

  Such cases will be explicitly documented as well as any extra option.

  ## Extended API

  Some adapters might extend the API with additional functions, therefore,
  it is important to review the adapters documentation.
  """

  @type t :: module

  @typedoc "Cache object"
  @type object :: Nebulex.Object.t()

  @typedoc "Object key"
  @type key :: any

  @typedoc "Object value"
  @type value :: any

  @typedoc "Cache entries"
  @type entries :: map | [{key, value}]

  @typedoc "Cache action options"
  @type opts :: Keyword.t()

  @typedoc "Return alternatives (value is the default)"
  @type return :: key | value | object

  @typedoc "Reduce callabck function"
  @type reducer :: (object, acc_in :: any -> acc_out :: any)

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Nebulex.Cache
      @behaviour Nebulex.Hook

      alias Nebulex.Cache.{Bucket, Stats}
      alias Nebulex.Hook

      {otp_app, adapter, behaviours, config} =
        Nebulex.Cache.Supervisor.compile_config(__MODULE__, opts)

      @otp_app otp_app
      @adapter adapter
      @config config
      @version_generator Keyword.get(config, :version_generator)
      @before_compile adapter

      ## Config and metadata

      @doc false
      def config do
        {:ok, config} = Nebulex.Cache.Supervisor.runtime_config(__MODULE__, @otp_app, [])
        config
      end

      @doc false
      def __adapter__, do: @adapter

      @doc false
      def __version_generator__, do: @version_generator

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
      def set(key, value, opts \\ []) do
        with_hooks(Nebulex.Cache.Object, :set, [key, value, opts])
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
        Bucket.size(__MODULE__)
      end

      @doc false
      def flush do
        Bucket.flush(__MODULE__)
      end

      @doc false
      def keys(opts \\ []) do
        Bucket.keys(__MODULE__, opts)
      end

      ## Multi

      if Nebulex.Adapter.Multi in behaviours do
        @doc false
        def mget(keys, opts \\ []) do
          with_hooks(Nebulex.Cache.Multi, :mget, [keys, opts])
        end

        @doc false
        def mset(objects, opts \\ []) do
          with_hooks(Nebulex.Cache.Multi, :mset, [objects, opts])
        end
      end

      ## Lists

      if Nebulex.Adapter.List in behaviours do
        @doc false
        def lpush(key, value, opts \\ []) do
          with_hooks(Nebulex.Cache.List, :lpush, [key, value, opts])
        end

        @doc false
        def rpush(key, value, opts \\ []) do
          with_hooks(Nebulex.Cache.List, :rpush, [key, value, opts])
        end

        @doc false
        def lpop(key, opts \\ []) do
          with_hooks(Nebulex.Cache.List, :lpop, [key, opts])
        end

        @doc false
        def rpop(key, opts \\ []) do
          with_hooks(Nebulex.Cache.List, :rpop, [key, opts])
        end

        @doc false
        def lrange(key, offset, limit, opts \\ []) do
          with_hooks(Nebulex.Cache.List, :lrange, [key, offset, limit, opts])
        end
      end

      ## Transactions

      if Nebulex.Adapter.Transaction in behaviours do
        @doc false
        def transaction(fun, opts \\ []) do
          Nebulex.Cache.Transaction.transaction(__MODULE__, fun, opts)
        end

        @doc false
        def in_transaction? do
          Nebulex.Cache.Transaction.in_transaction?(__MODULE__)
        end
      end

      ## Hooks

      @doc false
      def pre_hooks, do: {:async, []}

      @doc false
      def post_hooks, do: {:async, []}

      defoverridable pre_hooks: 0, post_hooks: 0

      ## Helpers

      defp with_hooks(wrapper, action, args) do
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

  @optional_callbacks [
    init: 1,
    mget: 2,
    mset: 2,
    lpush: 3,
    rpush: 3,
    lpop: 2,
    rpop: 2,
    lrange: 4,
    transaction: 2,
    in_transaction?: 0
  ]

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

    * `:on_conflict` - It may be one of `:error` (the default), `:nothing`,
      `nil`. See the "OnConflict" section for more information.

  ## Example

      "some value" =
        :a
        |> MyCache.set("some value", return: :key)
        |> MyCache.get()

      nil = MyCache.get(:non_existent_key)

  ## OnConflict

  The `:on_conflict` option supports the following values:

    * `:raise` - raises if there is a conflicting key
    * `:nothing` - ignores the error in case of conflicts
    * `:override` - same effect as `:nothing`

  ## Examples

      # Set a value
      1 = MyCache.set(:a, 1)

      # Gets with an invalid version but do nothing on conflicts.
      # Keep in mind that, although this returns successfully, the returned
      # struct does not reflect the data in the Cache. For instance, in case
      # of "on_conflict: :nothing", it returns the latest version of the
      # cached object.
      %Nebulex.Object{key: :a, value: 1} =
        MyCache.get(:a, return: :object, version: :invalid, on_conflict: :nothing)
      1 = MyCache.get(:a)
  """
  @callback get(key, opts) :: nil | return | no_return

  @doc """
  Similar to `get/2` but raises `KeyError` if `key` is not found.

  ## Options

  See the "Shared options" section at the module documentation.

  ## Example

      MyCache.get!(:a)
  """
  @callback get!(key, opts) :: return | no_return

  @doc """
  Sets the given `value` under `key` in the Cache.

  Returns the inserted `value` if the action is completed successfully.
  It is also possible to return the key or the object itself,
  depending on `:return` option.

  If `value` is `nil`, action is skipped and `nil` is returned instead.

  ## Options

  Besides the "Shared options" section at the module documentation,
  it accepts:

    * `:on_conflict` - It may be one of `:raise` (the default), `:nothing`,
      `:override`. See the "OnConflict" section for more information.

  ## Example

      "bar" = MyCache.set("foo", "bar")

      %Nebulex.Object{key: "foo"} =
        MyCache.set("foo", "bar", ttl: 100000, return: :object)

      # if the value is nil, then it is not stored (operation is skipped)
      nil = MyCache.set("foo", nil)

  ## OnConflict

  The `:on_conflict` option supports the following values:

    * `:raise` - raises if there is a conflicting key
    * `:nothing` - ignores the error in case of conflicts
    * `:override` - the command is executed ignoring the conflict, then
      the value on the existing key is replaced with the given `value`

  ## Examples

      # Set twice
      %Nebulex.Object{key: :a, version: v1} =
        MyCache.set(:a, 1, return: :object)

      %Nebulex.Object{key: :a, version: v2}
        MyCache.set(:a, 2, return: :object, version: v1)

      # Set with the same key and wrong version but do nothing on conflicts.
      # Keep in mind that, although this returns successfully, the returned
      # struct does not reflect the data in the Cache. For instance, in case
      # of "on_conflict: :nothing", the returned object isn't set.
      %Nebulex.Object{key: :a, value: 2} =
        MyCache.set(:a, 3, return: :object, version: v1, on_conflict: :nothing)
      2 = MyCache.get(:a)

      # Set with the same key and wrong version but replace the current
      # value on conflicts.
      3 = MyCache.set(:a, 3, version: v1, on_conflict: :override)
      3 = MyCache.get(:a)
  """
  @callback set(key, value, opts) :: return | no_return

  @doc """
  Stores the given `value` under `key` in the Cache, only if it does not
  already exist.

  If cache doesn't contain the given `key`, then `{:ok, value}` is returned.
  If cache contains `key`, `:error` is returned.

  If `value` is `nil`, then it is not cached and `nil` is returned instead.

  ## Options

  See the "Shared options" section at the module documentation.

  For `add` operation, the option `:version` is ignored.

  ## Example

      {ok, "bar"} = MyCache.add("foo", "bar")

      :error = MyCache.add("foo", "bar")

      # if the value is nil, it is not stored (operation is skipped)
      {ok, nil} = MyCache.add("foo", nil)
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
  Alters the value stored under `key` to `value`, but only if the entry `key`
  already exists in the cache.

  If cache contains the given `key`, then `{:ok, value}` is returned.
  If cache doesn't contain `key`, `:error` is returned.

  This action only updates the `value` and version of the cached object,
  `ttl` is not altered. Therefore, if we return the cached object, the
  contained `ttl` might not be the remaining one (it might be `nil`),
  but this depends on the adapter.

  ## Options

  Besides the "Shared options" section at the module documentation,
  it accepts:

    * `:on_conflict` - Same as callback `set/3`.

  ## Example

      :error = MyCache.replace("foo", "bar")

      "bar" = MyCache.set("foo", "bar")

      {:ok, "bar"} = MyCache.replace("foo", "bar")
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

      nil =
        :a
        |> MyCache.set(1, return: :key)
        |> MyCache.delete()
        |> MyCache.get()

      :non_existent_key = MyCache.delete(:non_existent_key)

  ## OnConflict

  The `:on_conflict` option supports the following values:

    * `:raise` - raises if there is a conflicting key
    * `:nothing` - ignores the error in case of conflicts
    * `:override` - the command is executed ignoring the conflict, then
      the value on the existing key is deleted

  ## Examples

      # Set a value
      1 = MyCache.set(:a, 1)

      # Delete with an invalid version but do nothing on conflicts.
      # Keep in mind that, although this returns successfully, the returned
      # `kwy` does not reflect the data in the Cache. For instance, in case
      # of "on_conflict: :nothing", the returned `key` isn't deleted.
      :a = MyCache.delete(:a, version: :invalid, on_conflict: :nothing)
      1 = MyCache.get(:a)

      # Delete with the same invalid version but force to delete the current
      # value on conflicts (if exist).
      :a = MyCache.delete(:a, version: :invalid, on_conflict: :override)
      nil = MyCache.get(:a)
  """
  @callback delete(key, opts) :: return | no_return

  @doc """
  Returns and removes the object with key `key` in the cache.

  Returns `nil` if no result was found.

  ## Options

  Besides the "Shared options" section at the module documentation,
  it accepts:

    * `:on_conflict` - Same as callback `set/3`.

  ## Examples

      1 = MyCache.set(:a, 1)

      1 = MyCache.take(:a)
      nil = MyCache.take(:a)

      %Nebulex.Object{key: :a, value: 1} =
        :a
        |> MyCache.set(1, return: :key)
        |> MyCache.take(return: :object)
  """
  @callback take(key, opts) :: nil | return | no_return

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

      1 = MyCache.set(:a, 1)

      true = MyCache.has_key?(:a)

      false = MyCache.has_key?(:b)
  """
  @callback has_key?(key) :: boolean

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
      {nil, "value!"} =
        MyCache.get_and_update(:a, fn current_value ->
          {current_value, "value!"}
        end)

      # update existing key
      {"value!", "new value!"} =
        MyCache.get_and_update(:a, fn current_value ->
          {current_value, "new value!"}
        end)

      # pop/remove value if exist
      {"new value!", nil} = MyCache.get_and_update(:a, fn _ -> :pop end)

      # pop/remove nonexistent key
      {nil, nil} = MyCache.get_and_update(:b, fn _ -> :pop end)

      # update existing key but returning the object
      {"hello", %Object{key: :a, value: "hello world", ttl: _, version: _}} =
        :a
        |> MyCache.set!("hello", return: :key)
        |> MyCache.get_and_update(fn current_value ->
          {current_value, "hello world"}
        end, return: :object)
  """
  @callback get_and_update(key, (value -> {get, update} | :pop), opts) ::
              {get, update} | no_return
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

      1 = MyCache.update(:a, 1, &(&1 * 2))

      2 = MyCache.update(:a, 1, &(&1 * 2))

      %Nebulex.Object{value: 4} =
        MyCache.update(:a, 1, &(&1 * 2), return: :object)
  """
  @callback update(key, initial :: value, (value -> value), opts) :: return | no_return

  @doc """
  Updates (increment or decrement) the counter mapped to the given `key`.

  If `incr >= 0` then the current value is incremented by that amount,
  otherwise the current value is decremented.

  If `incr` is not a valid integer, then an `ArgumentError` exception
  is raised.

  ## Options

  See the "Shared options" section at the module documentation.

  For this command, the option `:version` is ignored.

  ## Examples

      1 = MyCache.update_counter(:a)

      3 = MyCache.update_counter(:a, 2)

      2 = MyCache.update_counter(:a, -1)

      %Nebulex.Object{key: :a, value: 2} =
        MyCache.update_counter(:a, 0, return: :object)
  """
  @callback update_counter(key, incr :: integer, opts) :: integer | no_return

  @doc """
  Returns the total number of cached entries.

  ## Examples

      for x <- 1..10, do: MyCache.set(x, x)

      10 = MyCache.size()

      for x <- 1..5, do: MyCache.delete(x)

      5 = MyCache.size()
  """
  @callback size() :: integer

  @doc """
  Flushes the cache.

  ## Examples

      for x <- 1..5, do: MyCache.set(x, x)

      :ok = MyCache.flush()

      for x <- 1..5, do: nil = MyCache.get(x)
  """
  @callback flush() :: :ok | no_return

  @doc """
  Returns all cached keys.

  ## Options

  See adapters documentation. For example, in `Nebulex.Adapters.Dist`
  adapter, it is possible to pass `:timeout` option.

  ## Examples

      for x <- 1..3, do: MyCache.set(x, x*2, return: :key)

      [1, 2, 3] = MyCache.keys()

  **WARNING:** This is an expensive operation, beware of using it in prod.
  """
  @callback keys(opts) :: [key]

  @doc """
  Returns a map with the values or objects (check `:return` option) for all
  specified keys. For every key that does not hold a value or does not exist,
  that key is simply ignored. Because of this, the operation never fails.

  ## Options

  See the "Shared options" section at the module documentation.

  For bulk operations like `mget`, the option `:version` is ignored.

  ## Example

      :ok = MyCache.mset([a: 1, c: 3])

      %{a: 1, c: 3} = MyCache.mget([:a, :b, :c])
  """
  @callback mget([key], opts) :: map

  @doc """
  Sets the given `entries`, replacing existing ones, just as regular `set`.

  Returns `:ok` if the all the objects were successfully set, otherwise
  `{:error, failed_keys}`, where `failed_keys` contains the keys that
  could not be set.

  Ideally, this operation should be atomic, so all given keys are set at once.
  But it depends purely on the adapter's implementation and the backed used
  internally by this adapter. Hence, it is recommended to checkout the
  adapter's documentation.

  ## Options

  See the "Shared options" section at the module documentation.

  For bulk operations like `mset`, the option `:version` is ignored.

  ## Example

      :ok = MyCache.mset(%{"apples" => 1, "bananas" => 3})

      {:error, [:a, :b]} = MyCache.mset([a: 1, b: 2, c: 3], ttl: 1000)
  """
  @callback mset(entries, opts) :: :ok | {:error, failed_keys :: [key]}

  @doc """
  Insert all the specified values at the head of the list stored at `key`.
  If `key` does not exist, it is created as empty list before performing
  the push operations. When key holds a value that is not a list, an error
  is raised.

  Elements are inserted one after the other to the head of the list, from
  the leftmost element to the rightmost element. So for instance the command
  `lpush(:mykey, [1, 2, 3])` will result into a list containing 3 as first
  element, 2 as second element and 1 as third element.

  Returns the length of the list after the push operations.

  ## Options

  See the "Shared options" section at the module documentation.

  ## Example

      3 = MyCache.lpush(:mykey, [1, 2, 3])
      4 = MyCache.lpush(:mykey, ["654"])

      ["654", 3, 2, 1] = MyCache.get(:mykey)
  """
  @callback lpush(key, elements :: [value], opts) :: integer | no_return

  @doc """
  Insert all the specified values at the tail of the list stored at `key`.
  If key does not exist, it is created as empty list before performing
  the push operation. When key holds a value that is not a list, an error
  is raised.

  Elements are inserted one after the other to the tail of the list, from
  the leftmost element to the rightmost element. So for instance the command
  `rpush(:mykey, [1, 2, 3])` will result into a list containing 1 as first
  element, 2 as second element and 3 as third element.

  Returns the length of the list after the push operations.

  ## Options

  See the "Shared options" section at the module documentation.

  ## Example

      3 = MyCache.rpush(:mykey, [1, 2, 3])
      4 = MyCache.rpush(:mykey, ["456"])

      [1, 2, 3, "456"] = MyCache.get(:mykey)
  """
  @callback rpush(key, elements :: [value], opts) :: integer | no_return

  @doc """
  Removes and returns the first element of the list stored at `key`, or `nil`
  when key does not exist.

  ## Options

  See the "Shared options" section at the module documentation.

  ## Example

      2 = MyCache.lpush(:mykey, ["foo", "bar"])

      "bar" = MyCache.lpop(:mykey)
  """
  @callback lpop(key, opts) :: nil | value | no_return

  @doc """
  Removes and returns the last element of the list stored at `key`, or `nil`
  when key does not exist.

  ## Options

  See the "Shared options" section at the module documentation.

  ## Example

      2 = MyCache.rpush(:mykey, ["foo", "bar"])

      "bar" = MyCache.rpop(:mykey)
  """
  @callback rpop(key, opts) :: nil | value | no_return

  @doc """
  Returns the specified elements of the list stored at `key`. The `offset`
  is an integer >= 1 and the `limit` an integer >= 0.

  ## Options

  See the "Shared options" section at the module documentation.

  ## Example

      5 = MyCache.rpush(:mykey, [5, 4, 3, 2, 1])

      [2, 3, 4] = MyCache.lrange(:mykey, 2, 3)

      [2, 3, 4, 5] = MyCache.lrange(:mykey, 2, 5)

      [] = MyCache.lrange(:mykey, 6, 3)
  """
  @callback lrange(key, offset :: pos_integer, limit :: non_neg_integer, opts) ::
              [value] | no_return

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
