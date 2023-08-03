defmodule Nats.NatsPubsub do
  @moduledoc """
  Nats handler for PubSub
  """
  use GenServer

  require Logger

  defmodule State do
    defstruct id: nil, name: nil, gnat: nil, serializer: nil

    @type t :: %__MODULE__{
            id: Node.t(),
            name: String.t(),
            gnat: any(),
            serializer: module()
          }
  end

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

    GenServer.call(adapter_name, {:broadcast, topic, message, metadata, adapter_name})
  end

  ## GenServer Callbacks
  @impl true
  @doc false
  def init(opts) do
    Process.flag(:trap_exit, true)
    name = Keyword.fetch!(opts, :name)
    nats_conn = Keyword.fetch!(opts, :connection)
    serializer = Keyword.get(opts, :serializer, Nats.Serializer.Native)
    {:ok, %State{name: name}, {:continue, {:setup, nats_conn, serializer}}}
  end

  @impl true
  def handle_continue({:setup, nats_conn, serializer}, state) do
    {:ok, gnat} =
      case Gnat.start_link(nats_conn) do
        {:ok, gnat} ->
          {:ok, gnat}

        _ ->
          raise RuntimeError, "Could not connect to Nats with options #{inspect(nats_conn)}"
      end

    {:noreply, %State{state | id: node(), gnat: gnat, serializer: serializer}}
  end

  @impl true
  def handle_call(
        {:broadcast, topic, message, metadata, adapter_name} = _event,
        _from,
        %State{name: name, gnat: gnat, serializer: serializer} = state
      ) do
    from = Keyword.get(metadata, :from, node())
    dispatcher = Keyword.get(metadata, :dispatcher)
    serializer_type = get_serializer_type(serializer)
    headers = build_headers(metadata)

    headers =
      (headers ++ [{"serializer_type", serializer_type}])
      |> List.flatten()

    msg = %{
      dispatcher: dispatcher,
      from: to_string(from),
      name: name,
      payload: message,
      pubsub_name: adapter_name
    }

    res =
      case serializer.encode(msg) do
        {:ok, payload} ->
          topic = "nodes.pubsub.#{topic}"
          Gnat.pub(gnat, topic, payload, headers: headers)

        _ ->
          :error
      end

    {:reply, res, state}
  end

  @impl true
  def handle_info(event, state) do
    Logger.warning("An unexpected event has occurred. Event: #{inspect(event)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.warning("#{inspect(__MODULE__)} terminate with reason: #{inspect(reason)}")
  end

  defp get_serializer_type(serializer) do
    case serializer do
      Nats.Serializer.Json ->
        "json"

      _ ->
        "native"
    end
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
end
