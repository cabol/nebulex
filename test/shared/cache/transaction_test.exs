defmodule Nebulex.Cache.TransactionTest do
  import Nebulex.CacheCase

  deftests do
    describe "transaction" do
      test "ok: single transaction", %{cache: cache} do
        assert cache.transaction(fn ->
                 with :ok <- cache.put(1, 11),
                      11 <- cache.fetch!(1),
                      :ok <- cache.delete(1) do
                   cache.get!(1)
                 end
               end) == {:ok, nil}
      end

      test "ok: nested transaction", %{cache: cache} do
        assert cache.transaction(
                 [keys: [1]],
                 fn ->
                   cache.transaction(
                     [keys: [2]],
                     fn ->
                       with :ok <- cache.put(1, 11),
                            11 <- cache.fetch!(1),
                            :ok <- cache.delete(1) do
                         cache.get!(1)
                       end
                     end
                   )
                 end
               ) == {:ok, {:ok, nil}}
      end

      test "ok: single transaction with read and write operations", %{cache: cache} do
        assert cache.put(:test, ["old value"]) == :ok
        assert cache.fetch!(:test) == ["old value"]

        assert cache.transaction(
                 [keys: [:test]],
                 fn ->
                   ["old value"] = value = cache.fetch!(:test)
                   :ok = cache.put(:test, ["new value" | value])
                   cache.fetch!(:test)
                 end
               ) == {:ok, ["new value", "old value"]}

        assert cache.fetch!(:test) == ["new value", "old value"]
      end

      test "error: exception is raised", %{cache: cache} do
        assert_raise MatchError, fn ->
          cache.transaction(fn ->
            with :ok <- cache.put(1, 11),
                 11 <- cache.fetch!(1),
                 :ok <- cache.delete(1) do
              :ok = cache.get(1)
            end
          end)
        end
      end

      test "aborted", %{name: name, cache: cache} do
        Task.start_link(fn ->
          _ = cache.put_dynamic_cache(name)

          cache.transaction(
            [keys: [:aborted], retries: 1],
            fn ->
              :ok = cache.put(:aborted, true)
              Process.sleep(1100)
            end
          )
        end)

        :ok = Process.sleep(200)

        assert_raise Nebulex.Error, ~r"Cache #{inspect(name)} has aborted a transaction", fn ->
          {:error, %Nebulex.Error{} = reason} =
            cache.transaction(
              [keys: [:aborted], retries: 1],
              fn ->
                cache.get(:aborted)
              end
            )

          raise reason
        end
      end
    end

    describe "in_transaction?" do
      test "returns true if calling process is already within a transaction", %{cache: cache} do
        assert cache.in_transaction?() == {:ok, false}

        cache.transaction(fn ->
          :ok = cache.put(1, 11, return: :key)
          {:ok, true} = cache.in_transaction?()
        end)
      end
    end
  end
end
