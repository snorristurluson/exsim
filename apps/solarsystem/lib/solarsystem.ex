require Logger

defmodule Solarsystem do
  @moduledoc """
  Documentation for Solarsystem.
  """

  use GenServer

  def start(name) do
    Logger.info "Starting #{name}"
    case GenServer.whereis({:global, name}) do
      :nil -> GenServer.start_link(__MODULE__, name, [{:name, {:global, name}}])
      pid -> {:ok, pid}
    end

  end

  def add_player(pid, player) do
    GenServer.call(pid, {:add_player, player})
  end

  def broadcast(pid, message) do
    GenServer.cast(pid, {:broadcast, message})
  end

  # Server callbacks

  def init(name) do
    Logger.info "init for #{name}"
    Process.send_after(self(), {:tick}, 250)
    {:ok, pid} = PhysicsProxy.start_link(name, 4041)
    {:ok, %{players: [], physics: pid}}
  end

  def handle_call({:add_player, player}, _from, state) do
    Logger.info "Adding player"
    player_id = Player.get_id(player)
    Logger.info "Adding player #{player_id}"
    ship = Player.get_ship(player)
    typeid = Ship.get_typeid(ship)
    {x, y, z} = Ship.get_position(ship)
    command = %{command: "addship", owner: player_id, type: typeid, position: %{x: x, y: y, z: z}}
    PhysicsProxy.send_command(state[:physics], command)
    player_list = state[:players]
    state = Map.put(state, :players, player_list)
    {:reply, :ok, state}
  end

  def handle_call(msg, _from, state) do
    Logger.warn "Unhandled msg #{msg}"
    {:reply, :ok, state}
  end

  def handle_cast({:broadcast, message}, state) do
    Logger.info "Broadcasting message"
    send_message_to_players(message, state[:players])
    {:noreply, state}
  end

  def handle_info({:tick}, state) do
    PhysicsProxy.send_command(state[:physics], %{command: "stepsimulation", timestep: 0.250})
    PhysicsProxy.send_command(state[:physics], %{command: "getstate"})

    Process.send_after(self(), {:tick}, 250)

    {:noreply, state}
  end

  defp send_message_to_players(message, [head|tail]) do
    Player.send_message(head, message)
    send_message_to_players(message, tail)
  end

  defp send_message_to_players(_message, []), do: nil

end
