defmodule Nebulex.Cache.CompositeKVTest do
  import Nebulex.CacheCase

  deftests do
    describe "get_and_update/3" do
      test "gets and updates the value", %{cache: cache} do
        assert cache.get_and_update(:counter, &cache.get_and_update_fun/1) == {:ok, {nil, 1}}
        assert cache.get_and_update(:counter, &cache.get_and_update_fun/1) == {:ok, {1, 2}}
        assert cache.fetch!(:counter) == 2
      end

      test "does not write when the function returns {get, nil}", %{cache: cache} do
        :ok = cache.put(:counter, 1)

        assert cache.get_and_update(:counter, &{&1, nil}) == {:ok, {1, 1}}
        assert cache.fetch!(:counter) == 1
      end

      test "pops the key when the function returns :pop", %{cache: cache} do
        :ok = cache.put(:counter, 1)

        assert cache.get_and_update(:counter, fn _ -> :pop end) == {:ok, {1, nil}}
        assert cache.has_key?(:counter) == {:ok, false}
        assert cache.get_and_update(:counter, fn _ -> :pop end) == {:ok, {nil, nil}}
      end

      test "raises if the function returns an invalid value", %{cache: cache} do
        assert_raise ArgumentError, ~r"must return a two-element tuple or :pop", fn ->
          cache.get_and_update(:counter, &cache.get_and_update_bad_fun/1)
        end
      end

      test "honors the :ttl option", %{cache: cache} do
        ttl = :timer.seconds(1)

        assert cache.get_and_update(:counter, &cache.get_and_update_fun/1, ttl: ttl) ==
                 {:ok, {nil, 1}}

        assert_expires(cache, :counter, ttl)
      end
    end

    describe "get_and_update!/3" do
      test "gets and updates the value", %{cache: cache} do
        assert cache.get_and_update!(:counter, &cache.get_and_update_fun/1) == {nil, 1}
        assert cache.get_and_update!(:counter, &cache.get_and_update_fun/1) == {1, 2}
        assert cache.get_and_update!(:counter, fn _ -> :pop end) == {2, nil}
        assert cache.get_and_update!(:counter, fn _ -> :pop end) == {nil, nil}
      end
    end

    describe "update/4" do
      test "stores the initial value when the key is missing", %{cache: cache} do
        assert cache.update(:counter, 1, &Integer.to_string/1) == {:ok, 1}
        assert cache.fetch!(:counter) == 1
      end

      test "applies the function to the current value", %{cache: cache} do
        :ok = cache.put(:counter, 2)

        assert cache.update(:counter, 1, &Integer.to_string/1) == {:ok, "2"}
        assert cache.fetch!(:counter) == "2"
      end

      test "honors the :ttl option", %{cache: cache} do
        ttl = :timer.seconds(1)

        assert cache.update(:counter, 1, &Integer.to_string/1, ttl: ttl) == {:ok, 1}

        assert_expires(cache, :counter, ttl)
      end
    end

    describe "update!/4" do
      test "updates an entry under a key applying a function on the value", %{cache: cache} do
        :ok = cache.put("update_int", "123")
        :ok = cache.put("update_str", "foo")

        assert cache.update!("update_int", 1, &String.to_integer/1) == 123
        assert cache.update!("update_str", "str", &String.to_atom/1) == :foo
      end

      test "creates the entry with the default value if key does not exist", %{cache: cache} do
        assert cache.update!("k123", "123", &Integer.to_string/1) == "123"
      end

      test "updates existing value with nil", %{cache: cache} do
        assert cache.update!("update with nil", nil, &Integer.to_string/1) == nil
        assert cache.fetch!("update with nil") == nil
      end

      test "raises because the cache is not started" do
        defmodule UnknownCache do
          use Nebulex.Cache,
            otp_app: :nebulex,
            adapter: Nebulex.Adapters.Nil
        end

        assert_raise Nebulex.CacheNotFoundError, ~r"unable to find cache:", fn ->
          UnknownCache.update!("error", 1, &String.to_integer/1)
        end
      end
    end

    describe "fetch_or_store/3" do
      test "stores the value on a miss and returns it on a hit", %{cache: cache} do
        assert cache.fetch_or_store(:key, &cache.fetch_or_store_fun/0) == {:ok, "value"}
        assert cache.fetch!(:key) == "value"

        assert cache.fetch_or_store(:key, &must_not_be_called/0) == {:ok, "value"}
      end

      test "does not write when the function returns an error", %{cache: cache} do
        assert {:error, %Nebulex.Error{reason: :error, metadata: metadata}} =
                 cache.fetch_or_store(:key, &cache.fetch_or_store_error_fun/0)

        assert Keyword.fetch!(metadata, :command) == :fetch_or_store
        assert Keyword.fetch!(metadata, :key) == :key
        assert cache.has_key?(:key) == {:ok, false}
      end

      test "raises if the function returns an invalid value", %{cache: cache} do
        assert_raise RuntimeError, ~r"must return \{:ok, value\} or \{:error, reason\}", fn ->
          cache.fetch_or_store(:key, &cache.get_or_store_fun/0)
        end
      end

      test "honors the :ttl option", %{cache: cache} do
        ttl = :timer.seconds(1)

        assert cache.fetch_or_store(:key, &cache.fetch_or_store_fun/0, ttl: ttl) ==
                 {:ok, "value"}

        assert_expires(cache, :key, ttl)
      end
    end

    describe "fetch_or_store!/3" do
      test "returns the value", %{cache: cache} do
        assert cache.fetch_or_store!(:key, &cache.fetch_or_store_fun/0) == "value"
        assert cache.fetch_or_store!(:key, &must_not_be_called/0) == "value"
      end

      test "raises when the function returns an error", %{cache: cache} do
        assert_raise Nebulex.Error, ~r"fetch_or_store command failed with reason: :error", fn ->
          cache.fetch_or_store!(:key, &cache.fetch_or_store_error_fun/0)
        end
      end
    end

    describe "get_or_store/3" do
      test "stores the value on a miss and returns it on a hit", %{cache: cache} do
        assert cache.get_or_store(:key, &cache.get_or_store_fun/0) == {:ok, "value"}
        assert cache.fetch!(:key) == "value"

        assert cache.get_or_store(:key, &must_not_be_called/0) == {:ok, "value"}
      end

      test "honors the :ttl option", %{cache: cache} do
        ttl = :timer.seconds(1)

        assert cache.get_or_store(:key, &cache.get_or_store_fun/0, ttl: ttl) == {:ok, "value"}

        assert_expires(cache, :key, ttl)
      end
    end

    describe "get_or_store!/3" do
      test "returns the value", %{cache: cache} do
        assert cache.get_or_store!(:key, &cache.get_or_store_fun/0) == "value"
        assert cache.get_or_store!(:key, &must_not_be_called/0) == "value"
      end
    end

    ## Helpers

    defp must_not_be_called do
      flunk("the function must not be called")
    end

    defp assert_expires(cache, key, ttl) do
      assert cache.has_key?(key) == {:ok, true}

      _ = t_sleep(ttl + 100)

      assert cache.has_key?(key) == {:ok, false}
    end
  end
end
