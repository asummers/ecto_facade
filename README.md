# EctoFacade

EctoFacade can be used as interface through which you can query multiple repositories.
Main objective of this is to use separate separate repository for writes and separate repository for reads.

For example:

Lets say you have PostgreSQL database replicated to 4 different slave nodes that should be used for reads only.
With this small library you can do that!

## Installation

```elixir
def deps do
  [
    {:ecto_facade, "~> 0.1.0"}
  ]
end
```

## Usage

```elixir
defmodule MyApp.FacadeRepo do
  use EctoFacade.Repo,
    master_repo: MyApp.Repo,
    read_repos: [MyApp.ReadReplicaOne, MyApp.ReadReplicaTwo],
    algorithm: MyApp.Repo.ReadAlgorithm
end
```

for more information please check documentation

## Documentation

[Hex.pm](https://hexdocs.pm/ecto_facade)

