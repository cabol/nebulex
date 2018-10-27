defmodule Nebulex.Cache.Object do
  @moduledoc false

  alias Nebulex.Object
  alias Nebulex.Object.Version

  @doc """
  Implementation for `Nebulex.Cache.get/2`.
  """
  def get(cache, key, opts) do
    cache
    |> cache.__adapter__.get(key, opts)
    |> Version.validate(cache, opts)
    |> elem(1)
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

    case Keyword.get(opts, :return) do
      :object ->
        objects_map

      _ ->
        Enum.reduce(objects_map, %{}, fn {key, obj}, acc ->
          Map.put(acc, key, return(obj, opts))
        end)
    end
  end

  @doc """
  Implementation for `Nebulex.Cache.set/3`.
  """
  def set(_cache, _key, nil, _opts), do: nil

  def set(cache, key, value, opts) do
    cache
    |> do_set(key, value, opts)
    |> elem(1)
    |> return(opts)
  end

  defp do_set(cache, key, value, opts) do
    case Version.validate(key, cache, opts) do
      {:nothing, cached} ->
        {true, cached}

      {:override, cached} ->
        object = %Object{
          key: key,
          value: value,
          version: cache.object_vsn(cached),
          expire_at: Object.expire_at(Keyword.get(opts, :ttl))
        }

        {cache.__adapter__.set(cache, object, opts), object}
    end
  end

  @doc """
  Implementation for `Nebulex.Cache.set_many/2`.
  """
  def set_many(_cache, [], _opts), do: :ok
  def set_many(_cache, entries, _opts) when map_size(entries) == 0, do: :ok

  def set_many(cache, entries, opts) do
    ttl = Keyword.get(opts, :ttl)

    objects =
      for entry <- entries do
        case entry do
          {key, value} ->
            %Object{
              key: key,
              value: value,
              version: cache.object_vsn(nil),
              expire_at: Object.expire_at(ttl)
            }

          %Object{} = object ->
            %{object | version: cache.object_vsn(nil)}
        end
      end

    cache.__adapter__.set_many(cache, objects, opts)
  end

  @doc """
  Implementation for `Nebulex.Cache.add/3`.
  """
  def add(_cache, _key, nil, _opts), do: {:ok, nil}

  def add(cache, key, value, opts) do
    cache
    |> do_set(key, value, Keyword.put(opts, :action, :add))
    |> handle_set_response(opts)
  end

  @doc """
  Implementation for `Nebulex.Cache.add!/3`.
  """
  def add!(cache, key, value, opts) do
    case add(cache, key, value, opts) do
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
    |> do_set(key, value, Keyword.put(opts, :action, :replace))
    |> handle_set_response(opts)
  end

  @doc """
  Implementation for `Nebulex.Cache.replace!/3`.
  """
  def replace!(cache, key, value, opts) do
    case replace(cache, key, value, opts) do
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
    case replace(cache, key, value, opts) do
      {:ok, return} ->
        return

      :error ->
        add!(cache, key, value, opts)
    end
  end

  @doc """
  Implementation for `Nebulex.Cache.delete/2`.
  """
  def delete(cache, key, opts) do
    key
    |> Version.validate(cache, opts)
    |> case do
      {:nothing, cached} ->
        cached

      {:override, cached} ->
        :ok = cache.__adapter__.delete(cache, key, opts)
        cached || %Object{key: key}
    end
    |> return(Keyword.put_new(opts, :return, :key))
  end

  @doc """
  Implementation for `Nebulex.Cache.take/2`.
  """
  def take(_cache, nil, _opts), do: nil

  def take(cache, key, opts) do
    key
    |> Version.validate(cache, opts)
    |> case do
      {:nothing, cached} ->
        cached

      {:override, _cached} ->
        cache.__adapter__.take(cache, key, opts)
    end
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
  Implementation for `Nebulex.Cache.object_info/2`.
  """
  def object_info(cache, key, attr) when attr in [:ttl, :version] do
    cache.__adapter__.object_info(cache, key, attr)
  end

  def object_info(_cache, _key, attr) do
    raise ArgumentError, "attr must be `:ttl` or `:version`, got: #{inspect(attr)}"
  end

  @doc """
  Implementation for `Nebulex.Cache.expire/2`.
  """
  def expire(cache, key, ttl) when (is_integer(ttl) and ttl >= 0) or ttl == :infinity do
    cache.__adapter__.expire(cache, key, ttl)
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
        {get, replace!(cache, key, update, opts)}

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
    case cache.__adapter__.get(cache, key, opts) do
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

  defp handle_set_response({true, obj}, opts), do: {:ok, return(obj, opts)}
  defp handle_set_response({false, _}, _opts), do: :error

  def return(nil, _), do: nil

  def return(%Object{} = object, opts) do
    case Keyword.get(opts, :return, :value) do
      :object -> object
      :value -> object.value
      :key -> object.key
    end
  end
end
