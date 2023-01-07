defmodule Nebulex.Cache.TransactionTest do
  import Nebulex.CacheCase

  deftests do
    describe "transaction" do
      test "ok: single transaction", %{cache: cache} do
        refute cache.transaction(fn ->
                 with :ok <- cache.put(1, 11),
                      11 <- cache.get!(1),
                      :ok <- cache.delete(1) do
                   cache.get(1)
                 end
               end)
      end

      test "ok: nested transaction", %{cache: cache} do
        refute cache.transaction(
                 [keys: [1]],
                 fn ->
                   cache.transaction(
                     [keys: [2]],
                     fn ->
                       with :ok <- cache.put(1, 11),
                            11 <- cache.get!(1),
                            :ok <- cache.delete(1) do
                         cache.get(1)
                       end
                     end
                   )
                 end
               )
      end

      test "ok: single transaction with read and write operations", %{cache: cache} do
        assert cache.put(:test, ["old value"]) == :ok
        assert cache.get(:test) == ["old value"]

        assert cache.transaction(
                 [keys: [:test]],
                 fn ->
                   ["old value"] = value = cache.get(:test)
                   :ok = cache.put(:test, ["new value" | value])
                   cache.get(:test)
                 end
               ) == ["new value", "old value"]

        assert cache.get(:test) == ["new value", "old value"]
      end

      test "raises exception", %{cache: cache} do
        assert_raise MatchError, fn ->
          cache.transaction(fn ->
            with :ok <- cache.put(1, 11),
                 11 <- cache.get!(1),
                 :ok <- cache.delete(1) do
              :ok = cache.get(1)
            end
          end)
        end
      end

      test "aborted", %{name: name, cache: cache} do
        key = {name, :aborted}

        Task.start_link(fn ->
          _ = cache.put_dynamic_cache(name)

          cache.transaction(
            [keys: [key], retries: 1],
            fn ->
              :ok = cache.put(key, true)
              Process.sleep(2000)
            end
          )
        end)

        :ok = Process.sleep(200)

        assert_raise RuntimeError, "transaction aborted", fn ->
          cache.transaction(
            [keys: [key], retries: 1],
            fn ->
              cache.get(key)
            end
          )
        end
      end
    end

    describe "in_transaction?" do
      test "returns true if calling process is already within a transaction", %{cache: cache} do
        refute cache.in_transaction?()

        cache.transaction(fn ->
          :ok = cache.put(1, 11, return: :key)
          true = cache.in_transaction?()
        end)
      end
    end
  end
end
