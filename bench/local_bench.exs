defmodule LocalBench do
  use Benchfella

  Application.put_env(:nebulex, LocalBench.Cache, gc_interval: 3600, n_shards: 2)

  defmodule Cache do
    use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Local
  end

  @bulk_objs Enum.map(1..1000, &%Nebulex.Object{key: &1, value: &1})
  @bulk_keys Enum.to_list(1..1000)

  setup_all do
    res = Cache.start_link()
    :ok = Enum.each(1..1000, fn x -> Cache.set(x, x) end)
    res
  end

  teardown_all pid do
    _ = :timer.sleep(10)
    if Process.alive?(pid), do: Cache.stop(pid, 1)
  end

  before_each_bench _ do
    key = Enum.random(1..1000)
    {:ok, key}
  end

  bench "get" do
    Cache.get(bench_context)
    :ok
  end

  bench "get!" do
    Cache.get!(bench_context)
    :ok
  end

  bench "mget" do
    Cache.mget(@bulk_keys)
    :ok
  end

  bench "set" do
    Cache.set(bench_context, bench_context)
    :ok
  end

  bench "mset" do
    Cache.mset(@bulk_objs)
    :ok
  end

  bench "add" do
    Cache.add(bench_context, bench_context)
    :ok
  end

  bench "delete" do
    Cache.delete(bench_context)
    :ok
  end

  bench "take" do
    Cache.take(bench_context)
    :ok
  end

  bench "has_key?" do
    Cache.has_key?(bench_context)
    :ok
  end

  bench "size" do
    Cache.size()
    :ok
  end

  bench "keys" do
    Cache.keys()
    :ok
  end

  bench "get_and_update" do
    Cache.get_and_update(bench_context, fn v ->
      if v, do: {v, v}, else: {v, 1}
    end)

    :ok
  end

  bench "update" do
    Cache.update(bench_context, 1, & &1)
    :ok
  end

  bench "update_counter" do
    Cache.update_counter(bench_context, 1)
    :ok
  end

  bench "transaction" do
    Cache.transaction(
      fn ->
        Cache.update_counter(bench_context, 1)
        :ok
      end,
      keys: [1]
    )
  end
end
