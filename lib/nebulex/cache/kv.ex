defmodule Nebulex.Cache.KV do
  @moduledoc false

  import Nebulex.Adapter
  import Nebulex.Utils, only: [is_timeout: 1, unwrap_or_raise: 1]

  alias Nebulex.Cache.Options

  @doc """
  Implementation for `c:Nebulex.Cache.fetch/2`.
  """
  defcommand fetch(name, key, opts)

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
    name
    |> lookup_meta()
    |> do_get(key, default, opts)
  end

  defp do_get(adapter_meta, key, default, opts) do
    with {:error, %Nebulex.KeyError{key: ^key}} <- run_command(adapter_meta, :fetch, [key], opts) do
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
  Implementation for `c:Nebulex.Cache.put/3`.
  """
  def put(name, key, value, opts) do
    with {:ok, _} <- do_put(name, key, value, :put, opts) do
      :ok
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
    {ttl, opts} = Options.pop_and_validate_timeout!(opts, :ttl)
    {keep_ttl?, opts} = Options.pop_and_validate_boolean!(opts, :keep_ttl, on_write == :replace)

    do_put(name, key, value, on_write, ttl, keep_ttl?, opts)
  end

  @compile {:inline, do_put: 7}
  defcommandp do_put(name, key, value, on_write, ttl, keep_ttl?, opts), command: :put

  @doc """
  Implementation for `c:Nebulex.Cache.put_all/2`.
  """
  def put_all(name, entries, opts) do
    with {:ok, _} <- do_put_all(name, entries, :put, opts) do
      :ok
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
    {ttl, opts} = Options.pop_and_validate_timeout!(opts, :ttl)

    do_put_all(name, entries, on_write, ttl, opts)
  end

  @compile {:inline, do_put_all: 5}
  defcommandp do_put_all(name, entries, on_write, ttl, opts), command: :put_all

  @doc """
  Implementation for `c:Nebulex.Cache.delete/2`.
  """
  defcommand delete(name, key, opts)

  @doc """
  Implementation for `c:Nebulex.Cache.delete!/2`.
  """
  def delete!(name, key, opts) do
    unwrap_or_raise delete(name, key, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.take/2`.
  """
  defcommand take(name, key, opts)

  @doc """
  Implementation for `c:Nebulex.Cache.take!/2`.
  """
  def take!(name, key, opts) do
    unwrap_or_raise take(name, key, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.has_key?/1`.
  """
  defcommand has_key?(name, key, opts)

  @doc """
  Implementation for `c:Nebulex.Cache.ttl/1`.
  """
  defcommand ttl(name, key, opts)

  @doc """
  Implementation for `c:Nebulex.Cache.ttl!/1`.
  """
  def ttl!(name, key, opts) do
    unwrap_or_raise ttl(name, key, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.expire/2`.
  """
  def expire(name, key, ttl, opts) do
    ttl =
      (is_timeout(ttl) && ttl) ||
        raise ArgumentError, "expected ttl to be a valid timeout, got: #{inspect(ttl)}"

    do_expire(name, key, ttl, opts)
  end

  @compile {:inline, do_expire: 4}
  defcommandp do_expire(name, key, ttl, opts), command: :expire

  @doc """
  Implementation for `c:Nebulex.Cache.expire!/2`.
  """
  def expire!(name, key, ttl, opts) do
    unwrap_or_raise expire(name, key, ttl, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.touch/1`.
  """
  defcommand touch(name, key, opts)

  @doc """
  Implementation for `c:Nebulex.Cache.touch!/1`.
  """
  def touch!(name, key, opts) do
    unwrap_or_raise touch(name, key, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.incr/3`.
  """
  def incr(name, key, amount, opts)

  def incr(name, key, amount, opts) when is_integer(amount) do
    {default, opts} = Options.pop_and_validate_integer!(opts, :default)
    {ttl, opts} = Options.pop_and_validate_timeout!(opts, :ttl)

    do_incr(name, key, amount, default, ttl, opts)
  end

  def incr(_name, _key, amount, _opts) do
    raise ArgumentError,
          "invalid value for amount argument: expected integer, got: #{inspect(amount)}"
  end

  @compile {:inline, do_incr: 6}
  defcommandp do_incr(name, key, amount, default, ttl, opts), command: :update_counter

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
    raise ArgumentError,
          "invalid value for amount argument: expected integer, got: #{inspect(amount)}"
  end

  @doc """
  Implementation for `c:Nebulex.Cache.decr!/3`.
  """
  def decr!(name, key, amount, opts) do
    unwrap_or_raise decr(name, key, amount, opts)
  end

  @doc """
  Implementation for `c:Nebulex.Cache.get_and_update/3`.
  """
  def get_and_update(name, key, fun, opts) when is_function(fun, 1) do
    {ttl, opts} = Options.pop_and_validate_timeout!(opts, :ttl)
    {keep_ttl?, opts} = Options.pop_and_validate_boolean!(opts, :keep_ttl)

    adapter_meta = lookup_meta(name)

    with {:ok, current} <- do_get(adapter_meta, key, nil, opts) do
      {:ok, eval_get_and_update_function(current, adapter_meta, key, ttl, keep_ttl?, opts, fun)}
    end
  end

  defp eval_get_and_update_function(current, adapter_meta, key, ttl, keep_ttl?, opts, fun) do
    case fun.(current) do
      {get, nil} ->
        {get, get}

      {get, update} ->
        {:ok, true} = run_command(adapter_meta, :put, [key, update, :put, ttl, keep_ttl?], opts)

        {get, update}

      :pop when is_nil(current) ->
        {nil, nil}

      :pop ->
        :ok = run_command(adapter_meta, :delete, [key], opts)

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
  def update(name, key, initial, fun, opts) when is_function(fun, 1) do
    {ttl, opts} = Options.pop_and_validate_timeout!(opts, :ttl)
    {keep_ttl?, opts} = Options.pop_and_validate_boolean!(opts, :keep_ttl)

    adapter_meta = lookup_meta(name)

    value =
      case run_command(adapter_meta, :fetch, [key], opts) do
        {:ok, value} -> fun.(value)
        {:error, %Nebulex.KeyError{key: ^key}} -> initial
        {:error, _} = error -> throw({:return, error})
      end

    with {:ok, true} <- run_command(adapter_meta, :put, [key, value, :put, ttl, keep_ttl?], opts) do
      {:ok, value}
    end
  catch
    {:return, error} -> error
  end

  @doc """
  Implementation for `c:Nebulex.Cache.update!/4`.
  """
  def update!(name, key, initial, fun, opts) do
    unwrap_or_raise update(name, key, initial, fun, opts)
  end
end
