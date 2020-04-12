defmodule Nebulex.Cache.EntryTest do
  import Nebulex.SharedTestCase

  deftests "cache" do
    alias Nebulex.TestCache.Partitioned

    ## Entries

    test "delete" do
      for x <- 1..3, do: @cache.put(x, x * 2)

      assert 2 == @cache.get(1)
      assert :ok == @cache.delete(1)
      refute @cache.get(1)

      assert 4 == @cache.get(2)
      assert 6 == @cache.get(3)

      assert :ok == @cache.delete(:non_existent)
      refute @cache.get(:non_existent)
    end

    test "get" do
      for x <- 1..2, do: @cache.put(x, x)

      assert 1 == @cache.get(1)
      assert 2 == @cache.get(2)
      refute @cache.get(3)
    end

    test "get!" do
      for x <- 1..2, do: @cache.put(x, x)

      assert 1 == @cache.get!(1)
      assert 2 == @cache.get!(2)

      assert_raise KeyError, fn ->
        @cache.get!(3)
      end
    end

    test "get_all" do
      assert @cache.put_all(a: 1, c: 3)

      map = @cache.get_all([:a, :b, :c], version: -1)
      assert %{a: 1, c: 3} == map
      refute map[:b]

      assert 0 == map_size(@cache.get_all([]))
      assert 2 == @cache.flush()
    end

    test "put" do
      for x <- 1..4, do: assert(:ok == @cache.put(x, x))

      assert 1 == @cache.get(1)
      assert 2 == @cache.get(2)

      for x <- 3..4, do: assert(:ok = @cache.put(x, x * x))
      assert 9 == @cache.get(3)
      assert 16 == @cache.get(4)

      assert :ok == @cache.put("foo", nil)
      refute @cache.get("foo")
    end

    test "put_new" do
      assert @cache.put_new("foo", "bar")
      assert "bar" == @cache.get("foo")

      refute @cache.put_new("foo", "bar bar")
      assert "bar" == @cache.get("foo")

      assert @cache.put_new(:mykey, nil)
      refute @cache.get(:mykey)
    end

    test "put_new!" do
      assert @cache.put_new!("hello", "world")

      message = ~r"key \"hello\" already exists in cache"

      assert_raise Nebulex.KeyAlreadyExistsError, message, fn ->
        @cache.put_new!("hello", "world world")
      end
    end

    test "replace" do
      refute @cache.replace("foo", "bar")

      assert :ok == @cache.put("foo", "bar")
      assert "bar" == @cache.get("foo")

      assert @cache.replace("foo", "bar bar")
      assert "bar bar" == @cache.get("foo")

      assert @cache.replace(:mykey, nil)
      refute @cache.get(:mykey)
    end

    test "replace!" do
      assert_raise KeyError, fn ->
        @cache.replace!("foo", "bar")
      end

      assert :ok == @cache.put("foo", "bar")
      assert @cache.replace!("foo", "bar bar")
      assert "bar bar" == @cache.get("foo")
    end

    test "put key terms" do
      refute @cache.get({:mykey, 1, "hello"})
      assert :ok == @cache.put({:mykey, 1, "hello"}, "world")
      assert "world" == @cache.get({:mykey, 1, "hello"})

      refute @cache.get(%{a: 1, b: 2})
      assert :ok == @cache.put(%{a: 1, b: 2}, "value")
      assert "value" == @cache.get(%{a: 1, b: 2})
    end

    test "put with invalid options" do
      for action <- [:put, :put_new, :replace] do
        assert_raise ArgumentError, ~r"expected ttl: to be a valid timeout", fn ->
          apply(@cache, action, ["hello", "world", [ttl: "1"]])
        end
      end
    end

    test "put_all" do
      entries = [{0, nil} | for(x <- 1..3, do: {x, x})]
      assert @cache.put_all(entries, ttl: 1000)

      refute @cache.get(0)
      for x <- 1..3, do: assert(x == @cache.get(x))
      :ok = Process.sleep(1200)
      for x <- 1..3, do: refute(@cache.get(x))

      assert @cache.put_all(%{"apples" => 1, "bananas" => 3})
      assert @cache.put_all(blueberries: 2, strawberries: 5)
      assert 1 == @cache.get("apples")
      assert 3 == @cache.get("bananas")
      assert 2 == @cache.get(:blueberries)
      assert 5 == @cache.get(:strawberries)

      assert @cache.put_all([])
      assert @cache.put_all(%{})
      assert count = @cache.size()
      assert count == @cache.flush()
    end

    test "put_new_all" do
      assert @cache.put_new_all(%{"apples" => 1, "bananas" => 3}, ttl: 1000)
      assert 1 == @cache.get("apples")
      assert 3 == @cache.get("bananas")

      refute @cache.put_new_all(%{"apples" => 3, "oranges" => 1})
      assert 1 == @cache.get("apples")
      assert 3 == @cache.get("bananas")
      refute @cache.get("oranges")

      :ok = Process.sleep(1200)
      refute @cache.get("apples")
      refute @cache.get("bananas")
    end

    test "put_all with invalid options" do
      assert_raise ArgumentError, ~r"expected ttl: to be a valid timeout", fn ->
        @cache.put_all(%{"apples" => 1, "bananas" => 3}, ttl: "1")
      end
    end

    test "take" do
      for x <- 1..2, do: @cache.put(x, x)

      assert 1 == @cache.take(1)
      assert 2 == @cache.take(2)
      refute @cache.take(3)
      refute @cache.take(nil)

      for x <- 1..3, do: refute(@cache.get(x))

      assert :ok == @cache.put("foo", "bar", ttl: 500)
      :ok = Process.sleep(600)
      refute @cache.take(1)
    end

    test "take!" do
      assert :ok == @cache.put(1, 1, ttl: 100)
      assert 1 == @cache.take!(1)

      assert_raise KeyError, fn ->
        @cache.take!(1)
      end

      assert_raise KeyError, fn ->
        @cache.take!(nil)
      end
    end

    test "has_key?" do
      for x <- 1..2, do: @cache.put(x, x)

      assert @cache.has_key?(1)
      assert @cache.has_key?(2)
      refute @cache.has_key?(3)
    end

    test "has_key? expired key" do
      assert :ok == @cache.put("foo", "bar", ttl: 500)
      assert @cache.has_key?("foo")

      Process.sleep(600)
      refute @cache.has_key?("foo")
    end

    test "ttl" do
      assert :ok == @cache.put(:a, 1, ttl: 500)
      assert @cache.ttl(:a) > 0
      assert :ok == @cache.put(:b, 2)

      :ok = Process.sleep(10)
      assert @cache.ttl(:a) > 0
      assert @cache.ttl(:b) == :infinity
      refute @cache.ttl(:c)

      :ok = Process.sleep(600)
      refute @cache.ttl(:a)
    end

    test "expire" do
      assert :ok == @cache.put(:a, 1, ttl: 500)
      assert @cache.ttl(:a) > 0

      assert @cache.expire(:a, 1000)
      assert @cache.ttl(:a) > 100

      assert @cache.expire(:a, :infinity)
      assert @cache.ttl(:a) == :infinity

      refute @cache.expire(:b, 5)

      assert_raise ArgumentError, ~r"expected ttl to be a valid timeout", fn ->
        @cache.expire(:a, "hello")
      end
    end

    test "touch" do
      assert :ok == @cache.put(:touch, 1, ttl: 1000)

      :ok = Process.sleep(100)
      assert @cache.touch(:touch)

      :ok = Process.sleep(200)
      assert @cache.touch(:touch)
      assert 1 == @cache.get(:touch)

      :ok = Process.sleep(1100)
      refute @cache.get(:touch)

      refute @cache.touch(:non_existent)
    end

    test "size" do
      for x <- 1..100, do: @cache.put(x, x)
      assert 100 == @cache.size

      for x <- 1..50, do: @cache.delete(x)
      assert 50 == @cache.size

      for x <- 51..60, do: assert(@cache.get(x) == x)
      assert 50 == @cache.size()
    end

    test "flush" do
      Enum.each(1..2, fn _ ->
        for x <- 1..100, do: @cache.put(x, x)

        assert @cache.flush() == 100
        :ok = Process.sleep(500)

        for x <- 1..100, do: refute(@cache.get(x))
      end)
    end

    test "update" do
      for x <- 1..2, do: @cache.put(x, x)

      fun = &Integer.to_string/1

      assert "1" == @cache.update(1, 1, fun)
      assert "2" == @cache.update(2, 1, fun)
      assert 1 == @cache.update(3, 1, fun)
      refute @cache.update(4, nil, fun)
      refute @cache.get(4)
    end

    test "incr" do
      assert 1 == @cache.incr(:counter)
      assert 2 == @cache.incr(:counter)
      assert 4 == @cache.incr(:counter, 2)
      assert 7 == @cache.incr(:counter, 3)
      assert 7 == @cache.incr(:counter, 0)

      assert 7 == :counter |> @cache.get() |> to_int()

      assert 6 == @cache.incr(:counter, -1)
      assert 5 == @cache.incr(:counter, -1)
      assert 3 == @cache.incr(:counter, -2)
      assert 0 == @cache.incr(:counter, -3)

      assert_raise ArgumentError, fn ->
        @cache.incr(:counter, "foo")
      end
    end

    test "incr and then set ttl" do
      assert 1 == @cache.incr(:counter, 1)
      assert :infinity == @cache.ttl(:counter)

      assert @cache.expire(:counter, 500)
      :ok = Process.sleep(600)
      refute @cache.get(:counter)
    end

    test "key expiration with ttl" do
      assert :ok == @cache.put(1, 11, ttl: 1000)
      assert 11 == @cache.get!(1)

      :ok = Process.sleep(10)
      assert 11 == @cache.get(1)
      :ok = Process.sleep(1100)
      refute @cache.get(1)

      ops = [
        put: ["foo", "bar", [ttl: 1000]],
        put_all: [[{"foo", "bar"}], [ttl: 1000]]
      ]

      for {action, args} <- ops do
        assert :ok == apply(@cache, action, args)
        :ok = Process.sleep(10)
        assert "bar" == @cache.get("foo")
        :ok = Process.sleep(1200)
        refute @cache.get("foo")

        assert :ok == apply(@cache, action, args)
        :ok = Process.sleep(10)
        assert "bar" == @cache.get("foo")
        :ok = Process.sleep(1200)
        refute @cache.get("foo")
      end
    end

    test "entry ttl" do
      assert :ok == @cache.put(1, 11, ttl: 1000)
      assert 11 == @cache.get!(1)

      for _ <- 3..1 do
        assert @cache.ttl(1) > 0
        Process.sleep(200)
      end

      :ok = Process.sleep(500)
      refute @cache.ttl(1)
      assert :ok == @cache.put(1, 11, ttl: 1000)
      assert @cache.ttl(1) > 0
    end

    test "get_and_update existing entry with ttl" do
      assert :ok == @cache.put(1, 1, ttl: 1000)
      assert @cache.ttl(1) > 0

      :ok = Process.sleep(10)

      assert {1, 2} == @cache.get_and_update(1, &Partitioned.get_and_update_fun/1)
      assert :infinity == @cache.ttl(1)

      :ok = Process.sleep(1200)
      assert 2 == @cache.get(1)
    end

    test "update existing entry with ttl" do
      assert :ok == @cache.put(1, 1, ttl: 1000)
      assert @cache.ttl(1) > 0

      :ok = Process.sleep(10)

      assert "1" == @cache.update(1, 10, &Integer.to_string/1)
      assert @cache.ttl(1) == :infinity

      :ok = Process.sleep(1200)
      assert "1" == @cache.get(1)
    end

    ## Helpers

    defp to_int(data) when is_integer(data), do: data
    defp to_int(data) when is_binary(data), do: String.to_integer(data)
  end
end
