Supervisor.start_link(
  [
    {
      Phoenix.PubSub,
      name: Phoenix.PubSubTest,
      adapter: PhoenixPubsubNats,
      connection: %{host: '127.0.0.1', port: 4222}
    }
  ],
  strategy: :one_for_one
)

ExUnit.start()
