defmodule PhoenixPubsubNats do
  @moduledoc """
  Phoenix PubSub adapter based on Nats.

  An example usage (add this to your supervision tree):
  ```elixir
  {
      Phoenix.PubSub,
      name: Phoenix.PubSubTest,
      adapter: PhoenixPubsubNats,
      connection: %{host: '127.0.0.1', port: 4222}
    }
  ```
  where `connection` is configured separately based on the `gnat`
  [documentation](https://hexdocs.pm/gnat/readme.html).

  Optional parameters:

  * `serializer`: Used to convert messages to/from the underlying Nats system.
                  This library provides two implementations of the `Nats.Serializer`
                  serialization module, namely:
                  * `Nats.Serializer.Native`: Convert messages using Erlang's native serialization mechanism.
                  * `Nats.Serializer.Json`: Convert messages using Json format.
  """
  use Supervisor

  @moduledoc since: "0.1.0"

  @behaviour Phoenix.PubSub.Adapter

  @impl true
  defdelegate node_name(adapter_name),
    to: Nats.NatsPubsub

  @impl true
  defdelegate broadcast(adapter_name, topic, message, dispatcher),
    to: Nats.NatsPubsub

  @impl true
  defdelegate direct_broadcast(adapter_name, node_name, topic, message, dispatcher),
    to: Nats.NatsPubsub

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    connection_name = Module.concat(__MODULE__, "Connection")

    children = [
      {Gnat.ConnectionSupervisor, connection_settings(connection_name, opts)},
      {Nats.ConsumerSupervisor, opts},
      {Nats.NatsPubsub, opts}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp connection_settings(name, opts) do
    nats_conn = Keyword.fetch!(opts, :connection)

    %{
      name: name,
      backoff_period: 3000,
      connection_settings: [
        nats_conn
      ]
    }
  end
end
