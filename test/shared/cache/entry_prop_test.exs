defmodule Nebulex.Cache.EntryPropTest do
  import Nebulex.CacheCase

  deftests do
    use ExUnitProperties

    describe "key/value entries" do
      property "any term", %{cache: cache} do
        check all term <- term() do
          refute cache.get(term)

          refute cache.replace(term, term)
          assert cache.put(term, term) == :ok
          refute cache.put_new(term, term)
          assert cache.get(term) == term

          assert cache.replace(term, "replaced")
          assert cache.get(term) == "replaced"

          assert cache.take(term) == "replaced"
          refute cache.take(term)

          assert cache.put_new(term, term)
          assert cache.get(term) == term

          assert cache.delete(term) == :ok
          refute cache.get(term)
        end
      end
    end
  end
end
