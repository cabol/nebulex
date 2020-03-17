defmodule Nebulex.Cache.Entry do
  @moduledoc false

  import Nebulex.Helpers

  alias Nebulex.Time

  @doc """
  Implementation for `c:Nebulex.Cache.get/2`.
  """
  def get(cache, key, opts) do
    cache.__adapter__.get(cache, key, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.get!/2`.
  """
  def get!(cache, key, opts) do
    if result = cache.get(key, opts) do
      result
    else
      raise KeyError, key: key, term: cache
    end
  end

  @doc """
  Implementation for `c:Nebulex.Cache.get_all/2`.
  """
  def get_all(_cache, [], _opts), do: %{}

  def get_all(cache, keys, opts) do
    cache.__adapter__.get_all(cache, keys, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.put/3`.
  """
  def put(cache, key, value, opts) do
    true = do_put(cache, key, value, :put, opts)
    :ok
  end

  @doc """
  Implementation for `c:Nebulex.Cache.put_new/3`.
  """
  def put_new(cache, key, value, opts) do
    do_put(cache, key, value, :put_new, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.put_new!/3`.
  """
  def put_new!(cache, key, value, opts) do
    with false <- cache.put_new(key, value, opts) do
      raise Nebulex.KeyAlreadyExistsError, cache: cache, key: key
    end
  end

  @doc """
  Implementation for `c:Nebulex.Cache.replace/3`.
  """
  def replace(cache, key, value, opts) do
    do_put(cache, key, value, :replace, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.replace!/3`.
  """
  def replace!(cache, key, value, opts) do
    with false <- cache.replace(key, value, opts) do
      raise KeyError, key: key, term: cache
    end
  end

  defp do_put(_cache, _key, nil, _on_write, _opts), do: true

  defp do_put(cache, key, value, on_write, opts) do
    cache.__adapter__.put(cache, key, value, get_ttl(opts), on_write, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.put_all/2`.
  """
  def put_all(cache, entries, opts) do
    _ = do_put_all(cache, entries, :put, opts)
    :ok
  end

  @doc """
  Implementation for `c:Nebulex.Cache.put_new_all/2`.
  """
  def put_new_all(cache, entries, opts) do
    do_put_all(cache, entries, :put_new, opts)
  end

  def do_put_all(_cache, [], _on_write, _opts), do: true
  def do_put_all(_cache, entries, _on_write, _opts) when map_size(entries) == 0, do: true

  def do_put_all(cache, entries, on_write, opts) do
    cache.__adapter__.put_all(cache, entries, get_ttl(opts), on_write, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.delete/2`.
  """
  def delete(cache, key, opts) do
    cache.__adapter__.delete(cache, key, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.take/2`.
  """
  def take(_cache, nil, _opts), do: nil

  def take(cache, key, opts) do
    cache.__adapter__.take(cache, key, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.take!/2`.
  """
  def take!(cache, key, opts) do
    if result = cache.take(key, opts) do
      result
    else
      raise KeyError, key: key, term: cache
    end
  end

  @doc """
  Implementation for `c:Nebulex.Cache.has_key?/1`.
  """
  def has_key?(cache, key) do
    cache.__adapter__.has_key?(cache, key)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.get_and_update/3`.
  """
  def get_and_update(cache, key, fun, opts) when is_function(fun, 1) do
    current = cache.__adapter__.get(cache, key, opts)

    case fun.(current) do
      {get, update} ->
        :ok = put(cache, key, update, opts)
        {get, update}

      :pop ->
        if current, do: delete(cache, key, opts)
        {current, nil}

      other ->
        raise ArgumentError,
              "the given function must return a two-element tuple or :pop, " <>
                "got: #{inspect(other)}"
    end
  end

  @doc """
  Implementation for `c:Nebulex.Cache.update/4`.
  """
  def update(cache, key, initial, fun, opts) do
    value =
      case cache.__adapter__.get(cache, key, opts) do
        nil -> initial
        val -> fun.(val)
      end

    :ok = put(cache, key, value, opts)
    value
  end

  @doc """
  Implementation for `c:Nebulex.Cache.incr/3`.
  """
  def incr(cache, key, incr, opts) when is_integer(incr) do
    cache.__adapter__.incr(cache, key, incr, get_ttl(opts), opts)
  end

  def incr(_cache, _key, incr, _opts) do
    raise ArgumentError, "expected incr to be an integer, got: #{inspect(incr)}"
  end

  @doc """
  Implementation for `c:Nebulex.Cache.ttl/1`.
  """
  def ttl(cache, key) do
    cache.__adapter__.ttl(cache, key)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.expire/2`.
  """
  def expire(cache, key, ttl) do
    ttl =
      (Time.timeout?(ttl) && ttl) ||
        raise ArgumentError, "expected ttl to be a valid timeout, got: #{inspect(ttl)}"

    cache.__adapter__.expire(cache, key, ttl)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.touch/1`.
  """
  def touch(cache, key) do
    cache.__adapter__.touch(cache, key)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.size/0`.
  """
  def size(cache) do
    cache.__adapter__.size(cache)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.flush/0`.
  """
  def flush(cache) do
    cache.__adapter__.flush(cache)
  end

  ## Helpers

  defp get_ttl(opts) do
    case get_option(opts, :ttl, &Time.timeout?/1, :infinity, &{:error, &1}) do
      {:error, val} ->
        raise ArgumentError, "expected ttl: to be a valid timeout, got: #{inspect(val)}"

      val ->
        val
    end
  end
end
