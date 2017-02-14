defmodule Nebulex.Cache do
  @moduledoc """
  Cache Main Interface.

  A Cache maps to an underlying implementation, controlled by the
  adapter. For example, Nebulex ships with a defaukt adapter that
  implements a Generational Cache.

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

    * `:adapter` - a compile-time option that specifies the adapter

    * `:version_generator` - this option specifies the module that
      implements the `Nebulex.Version` interface. This interface
      defines only one callback `generate/1` that is invoked by
      the adapters to generate new object versions. If this option
      is not set, the default will be: `Nebulex.Version.Default`.

  ## Shared options

  Almost all of the Cache operations below accept the following options:

    * `:return` - selects return type. When `:value` (the default), returns
      the object `value`. When `:object`, returns the `Nebulex.Object.t`.
    * `:version` - The version of the object on which the operation will
      take place. The version can be any term (default: `nil`).
    * `:ttl` - Time To Live (TTL) or expiration time in milliseconds
      for a key (default: `:infinity`) – applies to write operations.

  Such cases will be explicitly documented as well as any extra option.

  ## Extended API

  Some adapters might extend the API with additional functions, therefore,
  it is important to review the adapters documentation.
  """

  @type t      :: module
  @type key    :: any
  @type value  :: any
  @type object :: Nebulex.Object.t
  @type opts   :: Keyword.t
  @type return :: key | value | object

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Nebulex.Cache

      {otp_app, adapter, config} = Nebulex.Cache.Supervisor.compile_config(__MODULE__, opts)
      @otp_app otp_app
      @adapter adapter
      @config config
      @before_compile adapter

      def __adapter__ do
        @adapter
      end

      def config do
        {:ok, config} = Nebulex.Cache.Supervisor.runtime_config(__MODULE__, @otp_app, [])
        config
      end

      def start_link(opts \\ []) do
        Nebulex.Cache.Supervisor.start_link(__MODULE__, @otp_app, @adapter, opts)
      end

      def stop(pid, timeout \\ 5000) do
        Supervisor.stop(pid, :normal, timeout)
      end

      def get(key, opts \\ []) do
        @adapter.get(__MODULE__, key, opts)
      end

      def get!(key, opts \\ []) do
        case get(key, opts) do
          nil -> raise KeyError, key: key, term: __MODULE__
          val -> val
        end
      end

      def set(key, value, opts \\ []) do
        @adapter.set(__MODULE__, key, value, opts)
      end

      def delete(key, opts \\ []) do
        @adapter.delete(__MODULE__, key, opts)
      end

      def has_key?(key) do
        @adapter.has_key?(__MODULE__, key)
      end

      def pop(key, opts \\ []) do
        @adapter.pop(__MODULE__, key, opts)
      end

      def get_and_update(key, fun, opts \\ []) do
        @adapter.get_and_update(__MODULE__, key, fun, opts)
      end

      def update(key, initial, fun, opts \\ []) do
        @adapter.update(__MODULE__, key, initial, fun, opts)
      end

      def transaction(key \\ nil, fun) do
        @adapter.transaction(__MODULE__, key, fun)
      end
    end
  end

  @optional_callbacks [init: 1]

  @doc """
  Returns the adapter tied to the cache.
  """
  @callback __adapter__ :: Nebulex.Adapter.t

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
            {:ok, pid} | {:error, {:already_started, pid}} | {:error, term}

  @doc """
  A callback executed when the cache starts or when configuration is read.
  """
  @callback init(config :: Keyword.t) :: {:ok, Keyword.t} | :ignore

  @doc """
  Shuts down the cache represented by the given pid.
  """
  @callback stop(pid, timeout) :: :ok

  @doc """
  Fetches a value or object from Cache where the key matches the
  given `key`.

  Returns `nil` if no result was found.

  ## Options

    * `:on_conflict` - It may be one of `:raise` (the default), `:nothing`,
      `nil`. See the "OnConflict" section for more information.

  See the "Shared options" section at the module documentation.

  ## Example

      "some value" = :a
      |> MyCache.set("some value", return: :key)
      |> MyCache.get

      nil = MyCache.get :non_existent_key

  ## OnConflict

  The `:on_conflict` option supports the following values:

    * `:raise` - raises if there is a conflicting key
    * `:nothing` - ignores the error in case of conflicts
    * `nil` - forces to return `nil`

  ## Examples

      # Set a value
      1 = MyCache.set :a, 1

      # Gets with an invalid version but do nothing on conflicts.
      # Keep in mind that, although this returns successfully, the returned
      # struct does not reflect the data in the Cache. For instance, in case
      # of "on_conflict: :nothing", it returns the latest version of the
      # cached object.
      %Nebulex.Object{key: :a, value: 1} =
        MyCache.get :a, return: :object, version: :invalid, on_conflict: :nothing
      1 = MyCache.get :a

      # Gets with the same invalid version but force to return `nil`
      nil = MyCache.get :a, version: :invalid, on_conflict: nil
      1 = MyCache.get :a
  """
  @callback get(key, opts) :: nil | return | no_return

  @doc """
  Similar to `get/2` but raises `KeyError` if no value associated with the
  given `key` was found.

  ## Options

  See the "Shared options" section at the module documentation.

  ## Example

      MyCache.get!(:a)
  """
  @callback get!(key, opts) :: return | no_return

  @doc """
  Sets the given `value` under `key` in the Cache.

  It returns `value` or `Nebulex.Object.t` (depends on `:return` option)
  if the value has been successfully inserted.

  ## Options

    * `:on_conflict` - It may be one of `:raise` (the default), `:nothing`,
      `:replace`. See the "OnConflict" section for more information.

  See the "Shared options" section at the module documentation.

  ## Example

      %Nebulex.Object{key: :a} =
        MyCache.set :a, "anything", ttl: 100000, return: :object

  ## OnConflict

  The `:on_conflict` option supports the following values:

    * `:raise` - raises if there is a conflicting key
    * `:nothing` - ignores the error in case of conflicts
    * `:replace` - replace the value on the existing key with
      the given `value`

  ## Examples

      # Set twice
      %Nebulex.Object{key: :a, version: v1} = MyCache.set :a, 1, return: :object
      %Nebulex.Object{key: :a, version: v2}
        MyCache.set :a, 2, return: :object, version: v1

      # Set with the same key and wrong version but do nothing on conflicts.
      # Keep in mind that, although this returns successfully, the returned
      # struct does not reflect the data in the Cache. For instance, in case
      # of "on_conflict: :nothing", the returned object isn't set.
      %Nebulex.Object{key: :a, value: 2} =
        MyCache.set :a, 3, return: :object, version: v1, on_conflict: :nothing
      2 = MyCache.get :a

      # Set with the same key and wrong version but replace the current
      # value on conflicts.
      3 = MyCache.set :a, 3, version: v1, on_conflict: :replace
      3 = MyCache.get :a
  """
  @callback set(key, value, opts) :: return | no_return

  @doc """
  Deletes the cached entry in for a specific `key`.

  It returns `value` or `Nebulex.Object.t` (depends on `:return` option)
  if the value has been successfully deleted. If `:version` option
  is not provided, then the object value will be `nil`.

  ## Options

    * `:on_conflict` - It may be one of `:raise` (the default), `:nothing`,
      `:delete`. See the "OnConflict" section for more information.

  See the "Shared options" section at the module documentation.

  ## Example

      %Nebulex.Object{key: :a, value: nil} = :a
      |> MyCache.set(1, return: :key)
      |> MyCache.delete(return: :object)
      nil = MyCache.get :a

      nil = MyCache.delete :non_existent_key

      # If version option is not provided, then the value will be nil
      1 = MyCache.set :a, 1
      nil = MyCache.delete :a

  ## OnConflict

  The `:on_conflict` option supports the following values:

    * `:raise` - raises if there is a conflicting key
    * `:nothing` - ignores the error in case of conflicts
    * `:delete` - deletes the value on the existing key

  ## Examples

      # Set a value
      1 = MyCache.set :a, 1

      # Delete with an invalid version but do nothing on conflicts.
      # Keep in mind that, although this returns successfully, the returned
      # struct does not reflect the data in the Cache. For instance, in case
      # of "on_conflict: :nothing", the returned object isn't deleted.
      %Nebulex.Object{key: :a, value: 1} =
        MyCache.delete :a, return: :object, version: :invalid, on_conflict: :nothing
      1 = MyCache.get :a

      # Delete with the same invalid version but force to delete the current
      # value on conflicts (if it exist).
      1 = MyCache.delete :a, version: :invalid, on_conflict: :delete
      nil = MyCache.get :a
  """
  @callback delete(key, opts) :: return | no_return

  @doc """
  Returns whether the given `key` exists in Cache.

  ## Examples

      1 = MyCache.set(:a, 1)

      true = MyCache.has_key?(:a)

      false = MyCache.has_key?(:b)
  """
  @callback has_key?(key) :: boolean

  @doc """
  Returns and removes the value/object associated with `key` in Cache.

  Returns `nil` if no result was found.

  ## Options

    * `:on_conflict` - same as callback `get/2`.

  See the "Shared options" section at the module documentation.

  ## Examples

      1 = MyCache.set(:a, 1)

      1 = MyCache.pop(:a)
      nil = MyCache.pop(:b)

      %Nebulex.Object{key: :a, value: 1} =
        :a |> MyCache.set(1, return: :key) |> MyCache.pop(return: :object)
  """
  @callback pop(key, opts) :: return | no_return

  @doc """
  Gets the value from `key` and updates it, all in one pass.

  `fun` is called with the current cached value under `key` (or `nil`
  if `key` hasn't been cached) and must return a two-element tuple:
  the "get" value (the retrieved value, which can be operated on before
  being returned) and the new value to be stored under `key`. `fun` may
  also return `:pop`, which means the current value shall be removed
  from Cache and returned.

  The returned value is a tuple with the "get" value returned by
  `fun` and the new updated value under `key`.

  ## Options

    * `:on_conflict` - same as callback `get/2`.

  Note that for this function `:return` option hasn't any effect,
  since it always returns a tuple `{get :: value, update :: value}`
  in case of success.

  See the "Shared options" section at the module documentation.

  ## Examples

      # update a nonexistent key
      {nil, "value!"} = MyCache.get_and_update(:a, fn current_value ->
        {current_value, "value!"}
      end)

      # update a existent key
      {"value!", "new value!"} = MyCache.get_and_update(:a, fn current_value ->
        {current_value, "new value!"}
      end)

      # pop/remove value if it exists
      {"new value!", nil} = MyCache.get_and_update(:a, fn _ -> :pop end)

      # pop/remove a nonexistent key
      {nil, nil} = MyCache.get_and_update(:b, fn _ -> :pop end)
  """
  @callback get_and_update(key, (value -> {get, update} | :pop), opts) ::
            no_return | {get, update} when get: value, update: value

  @doc """
  Updates the cached `key` with the given function.

  If `key` is present in Cache with value `value`, `fun` is invoked with
  argument `value` and its result is used as the new value of `key`.

  If `key` is not present in Cache, `initial` is inserted as the value
  of `key`.

  ## Options

    * `:on_conflict` - same as callback `get/2`.

  Note that for this function `:return` option hasn't any effect,
  since it always returns the object value.

  See the "Shared options" section at the module documentation.

  ## Examples

      1 = MyCache.update(:a, 1, &(&1 * 2))

      2 = MyCache.update(:a, 1, &(&1 * 2))
  """
  @callback update(key, initial :: value, (value -> value), opts) :: value | no_return

  @doc """
  Sets a lock on the caller Cache and `key`. If this succeeds, `fun` is
  evaluated and the result is returned.

  If `key` is not provided, it is set to `nil` by default.

  ## Examples

      1 = MyCache.transaction fn ->
        1 = MyCache.set(:a, 1)
        true = MyCache.has_key?(:a)
        MyCache.get(:a)
      end

      :ok = MyCache.transaction :a, fn ->
        1 = MyCache.set(:a, 1)
        true = MyCache.has_key?(:a)
        false = MyCache.has_key?(:b)
        :ok
      end
  """
  @callback transaction(key, (... -> any)) :: any
end
