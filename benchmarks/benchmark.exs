## Benchmarks

nodes = [:"node1@127.0.0.1", :"node2@127.0.0.1"]
Nebulex.Cluster.spawn(nodes)

alias Nebulex.NodeCase
alias Nebulex.TestCache.Cache
alias Nebulex.TestCache.Partitioned

# start local caches
{:ok, local_ets} = Cache.start_link(name: :cache_ets_bench)
{:ok, local_shards} = Cache.start_link(name: :cache_shards_bench, backend: :shards)

# start distributed caches
{:ok, dist} = Partitioned.start_link(primary: [backend: :shards])
node_pid_list = NodeCase.start_caches(Node.list(), [{Partitioned, primary: [backend: :shards]}])

# default cache
default_dynamic_cache = Cache.get_dynamic_cache()

inputs = %{
  "Generational Local Cache with ETS" => {Cache, :cache_ets_bench},
  "Generational Local Cache with Shards" => {Cache, :cache_shards_bench},
  "Partitioned Cache" => {Partitioned, Partitioned}
}

benchmarks = %{
  "get" => fn {cache, sample} ->
    cache.get(sample)
  end,
  "get_all" => fn {cache, sample} ->
    cache.get_all([sample])
  end,
  "put" => fn {cache, sample} ->
    cache.put(sample, sample)
  end,
  "put_new" => fn {cache, sample} ->
    cache.put_new(sample, sample)
  end,
  "replace" => fn {cache, sample} ->
    cache.replace(sample, sample)
  end,
  "put_all" => fn {cache, sample} ->
    cache.put_all([{sample, sample}])
  end,
  "delete" => fn {cache, sample} ->
    cache.delete(sample)
  end,
  "take" => fn {cache, sample} ->
    cache.take(sample)
  end,
  "has_key?" => fn {cache, sample} ->
    cache.has_key?(sample)
  end,
  "size" => fn {cache, _sample} ->
    cache.size()
  end,
  "ttl" => fn {cache, sample} ->
    cache.ttl(sample)
  end,
  "expire" => fn {cache, sample} ->
    cache.expire(sample, 1)
  end,
  "get_and_update" => fn {cache, sample} ->
    cache.get_and_update(sample, &Partitioned.get_and_update_fun/1)
  end,
  "update" => fn {cache, sample} ->
    cache.update(sample, 1, &Kernel.+(&1, 1))
  end,
  "incr" => fn {cache, _sample} ->
    cache.incr(:counter, 1)
  end,
  "all" => fn {cache, _sample} ->
    cache.all()
  end,
  "transaction" => fn {cache, sample} ->
    cache.transaction([keys: [sample]], fn ->
      cache.incr(sample, 1)
    end)
  end
}

Benchee.run(
  benchmarks,
  inputs: inputs,
  before_scenario: fn {cache, name} ->
    _ = cache.put_dynamic_cache(name)
    {cache, 101}
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
if Process.alive?(local_ets), do: Supervisor.stop(local_ets)
if Process.alive?(local_shards), do: Supervisor.stop(local_shards)
if Process.alive?(dist), do: Supervisor.stop(dist)
NodeCase.stop_caches(node_pid_list)
