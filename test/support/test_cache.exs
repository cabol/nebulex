defmodule Nebulex.TestCache do
  defmodule Local do
    use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Local
  end

  defmodule LocalWithGC do
    use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Local
  end

  defmodule DistLocal do
    use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Local
  end

  defmodule Dist do
    use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Dist

    def get_and_update_fun(nil), do: {nil, 1}
    def get_and_update_fun(current) when is_integer(current), do: {current, current * 2}

    def wrong_get_and_update_fun(_), do: :other

    def update_fun(nil), do: 1
    def update_fun(current) when is_integer(current), do: current * 2
  end

  defmodule Multilevel do
    use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Multilevel

    defmodule L1 do
      use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Local
    end

    defmodule L2 do
      use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Local
    end

    defmodule L3 do
      use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Local
    end
  end

  defmodule MultilevelExclusive do
    use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Multilevel

    defmodule L1 do
      use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Local
    end

    defmodule L2 do
      use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Local
    end

    defmodule L3 do
      use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Local
    end
  end
end
