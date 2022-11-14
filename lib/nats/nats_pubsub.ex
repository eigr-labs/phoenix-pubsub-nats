defmodule Nats.NatsPubsub do
  @moduledoc """
  Nats handler for PubSub
  """
  use GenServer

  require Logger

  defmodule State do
    defstruct id: nil, pubsub_name: nil, gnat: nil, subscription: nil, serializer: nil

    @type t :: %__MODULE__{
            id: Node.t(),
            pubsub_name: String.t(),
            gnat: any(),
            subscription: String.t(),
            serializer: module()
          }
  end

  @main_topic "nodes.pubsub.*"

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:adapter_name])
  end

  @doc false
  def node_name(_adapter_name), do: node()

  @doc false
  def broadcast(adapter_name, topic, message, dispatcher) do
    do_broadcast(adapter_name, topic, message, dispatcher)
  end

  @doc false
  def direct_broadcast(adapter_name, node_name, topic, message, dispatcher) do
    metadata = Keyword.put([], :target, node_name)
    do_broadcast(adapter_name, topic, message, dispatcher, metadata)
  end

  defp do_broadcast(adapter_name, topic, message, dispatcher, metadata \\ []) do
    metadata = Keyword.put(metadata, :from, node())
    metadata = Keyword.put(metadata, :dispatcher, dispatcher)

    GenServer.call(adapter_name, {:broadcast, topic, message, metadata})
  end

  ## GenServer Callbacks
  @impl true
  @doc false
  def init(state) do
    Process.flag(:trap_exit, true)
    nats_conn = Keyword.fetch!(state, :connection)
    pubsub_name = Keyword.get(state, :adapter_name, __MODULE__)
    serializer = Keyword.get(state, :serializer, Nats.Serializer.Native)
    {:ok, %State{pubsub_name: pubsub_name}, {:continue, {:setup, nats_conn, serializer}}}
  end

  @impl true
  def handle_continue({:setup, nats_conn, serializer}, state) do
    {gnat, subscription} =
      case Gnat.start_link(nats_conn) do
        {:ok, gnat} ->
          subscription = sub(gnat)
          {gnat, subscription}

        _ ->
          raise RuntimeError, "Could not connect to Nats with options #{inspect(nats_conn)}"
      end

    {:noreply,
     %State{state | id: node(), gnat: gnat, subscription: subscription, serializer: serializer}}
  end

  defp sub(gnat) do
    case Gnat.sub(gnat, self(), @main_topic) do
      {:ok, subscription} ->
        subscription

      _ ->
        raise RuntimeError,
              "Unable to subscribe Node #{inspect(node())} to channel #{@main_topic}"
    end
  end

  @impl true
  def handle_call(
        {:broadcast, topic, message, metadata},
        _from,
        %State{gnat: gnat, serializer: serializer} = state
      ) do
    headers = build_headers(metadata)

    res =
      case serializer.encode(message) do
        {:ok, payload} ->
          Gnat.pub(gnat, "nodes.pubsub.#{topic}", payload, headers: headers)

        _ ->
          :error
      end

    {:reply, res, state}
  end

  @impl true
  def handle_info(
        {:msg, %{topic: topic, reply_to: _to, headers: headers} = event},
        %State{pubsub_name: pubsub_name, serializer: serializer} = state
      ) do
    IO.puts("Received event #{inspect(event)}")
    current_node = to_string(node())

    case conver_headers_to_map(headers) do
      %{target: target}
      when not is_nil(target) and target != current_node ->
        # Direct broadcast and this is not the destination node.
        :ok

      %{from: ^current_node} ->
        # This node is the source, nothing to do, because local dispatch already
        # happened.
        :ok

      %{dispatcher: dispatcher} ->
        real_topic = get_real_topic(topic)
        payload = decode(serializer, event)

        Phoenix.PubSub.local_broadcast(
          pubsub_name,
          real_topic,
          payload,
          maybe_convert_to_existing_atom(dispatcher)
        )
    end

    {:noreply, state}
  end

  def handle_info(event, state) do
    Logger.warning("An unexpected event has occurred. Event: #{inspect(event)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.warning("#{inspect(__MODULE__)} terminate with reason: #{inspect(reason)}")
  end

  defp build_headers([]), do: []

  defp build_headers(metadata) when is_list(metadata) do
    Enum.map(metadata, fn {key, value} ->
      key = if is_atom(key), do: Atom.to_string(key), else: key
      value = if is_atom(value), do: Atom.to_string(value), else: value
      {key, value}
    end)
  end

  defp build_headers(_), do: []

  defp decode(serializer, %{body: body} = event) do
    case serializer.decode(body) do
      {:ok, payload} ->
        payload

      _ ->
        raise ArgumentError, "Could not deserialize event: #{inspect(event)}"
    end
  end

  defp get_real_topic(topic) do
    String.replace(topic, "nodes.pubsub.", "")
  end

  defp conver_headers_to_map(headers), do: Enum.into(headers, %{})

  defp maybe_convert_to_existing_atom(string) when is_binary(string),
    do: String.to_existing_atom(string)

  defp maybe_convert_to_existing_atom(atom) when is_atom(atom), do: atom
end
