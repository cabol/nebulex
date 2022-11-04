defmodule Nebulex.Adapters.MultilevelConcurrencyTest do
  use ExUnit.Case, async: true

  import Nebulex.CacheCase

  alias Nebulex.TestCache.Multilevel.L2

  defmodule SleeperMock do
    @moduledoc false
    @behaviour Nebulex.Adapter
    @behaviour Nebulex.Adapter.Entry
    @behaviour Nebulex.Adapter.Queryable

    alias Nebulex.Adapters.Local

    @impl true
    defmacro __before_compile__(_), do: :ok

    @impl true
    defdelegate init(opts), to: Local

    def post(opts) do
      with f when is_function(f) <- opts[:post] do
        f.()
      end
    end

    @impl true
    defdelegate get(meta, key, opts), to: Local

    @impl true
    defdelegate put(meta, key, value, ttl, on_write, opts), to: Local

    @impl true
    def delete(meta, key, opts) do
      result = Local.delete(meta, key, opts)
      post(opts)
      result
    end

    @impl true
    defdelegate take(meta, key, opts), to: Local

    @impl true
    defdelegate has_key?(meta, key), to: Local

    @impl true
    defdelegate ttl(meta, key), to: Local

    @impl true
    defdelegate expire(meta, key, ttl), to: Local

    @impl true
    defdelegate touch(meta, key), to: Local

    @impl true
    defdelegate update_counter(meta, key, amount, ttl, default, opts), to: Local

    @impl true
    defdelegate get_all(meta, keys, opts), to: Local

    @impl true
    defdelegate put_all(meta, entries, ttl, on_write, opts), to: Local

    @impl true
    def execute(meta, operation, query, opts) do
      result = Local.execute(meta, operation, query, opts)
      post(opts)
      result
    end

    @impl true
    defdelegate stream(meta, query, opts), to: Local
  end

  defmodule L1 do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: SleeperMock
  end

  defmodule Multilevel do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Multilevel
  end

  @levels [
    {L1, name: :multilevel_concurrency_l1},
    {L2, name: :multilevel_concurrency_l2}
  ]

  setup_with_cache(Multilevel,
    model: :inclusive,
    levels: @levels
  )

  describe "delete" do
    test "deletes in reverse order", %{cache: cache} do
      test_pid = self()

      assert :ok = cache.put("foo", "stale")

      task =
        Task.async(fn ->
          cache.delete("foo",
            post: fn ->
              send(test_pid, :deleted_in_l1)

              receive do
                :continue -> :ok
              after
                5000 ->
                  raise "Did not receive continue message"
              end
            end
          )
        end)

      assert_receive :deleted_in_l1
      refute cache.get("foo")
      send(task.pid, :continue)
      assert Task.await(task) == :ok
      assert cache.get("foo", level: 1) == nil
      assert cache.get("foo", level: 2) == nil
    end
  end

  describe "delete_all" do
    test "deletes in reverse order", %{cache: cache} do
      test_pid = self()

      assert :ok = cache.put_all(%{a: "stale", b: "stale"})

      task =
        Task.async(fn ->
          cache.delete_all(nil,
            post: fn ->
              send(test_pid, :deleted_in_l1)

              receive do
                :continue -> :ok
              after
                5000 ->
                  raise "Did not receive continue message"
              end
            end
          )
        end)

      assert_receive :deleted_in_l1
      refute cache.get(:a)
      refute cache.get(:b)
      send(task.pid, :continue)
      assert Task.await(task) == 4
      assert cache.get_all([:a, :b]) == %{}
    end
  end
end
