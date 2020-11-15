defmodule BenchHelper do
  @moduledoc """
  Benchmark commons.
  """

  @doc false
  def benchmarks(cache) do
    %{
      "get" => fn ->
        cache.get("foo")
      end,
      "get_all" => fn ->
        cache.get_all(["foo", "bar"])
      end,
      "put" => fn ->
        cache.put("foo", "bar")
      end,
      "put_new" => fn ->
        cache.put_new("foo", "bar")
      end,
      "replace" => fn ->
        cache.replace("foo", "bar")
      end,
      "put_all" => fn ->
        cache.put_all([{"foo", "bar"}])
      end,
      "delete" => fn ->
        cache.delete("foo")
      end,
      "take" => fn ->
        cache.take("foo")
      end,
      "has_key?" => fn ->
        cache.has_key?("foo")
      end,
      "size" => fn ->
        cache.size()
      end,
      "ttl" => fn ->
        cache.ttl("foo")
      end,
      "expire" => fn ->
        cache.expire("foo", 1)
      end,
      "incr" => fn ->
        cache.incr(:counter, 1)
      end,
      "update" => fn ->
        cache.update("update", 1, &Kernel.+(&1, 1))
      end,
      "all" => fn ->
        cache.all()
      end
    }
  end

  @doc false
  def run(benchmarks) do
    Benchee.run(
      benchmarks,
      formatters: [
        {Benchee.Formatters.Console, comparison: false, extended_statistics: true},
        {Benchee.Formatters.HTML, extended_statistics: true, auto_open: false}
      ],
      print: [
        fast_warning: false
      ]
    )
  end
end
