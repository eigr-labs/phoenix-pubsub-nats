Code.require_file("support/nats_proxy.exs", __DIR__)

# The adapter reaches NATS through the proxy, so tests can cut its connections.
{:ok, _proxy} =
  "NATS_PORT"
  |> System.get_env("4222")
  |> String.to_integer()
  |> NatsProxy.start_link()

Supervisor.start_link(
  [
    {
      Phoenix.PubSub,
      name: Phoenix.PubSubTest,
      adapter: PhoenixPubsubNats,
      connection: %{host: ~c"127.0.0.1", port: NatsProxy.port()}
    }
  ],
  strategy: :one_for_one
)

ExUnit.start()
