defmodule Nebulex.Cache.TransactionTest do
  import Nebulex.SharedTestCase

  deftests do
    test "transaction" do
      refute @cache.transaction(fn ->
               1
               |> @cache.set(11, return: :key)
               |> @cache.get!(return: :key)
               |> @cache.delete(return: :key)
               |> @cache.get()
             end)

      assert_raise MatchError, fn ->
        @cache.transaction(fn ->
          :ok =
            1
            |> @cache.set(11, return: :key)
            |> @cache.get!(return: :key)
            |> @cache.delete(return: :key)
            |> @cache.get()
        end)
      end
    end

    test "nested transaction" do
      refute @cache.transaction(
               fn ->
                 @cache.transaction(
                   fn ->
                     1
                     |> @cache.set(11, return: :key)
                     |> @cache.get!(return: :key)
                     |> @cache.delete(return: :key)
                     |> @cache.get
                   end,
                   keys: [2]
                 )
               end,
               keys: [1]
             )
    end

    test "set and get within a transaction" do
      assert ["old value"] == @cache.set(:test, ["old value"])

      assert ["new value", "old value"] ==
               @cache.transaction(
                 fn ->
                   value = @cache.get(:test)

                   assert ["old value"] == value

                   @cache.set(:test, ["new value" | value])
                 end,
                 keys: [:test]
               )

      assert ["new value", "old value"] == @cache.get(:test)
    end

    test "transaction aborted" do
      spawn_link(fn ->
        @cache.transaction(
          fn ->
            Process.sleep(1100)
          end,
          keys: [1],
          retries: 1
        )
      end)

      Process.sleep(200)

      assert_raise RuntimeError, "transaction aborted", fn ->
        @cache.transaction(
          fn ->
            @cache.get(1)
          end,
          keys: [1],
          retries: 1
        )
      end
    end

    test "in_transaction?" do
      refute @cache.in_transaction?()

      @cache.transaction(fn ->
        _ = @cache.set(1, 11, return: :key)
        true = @cache.in_transaction?()
      end)
    end
  end
end
