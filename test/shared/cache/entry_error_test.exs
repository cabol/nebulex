defmodule Nebulex.Cache.EntryErrorTest do
  import Nebulex.CacheCase

  deftests do
    import Mock

    describe "put/3" do
      test_with_mock "returns an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        put: fn _, _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert cache.put("hello", "world") ==
                 {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
      end
    end

    describe "put!/3" do
      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        put: fn _, _, _, _, _, _ -> {:error, %RuntimeError{message: "error"}} end do
        assert_raise RuntimeError, ~r"error", fn ->
          cache.put!("hello", "world")
        end
      end
    end

    describe "put_new/3" do
      test_with_mock "returns an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        put: fn _, _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert cache.put_new("hello", "world") ==
                 {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
      end
    end

    describe "put_new!/3" do
      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        put: fn _, _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.put_new!("hello", "world")
        end
      end
    end

    describe "replace/3" do
      test_with_mock "returns an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        put: fn _, _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert cache.replace("hello", "world") ==
                 {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
      end
    end

    describe "replace!/3" do
      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        put: fn _, _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.replace!("hello", "world")
        end
      end
    end

    describe "put_all/2" do
      test_with_mock "returns an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        put_all: fn _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert cache.put_all(%{"apples" => 1, "bananas" => 3}) ==
                 {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
      end
    end

    describe "put_all!/2" do
      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        put_all: fn _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.put_all!(other: 1)
        end
      end
    end

    describe "put_new_all/2" do
      test_with_mock "returns an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        put_all: fn _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert cache.put_new_all(%{"apples" => 1, "bananas" => 3}) ==
                 {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
      end
    end

    describe "put_new_all!/2" do
      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        put_all: fn _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.put_new_all!(other: 1)
        end
      end
    end

    describe "fetch/2" do
      test_with_mock "returns an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        fetch: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert cache.fetch(1) == {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
      end
    end

    describe "fetch!/2" do
      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        fetch: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.fetch!("raise")
        end
      end
    end

    describe "get/2" do
      test_with_mock "returns an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        fetch: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert {:error, %Nebulex.Error{reason: :error}} = cache.get("error")
      end
    end

    describe "get!/2" do
      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        fetch: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.get!("raise")
        end
      end
    end

    describe "get_all/2" do
      test_with_mock "returns an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        get_all: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert cache.get_all(1) == {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
      end
    end

    describe "get_all!/2" do
      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        get_all: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.get_all!([:foo])
        end
      end
    end

    describe "delete/2" do
      test_with_mock "returns an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        delete: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert cache.delete("error") ==
                 {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
      end
    end

    describe "delete!/2" do
      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        delete: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.delete!("raise")
        end
      end
    end

    describe "take/2" do
      test_with_mock "returns an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        take: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert cache.take("error") ==
                 {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
      end
    end

    describe "take!/2" do
      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        take: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.take!("raise")
        end
      end
    end

    describe "exists?/1" do
      test_with_mock "returns an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        exists?: fn _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert cache.exists?("error") ==
                 {:error, %Nebulex.Error{module: Nebulex.Error, reason: :error}}
      end
    end

    describe "update!/4" do
      test_with_mock "raises because put error",
                     %{cache: cache},
                     cache.__adapter__(),
                     [:passthrough],
                     put: fn _, _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.update!("error", 1, &String.to_integer/1)
        end
      end

      test_with_mock "raises because fetch error",
                     %{cache: cache},
                     cache.__adapter__(),
                     [:passthrough],
                     fetch: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.update!("error", 1, &String.to_integer/1)
        end
      end
    end

    describe "incr!/3" do
      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        update_counter: fn _, _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.incr!(:raise)
        end
      end
    end

    describe "decr!/3" do
      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        update_counter: fn _, _, _, _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.decr!(:raise)
        end
      end
    end
  end
end
