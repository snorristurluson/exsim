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

  def handle_info({:tcp, socket, cmd}, state) do
    json = try do
      Poison.decode!(cmd)
    rescue
      _ -> "error"
    end
    case json do
      %{"settargetlocation" => location} -> set_target_location(location, state)
      _ -> state
    end
    {:noreply, state}
  end

  def handle_info({:tcp_closed, socket}, state) do
    Logger.info "Socket closed for player #{state[:id]}"
    {:stop, :normal, state}
  end

  def handle_info(_, state) do
    Logger.info "Unhandled info"
    {:noreply, state}
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  def terminate(reason, state) do
    Logger.info "Terminating player #{state[:id]}"
    ship = state[:ship]
    solarsystem = Ship.get_solarsystem(ship)
    Solarsystem.remove_ship(solarsystem, ship)
    GenServer.stop(ship, :normal)
    :normal
  end

  defp set_target_location(location, state) do
    Ship.set_target_location(state[:ship], location)
    state
  end
end