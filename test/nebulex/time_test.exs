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

  test "expiry_time" do
    assert Time.expiry_time(1) == 1000
    assert Time.expiry_time(10, :second) == 10_000
    assert Time.expiry_time(10, :minute) == 600_000
    assert Time.expiry_time(1, :hour) == 3_600_000
    assert Time.expiry_time(1, :day) == 86_400_000

    assert_raise ArgumentError, ~r"invalid time. The time is expected to be a positive", fn ->
      Time.expiry_time(-1, :day)
    end

    assert_raise ArgumentError, ~r"unsupported time unit. Expected :second, :minute,", fn ->
      Time.expiry_time(1, :other)
    end
  end
end
