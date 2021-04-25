## Benchmarks

:ok = Application.start(:telemetry)
Code.require_file("bench_helper.exs", __DIR__)

defmodule Cache do
  @moduledoc false
  use Nebulex.Cache,
    otp_app: :nebulex,
    adapter: Nebulex.Adapters.Local
end

# start local cache
{:ok, local} = Cache.start_link()

Cache
|> BenchHelper.benchmarks()
|> BenchHelper.run()

# stop cache
if Process.alive?(local), do: Supervisor.stop(local)
