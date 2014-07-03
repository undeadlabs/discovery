# Discovery

An Elixir library for auto discovering Erlang nodes with Consul

## Requirements

* Elixir 0.14.0 or newer

## Installation

Add Discovery as a dependency in your `mix.exs` file

```elixir
def application do
  [applications: [:discovery]]
end

defp deps do
  [
    {:discovery, git: "git@github.com:undeadlabs/discovery.git"}
  ]
end
```

Then run `mix deps.get` in your shell to fetch the dependencies.

## Authors

Jamie Winsor (<jamie@undeadlabs.com>)
