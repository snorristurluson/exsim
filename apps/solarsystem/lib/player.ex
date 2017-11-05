require Logger

defmodule Player do
  @moduledoc false
  


  use GenServer

  def start_link(id, socket) do
    name = "player_#{id}"
    state = %{id: id, socket: socket}
    GenServer.start_link(__MODULE__, state, [{:name, {:global, name}}])
  end

  def get_id(pid) do
    GenServer.call(pid, {:get_id})
  end

  def get_ship(pid) do
    GenServer.call(pid, {:get_ship})
  end

  def handle_command(pid, "") do
    nil
  end

  def handle_command(pid, data) do
    GenServer.cast(pid, {:handle_command, data})
  end

  def send_message(pid, message) do
    GenServer.call(pid, {:send_message, message})
  end

  # Server callbacks

  def init(state) do
    Logger.info "Starting player #{state[:id]}"
    {:ok, ship} = Ship.start_link(state[:id], 42, state[:socket])
    Logger.info "Starting player #{state[:id]} - created ship"
    state = Map.put(state, :ship, ship)
    {:ok, state}
  end

  def handle_call({:get_id}, _from, state) do
    {:reply, state[:id], state}
  end

  def handle_call({:get_ship}, _from, state) do
    {:reply, state[:ship], state}
  end

  def handle_call({:send_message, message}, _from, state) do
    socket = state[:socket]
    :gen_tcp.send(socket, message)
    {:reply, :ok, state}
  end

  def handle_call(_msg, _from, state) do
    {:reply, :ok, state}
  end

  def handle_cast({:handle_command, cmd}, state) do
    Logger.info "handle_command received: #{cmd}"
    IO.inspect state
    json = try do
      Poison.decode!(cmd)
    rescue
      _ -> "error"
    end
    IO.inspect(json)
    case json do
      %{"settargetlocation" => location} -> set_target_location(location, state)
      _ -> state
    end
    {:noreply, state}
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  defp set_target_location(location, state) do
    Ship.set_target_location(state[:ship], location)
    state
  end
end