# Load support modules
Code.require_file("support/test_adapter.exs", __DIR__)
Code.require_file("support/fake_adapter.exs", __DIR__)
Code.require_file("support/test_cache.exs", __DIR__)
Code.require_file("support/cache_case.exs", __DIR__)

# Load shared test cases
for file <- File.ls!("test/shared/cache") do
  Code.require_file("./shared/cache/" <> file, __DIR__)
end

# Load shared test cases
for file <- File.ls!("test/shared"), not File.dir?("test/shared/" <> file) do
  Code.require_file("./shared/" <> file, __DIR__)
end

# Mocks
[
  Mix.Project,
  Nebulex.Cache.Registry
]
|> Enum.each(&Mimic.copy/1)

# Start Telemetry
_ = Application.start(:telemetry)

# For tasks/generators testing
Mix.start()
Mix.shell(Mix.Shell.Process)

# Start ExUnit
ExUnit.start()
