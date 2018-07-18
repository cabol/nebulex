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
    |> Version.validate(opts)
    |> elem(1)
    |> validate_return(opts)
  end

  @doc """
  Implementation for `Nebulex.Cache.set/3`.
  """
  def set(cache, key, value, opts) do
    do_set(%Object{key: key, value: value}, nil, cache, opts)
  end

  defp do_set(%Object{value: nil}, _cached, _cache, _opts), do: nil

  defp do_set(object, cached, cache, opts) do
    object
    |> validate_vsn(cached, &on_conflict_set/2, cache, opts)
    |> maybe_set_obj(cache, opts)
    |> validate_return(opts)
  end

  @doc """
  Implementation for `Nebulex.Cache.delete/2`.
  """
  def delete(cache, key, opts) do
    do_delete(%Object{key: key}, nil, cache, opts)
  end

  def do_delete(object, cached, cache, opts) do
    object
    |> validate_vsn(cached, &on_conflict_del/2, cache, opts)
    |> maybe_del_obj(cache, opts)
    |> validate_return(opts)
  end

  @doc """
  Implementation for `Nebulex.Cache.pop/2`.
  """
  def pop(cache, key, opts) do
    cache
    |> get(key, ret_obj(opts))
    |> case do
      nil -> nil
      obj -> do_delete(obj, obj, cache, opts)
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
    current = get(cache, key, ret_obj(opts)) || %Object{}

    case fun.(current.value) do
      {get, update} ->
        {get, do_set(%{current | key: key, value: update}, current, cache, opts)}

      :pop ->
        _ = do_delete(current, current, cache, opts)
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
    |> get(key, ret_obj(opts))
    |> case do
      nil ->
        do_set(%Object{key: key, value: initial}, nil, cache, opts)

      obj ->
        do_set(%{obj | value: fun.(obj.value)}, obj, cache, opts)
    end
  end

  @doc """
  Implementation for `Nebulex.Cache.update_counter/3`.
  """
  def update_counter(cache, key, incr, opts) when is_integer(incr) do
    cache.__adapter__.update_counter(cache, key, incr, opts)
  end

  def update_counter(_cache, _key, incr, _opts) do
    raise ArgumentError, "the incr must be a valid integer, got: #{inspect incr}"
  end

  ## Private Functions

  def validate_vsn(object, cached, on_conflict, cache, opts) do
    opts
    |> Keyword.get(:version)
    |> case do
      nil ->
        object

      _vsn ->
        cache
        |> maybe_get_obj(object.key, cached)
        |> Version.validate(opts)
        |> on_conflict.(object)
    end
  end

  defp maybe_get_obj(cache, key, nil), do: cache.__adapter__.get(cache, key, [])
  defp maybe_get_obj(_cache, _key, cached), do: cached

  defp maybe_set_obj({:nothing, cached}, _cache, _opts), do: cached
  defp maybe_set_obj(obj, cache, opts), do: cache.__adapter__.set(cache, obj, opts)

  defp maybe_del_obj({:nothing, cached}, _cache, _opts), do: cached

  defp maybe_del_obj(obj, cache, opts) do
    _ = cache.__adapter__.delete(cache, obj.key, opts)
    obj
  end

  defp on_conflict_set({:override, _}, obj), do: obj
  defp on_conflict_set(other, _obj), do: other

  defp on_conflict_del({:override, nil}, obj), do: {:nothing, obj}
  defp on_conflict_del({:override, cached}, _obj), do: cached
  defp on_conflict_del(other, _obj), do: other

  defp validate_return(nil, _), do: nil

  defp validate_return(%Object{} = object, opts) do
    case Keyword.get(opts, :return, :value) do
      :object -> object
      :value  -> object.value
      :key    -> object.key
    end
  end

  defp ret_obj(opts), do: Keyword.put(opts, :return, :object)
end
