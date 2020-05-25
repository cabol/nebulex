## Benchmarks

# nodes = [:"node1@127.0.0.1", :"node2@127.0.0.1"]
# Nebulex.Cluster.spawn(nodes)

# alias Nebulex.NodeCase
alias Nebulex.TestCache.Cache
alias Nebulex.TestCache.Partitioned

# start caches
{:ok, local_ets} = Cache.start_link(name: :cache_ets)
{:ok, local_shards} = Cache.start_link(name: :cache_shards, backend: :shards)
# {:ok, dist} = Partitioned.start_link()
# node_pid_list = NodeCase.start_caches(Node.list(), [Partitioned])

# default cache
default_dynamic_cache = Cache.get_dynamic_cache()

# samples
keys = Enum.to_list(1..10_000)

# init caches
# Enum.each(1..5000, fn x ->
#   ETS.put(x, x)
#   Shards.put(x, x)
#   # Partitioned.put(x, x)
# end)

inputs = %{
  "Generational Local Cache with ETS" => {Cache, :cache_ets},
  "Generational Local Cache with Shards" => {Cache, :cache_shards}
  # "Partitioned Cache" => {Partitioned, nil}
}

benchmarks = %{
  "get" => fn {cache, random} ->
    cache.get(random)
  end,
  "get_all" => fn {cache, random} ->
    cache.get_all([random])
  end,
  "put" => fn {cache, random} ->
    cache.put(random, random)
  end,
  "put_new" => fn {cache, random} ->
    cache.put_new(random, random)
  end,
  "replace" => fn {cache, random} ->
    cache.replace(random, random)
  end,
  "put_all" => fn {cache, random} ->
    cache.put_all([{random, random}])
  end,
  "delete" => fn {cache, random} ->
    cache.delete(random)
  end,
  "take" => fn {cache, random} ->
    cache.take(random)
  end,
  "has_key?" => fn {cache, random} ->
    cache.has_key?(random)
  end,
  "size" => fn {cache, _random} ->
    cache.size()
  end,
  "ttl" => fn {cache, random} ->
    cache.ttl(random)
  end,
  "expire" => fn {cache, random} ->
    cache.expire(random, 1)
  end,
  "get_and_update" => fn {cache, random} ->
    cache.get_and_update(random, &Partitioned.get_and_update_fun/1)
  end,
  "update" => fn {cache, random} ->
    cache.update(random, 1, &Kernel.+(&1, 1))
  end,
  "incr" => fn {cache, _random} ->
    cache.incr(:counter, 1)
  end,
  "all" => fn {cache, _random} ->
    cache.all()
  end,
  "transaction" => fn {cache, random} ->
    cache.transaction([keys: [random]], fn ->
      cache.incr(random, 1)
    end)
  end
}

Benchee.run(
  benchmarks,
  inputs: inputs,
  before_scenario: fn {cache, name} ->
    _ = cache.put_dynamic_cache(name)
    {cache, Enum.random(keys)}
  end,
  after_scenario: fn {cache, _} ->
    _ = cache.put_dynamic_cache(default_dynamic_cache)
  end,
  formatters: [
    {Benchee.Formatters.Console, comparison: false, extended_statistics: true},
    {Benchee.Formatters.HTML, extended_statistics: true}
  ],
  print: [
    fast_warning: false
  ]
)

# stop caches s
if Process.alive?(local_ets), do: Cache.stop(local_ets)
if Process.alive?(local_shards), do: Cache.stop(local_shards)
# if Process.alive?(dist), do: Partitioned.stop(dist)
# NodeCase.stop_caches(node_pid_list)
