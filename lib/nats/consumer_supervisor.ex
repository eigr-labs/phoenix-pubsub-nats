defmodule Nats.ConsumerSupervisor do
  @moduledoc false
  use Supervisor
  require Logger

  @main_topic "nodes.pubsub.*"

  def start_link(state) do
    Supervisor.start_link(__MODULE__, state, name: __MODULE__)
  end

  def child_spec(state) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [state]}
    }
  end

  @impl true
  def init(_state) do
    Logger.debug("Initializing Nats PubSub consumer for Node #{inspect(node())}")
    connection_name = Module.concat(PhoenixPubsubNats, "Connection")

    connection_params = %{
      connection_name: connection_name,
      module: Nats.Consumer,
      subscription_topics: [
        %{topic: @main_topic}
      ]
    }

    children = [
      {Gnat.ConsumerSupervisor, connection_params}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
