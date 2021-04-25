## Benchmarks

:ok = Application.start(:telemetry)
Code.require_file("bench_helper.exs", __DIR__)

nodes = [:"node1@127.0.0.1", :"node2@127.0.0.1"]
Nebulex.Cluster.spawn(nodes)

alias Nebulex.NodeCase
alias Nebulex.TestCache.Partitioned

# start distributed caches
{:ok, dist} = Partitioned.start_link(primary: [backend: :shards])
node_pid_list = NodeCase.start_caches(Node.list(), [{Partitioned, primary: [backend: :shards]}])

Partitioned
|> BenchHelper.benchmarks()
|> BenchHelper.run(parallel: 4, time: 30)

# stop caches
if Process.alive?(dist), do: Supervisor.stop(dist)
NodeCase.stop_caches(node_pid_list)
