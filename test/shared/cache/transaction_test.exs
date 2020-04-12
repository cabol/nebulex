defmodule Nebulex.Cache.TransactionTest do
  import Nebulex.SharedTestCase

  deftests "transaction" do
    test "transaction" do
      refute @cache.transaction(fn ->
               with :ok <- @cache.put(1, 11),
                    11 <- @cache.get!(1),
                    :ok <- @cache.delete(1),
                    value <- @cache.get(1) do
                 value
               end
             end)

      assert_raise MatchError, fn ->
        @cache.transaction(fn ->
          with :ok <- @cache.put(1, 11),
               11 <- @cache.get!(1),
               :ok <- @cache.delete(1) do
            :ok = @cache.get(1)
          end
        end)
      end
    end

    test "nested transaction" do
      refute @cache.transaction(
               [keys: [1]],
               fn ->
                 @cache.transaction(
                   [keys: [2]],
                   fn ->
                     with :ok <- @cache.put(1, 11),
                          11 <- @cache.get!(1),
                          :ok <- @cache.delete(1),
                          value <- @cache.get(1) do
                       value
                     end
                   end
                 )
               end
             )
    end

    test "set and get within a transaction" do
      assert :ok == @cache.put(:test, ["old value"])
      assert ["old value"] == @cache.get(:test)

      assert ["new value", "old value"] ==
               @cache.transaction(
                 [keys: [:test]],
                 fn ->
                   ["old value"] = value = @cache.get(:test)
                   :ok = @cache.put(:test, ["new value" | value])
                   @cache.get(:test)
                 end
               )

      assert ["new value", "old value"] == @cache.get(:test)
    end

    test "transaction aborted" do
      spawn_link(fn ->
        @cache.transaction(
          [keys: [1], retries: 1],
          fn ->
            Process.sleep(1100)
          end
        )
      end)

      Process.sleep(200)

      assert_raise RuntimeError, "transaction aborted", fn ->
        @cache.transaction(
          [keys: [1], retries: 1],
          fn ->
            @cache.get(1)
          end
        )
      end
    end

    test "in_transaction?" do
      refute @cache.in_transaction?()

      @cache.transaction(fn ->
        :ok = @cache.put(1, 11, return: :key)
        true = @cache.in_transaction?()
      end)
    end
  end
end
