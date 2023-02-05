# Load support modules
for file <- File.ls!("test/support") do
  Code.require_file("support/" <> file, __DIR__)
end

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
