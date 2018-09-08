defmodule DistBench do
  use Benchfella

  alias Nebulex.NodeCase
  alias Nebulex.TestCache.Dist
  alias Nebulex.TestCache.DistLocal

  @bulk_objs Enum.map(1..1000, &%Nebulex.Object{key: &1, value: &1})
  @bulk_keys Enum.to_list(1..1000)

  setup_all do
    {:ok, local} = DistLocal.start_link()
    {:ok, dist} = Dist.start_link()
    node_pid_list = NodeCase.start_caches(Node.list(), [DistLocal, Dist])

    :ok = Enum.each(1..1000, fn x -> Dist.set(x, x) end)
    {:ok, {local, dist, node_pid_list}}
  end

  teardown_all {local, dist, node_pid_list} do
    _ = :timer.sleep(100)
    if Process.alive?(local), do: DistLocal.stop(local)
    if Process.alive?(dist), do: Dist.stop(dist)
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

  bench "add" do
    Dist.add(bench_context, bench_context)
    :ok
  end

  bench "replace" do
    Dist.replace(bench_context, bench_context)
    :ok
  end

  bench "delete" do
    Dist.delete(bench_context)
    :ok
  end

  bench "take" do
    Dist.take(bench_context)
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

  bench "get_and_update" do
    Dist.get_and_update(:non_existent, &Dist.get_and_update_fun/1)
    :ok
  end

  bench "update" do
    Dist.update(:non_existent, 1, &Dist.update_fun/1)
    :ok
  end

  bench "update_counter" do
    Dist.update_counter(bench_context, 1)
    :ok
  end

  bench "mget" do
    Dist.mget(@bulk_keys)
    :ok
  end

  bench "mset" do
    Dist.mset(@bulk_objs)
    :ok
  end

  bench "transaction" do
    Dist.transaction(
      fn ->
        Dist.update_counter(bench_context, 1)
        :ok
      end,
      keys: [1]
    )
  end
end
