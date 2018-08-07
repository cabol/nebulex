defmodule Nebulex.Cache.Object do
  @moduledoc false

  alias Nebulex.Object

  @doc """
  Implementation for `Nebulex.Cache.get/2`.
  """
  def get(cache, key, opts) do
    cache
    |> cache.__adapter__.get(key, opts)
    |> validate_return(opts)
  end

  @doc """
  Implementation for `Nebulex.Cache.mget/2`.
  """
  def mget(_cache, [], _opts), do: %{}

  def mget(cache, keys, opts) do
    objects_map = cache.__adapter__.mget(cache, keys, opts)

    case opts[:return] do
      :object ->
        objects_map

      _ ->
        Enum.reduce(objects_map, %{}, fn {key, obj}, acc ->
          Map.put(acc, key, validate_return(obj, opts))
        end)
    end
  end

  @doc """
  Implementation for `Nebulex.Cache.set/3`.
  """
  def set(_cache, _key, nil, _opts), do: nil

  def set(cache, key, value, opts) do
    cache
    |> cache.__adapter__.set(%Object{key: key, value: value}, opts)
    |> validate_return(opts)
  end

  @doc """
  Implementation for `Nebulex.Cache.add/3`.
  """
  def add(_cache, _key, nil, _opts), do: {:ok, nil}

  def add(cache, key, value, opts) do
    case cache.__adapter__.add(cache, %Object{key: key, value: value}, opts) do
      {:ok, object} -> {:ok, validate_return(object, opts)}
      :error -> :error
    end
  end

  @doc """
  Implementation for `Nebulex.Cache.mset/2`.
  """
  def mset(_cache, [], _opts), do: :ok
  def mset(_cache, entries, _opts) when map_size(entries) == 0, do: :ok

  def mset(cache, entries, opts) do
    objects = for {key, value} <- entries, do: %Object{key: key, value: value}
    cache.__adapter__.mset(cache, objects, opts)
  end

  @doc """
  Implementation for `Nebulex.Cache.delete/2`.
  """
  def delete(cache, key, opts) do
    cache
    |> cache.__adapter__.delete(key, opts)
    |> validate_return(opts)
  end

  @doc """
  Implementation for `Nebulex.Cache.take/2`.
  """
  def take(_cache, nil, _opts), do: nil

  def take(cache, key, opts) do
    cache
    |> cache.__adapter__.take(key, opts)
    |> validate_return(opts)
  end

  @doc """
  Implementation for `Nebulex.Cache.has_key?/1`.
  """
  def has_key?(cache, key) do
    cache.__adapter__.has_key?(cache, key)
  end

  @doc """
  Implementation for `Nebulex.Cache.get_and_update/3`.
  """
  def get_and_update(cache, key, fun, opts) when is_function(fun, 1) do
    {get, update} = cache.__adapter__.get_and_update(cache, key, fun, opts)
    {get, validate_return(update, opts)}
  end

  @doc """
  Implementation for `Nebulex.Cache.update/4`.
  """
  def update(cache, key, initial, fun, opts) do
    cache
    |> cache.__adapter__.update(key, initial, fun, opts)
    |> validate_return(opts)
  end

  @doc """
  Implementation for `Nebulex.Cache.update_counter/3`.
  """
  def update_counter(cache, key, incr, opts) do
    cache.__adapter__.update_counter(cache, key, incr, opts)
  end

  ## Private Functions

  defp validate_return(nil, _), do: nil

  defp validate_return(%Object{} = object, opts) do
    case Keyword.get(opts, :return, :value) do
      :object -> object
      :value -> object.value
      :key -> object.key
    end
  end
end
