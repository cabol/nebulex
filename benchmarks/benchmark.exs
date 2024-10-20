## Benchmarks

_ = Application.start(:telemetry)

defmodule Cache do
  @moduledoc false
  use Nebulex.Cache,
    otp_app: :nebulex,
    adapter: Nebulex.Adapters.Nil
end

benchmarks = %{
  "fetch" => fn ->
    Cache.fetch("foo")
  end,
  "put" => fn ->
    Cache.put("foo", "bar")
  end,
  "get" => fn ->
    Cache.get("foo")
  end,
  "get_all" => fn ->
    Cache.get_all(in: ["foo", "bar"])
  end,
  "put_new" => fn ->
    Cache.put_new("foo", "bar")
  end,
  "replace" => fn ->
    Cache.replace("foo", "bar")
  end,
  "put_all" => fn ->
    Cache.put_all([{"foo", "bar"}])
  end,
  "delete" => fn ->
    Cache.delete("foo")
  end,
  "take" => fn ->
    Cache.take("foo")
  end,
  "has_key?" => fn ->
    Cache.has_key?("foo")
  end,
  "count_all" => fn ->
    Cache.count_all()
  end,
  "ttl" => fn ->
    Cache.ttl("foo")
  end,
  "expire" => fn ->
    Cache.expire("foo", 1)
  end,
  "incr" => fn ->
    Cache.incr(:counter, 1)
  end,
  "update" => fn ->
    Cache.update(1, 1, &Kernel.+(&1, 1))
  end
}

# Start cache
{:ok, pid} = Cache.start_link()

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

# Stop cache
if Process.alive?(pid), do: Supervisor.stop(pid)
