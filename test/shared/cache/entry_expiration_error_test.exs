defmodule Nebulex.Cache.EntryExpirationErrorTest do
  import Nebulex.CacheCase

  deftests do
    import Mock

    describe "expire!/2" do
      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        expire: fn _, _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.expire!(:raise, 100)
        end
      end
    end

    describe "touch!/1" do
      test_with_mock "raises an error", %{cache: cache}, cache.__adapter__(), [:passthrough],
        touch: fn _, _ -> {:error, %Nebulex.Error{reason: :error}} end do
        assert_raise Nebulex.Error, ~r"Nebulex error:\n\n:error", fn ->
          cache.touch!(:raise)
        end
      end
    end
  end
end
