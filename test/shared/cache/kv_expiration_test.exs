defmodule Nebulex.Cache.KVExpirationTest do
  import Nebulex.CacheCase

  deftests do
    import Nebulex.CacheCase, only: [t_sleep: 1, rand_int: 0, rand_int: 1, rand_str: 0, rand_str: 1]

    describe ":ttl option on" do
      test "put!", %{cache: cache} do
        ttl = :timer.seconds(1)

        assert cache.put!("put with ttl", "test", ttl: ttl) == :ok
        assert cache.has_key?("put with ttl") == {:ok, true}

        _ = t_sleep(ttl + 100)

        assert cache.has_key?("put with ttl") == {:ok, false}
      end

      test "put_all!", %{cache: cache} do
        ttl = :timer.seconds(1)

        keys = rand_int(3)
        entries = [{"nil", nil} | Enum.map(keys, &{&1, &1})]

        assert cache.put_all!(entries, ttl: ttl) == :ok
        refute cache.get!("nil")

        for k <- keys do
          assert cache.fetch!(k) == k
        end

        _ = t_sleep(ttl + 200)

        for k <- keys do
          refute cache.get!(k)
        end
      end

      test "put_new_all!", %{cache: cache} do
        ttl = :timer.seconds(1)

        [k1, k2, k3] = rand_str(3)

        assert cache.put_new_all!(%{k1 => 1, k2 => 3}, ttl: ttl) == true
        assert cache.fetch!(k1) == 1
        assert cache.fetch!(k2) == 3

        assert cache.put_new_all!(%{k1 => 3, k3 => 1}) == false
        assert cache.fetch!(k1) == 1
        assert cache.fetch!(k2) == 3
        refute cache.get!(k3)

        _ = t_sleep(ttl + 200)

        refute cache.get!(k1)
        refute cache.get!(k2)
      end

      test "take", %{cache: cache} do
        ttl = :timer.seconds(1)

        :ok = cache.put!("take with ttl", "test", ttl: ttl)

        _ = t_sleep(ttl + 100)

        assert {:error, %Nebulex.KeyError{key: "take with ttl"}} = cache.take("take with ttl")
      end

      test "take!", %{cache: cache} do
        ttl = :timer.seconds(1)

        :ok = cache.put!("take! with ttl", "test", ttl: ttl)

        _ = t_sleep(ttl + 100)

        assert_raise Nebulex.KeyError, ~r"key \"take! with ttl\"", fn ->
          cache.take!("take! with ttl")
        end
      end

      test "put! [keep_ttl: true]", %{cache: cache} do
        ttl = :timer.seconds(1)
        str = rand_str()

        assert cache.put!(str, str, ttl: ttl, keep_ttl: true) == :ok
        assert cache.has_key?(str) == {:ok, true}

        assert cache.put!(str, str, keep_ttl: true) == :ok

        _ = t_sleep(ttl + 100)

        assert cache.has_key?(str) == {:ok, false}
      end

      test "put! [keep_ttl: false] (default)", %{cache: cache} do
        str = rand_str()

        assert cache.put!(str, str, ttl: :timer.seconds(1)) == :ok
        assert cache.ttl!(str) |> is_integer()

        assert cache.put!(str, str, ttl: :timer.minutes(1), keep_ttl: false) == :ok
        assert cache.ttl!(str) > :timer.seconds(1)

        assert cache.put!(str, str) == :ok
        assert cache.ttl!(str) == :infinity
      end

      test "replace! [keep_ttl: true]  (default)", %{cache: cache} do
        ttl = :timer.seconds(1)
        str = rand_str()

        assert cache.put!(str, str, ttl: ttl, keep_ttl: true) == :ok
        assert cache.has_key?(str) == {:ok, true}

        assert cache.replace!(str, str, keep_ttl: true) == true
        assert cache.replace!(str, str) == true

        _ = t_sleep(ttl + 100)

        assert cache.has_key?(str) == {:ok, false}
      end

      test "replace! [keep_ttl: false]", %{cache: cache} do
        str = rand_str()

        assert cache.put!(str, str, ttl: :timer.seconds(1)) == :ok
        assert cache.ttl!(str) |> is_integer()

        assert cache.replace!(str, str, keep_ttl: false) == true
        assert cache.ttl!(str) == :infinity
      end

      test "incr!", %{cache: cache} do
        ttl = :timer.seconds(1)

        assert cache.incr!(:incr_counter, 1, ttl: ttl) == 1
        assert cache.incr!(:incr_counter, 2) == 3

        t = t_sleep(ttl + 100)

        assert cache.incr!(:incr_counter, 1, ttl: ttl) == 1
        assert cache.incr!(:incr_counter) == 2

        _ = t_sleep(t + ttl + 100)

        refute cache.get!(:incr_counter)
      end
    end

    describe "ttl!/1" do
      test "returns the remaining ttl for the given key", %{cache: cache} do
        ttl = :timer.seconds(1)

        assert cache.put!(:ttl!, 1, ttl: ttl) == :ok
        assert cache.ttl!(:ttl!) > 0
        assert cache.put!(:infinity_ttl, 2) == :ok

        t = t_sleep(10)

        assert cache.ttl!(:ttl!) > 0
        assert cache.ttl!(:infinity_ttl) == :infinity

        _ = t_sleep(ttl + t + 10)

        assert {:error, %Nebulex.KeyError{key: :ttl!}} = cache.ttl(:ttl!)
        assert cache.ttl!(:infinity_ttl) == :infinity
      end

      test "raises Nebulex.KeyError if key does not exist", %{cache: cache} do
        msg = ~r/key :non_existent not found/

        assert_raise Nebulex.KeyError, msg, fn ->
          cache.ttl!(:non_existent)
        end
      end
    end

    describe "expire!/2" do
      test "alters the expiration time for the given key", %{cache: cache} do
        assert cache.put!(:expire!, 1, ttl: :timer.seconds(1)) == :ok
        assert cache.ttl!(:expire!) > 0

        assert cache.expire!(:expire!, :timer.seconds(10)) == true
        assert cache.ttl!(:expire!) > :timer.seconds(1)

        assert cache.expire!(:expire!, :infinity) == true
        assert cache.ttl!(:expire!) == :infinity
      end

      test "returns false if key does not exist", %{cache: cache} do
        assert cache.expire!(:non_existent, 100) == false
        assert cache.expire!(:non_existent, :infinity) == false
      end

      test "raises when ttl is invalid", %{cache: cache} do
        assert_raise ArgumentError, ~r"expected ttl to be a valid timeout", fn ->
          cache.expire!(:expire!, "hello")
        end
      end
    end

    describe "touch!/1" do
      test "updates the last access time for the given entry", %{cache: cache} do
        ttl = :timer.seconds(1)

        assert cache.put!(:touch, 1, ttl: ttl) == :ok

        t = t_sleep(10)

        assert cache.touch!(:touch) == true

        t = t_sleep(t + 10)

        assert cache.touch!(:touch) == true
        assert cache.fetch!(:touch) == 1

        _ = t_sleep(ttl + t + 10)

        refute cache.get!(:touch)
      end

      test "returns false if key does not exist", %{cache: cache} do
        assert cache.touch!(:non_existent) == false
      end
    end

    describe "expiration" do
      test "single entry put with  ttl", %{cache: cache} do
        ttl = :timer.seconds(1)
        key = rand_int()

        assert cache.put!(key, 11, ttl: ttl) == :ok

        t =
          Enum.reduce(1..3, 0, fn _, acc ->
            assert cache.ttl!(key) > 0

            t_sleep(acc + 10)
          end)

        _ = t_sleep(ttl + t)

        assert {:error, %Nebulex.KeyError{key: ^key}} = cache.ttl(key)
        assert cache.put!(key, 11, ttl: 1000) == :ok
        assert cache.ttl!(key) > 0
      end

      test "multiple entries put with ttl", %{cache: cache} do
        ttl = :timer.seconds(1)
        key = rand_int()

        assert cache.put!(key, 11, ttl: ttl) == :ok
        assert cache.fetch!(key) == 11

        t = t_sleep(10)

        assert cache.fetch!(key) == 11

        t = t_sleep(t + ttl)

        refute cache.get!(key)

        ops = [
          put!: [key, "bar", [ttl: ttl]],
          put_all!: [[{key, "bar"}], [ttl: ttl]]
        ]

        Enum.reduce(ops, t, fn {action, args}, acc ->
          assert apply(cache, action, args) == :ok

          t = t_sleep(acc + 10)

          assert cache.fetch!(key) == "bar"

          t = t_sleep(t + ttl + 10)

          refute cache.get!(key)

          t
        end)
      end
    end

    describe "get_and_update with ttl" do
      test "existing entry", %{cache: cache} do
        ttl = :timer.seconds(1)
        key = rand_int()

        assert cache.put!(key, 1, ttl: ttl) == :ok
        assert cache.ttl!(key) > 0

        t = t_sleep(10)

        assert cache.get_and_update!(key, &cache.get_and_update_fun/1) == {1, 2}
        assert cache.ttl!(key) == :infinity

        _ = t_sleep(t + ttl + 10)

        assert cache.fetch!(key) == 2
      end
    end

    describe "update with ttl" do
      test "existing entry", %{cache: cache} do
        ttl = :timer.seconds(1)
        key = rand_int()

        assert cache.put!(key, 1, ttl: ttl) == :ok
        assert cache.ttl!(key) > 0

        t = t_sleep(10)

        assert cache.update!(key, 10, &Integer.to_string/1) == "1"
        assert cache.ttl!(key) == :infinity

        _ = t_sleep(t + ttl + 10)

        assert cache.fetch!(key) == "1"
      end
    end

    describe "incr with ttl" do
      test "increments a counter", %{cache: cache} do
        ttl = :timer.seconds(1)

        assert cache.incr!(:counter_ttl, 1, ttl: ttl) == 1
        assert cache.incr!(:counter_ttl, 1, ttl: ttl) == 2
        assert cache.ttl!(:counter_ttl) > 0

        _ = t_sleep(ttl + 200)

        refute cache.get!(:counter_ttl)
      end

      test "increments a counter and then set ttl", %{cache: cache} do
        assert cache.incr!(:counter_ttl2, 1) == 1
        assert cache.ttl!(:counter_ttl2) == :infinity

        ttl = :timer.seconds(1)

        assert cache.expire!(:counter_ttl2, ttl) == true

        _ = t_sleep(ttl + 100)

        refute cache.get!(:counter_ttl2)
      end
    end
  end
end
