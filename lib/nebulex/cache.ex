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

      :ok = MyCache.set_many([a: 1, c: 3])

      %{a: 1, c: 3} = MyCache.get_many([:a, :b, :c])
  """
  @callback get_many([key], opts) :: map

  @doc """
  Sets the given `value` under `key` into the cache.

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

      :ok = MyCache.set_many(apples: 3, bananas: 1)

      :ok = MyCache.set_many(%{"apples" => 1, "bananas" => 3})

      # set a custom list of objects
      :ok =
        MyCache.set_many([
          %Nebulex.Object{key: :apples, value: 1},
          %Nebulex.Object{key: :bananas, value: 2, expire_at: 5}
        ])

      # for some reason `:c` couldn't be set, so we got an error
      {:error, [:c]} = MyCache.set_many([a: 1, b: 2, c: 3], ttl: 1000)
  """
  @callback set_many(entries, opts) :: :ok | {:error, failed_keys :: [key]}

  @doc """
  Sets the given `value` under `key` into the cache, only if it does not
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
  Alters the entry stored under `key` into the cache, but only if the entry
  already exists into the cache. All attributes of the cached object can be
  updated, either the value if `value` is different than `nil`, or the expiry
  time if option `:ttl` is set in `opts`. The version is always regenerated.

  If cache contains the given `key`, then `{:ok, value}` is returned.
  If cache doesn't contain `key`, `:error` is returned.

  In the case the cached object is returned, and `:ttl` option is not set,
  then the contained `expire_at` might not be the current one, since it
  is not being modified, but this depends on the adapter.

  ## Options

  Besides the "Shared options" section at the module documentation,
  it accepts:

    * `:on_conflict` - Same as callback `set/3`.

  ## Example

      :error = MyCache.replace("foo", "bar")

      "bar" = MyCache.set("foo", "bar")

      # update only current value
      {:ok, "bar"} = MyCache.replace("foo", "bar")

      # update current value and TTL
      {:ok, "bar"} = MyCache.replace("foo", "bar", ttl: 10)

      # update only the TTL
      {:ok, nil} = MyCache.replace("foo", nil, ttl: 30)
  """
  @callback replace(key, value, opts) :: {:ok, return} | :error

  @doc """
  Similar to `replace/3` but raises `KeyError` if `key` is not found.

  ## Options

  Besides the "Shared options" section at the module documentation,
  it accepts:

    * `:on_conflict` - Same as callback `set/3`.

  ## Example

      MyCache.set("foo", "bar")

      MyCache.replace!("foo", "bar")

      "bar" =
        "foo"
        |> MyCache.replace(nil, ttl: 30, return: :key)
        |> MyCache.get!()
  """
  @callback replace!(key, value, opts) :: return | no_return

  @doc """
  When the `key` already exists, the cached value is replaced by `value`,
  otherwise the entry is created at fisrt time.

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
  @callback delete(key, opts) :: return | nil

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
      {"hello", %Object{key: :a, value: "hello world"}} =
        :a
        |> MyCache.set!("hello", return: :key)
        |> MyCache.get_and_update(fn current_value ->
          {current_value, "hello world"}
        end, return: :object)
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

      1 = MyCache.update(:a, 1, &(&1 * 2))

      2 = MyCache.update(:a, 1, &(&1 * 2))

      %Nebulex.Object{value: 4} =
        MyCache.update(:a, 1, &(&1 * 2), return: :object)
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

      1 = MyCache.update_counter(:a)

      3 = MyCache.update_counter(:a, 2)

      2 = MyCache.update_counter(:a, -1)

      %Nebulex.Object{key: :a, value: 2} =
        MyCache.update_counter(:a, 0, return: :object)
  """
  @callback update_counter(key, incr :: integer, opts) :: integer

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

      # fetch all (with default params)
      MyCache.all()

      # fetch all entries and return values
      MyCache.all(:all, return: :value)

      # fetch all entries and return objects
      MyCache.all(:all, return: :object)

      # fetch all entries that match with the given query
      MyCache.all(myquery)

  ## Query

  Query spec is defined by the adapter, hence, it is recommended to check out
  adapters documentation. For instance, the built-in `Nebulex.Adapters.Local`
  adapter supports `:all | :all_unexpired | :all_expired | :ets.match_spec()`
  as query value.

  ## Examples

      # additional built-in queries for Nebulex.Adapters.Local adapter
      MyCache.all(:all_unexpired)
      MyCache.all(:all_expired)

      # if we are using Nebulex.Adapters.Local adapter, the stored entry
      # is a tuple {key, value, version, expire_at}, then the match spec
      # could be something like:
      spec = [{{:"$1", :"$2", :_, :_}, [{:>, :"$2", 10}], [{{:"$1", :"$2"}}]}]
      MyCache.all(spec)

      # using Ex2ms
      import Ex2ms

      spec =
        fun do
          {key, value, _, _} when value > 10 -> {key, value}
        end

      MyCache.all(spec)

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

      # stream all (with default params)
      MyCache.stream()

      # stream all entries and return values
      MyCache.stream(:all, return: :value, page_size: 3)

      # stream all entries and return objects
      MyCache.stream(:all, return: :object, page_size: 3)

      # stream all entries that match with the given query
      MyCache.stream(myquery, page_size: 3)

      # additional built-in queries for Nebulex.Adapters.Local adapter
      MyCache.stream(:all_unexpired)
      MyCache.stream(:all_expired)

      # if we are using Nebulex.Adapters.Local adapter, the stored entry
      # is a tuple {key, value, version, expire_at}, then the match spec
      # could be something like:
      spec = [{{:"$1", :"$2", :_, :_}, [{:>, :"$2", 10}], [{{:"$1", :"$2"}}]}]
      MyCache.stream(spec, page_size: 3)

      # using Ex2ms
      import Ex2ms

      spec =
        fun do
          {key, value, _, _} when value > 10 -> {key, value}
        end

      MyCache.stream(spec, page_size: 3)

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
