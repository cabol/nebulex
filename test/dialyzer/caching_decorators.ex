defmodule Nebulex.Dialyzer.CachingDecorators do
  @moduledoc false
  use Nebulex.Caching

  defmodule Account do
    @moduledoc false
    defstruct [:id, :username, :password]
    @type t :: %__MODULE__{}
  end

  @ttl :timer.seconds(3600)

  ## Annotated Functions

  @spec get_account(integer) :: Account.t()
  @decorate cacheable(cache: Cache, key: {Account, id})
  def get_account(id) do
    %Account{id: id}
  end

  @spec get_account_by_username(binary) :: Account.t()
  @decorate cacheable(cache: Cache, key: {Account, username}, opts: [ttl: @ttl])
  def get_account_by_username(username) do
    %Account{username: username}
  end

  @spec update_account(Account.t()) :: {:ok, Account.t()}
  @decorate cache_put(
              cache: Cache,
              keys: [{Account, acct.id}, {Account, acct.username}],
              match: &match/1,
              opts: [ttl: @ttl]
            )
  def update_account(%Account{} = acct) do
    {:ok, acct}
  end

  @spec update_account_by_id(binary, %{optional(atom) => term}) :: {:ok, Account.t()}
  @decorate cache_put(cache: Cache, key: {Account, id}, match: &match/1, opts: [ttl: @ttl])
  def update_account_by_id(id, attrs) do
    {:ok, struct(Account, Map.put(attrs, :id, id))}
  end

  @spec delete_account(Account.t()) :: Account.t()
  @decorate cache_evict(cache: Cache, keys: [{Account, acct.id}, {Account, acct.username}])
  def delete_account(%Account{} = acct) do
    acct
  end

  @spec delete_all_accounts(term) :: :ok
  @decorate cache_evict(cache: Cache, all_entries: true)
  def delete_all_accounts(filter) do
    filter
  end

  @spec get_user_key(integer) :: binary
  @decorate cacheable(
              cache: {__MODULE__, :dynamic_cache, [:dynamic]},
              key_generator: {__MODULE__, [id]}
            )
  def get_user_key(id), do: id

  @spec update_user_key(integer) :: binary
  @decorate cacheable(cache: Cache, key_generator: {__MODULE__, :generate_key, [id]})
  def update_user_key(id), do: id

  ## Helpers

  defp match({:ok, _} = ok), do: {true, ok}
  defp match({:error, _}), do: false

  def generate(mod, fun, args), do: :erlang.phash2({mod, fun, args})

  def generate_key(args), do: :erlang.phash2(args)

  def dynamic_cache(_, _, _, _), do: Cache
end
