defmodule Nebulex.FakeAdapter do
  @moduledoc false

  # Provide Cache Implementation
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.KV
  @behaviour Nebulex.Adapter.Queryable
  @behaviour Nebulex.Adapter.Transaction
  @behaviour Nebulex.Adapter.Info

  ## Nebulex.Adapter

  @impl true
  defmacro __before_compile__(_), do: :ok

  @impl true
  def init(_opts) do
    child_spec = Supervisor.child_spec({Agent, fn -> :ok end}, id: Agent)

    {:ok, child_spec, %{}}
  end

  ## Nebulex.Adapter.KV

  @impl true
  def fetch(_, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @impl true
  def put(_, :error, :timeout, _, _, _, _), do: {:error, %Nebulex.Error{reason: :timeout}}
  def put(_, :error, reason, _, _, _, _), do: {:error, reason}
  def put(_, _, _, _, _, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @impl true
  def put_all(_, _, _, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @impl true
  def delete(_, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @impl true
  def take(_, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @impl true
  def has_key?(_, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @impl true
  def ttl(_, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @impl true
  def expire(_, _, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @impl true
  def touch(_, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @impl true
  def update_counter(_, _, _, _, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  ## Nebulex.Adapter.Queryable

  @impl true
  def execute(_, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @impl true
  def stream(_, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  ## Nebulex.Adapter.Info

  @impl true
  def info(_, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  ## Nebulex.Adapter.Transaction

  @impl true
  def transaction(_, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @impl true
  def in_transaction?(_, _), do: {:error, %Nebulex.Error{reason: :error}}
end
