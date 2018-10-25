defmodule Benchmark do
  @moduledoc false

  alias Nebulex.TestCache.Dist

  @bulk for x <- 1..100, do: {x, x}

  @doc false
  def jobs do
    %{
      "get" => fn {cache, random} ->
        cache.get(random)
      end,
      "set" => fn {cache, random} ->
        cache.set(random, random)
      end,
      "add" => fn {cache, random} ->
        cache.add(random, random)
      end,
      "replace" => fn {cache, random} ->
        cache.replace(random, random)
      end,
      "add_or_replace!" => fn {cache, random} ->
        cache.add_or_replace!(random, random)
      end,
      "get_many" => fn {cache, _random} ->
        cache.get_many(1..100)
      end,
      "set_many" => fn {cache, _random} ->
        cache.set_many(@bulk)
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
      "object_info" => fn {cache, random} ->
        cache.object_info(random, :ttl)
      end,
      "expire" => fn {cache, random} ->
        cache.expire(random, 1)
      end,
      "get_and_update" => fn {cache, random} ->
        cache.get_and_update(random, &Dist.get_and_update_fun/1)
      end,
      "update" => fn {cache, random} ->
        cache.update(random, 1, &Kernel.+(&1, 1))
      end,
      "update_counter" => fn {cache, random} ->
        cache.update_counter(random, 1)
      end,
      "all" => fn {cache, _random} ->
        cache.all()
      end,
      "transaction" => fn {cache, random} ->
        cache.transaction(
          fn ->
            cache.update_counter(random, 1)
            :ok
          end,
          keys: [random]
        )
      end
    }
  end
end

## Benchmarks

required_files =
  for file <- File.ls!("test/support") do
    {file, Code.require_file("../test/support/" <> file, __DIR__)}
  end

nodes = Keyword.values(Nebulex.Cluster.spawn())

Enum.each(required_files, fn {file, loaded} ->
  Enum.each(loaded, fn {mod, bin} ->
    expected = List.duplicate({:module, mod}, length(nodes))

    {^expected, []} =
      :rpc.multicall(
        nodes,
        :code,
        :load_binary,
        [mod, to_charlist(file), bin]
      )
  end)
end)

alias Nebulex.NodeCase
alias Nebulex.TestCache.{Dist, DistLocal, Versionless}

# start caches
{:ok, local} = Versionless.start_link()
{:ok, primary} = DistLocal.start_link()
{:ok, dist} = Dist.start_link()
node_pid_list = NodeCase.start_caches(Node.list(), [DistLocal, Dist])

# samples
keys = Enum.to_list(1..10_000)

# init caches
Enum.each(1..5000, fn x ->
  Versionless.set(x, x)
  Dist.set(x, x)
end)

inputs = %{
  "Generational Local Cache" => Versionless,
  "Distributed Cache" => Dist
}

Benchee.run(
  Benchmark.jobs(),
  inputs: inputs,
  before_scenario: fn cache ->
    {cache, Enum.random(keys)}
  end,
  console: [
    comparison: false,
    extended_statistics: true
  ],
  formatters: [
    Benchee.Formatters.Console,
    Benchee.Formatters.HTML
  ],
  formatter_options: [
    html: [
      auto_open: false
    ]
  ],
  print: [
    fast_warning: false
  ]
)

# stop caches s
if Process.alive?(local), do: Nebulex.TestCache.Versionless.stop(local)
if Process.alive?(primary), do: DistLocal.stop(primary)
if Process.alive?(dist), do: Dist.stop(dist)
NodeCase.stop_caches(node_pid_list)
