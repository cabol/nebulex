defmodule Nebulex.Cache.KVExpirationTest do
  import Nebulex.CacheCase

  deftests do
    import Nebulex.CacheCase, only: [t_sleep: 1]

    describe ":ttl option on" do
      test "put!", %{cache: cache} do
        ttl = :timer.seconds(1)

        assert cache.put!("foo", "bar", ttl: ttl) == :ok
        assert cache.has_key?("foo") == {:ok, true}

        _ = t_sleep(ttl + 100)

        assert cache.has_key?("foo") == {:ok, false}
      end

      test "put_all!", %{cache: cache} do
        ttl = :timer.seconds(1)

        entries = [{0, nil} | for(x <- 1..3, do: {x, x})]

        assert cache.put_all!(entries, ttl: ttl) == :ok

        refute cache.get!(0)

        for x <- 1..3, do: assert(cache.fetch!(x) == x)

        _ = t_sleep(ttl + 200)

        for x <- 1..3, do: refute(cache.get!(x))
      end

      test "put_new_all!", %{cache: cache} do
        ttl = :timer.seconds(1)

        assert cache.put_new_all!(%{"apples" => 1, "bananas" => 3}, ttl: ttl) == true
        assert cache.fetch!("apples") == 1
        assert cache.fetch!("bananas") == 3

        assert cache.put_new_all!(%{"apples" => 3, "oranges" => 1}) == false
        assert cache.fetch!("apples") == 1
        assert cache.fetch!("bananas") == 3
        refute cache.get!("oranges")

        _ = t_sleep(ttl + 200)

        refute cache.get!("apples")
        refute cache.get!("bananas")
      end

      test "take", %{cache: cache} do
        ttl = :timer.seconds(1)

        :ok = cache.put!("foo", "bar", ttl: ttl)

        _ = t_sleep(ttl + 100)

        assert {:error, %Nebulex.KeyError{key: "foo"}} = cache.take("foo")
      end

      test "take!", %{cache: cache} do
        ttl = :timer.seconds(1)

        :ok = cache.put!(1, 1, ttl: ttl)

        _ = t_sleep(ttl + 100)

        assert_raise Nebulex.KeyError, ~r"key 1", fn ->
          cache.take!(1)
        end
      end

      test "put! [keep_ttl: true]", %{cache: cache} do
        ttl = :timer.seconds(1)

        assert cache.put!("foo", "bar", ttl: ttl) == :ok
        assert cache.has_key?("foo") == {:ok, true}

        assert cache.put!("foo", "bar", keep_ttl: true) == :ok

        _ = t_sleep(ttl + 100)

        assert cache.has_key?("foo") == {:ok, false}
      end

      test "put! [keep_ttl: false] (default)", %{cache: cache} do
        assert cache.put!("foo", "bar", ttl: :timer.seconds(1)) == :ok
        assert cache.ttl!("foo") |> is_integer()

        assert cache.put!("foo", "bar", ttl: :timer.minutes(1), keep_ttl: false) == :ok
        assert cache.ttl!("foo") > :timer.seconds(1)

        assert cache.put!("foo", "bar") == :ok
        assert cache.ttl!("foo") == :infinity
      end

      test "replace! [keep_ttl: true]  (default)", %{cache: cache} do
        ttl = :timer.seconds(1)

        assert cache.put!("foo", "bar", ttl: ttl) == :ok
        assert cache.has_key?("foo") == {:ok, true}

        assert cache.replace!("foo", "bar", keep_ttl: true) == true
        assert cache.replace!("foo", "bar") == true

        _ = t_sleep(ttl + 100)

        assert cache.has_key?("foo") == {:ok, false}
      end

      test "replace! [keep_ttl: false]", %{cache: cache} do
        assert cache.put!("foo", "bar", ttl: :timer.seconds(1)) == :ok
        assert cache.ttl!("foo") |> is_integer()

        assert cache.replace!("foo", "bar", keep_ttl: false) == true
        assert cache.ttl!("foo") == :infinity
      end

      test "incr!", %{cache: cache} do
        ttl = :timer.seconds(1)

        assert cache.incr!(:counter, 1, ttl: ttl) == 1
        assert cache.incr!(:counter, 2) == 3

        t = t_sleep(ttl + 10)

        assert cache.incr!(:counter, 1, ttl: ttl) == 1
        assert cache.incr!(:counter) == 2

        _ = t_sleep(t + ttl + 10)

        refute cache.get!(:counter)
      end
    end

    describe "ttl!/1" do
      test "returns the remaining ttl for the given key", %{cache: cache} do
        ttl = :timer.seconds(1)

        assert cache.put!(:a, 1, ttl: ttl) == :ok
        assert cache.ttl!(:a) > 0
        assert cache.put!(:b, 2) == :ok

        t = t_sleep(10)

        assert cache.ttl!(:a) > 0
        assert cache.ttl!(:b) == :infinity

        _ = t_sleep(ttl + t + 10)

        assert {:error, %Nebulex.KeyError{key: :a}} = cache.ttl(:a)
        assert cache.ttl!(:b) == :infinity
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
        assert cache.put!(:a, 1, ttl: :timer.seconds(1)) == :ok
        assert cache.ttl!(:a) > 0

        assert cache.expire!(:a, :timer.seconds(10)) == true
        assert cache.ttl!(:a) > :timer.seconds(1)

        assert cache.expire!(:a, :infinity) == true
        assert cache.ttl!(:a) == :infinity
      end

      test "returns false if key does not exist", %{cache: cache} do
        assert cache.expire!(:non_existent, 100) == false
      end

      test "raises when ttl is invalid", %{cache: cache} do
        assert_raise ArgumentError, ~r"expected ttl to be a valid timeout", fn ->
          cache.expire!(:a, "hello")
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

        assert cache.put!(1, 11, ttl: ttl) == :ok

        t =
          Enum.reduce(1..3, 0, fn _, acc ->
            assert cache.ttl!(1) > 0

            t_sleep(acc + 10)
          end)

        _ = t_sleep(ttl + t)

        assert {:error, %Nebulex.KeyError{key: 1}} = cache.ttl(1)
        assert cache.put!(1, 11, ttl: 1000) == :ok
        assert cache.ttl!(1) > 0
      end

      test "multiple entries put with ttl", %{cache: cache} do
        ttl = :timer.seconds(1)

        assert cache.put!(1, 11, ttl: ttl) == :ok
        assert cache.fetch!(1) == 11

        t = t_sleep(10)

        assert cache.fetch!(1) == 11

        t = t_sleep(t + ttl)

        refute cache.get!(1)

        ops = [
          put!: ["foo", "bar", [ttl: ttl]],
          put_all!: [[{"foo", "bar"}], [ttl: ttl]]
        ]

        Enum.reduce(ops, t, fn {action, args}, acc ->
          assert apply(cache, action, args) == :ok

          t = t_sleep(acc + 10)

          assert cache.fetch!("foo") == "bar"

          t = t_sleep(t + ttl + 10)

          refute cache.get!("foo")

          t
        end)
      end
    end

    describe "get_and_update with ttl" do
      test "existing entry", %{cache: cache} do
        ttl = :timer.seconds(1)

        assert cache.put!(1, 1, ttl: ttl) == :ok
        assert cache.ttl!(1) > 0

        t = t_sleep(10)

        assert cache.get_and_update!(1, &cache.get_and_update_fun/1) == {1, 2}
        assert cache.ttl!(1) == :infinity

        _ = t_sleep(t + ttl + 10)

        assert cache.fetch!(1) == 2
      end
    end

    describe "update with ttl" do
      test "existing entry", %{cache: cache} do
        ttl = :timer.seconds(1)

        assert cache.put!(1, 1, ttl: ttl) == :ok
        assert cache.ttl!(1) > 0

        t = t_sleep(10)

        assert cache.update!(1, 10, &Integer.to_string/1) == "1"
        assert cache.ttl!(1) == :infinity

        _ = t_sleep(t + ttl + 10)

        assert cache.fetch!(1) == "1"
      end
    end

    describe "incr with ttl" do
      test "increments a counter", %{cache: cache} do
        ttl = :timer.seconds(1)

        assert cache.incr!(:counter, 1, ttl: ttl) == 1
        assert cache.ttl!(:counter) > 0

        _ = t_sleep(ttl + 200)

        refute cache.get!(:counter)
      end

      test "increments a counter and then set ttl", %{cache: cache} do
        assert cache.incr!(:counter, 1) == 1
        assert cache.ttl!(:counter) == :infinity

        ttl = :timer.seconds(1)

        assert cache.expire!(:counter, ttl) == true

        _ = t_sleep(ttl + 100)

        refute cache.get!(:counter)
      end
    end
  end
end
