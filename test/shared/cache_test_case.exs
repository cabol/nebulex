defmodule Nebulex.CacheTestCase do
  @moduledoc """
  Shared Tests
  """

  @default_tests [
    Nebulex.Cache.KVTest,
    Nebulex.Cache.KVExpirationTest,
    Nebulex.Cache.KVPropTest,
    Nebulex.Cache.QueryableTest,
    Nebulex.Cache.QueryableExpirationTest,
    Nebulex.Cache.QueryableQueryErrorTest,
    Nebulex.Cache.TransactionTest
  ]

  defmacro __using__(opts) do
    only =
      opts
      |> Keyword.get(:only, @default_tests)
      |> Code.eval_quoted()
      |> elem(0)

    except =
      opts
      |> Keyword.get(:except, [])
      |> Code.eval_quoted()
      |> elem(0)

    for test <- only -- except do
      quote do
        use unquote(test)
      end
    end
  end
end
