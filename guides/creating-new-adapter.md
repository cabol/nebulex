# Creating New Adapter

This guide will walk you through creating a custom Nebulex adapter. We will
start by creating a new project, making tests pass, and then implementing a
simple in-memory adapter. It will be roughly based on
[`NebulexRedisAdapter`](https://github.com/cabol/nebulex_redis_adapter/) so you
can consult this repo as an example.

## Mix Project

Nebulex's main repo contains some very useful shared tests that we are going to
take advantage of. To do so we will need to checkout Nebulex from Github as the
version published to Hex does not contain test code. To accommodate this
workflow we will start by creating a new project.

```console
mix new nebulex_memory_adapter
```

Now let's modify `mix.exs` so that we could fetch Nebulex repository.

```elixir
defmodule NebulexMemoryAdapter.MixProject do
  use Mix.Project

  @nbx_vsn "2.5.2"
  @version "0.1.0"

  def project do
    [
      app: :nebulex_memory_adapter,
      version: @version,
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      nebulex_dep(),
      {:telemetry, "~> 0.4 or ~> 1.0", optional: true}
    ]
  end

  defp nebulex_dep do
    if path = System.get_env("NEBULEX_PATH") do
      {:nebulex, "~> #{@nbx_vsn}", path: path}
    else
      {:nebulex, "~> #{@nbx_vsn}"}
    end
  end

  defp aliases do
    [
      "nbx.setup": [
        "cmd rm -rf nebulex",
        "cmd git clone --depth 1 --branch v#{@nbx_vsn} https://github.com/cabol/nebulex"
      ]
    ]
  end
end
```

As you can see here we define a `mix nbx.setup` task that will fetch a Nebulex
version to a folder specified in `NEBULEX_PATH` environmental variable. Let's
run it.

```console
export NEBULEX_PATH=nebulex
mix nbx.setup
```

Now is the good time to fetch other dependencies

```console
mix deps.get
```

## Tests

Before we start implementing our custom adapter, let's make our tests up and
running.

We start by defining a cache that uses our adapter in
`test/support/test_cache.ex`

```elixir
defmodule NebulexMemoryAdapter.TestCache do
  use Nebulex.Cache,
    otp_app: :nebulex_memory_adapter,
    adapter: NebulexMemoryAdapter
end
```

We won't be writing tests ourselves. Instead, we will use shared tests from the
Nebulex parent repo. To do so, we will create a helper module in
`test/shared/cache_test.exs` that will `use` test suites for behaviour we are
going to implement. The minimal set of behaviours is `Entry` and `Queryable` so
we'll go with them.

```elixir
defmodule NebulexMemoryAdapter.CacheTest do
  @moduledoc """
  Shared Tests
  """

  defmacro __using__(_opts) do
    quote do
      use Nebulex.Cache.EntryTest
      use Nebulex.Cache.QueryableTest
    end
  end
end
```

Let's now edit `test/nebulex_memory_adapter_test.exs` and make it run those
shared tests by calling `use NebulexMemoryAdapter.CacheTest`. We also need to
define a setup that will start our cache process and put the `cache` and `name`
keys into the test context.

```elixir
defmodule NebulexMemoryAdapterTest do
  use ExUnit.Case, async: true
  use NebulexMemoryAdapter.CacheTest

  alias NebulexMemoryAdapter.TestCache, as: Cache

  setup do
    {:ok, pid} = Cache.start_link()
    Cache.delete_all()
    :ok

    on_exit(fn ->
      :ok = Process.sleep(100)
      if Process.alive?(pid), do: Cache.stop(pid)
    end)

    {:ok, cache: Cache, name: Cache}
  end
end
```

Now it's time to grind through failing tests.

```console
mix test
== Compilation error in file test/support/test_cache.ex ==
** (ArgumentError) expected :adapter option given to Nebulex.Cache to list Nebulex.Adapter as a behaviour
    (nebulex 2.4.2) lib/nebulex/cache/supervisor.ex:50: Nebulex.Cache.Supervisor.compile_config/1
    test/support/test_cache.ex:2: (module)
```

Looks like our adapter needs to `Nebulex.Adapter` behaviour. Luckily, it's just
2 callback that we can copy from `Nebulex.Adapters.Nil`

```elixir
# lib/nebulex_memory_adapter.ex
defmodule NebulexMemoryAdapter do
  @behaviour Nebulex.Adapter

  @impl Nebulex.Adapter
  defmacro __before_compile__(_env), do: :ok

  @impl Nebulex.Adapter
  def init(_opts) do
    child_spec = Supervisor.child_spec({Agent, fn -> :ok end}, id: {Agent, 1})
    {:ok, child_spec, %{}}
  end
end
```

Another try

```console
mix test
== Compilation error in file test/nebulex_memory_adapter_test.exs ==
** (CompileError) test/nebulex_memory_adapter_test.exs:3: module Nebulex.Cache.EntryTest is not loaded and could not be found
    (elixir 1.13.2) expanding macro: Kernel.use/1
    test/nebulex_memory_adapter_test.exs:3: NebulexMemoryAdapterTest (module)
    expanding macro: NebulexMemoryAdapter.CacheTest.__using__/1
    test/nebulex_memory_adapter_test.exs:3: NebulexMemoryAdapterTest (module)
    (elixir 1.13.2) expanding macro: Kernel.use/1
    test/nebulex_memory_adapter_test.exs:3: NebulexMemoryAdapterTest (module)
```

Looks like files from Nebulex parent repo aren't automatically compiled. Let's
address this in `test/test_helper.exs`

```elixir
# Nebulex dependency path
nbx_dep_path = Mix.Project.deps_paths()[:nebulex]

for file <- File.ls!("#{nbx_dep_path}/test/support"), file != "test_cache.ex" do
  Code.require_file("#{nbx_dep_path}/test/support/" <> file, __DIR__)
end

for file <- File.ls!("#{nbx_dep_path}/test/shared/cache") do
  Code.require_file("#{nbx_dep_path}/test/shared/cache/" <> file, __DIR__)
end

for file <- File.ls!("#{nbx_dep_path}/test/shared"), file != "cache" do
  Code.require_file("#{nbx_dep_path}/test/shared/" <> file, __DIR__)
end

# Load shared tests
for file <- File.ls!("test/shared"), not File.dir?("test/shared/" <> file) do
  Code.require_file("./shared/" <> file, __DIR__)
end

ExUnit.start()
```

One more attempt

```console
mix test
< ... >
 54) test put_all/2 puts the given entries using different data types at once (NebulexMemoryAdapterTest)
     test/nebulex_memory_adapter_test.exs:128
     ** (UndefinedFunctionError) function NebulexMemoryAdapter.TestCache.delete_all/0 is undefined or private. Did you mean:

           * delete/1
           * delete/2

     stacktrace:
       (nebulex_memory_adapter 0.1.0) NebulexMemoryAdapter.TestCache.delete_all()
       test/nebulex_memory_adapter_test.exs:9: NebulexMemoryAdapterTest.__ex_unit_setup_0/1
       test/nebulex_memory_adapter_test.exs:1: NebulexMemoryAdapterTest.__ex_unit__/2



Finished in 0.2 seconds (0.2s async, 0.00s sync)
54 tests, 54 failures
```

## Implementation

Now that we have our failing tests we can write some implementation. We'll start
by making `delete_all/0` work as it is called in the setup.

```elixir
defmodule NebulexMemoryAdapter do
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.Queryable

  @impl Nebulex.Adapter
  defmacro __before_compile__(_env), do: :ok

  @impl Nebulex.Adapter
  def init(_opts) do
    child_spec = Supervisor.child_spec({Agent, fn -> %{} end}, id: {Agent, 1})
    {:ok, child_spec, %{}}
  end

  @impl Nebulex.Adapter.Queryable
  def execute(adapter_meta, :delete_all, query, opts) do
    deleted = Agent.get(adapter_meta.pid, &map_size/1)
    Agent.update(adapter_meta.pid, fn _state -> %{} end)

    deleted
  end
end
```

Did we make any progress?

```console
mix test
< ... >

 44) test decr/3 decrements a counter by the given amount with default (NebulexMemoryAdapterTest)
     test/nebulex_memory_adapter_test.exs:355
     ** (UndefinedFunctionError) function NebulexMemoryAdapter.update_counter/6 is undefined or private
     stacktrace:
       (nebulex_memory_adapter 0.1.0) NebulexMemoryAdapter.update_counter(%{cache: NebulexMemoryAdapter.TestCache, pid: #PID<0.549.0>}, :counter1, -1, :infinity, 10, [default: 10])
       test/nebulex_memory_adapter_test.exs:356: (test)



Finished in 5.7 seconds (5.7s async, 0.00s sync)
54 tests, 44 failures
```

We certainly did! From here you can continue to implement necessary callbacks
one-by-one or define them all in bulk. For posterity, we put a complete
`NebulexMemoryAdapter` module here that passes all tests.

```elixir
defmodule NebulexMemoryAdapter do
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.Entry
  @behaviour Nebulex.Adapter.Queryable

  @impl Nebulex.Adapter
  defmacro __before_compile__(_env), do: :ok

  @impl Nebulex.Adapter
  def init(_opts) do
    child_spec = Supervisor.child_spec({Agent, fn -> %{} end}, id: {Agent, 1})
    {:ok, child_spec, %{}}
  end

  @impl Nebulex.Adapter.Entry
  def get(adapter_meta, key, _opts) do
    Agent.get(adapter_meta.pid, &Map.get(&1, key))
  end

  @impl Nebulex.Adapter.Entry
  def get_all(adapter_meta, keys, _opts) do
    Agent.get(adapter_meta.pid, &Map.take(&1, keys))
  end

  @impl Nebulex.Adapter.Entry
  def put(adapter_meta, key, value, ttl, :put_new, opts) do
    if get(adapter_meta, key, []) do
      false
    else
      put(adapter_meta, key, value, ttl, :put, opts)
      true
    end
  end

  def put(adapter_meta, key, value, ttl, :replace, opts) do
    if get(adapter_meta, key, []) do
      put(adapter_meta, key, value, ttl, :put, opts)
      true
    else
      false
    end
  end

  def put(adapter_meta, key, value, _ttl, _on_write, _opts) do
    Agent.update(adapter_meta.pid, &Map.put(&1, key, value))
    true
  end

  @impl Nebulex.Adapter.Entry
  def put_all(adapter_meta, entries, ttl, :put_new, opts) do
    if get_all(adapter_meta, Map.keys(entries), []) == %{} do
      put_all(adapter_meta, entries, ttl, :put, opts)
      true
    else
      false
    end
  end

  def put_all(adapter_meta, entries, _ttl, _on_write, _opts) do
    entries = Map.new(entries)
    Agent.update(adapter_meta.pid, &Map.merge(&1, entries))
    true
  end

  @impl Nebulex.Adapter.Entry
  def delete(adapter_meta, key, _opts) do
    Agent.update(adapter_meta.pid, &Map.delete(&1, key))
  end

  @impl Nebulex.Adapter.Entry
  def take(adapter_meta, key, _opts) do
    value = get(adapter_meta, key, [])
    delete(adapter_meta, key, [])
    value
  end

  @impl Nebulex.Adapter.Entry
  def update_counter(adapter_meta, key, amount, _ttl, default, _opts) do
    Agent.update(adapter_meta.pid, fn state ->
      Map.update(state, key, default + amount, fn v -> v + amount end)
    end)

    get(adapter_meta, key, [])
  end

  @impl Nebulex.Adapter.Entry
  def has_key?(adapter_meta, key) do
    Agent.get(adapter_meta.pid, &Map.has_key?(&1, key))
  end

  @impl Nebulex.Adapter.Entry
  def ttl(_adapter_meta, _key) do
    nil
  end

  @impl Nebulex.Adapter.Entry
  def expire(_adapter_meta, _key, _ttl) do
    true
  end

  @impl Nebulex.Adapter.Entry
  def touch(_adapter_meta, _key) do
    true
  end

  @impl Nebulex.Adapter.Queryable
  def execute(adapter_meta, :delete_all, _query, _opts) do
    deleted = execute(adapter_meta, :count_all, nil, [])
    Agent.update(adapter_meta.pid, fn _state -> %{} end)

    deleted
  end

  def execute(adapter_meta, :count_all, _query, _opts) do
    Agent.get(adapter_meta.pid, &map_size/1)
  end

  def execute(adapter_meta, :all, _query, _opts) do
    Agent.get(adapter_meta.pid, &Map.values/1)
  end

  @impl Nebulex.Adapter.Queryable
  def stream(_adapter_meta, :invalid_query, _opts) do
    raise Nebulex.QueryError, message: "foo", query: :invalid_query
  end

  def stream(adapter_meta, _query, opts) do
    fun =
      case Keyword.get(opts, :return) do
        :value ->
          &Map.values/1

        {:key, :value} ->
          &Map.to_list/1

        _ ->
          &Map.keys/1
      end

    Agent.get(adapter_meta.pid, fun)
  end
end
```

Of course, this isn't a useful adapter in any sense but it should be enough to
get you started with your own.