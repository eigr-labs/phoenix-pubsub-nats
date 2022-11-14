defmodule PhoenixPubsubNatsTest do
  use ExUnit.Case
  doctest PhoenixPubsubNats

  alias Phoenix.PubSub

  defmodule ComplexModule do
    defstruct name: nil, age: nil
  end

  setup do
    PubSub.subscribe(Phoenix.PubSubTest, "test")
    {:ok, %{pubsub: Phoenix.PubSubTest, topic: "test"}}
  end

  test "broadcast complex events", config do
    event = %ComplexModule{name: "Adriano", age: 41}
    :ok = PubSub.broadcast(config.pubsub, config.topic, event)
    assert_receive ^event
  end
end
