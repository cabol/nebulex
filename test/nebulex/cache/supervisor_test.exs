defmodule Nebulex.Cache.SupervisorTest do
  use ExUnit.Case, async: true

  defmodule MyCache do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local

    def init(opts) do
      case Keyword.get(opts, :ignore) do
        true -> :ignore
        false -> opts
      end
    end
  end

  test "fails on init because :ignore is returned" do
    assert MyCache.start_link(ignore: true) == :ignore
  end

  test "fails on compile_config because missing otp_app" do
    assert_raise ArgumentError, "expected otp_app: to be given as argument", fn ->
      Nebulex.Cache.Supervisor.compile_config(adapter: TestAdapter)
    end
  end

  test "fails on compile_config because missing adapter" do
    assert_raise ArgumentError, "expected adapter: to be given as argument", fn ->
      Nebulex.Cache.Supervisor.compile_config(otp_app: :nebulex)
    end
  end

  test "fails on compile_config because adapter was not compiled" do
    msg = ~r"adapter TestAdapter was not compiled, ensure"

    assert_raise ArgumentError, msg, fn ->
      Nebulex.Cache.Supervisor.compile_config(otp_app: :nebulex, adapter: TestAdapter)
    end
  end

  test "fails on compile_config because adapter error" do
    msg = "expected :adapter option given to Nebulex.Cache to list Nebulex.Adapter as a behaviour"

    assert_raise ArgumentError, msg, fn ->
      defmodule MyAdapter do
      end

      defmodule MyCache2 do
        use Nebulex.Cache,
          otp_app: :nebulex,
          adapter: MyAdapter
      end

      Nebulex.Cache.Supervisor.compile_config(otp_app: :nebulex)
    end
  end

  test "start cache with custom adapter" do
    defmodule CustomCache do
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.TestCache.AdapterMock
    end

    assert {:ok, _pid} = CustomCache.start_link(child_name: :custom_cache)
    _ = Process.flag(:trap_exit, true)

    assert {:error, error} =
             CustomCache.start_link(name: :another_custom_cache, child_name: :custom_cache)

    assert_receive {:EXIT, _pid, ^error}
    assert CustomCache.stop() == :ok
  end
end
