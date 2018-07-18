defmodule Nebulex.Cache.SupervisorTest do
  use ExUnit.Case, async: true

  defmodule MyCache do
    use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Local
  end

  setup do
    _ = Application.put_env(:nebulex, MyCache, [n_shards: 2])
    {:ok, pid} = MyCache.start_link()
    :ok

    on_exit fn ->
      _ = :timer.sleep(10)
      if Process.alive?(pid), do: MyCache.stop(pid)
    end
  end

  test "fail on runtime_config because configuration for cache not specified" do
    _ = Application.delete_env(:nebulex, MyCache)

    msg = "configuration for Nebulex.Cache.SupervisorTest.MyCache not specified in :nebulex environment"
    assert_raise ArgumentError, msg, fn ->
      Nebulex.Cache.Supervisor.runtime_config(MyCache, :nebulex, nil)
    end
  end

  test "fail on compile_config because missing adapter" do
    opts = [otp_app: :nebulex, n_shards: 2]
    _ = Application.put_env(:nebulex, MyCache, opts)

    msg = "missing :adapter configuration in config :nebulex, Nebulex.Cache.SupervisorTest.MyCache"
    assert_raise ArgumentError, msg, fn ->
      Nebulex.Cache.Supervisor.compile_config(MyCache, opts)
    end
  end

  test "fail on compile_config because adapter was not compiled" do
    opts = [otp_app: :nebulex, n_shards: 2, adapter: TestAdapter]
    _ = Application.put_env(:nebulex, MyCache, opts)

    msg = ~r"adapter TestAdapter was not compiled, ensure"
    assert_raise ArgumentError, msg, fn ->
      Nebulex.Cache.Supervisor.compile_config(MyCache, opts)
    end
  end
end
