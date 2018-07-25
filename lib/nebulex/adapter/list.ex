defmodule Nebulex.Adapter.List do
  @moduledoc """
  Specifies the adapter lists API.

  This API is based on Redis Lists API.
  """

  @type cache :: Nebulex.Cache.t()
  @type key :: Nebulex.Cache.key()
  @type value :: Nebulex.Cache.value()
  @type opts :: Nebulex.Cache.opts()

  @doc """
  Insert all the specified values at the head of the list stored at `key`.
  If `key` does not exist, it is created as empty list before performing
  the push operations. When key holds a value that is not a list, an error
  is raised.

  Returns the length of the list after the push operations.

  See `Nebulex.Cache.lpush/3`.
  """
  @callback lpush(cache, key, elements :: [value], opts) :: integer | no_return

  @doc """
  Insert all the specified values at the tail of the list stored at `key`.
  If key does not exist, it is created as empty list before performing
  the push operation. When key holds a value that is not a list, an error
  is raised.

  Returns the length of the list after the push operations.

  See `Nebulex.Cache.rpush/3`.
  """
  @callback rpush(cache, key, elements :: [value], opts) :: integer | no_return

  @doc """
  Removes and returns the first element of the list stored at `key`, or `nil`
  when key does not exist.

  See `Nebulex.Cache.lpop/2`.
  """
  @callback lpop(cache, key, opts) :: nil | value | no_return

  @doc """
  Removes and returns the last element of the list stored at `key`, or `nil`
  when key does not exist.

  See `Nebulex.Cache.rpop/2`.
  """
  @callback rpop(cache, key, opts) :: nil | value | no_return

  @doc """
  Returns the specified elements of the list stored at `key`. The `offset`
  is an integer >= 1 and the `limit` an integer >= 0.

  See `Nebulex.Cache.lrange/4`.
  """
  @callback lrange(cache, key, offset :: pos_integer, limit :: non_neg_integer, opts) ::
              [value] | no_return
end
