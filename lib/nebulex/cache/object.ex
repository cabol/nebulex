defmodule Nebulex.Cache.Object do
  @moduledoc false

  alias Nebulex.Object

  @doc """
  Implementation for `Nebulex.Cache.get/2`.
  """
  def get(cache, key, opts) do
    cache
    |> cache.__adapter__.get(key, opts)
    |> return(opts)
  end

  @doc """
  Implementation for `Nebulex.Cache.get!/2`.
  """
  def get!(cache, key, opts) do
    if result = get(cache, key, opts) do
      result
    else
      raise KeyError, key: key, term: cache
    end
  end

  @doc """
  Implementation for `Nebulex.Cache.get_many/2`.
  """
  def get_many(_cache, [], _opts), do: %{}

  def get_many(cache, keys, opts) do
    objects_map = cache.__adapter__.get_many(cache, keys, opts)

    case opts[:return] do
      :object ->
        objects_map

      _ ->
        Enum.reduce(objects_map, %{}, fn {key, obj}, acc ->
          Map.put(acc, key, Nebulex.Cache.Object.return(obj, opts))
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
    |> return(opts)
  end

  @doc """
  Implementation for `Nebulex.Cache.add/3`.
  """
  def add(_cache, _key, nil, _opts), do: {:ok, nil}

  def add(cache, key, value, opts) do
    cache
    |> set(key, value, Keyword.put(opts, :set, :add))
    |> case do
      nil -> :error
      res -> {:ok, res}
    end
  end

  @doc """
  Implementation for `Nebulex.Cache.add!/3`.
  """
  def add!(cache, key, value, opts) do
    cache
    |> add(key, value, opts)
    |> case do
      {:ok, result} ->
        result

      :error ->
        raise Nebulex.KeyAlreadyExistsError, cache: cache, key: key
    end
  end

  @doc """
  Implementation for `Nebulex.Cache.replace/3`.
  """
  def replace(_cache, _key, nil, _opts), do: {:ok, nil}

  def replace(cache, key, value, opts) do
    cache
    |> set(key, value, Keyword.put(opts, :set, :replace))
    |> case do
      nil -> :error
      res -> {:ok, res}
    end
  end

  @doc """
  Implementation for `Nebulex.Cache.replace!/3`.
  """
  def replace!(cache, key, value, opts) do
    cache
    |> replace(key, value, opts)
    |> case do
      {:ok, result} ->
        result

      :error ->
        raise KeyError, key: key, term: cache
    end
  end

  @doc """
  Implementation for `Nebulex.Cache.add_or_replace!/3`.
  """
  def add_or_replace!(_cache, _key, nil, _opts), do: nil

  def add_or_replace!(cache, key, value, opts) do
    cache
    |> set(key, value, Keyword.put(opts, :set, :replace))
    |> case do
      nil -> add!(cache, key, value, opts)
      res -> res
    end
  end

  @doc """
  Implementation for `Nebulex.Cache.set_many/2`.
  """
  def set_many(_cache, [], _opts), do: :ok
  def set_many(_cache, entries, _opts) when map_size(entries) == 0, do: :ok

  def set_many(cache, entries, opts) do
    objects =
      for {key, value} <- entries, value != nil do
        %Object{key: key, value: value}
      end

    cache.__adapter__.set_many(cache, objects, opts)
  end

  @doc """
  Implementation for `Nebulex.Cache.delete/2`.
  """
  def delete(cache, key, opts) do
    cache
    |> cache.__adapter__.delete(key, opts)
    |> return(Keyword.put_new(opts, :return, :key))
  end

  @doc """
  Implementation for `Nebulex.Cache.take/2`.
  """
  def take(_cache, nil, _opts), do: nil

  def take(cache, key, opts) do
    cache
    |> cache.__adapter__.take(key, opts)
    |> return(opts)
  end

  @doc """
  Implementation for `Nebulex.Cache.take!/2`.
  """
  def take!(cache, key, opts) do
    if result = take(cache, key, opts) do
      result
    else
      raise KeyError, key: key, term: cache
    end
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
    current = cache.__adapter__.get(cache, key, opts) || %Object{key: key}

    case fun.(current.value) do
      {nil, update} ->
        {nil, set(cache, key, update, opts)}

      {get, update} ->
        {get, set(cache, key, update, Keyword.put(opts, :ttl, Object.ttl(current)))}

      :pop ->
        if current.value, do: delete(cache, key, opts)
        {current.value, nil}

      other ->
        raise ArgumentError,
              "the given function must return a two-element tuple or :pop, " <>
                "got: #{inspect(other)}"
    end
  end

  @doc """
  Implementation for `Nebulex.Cache.update/4`.
  """
  def update(cache, key, initial, fun, opts) do
    cache
    |> cache.__adapter__.get(key, opts)
    |> case do
      nil ->
        set(cache, key, initial, opts)

      object ->
        replace!(cache, key, fun.(object.value), opts)
    end
  end

  @doc """
  Implementation for `Nebulex.Cache.update_counter/3`.
  """
  def update_counter(cache, key, incr, opts) when is_integer(incr) do
    cache.__adapter__.update_counter(cache, key, incr, opts)
  end

  def update_counter(_cache, _key, incr, _opts) do
    raise ArgumentError, "the incr must be a valid integer, got: #{inspect(incr)}"
  end

  ## Helpers

  def return(nil, _), do: nil

  def return(%Object{} = object, opts) do
    case Keyword.get(opts, :return, :value) do
      :object -> object
      :value -> object.value
      :key -> object.key
    end
  end
end
