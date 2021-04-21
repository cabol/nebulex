defmodule Nebulex.DialyzerCachingTest do
  @moduledoc false
  use Nebulex.Caching

  defmodule Account do
    @moduledoc false
    defstruct [:id, :username, :password]
    @type t :: %__MODULE__{}
  end

  ## Annotated Functions

  @spec get_account(integer) :: Account.t()
  @decorate cacheable(cache: Cache, key: {Account, id})
  def get_account(id) do
    %Account{id: id}
  end

  @spec get_account_by_username(String.t()) :: Account.t()
  @decorate cacheable(cache: Cache, key: {Account, username})
  def get_account_by_username(username) do
    %Account{username: username}
  end

  @spec update_account(Account.t()) :: Account.t()
  @decorate cache_put(cache: Cache, key: {Account, acct.id})
  def update_account(acct) do
    acct
  end

  @spec delete_account(Account.t()) :: Account.t()
  @decorate cache_evict(cache: Cache, keys: [{Account, acct.id}, {Account, acct.username}])
  def delete_account(acct) do
    acct
  end
end
