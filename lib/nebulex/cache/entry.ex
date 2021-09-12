defmodule Nebulex.Cache.Entry do
  @moduledoc false

  import Nebulex.Helpers

  alias Nebulex.{Adapter, Time}

  # Inline common instructions
  @compile {:inline, get_ttl: 1}

  @doc """
  Implementation for `c:Nebulex.Cache.fetch/2`.
  """
  def fetch(name, key, opts) do
    Adapter.with_meta(name, & &1.fetch(&2, key, opts))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.fetch!/2`.
  """
  def fetch!(name, key, opts) do
    unwrap_or_raise fetch(name, key, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.get/3`.
  """
  def get(name, key, default, opts) do
    Adapter.with_meta(name, &do_get(&1, &2, key, default, opts))
  end

  defp do_get(adapter, adapter_meta, key, default, opts) do
    with {:error, %Nebulex.KeyError{key: ^key}} <- adapter.fetch(adapter_meta, key, opts) do
      {:ok, default}
    end
  end

  @doc """
  Implementation for `c:Nebulex.Cache.get!/3`.
  """
  def get!(name, key, default, opts) do
    unwrap_or_raise get(name, key, default, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.get_all/2`.
  """
  def get_all(name, keys, opts)

  def get_all(_name, [], _opts) do
    {:ok, %{}}
  end

  def get_all(name, keys, opts) do
    Adapter.with_meta(name, & &1.get_all(&2, keys, opts))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.get_all!/3`.
  """
  def get_all!(name, keys, opts) do
    unwrap_or_raise get_all(name, keys, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.put/3`.
  """
  def put(name, key, value, opts) do
    case do_put(name, key, value, :put, opts) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Implementation for `c:Nebulex.Cache.put!/3`.
  """
  def put!(name, key, value, opts) do
    _ = unwrap_or_raise do_put(name, key, value, :put, opts)
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
    unwrap_or_raise put_new(name, key, value, opts)
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
    unwrap_or_raise replace(name, key, value, opts)
  end

  defp do_put(name, key, value, on_write, opts) do
    Adapter.with_meta(name, & &1.put(&2, key, value, get_ttl(opts), on_write, opts))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.put_all/2`.
  """
  def put_all(name, entries, opts) do
    case do_put_all(name, entries, :put, opts) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Implementation for `c:Nebulex.Cache.put_all!/2`.
  """
  def put_all!(name, entries, opts) do
    _ = unwrap_or_raise do_put_all(name, entries, :put, opts)
    :ok
  end

  @doc """
  Implementation for `c:Nebulex.Cache.put_new_all/2`.
  """
  def put_new_all(name, entries, opts) do
    do_put_all(name, entries, :put_new, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.put_new_all!/2`.
  """
  def put_new_all!(name, entries, opts) do
    unwrap_or_raise put_new_all(name, entries, opts)
  end

  def do_put_all(_name, [], _on_write, _opts) do
    {:ok, true}
  end

  def do_put_all(_name, %{} = entries, _on_write, _opts) when map_size(entries) == 0 do
    {:ok, true}
  end

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
  Implementation for `c:Nebulex.Cache.delete!/2`.
  """
  def delete!(name, key, opts) do
    unwrap_or_raise delete(name, key, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.take/2`.
  """
  def take(name, key, opts) do
    Adapter.with_meta(name, & &1.take(&2, key, opts))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.take!/2`.
  """
  def take!(name, key, opts) do
    case take(name, key, opts) do
      {:ok, value} -> value
      {:error, reason} -> raise reason
    end
  end

  @doc """
  Implementation for `c:Nebulex.Cache.exists?/1`.
  """
  def exists?(name, key) do
    Adapter.with_meta(name, & &1.exists?(&2, key))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.get_and_update/3`.
  """
  def get_and_update(name, key, fun, opts) when is_function(fun, 1) do
    Adapter.with_meta(name, fn adapter, adapter_meta ->
      with {:ok, current} <- do_get(adapter, adapter_meta, key, nil, opts) do
        {:ok, eval_get_and_update_function(current, adapter, adapter_meta, key, opts, fun)}
      end
    end)
  end

  defp eval_get_and_update_function(current, adapter, adapter_meta, key, opts, fun) do
    case fun.(current) do
      {get, nil} ->
        {get, get}

      {get, update} ->
        {:ok, true} = adapter.put(adapter_meta, key, update, get_ttl(opts), :put, opts)
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
  end

  @doc """
  Implementation for `c:Nebulex.Cache.get_and_update!/3`.
  """
  def get_and_update!(name, key, fun, opts) do
    unwrap_or_raise get_and_update(name, key, fun, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.update/4`.
  """
  def update(name, key, initial, fun, opts) do
    Adapter.with_meta(name, fn adapter, adapter_meta ->
      value =
        case adapter.fetch(adapter_meta, key, opts) do
          {:ok, value} -> fun.(value)
          {:error, %Nebulex.KeyError{key: ^key}} -> initial
          {:error, _} = error -> throw({:return, error})
        end

      with {:ok, true} <- adapter.put(adapter_meta, key, value, get_ttl(opts), :put, opts) do
        {:ok, value}
      end
    end)
  catch
    {:return, error} -> error
  end

  @doc """
  Implementation for `c:Nebulex.Cache.update!/4`.
  """
  def update!(name, key, initial, fun, opts) do
    unwrap_or_raise update(name, key, initial, fun, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.incr/3`.
  """
  def incr(name, key, amount, opts)

  def incr(name, key, amount, opts) when is_integer(amount) do
    default = get_option(opts, :default, "an integer", &is_integer/1, 0)
    Adapter.with_meta(name, & &1.update_counter(&2, key, amount, get_ttl(opts), default, opts))
  end

  def incr(_cache, _key, amount, _opts) do
    raise ArgumentError, "expected amount to be an integer, got: #{inspect(amount)}"
  end

  @doc """
  Implementation for `c:Nebulex.Cache.incr!/3`.
  """
  def incr!(name, key, amount, opts) do
    unwrap_or_raise incr(name, key, amount, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.decr/3`.
  """
  def decr(name, key, amount, opts)

  def decr(name, key, amount, opts) when is_integer(amount) do
    incr(name, key, amount * -1, opts)
  end

  def decr(_cache, _key, amount, _opts) do
    raise ArgumentError, "expected amount to be an integer, got: #{inspect(amount)}"
  end

  @doc """
  Implementation for `c:Nebulex.Cache.decr!/3`.
  """
  def decr!(name, key, amount, opts) do
    unwrap_or_raise decr(name, key, amount, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.ttl/1`.
  """
  def ttl(name, key) do
    Adapter.with_meta(name, & &1.ttl(&2, key))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.ttl!/1`.
  """
  def ttl!(name, key) do
    case ttl(name, key) do
      {:ok, ttl} -> ttl
      {:error, reason} -> raise reason
    end
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
  Implementation for `c:Nebulex.Cache.expire!/2`.
  """
  def expire!(name, key, ttl) do
    unwrap_or_raise expire(name, key, ttl)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.touch/1`.
  """
  def touch(name, key) do
    Adapter.with_meta(name, & &1.touch(&2, key))
  end

  @doc """
  Implementation for `c:Nebulex.Cache.touch!/1`.
  """
  def touch!(name, key) do
    unwrap_or_raise touch(name, key)
  end

  ## Helpers

  defp get_ttl(opts) do
    get_option(opts, :ttl, "a valid timeout", &Time.timeout?/1, :infinity)
  end
end
