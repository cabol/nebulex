defmodule Nebulex.TimeTest do
  use ExUnit.Case, async: true

  alias Nebulex.Time

  test "now" do
    now = Time.now()
    assert is_integer(now) and now > 0
  end

  test "timeout?" do
    assert Time.timeout?(1)
    assert Time.timeout?(:infinity)
    refute Time.timeout?(-1)
    refute Time.timeout?(1.1)
    refute Time.timeout?("1")
  end
end
