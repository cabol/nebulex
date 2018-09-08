defmodule Nebulex.Object do
  @moduledoc """
  Defines a Cache Object.

  This is the struct used by the caches to store and retrieve data.
  """

  defstruct [:key, :value, :version, ttl: :infinity]

  @type t :: %__MODULE__{key: any, value: any, version: any, ttl: timeout}

  @doc """
  Returns the remaining time to live for the given object.

  ## Example

      obj = MyCache.set("foo", "bar", return: :object, ttl: 3)

      Nebulex.Object.ttl(obj)
  """
  @spec ttl(Nebulex.Object.t()) :: timeout
  def ttl(%Nebulex.Object{ttl: :infinity}), do: :infinity

  def ttl(%Nebulex.Object{ttl: ttl}) when is_integer(ttl) do
    remaining = ttl - DateTime.to_unix(DateTime.utc_now())
    if remaining >= 0, do: remaining, else: 0
  end

  @doc """
  Sets the version on `obj_or_objs`. The version is generated using the
  cache version generator.

  Returns the object or list of objects with the generated version.

  ## Example

      object = %Nebulex.Object{key: "foo", value: "bar"}

      Nebulex.Object.set_version(object, MyCache)

      Nebulex.Object.set_version([object], MyCache)
  """
  @spec set_version(obj_or_objs, Nebulex.Cache.t()) :: obj_or_objs
        when obj_or_objs: Nebulex.Object.t() | [Nebulex.Object.t()]
  def set_version(obj_or_objs, cache) do
    if versioner = cache.__version_generator__ do
      do_set_vsn(obj_or_objs, versioner)
    else
      obj_or_objs
    end
  end

  defp do_set_vsn(%Nebulex.Object{} = obj, versioner) do
    versioner.generate(obj)
  end

  defp do_set_vsn(objs, versioner) do
    for %Nebulex.Object{} = obj <- objs, do: versioner.generate(obj)
  end
end
