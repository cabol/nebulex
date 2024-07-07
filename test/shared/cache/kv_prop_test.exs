defmodule Nebulex.Cache.KVPropTest do
  import Nebulex.CacheCase

  deftests do
    use ExUnitProperties

    describe "key/value entries" do
      property "any term", %{cache: cache} do
        check all term <- term() do
          refute cache.get!(term)

          assert cache.replace!(term, term) == false
          assert cache.put!(term, term) == :ok
          assert cache.put_new!(term, term) == false
          assert cache.fetch!(term) == term

          assert cache.replace!(term, "replaced") == true
          assert cache.fetch!(term) == "replaced"

          assert cache.take!(term) == "replaced"
          assert {:error, %Nebulex.KeyError{key: key}} = cache.take(term)
          assert key == term

          assert cache.put_new!(term, term) == true
          assert cache.fetch!(term) == term

          assert cache.delete!(term) == :ok
          refute cache.get!(term)
        end
      end
    end
  end
end
