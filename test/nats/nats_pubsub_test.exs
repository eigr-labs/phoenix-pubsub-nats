defmodule Nats.NatsPubsubTest do
  # Cuts the adapter's NATS connections, so it runs alone.
  use ExUnit.Case, async: false

  alias Phoenix.PubSub

  @pubsub Phoenix.PubSubTest
  @topic "reconnect"

  setup do
    {:ok, gnat} = Gnat.start_link(%{host: ~c"127.0.0.1", port: NatsProxy.upstream_port()})
    {:ok, _sid} = Gnat.sub(gnat, self(), "nodes.pubsub.#{@topic}")
    :ok = PubSub.subscribe(@pubsub, @topic)
    on_exit(fn -> NatsProxy.refuse(false) end)
    published_to_nats()
    :ok
  end

  test "a broadcast after the connection drops reaches local subscribers, and NATS once it reconnects" do
    adapter = Process.whereis(Module.concat(@pubsub, "Adapter"))
    drop_connection()

    assert :ok = PubSub.broadcast(@pubsub, @topic, :after_drop)
    assert_receive :after_drop
    assert Process.whereis(Module.concat(@pubsub, "Adapter")) == adapter

    published_to_nats()
  end

  test "while NATS is unreachable, broadcasts reach local subscribers, and NATS once it's back" do
    NatsProxy.refuse(true)
    drop_connection()

    for n <- 1..3 do
      assert :ok = PubSub.broadcast(@pubsub, @topic, {:unreachable, n})
      assert_receive {:unreachable, ^n}
    end

    NatsProxy.refuse(false)
    published_to_nats()
  end

  # Cuts the connection and waits until it's gone, so the next broadcast finds none.
  defp drop_connection do
    connection = Process.whereis(PhoenixPubsubNats.Connection)
    ref = Process.monitor(connection)
    NatsProxy.drop()
    assert_receive {:DOWN, ^ref, :process, ^connection, _reason}
  end

  # Broadcasts until one reaches NATS: the adapter has a working connection.
  defp published_to_nats(tries \\ 100) do
    :ok = PubSub.broadcast(@pubsub, @topic, :ping)
    assert_receive :ping

    receive do
      {:msg, %{topic: "nodes.pubsub." <> @topic}} -> flush_nats()
    after
      100 ->
        if tries > 1,
          do: published_to_nats(tries - 1),
          else: flunk("no broadcast reached NATS")
    end
  end

  defp flush_nats do
    receive do
      {:msg, _msg} -> flush_nats()
    after
      0 -> :ok
    end
  end
end
