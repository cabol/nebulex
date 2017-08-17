defmodule DistBench do
  use Benchfella

  alias Nebulex.NodeCase
  alias Nebulex.TestCache.Dist
  alias Nebulex.TestCache.DistLocal, as: Local

  setup_all do
    {:ok, local} = Local.start_link
    {:ok, dist} = Dist.start_link
    node_pid_list = NodeCase.start_caches(Node.list(), [Local, Dist])

    :ok = Enum.each(1..1000, fn x -> Dist.set(x, x) end)
    {:ok, {local, dist, node_pid_list}}
  end

  teardown_all {local, dist, node_pid_list} do
    _ = :timer.sleep(100)
    if Process.alive?(local), do: Local.stop(local, 1)
    if Process.alive?(dist), do: Dist.stop(dist, 1)
    NodeCase.stop_caches(node_pid_list)
  end

  before_each_bench _ do
    key = Enum.random(1..1000)
    {:ok, key}
  end

  bench "get" do
    Dist.get(bench_context)
    :ok
  end

  bench "get!" do
    Dist.get!(bench_context)
    :ok
  end

  bench "set" do
    Dist.set(bench_context, bench_context)
    :ok
  end

  bench "delete" do
    Dist.delete(bench_context)
    :ok
  end

  bench "has_key?" do
    Dist.has_key?(bench_context)
    :ok
  end

  bench "size" do
    Dist.size()
    :ok
  end

  bench "keys" do
    Dist.keys()
    :ok
  end

  bench "reduce" do
    Dist.reduce({%{}, 0}, &Dist.reducer_fun/2)
    :ok
  end

  bench "to_map" do
    Dist.to_map()
    :ok
  end

  bench "pop" do
    Dist.pop(bench_context)
    :ok
  end

  bench "get_and_update" do
    Dist.get_and_update(:non_existent, &Dist.get_and_update_fun/1)
    :ok
  end

  bench "update" do
    Dist.update(:non_existent, 1, &Dist.update_fun/1)
    :ok
  end
end
