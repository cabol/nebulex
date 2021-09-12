defmodule BenchHelper do
  @moduledoc """
  Benchmark commons.
  """

  @doc false
  def benchmarks(cache) do
    %{
      "get" => fn input ->
        cache.get(input)
      end,
      "get_all" => fn input ->
        cache.get_all([input, "foo", "bar"])
      end,
      "put" => fn input ->
        cache.put(input, input)
      end,
      "put_new" => fn input ->
        cache.put_new(input, input)
      end,
      "replace" => fn input ->
        cache.replace(input, input)
      end,
      "put_all" => fn input ->
        cache.put_all([{input, input}, {"foo", "bar"}])
      end,
      "delete" => fn input ->
        cache.delete(input)
      end,
      "take" => fn input ->
        cache.take(input)
      end,
      "exists?" => fn input ->
        cache.exists?(input)
      end,
      "count_all" => fn _input ->
        cache.count_all()
      end,
      "ttl" => fn input ->
        cache.ttl(input)
      end,
      "expire" => fn input ->
        cache.expire(input, 1)
      end,
      "incr" => fn _input ->
        cache.incr(:counter, 1)
      end,
      "update" => fn input ->
        cache.update(input, 1, &Kernel.+(&1, 1))
      end,
      "all" => fn _input ->
        cache.all()
      end
    }
  end

  @doc false
  def run(benchmarks, opts \\ []) do
    Benchee.run(
      benchmarks,
      Keyword.merge(
        [
          inputs: %{"rand" => 100_000},
          before_each: fn n -> :rand.uniform(n) end,
          formatters: [
            {Benchee.Formatters.Console, comparison: false, extended_statistics: true},
            {Benchee.Formatters.HTML, extended_statistics: true, auto_open: false}
          ],
          print: [
            fast_warning: false
          ]
        ],
        opts
      )
    )
  end
end
