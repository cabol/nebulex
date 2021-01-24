defmodule Nebulex.Cache.Entry do
  @moduledoc false

  import Nebulex.Helpers

  alias Nebulex.{Adapter, Time}

  # Inline common instructions
  @compile {:inline, get_ttl: 1}

  @doc """
  Implementation for `c:Nebulex.Cache.get/2`.
  """
  def get(name, key, opts) do
    Adapter.with_meta(name, & &1.get(&2, key, opts))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.get!/2`.
  """
  def get!(name, key, opts) do
    if result = get(name, key, opts) do
      result
    else
      raise KeyError, key: key, term: name
    end
  end

  @doc """
  Implementation for `c:Nebulex.Cache.get_all/2`.
  """
  def get_all(_name, [], _opts), do: %{}

  def get_all(name, keys, opts) do
    Adapter.with_meta(name, & &1.get_all(&2, keys, opts))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.put/3`.
  """
  def put(name, key, value, opts) do
    true = do_put(name, key, value, :put, opts)
    :ok
  end

  @doc """
  Implementation for `c:Nebulex.Cache.put_new/3`.
  """
  def put_new(name, key, value, opts) do
    do_put(name, key, value, :put_new, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.put_new!/3`.
  """
  def put_new!(name, key, value, opts) do
    with false <- put_new(name, key, value, opts) do
      raise Nebulex.KeyAlreadyExistsError, cache: name, key: key
    end
  end

  @doc """
  Implementation for `c:Nebulex.Cache.replace/3`.
  """
  def replace(name, key, value, opts) do
    do_put(name, key, value, :replace, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.replace!/3`.
  """
  def replace!(name, key, value, opts) do
    with false <- replace(name, key, value, opts) do
      raise KeyError, key: key, term: name
    end
  end

  defp do_put(_name, _key, nil, _on_write, _opts), do: true

  defp do_put(name, key, value, on_write, opts) do
    Adapter.with_meta(name, & &1.put(&2, key, value, get_ttl(opts), on_write, opts))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.put_all/2`.
  """
  def put_all(name, entries, opts) do
    _ = do_put_all(name, entries, :put, opts)
    :ok
  end

  @doc """
  Implementation for `c:Nebulex.Cache.put_new_all/2`.
  """
  def put_new_all(name, entries, opts) do
    do_put_all(name, entries, :put_new, opts)
  end

  def do_put_all(_name, [], _on_write, _opts), do: true
  def do_put_all(_name, entries, _on_write, _opts) when map_size(entries) == 0, do: true

  def do_put_all(name, entries, on_write, opts) do
    Adapter.with_meta(name, & &1.put_all(&2, entries, get_ttl(opts), on_write, opts))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.delete/2`.
  """
  def delete(name, key, opts) do
    Adapter.with_meta(name, & &1.delete(&2, key, opts))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.take/2`.
  """
  def take(_name, nil, _opts), do: nil

  def take(name, key, opts) do
    Adapter.with_meta(name, & &1.take(&2, key, opts))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.take!/2`.
  """
  def take!(name, key, opts) do
    if result = take(name, key, opts) do
      result
    else
      raise KeyError, key: key, term: name
    end
  end

  @doc """
  Implementation for `c:Nebulex.Cache.has_key?/1`.
  """
  def has_key?(name, key) do
    Adapter.with_meta(name, & &1.has_key?(&2, key))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.get_and_update/3`.
  """
  def get_and_update(name, key, fun, opts) when is_function(fun, 1) do
    Adapter.with_meta(name, fn adapter, adapter_meta ->
      current = adapter.get(adapter_meta, key, opts)

      case fun.(current) do
        {get, nil} ->
          {get, get}

        {get, update} ->
          true = adapter.put(adapter_meta, key, update, get_ttl(opts), :put, opts)
          {get, update}

        :pop when is_nil(current) ->
          {nil, nil}

        :pop ->
          :ok = adapter.delete(adapter_meta, key, opts)
          {current, nil}

        other ->
          raise ArgumentError,
                "the given function must return a two-element tuple or :pop," <>
                  " got: #{inspect(other)}"
      end
    end)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.update/4`.
  """
  def update(name, key, initial, fun, opts) do
    Adapter.with_meta(name, fn adapter, adapter_meta ->
      adapter_meta
      |> adapter.get(key, opts)
      |> case do
        nil -> {initial, nil}
        val -> {fun.(val), val}
      end
      |> case do
        {nil, old} ->
          # avoid storing nil values
          old

        {new, _} ->
          true = adapter.put(adapter_meta, key, new, get_ttl(opts), :put, opts)
          new
      end
    end)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.incr/3`.
  """
  def incr(name, key, amount, opts) when is_integer(amount) do
    default = get_option(opts, :default, "an integer", &is_integer/1, 0)
    Adapter.with_meta(name, & &1.update_counter(&2, key, amount, get_ttl(opts), default, opts))
  end

  def incr(_cache, _key, amount, _opts) do
    raise ArgumentError, "expected amount to be an integer, got: #{inspect(amount)}"
  end

  @doc """
  Implementation for `c:Nebulex.Cache.decr/3`.
  """
  def decr(name, key, amount, opts) when is_integer(amount) do
    incr(name, key, amount * -1, opts)
  end

  def decr(_cache, _key, amount, _opts) do
    raise ArgumentError, "expected amount to be an integer, got: #{inspect(amount)}"
  end

  @doc """
  Implementation for `c:Nebulex.Cache.ttl/1`.
  """
  def ttl(name, key) do
    Adapter.with_meta(name, & &1.ttl(&2, key))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.expire/2`.
  """
  def expire(name, key, ttl) do
    ttl =
      (Time.timeout?(ttl) && ttl) ||
        raise ArgumentError, "expected ttl to be a valid timeout, got: #{inspect(ttl)}"

    Adapter.with_meta(name, & &1.expire(&2, key, ttl))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.touch/1`.
  """
  def touch(name, key) do
    Adapter.with_meta(name, & &1.touch(&2, key))
  end

  ## Helpers

  defp get_ttl(opts) do
    get_option(opts, :ttl, "a valid timeout", &Time.timeout?/1, :infinity)
  end
end
