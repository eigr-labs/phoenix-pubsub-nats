# Phoenix Pubsub Nats

Phoenix PubSub adapter based on Nats.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `phoenix_pubsub_nats` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_pubsub_nats, "~> 0.2.1"}
  ]
end
```

## Usage

An example usage (add this to your supervision tree):

  ```elixir
  # application.ex
  children = [
     {
        Phoenix.PubSub,
          name: Phoenix.PubSubTest,
          adapter: PhoenixPubsubNats,
          connection: %{host: '127.0.0.1', port: 4222}
     }
  ]
  
  ```
  where `connection` is configured separately based on the `gnat`
  [documentation](https://hexdocs.pm/gnat/readme.html).

  Optional parameters:

  * `serializer`: Used to convert messages to/from the underlying Nats system.
                  This library provides two implementations of the `Nats.Serializer`
                  serialization module, namely:
                  * `Nats.Serializer.Native`: Convert messages using Erlang's native serialization mechanism.
                  * `Nats.Serializer.Json`: Convert messages using Json format.

For more details on how to use it, see the [Phoenix.PubSub documentation](https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html).
