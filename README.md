# Mabeam

A Multi-Agent Framework for the BEAM

**Mabeam** is a framework for building multi-agent systems on the Erlang VM (BEAM). It provides a set of tools and abstractions for creating, managing, and communicating between agents.

## Features

*   **Agent Lifecycle Management:** Create, start, stop, and supervise agents.
*   **Message Passing:** Asynchronous message passing between agents.
*   **Agent Discovery:** Discover other agents in the system.
*   **Extensible:** Easily extend the framework with new agent types and behaviors.

## Installation

If available in Hex, the package can be installed by
adding `mabeam` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mabeam, "~> 0.0.1"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc) and published on [HexDocs](https://hexdocs.pm). Once published, the docs can be found at [https://hexdocs.pm/mabeam](https://hexdocs.pm/mabeam).