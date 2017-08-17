defmodule BenchCache do
  Application.put_env(:nebulex, :nodes, [:"node1@127.0.0.1", :"node2@127.0.0.1"])
  Application.put_env(:nebulex, BenchCache.Local, [gc_interval: 3600])
  Application.put_env(:nebulex, BenchCache.Dist, [local: BenchCache.Local])

  defmodule Local do
    use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Local
  end

  defmodule Dist do
    use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Dist
  end
end
