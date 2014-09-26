use Mix.Config

if Mix.env in [:dev, :prod, :test] do
  import_config "#{Mix.env}.exs"
end
