defmodule Nebulex.Cache.SupervisorTest do
  use ExUnit.Case, async: true

  defmodule MyCache do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local
  end

  setup do
    {:ok, pid} = MyCache.start_link()
    :ok

    on_exit(fn ->
      :ok = Process.sleep(10)
      if Process.alive?(pid), do: MyCache.stop(pid)
    end)
  end

  test "fail on compile_config because missing otp_app" do
    opts = [adapter: TestAdapter]
    :ok = Application.put_env(:nebulex, MyCache, opts)

    assert_raise ArgumentError, "expected otp_app: to be given as argument", fn ->
      Nebulex.Cache.Supervisor.compile_config(opts)
    end
  end

  test "fail on compile_config because missing adapter" do
    opts = [otp_app: :nebulex]
    :ok = Application.put_env(:nebulex, MyCache, opts)

    assert_raise ArgumentError, "expected adapter: to be given as argument", fn ->
      Nebulex.Cache.Supervisor.compile_config(opts)
    end
  end

  test "fail on compile_config because adapter was not compiled" do
    opts = [otp_app: :nebulex, adapter: TestAdapter]
    :ok = Application.put_env(:nebulex, MyCache, opts)

    msg = ~r"adapter TestAdapter was not compiled, ensure"

    assert_raise ArgumentError, msg, fn ->
      Nebulex.Cache.Supervisor.compile_config(opts)
    end
  end

  test "fail on compile_config because adapter error" do
    opts = [otp_app: :nebulex]
    :ok = Application.put_env(:nebulex, MyCache2, opts)

    msg = "expected :adapter option given to Nebulex.Cache to list Nebulex.Adapter as a behaviour"

    assert_raise ArgumentError, msg, fn ->
      defmodule MyAdapter do
      end

      defmodule MyCache2 do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: MyAdapter
      end

      Nebulex.Cache.Supervisor.compile_config(opts)
    end
  end
end
