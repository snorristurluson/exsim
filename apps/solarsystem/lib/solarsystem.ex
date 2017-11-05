require Logger

defmodule Solarsystem do
  @moduledoc """
  Documentation for Solarsystem.
  """

  use GenServer

  def start(name) do
    Logger.info "Starting #{name}"
    case GenServer.start_link(__MODULE__, name, [{:name, {:global, name}}]) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
    end
  end

  def add_player(pid, player) do
    GenServer.call(pid, {:add_player, player})
  end

  def broadcast(pid, message) do
    GenServer.cast(pid, {:broadcast, message})
  end

  def notify_ship_update_done(pid, ship) do
    GenServer.cast(pid, {:notify_ship_update_done, ship})
  end

  def distribute_state(pid, solarsystem_state) do
    GenServer.cast(pid, {:distribute_state, solarsystem_state})
  end

  def send_queued_physics_commands(pid, commands) do
    GenServer.cast(pid, {:send_queued_physics_commands, commands})
  end

  # Server callbacks

  def init(name) do
    Logger.info "Solarsystem init for #{name}"
    Process.send_after(self(), {:start_tick}, 250)
    {:ok, pid} = PhysicsProxy.start_link(self(), name, 4041)
    {:ok, %{
      name: name,
      players: [],
      ships: [],
      pending_ships: [],
      physics: pid}
    }
  end

  def handle_call({:add_player, player}, _from, state) do
    player_id = Player.get_id(player)
    Logger.info "Adding player #{player_id} to solarsystem #{state[:name]}"

    ship = Player.get_ship(player)
    Ship.set_solarsystem(ship, self())
    typeid = Ship.get_typeid(ship)
    {x, y, z} = Ship.get_position(ship)
    command = %{command: "addship", owner: player_id, type: typeid, position: %{x: x, y: y, z: z}}
    PhysicsProxy.send_command(state[:physics], command)

    {_, state} = Map.get_and_update(state, :players, fn current -> {current, [player | current]} end)
    {_, state} = Map.get_and_update(state, :ships, fn current -> {current, [ship | current]} end)

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

  def handle_cast({:notify_ship_update_done, ship}, state) do
    state = Map.put(state, :tick_start_time, System.monotonic_time(:millisecond))
    {_, newstate} = Map.get_and_update(state, :pending_ships, fn current -> {current, List.delete(current, ship)} end)
    case newstate[:pending_ships] do
      [] -> GenServer.cast(self(), {:end_tick})
      _ -> nil
    end
    {:noreply, newstate}
  end

  def handle_cast({:end_tick}, state) do
    PhysicsProxy.send_command(state[:physics], %{command: "stepsimulation", timestep: 0.250})
    PhysicsProxy.send_command(state[:physics], %{command: "getstate"})

    tick_duration = System.monotonic_time(:millisecond) - state[:tick_start_time]
    tick_duration = if tick_duration > 250 do
      250
    else
      tick_duration
    end
    Process.send_after(self(), {:start_tick}, 250 - tick_duration)

    {:noreply, state}
  end

  def handle_cast({:distribute_state, solarsystem_state}, state) do
    Enum.each(state[:ships], fn ship -> Ship.send_solarsystem_state(ship, solarsystem_state) end)
    {:noreply, state}
  end

  def handle_cast({:send_queued_physics_commands, commands}, state) do
    send_queued_physics_commands_helper(state[:physics], commands)
    {:noreply, state}
  end

  def handle_info({:start_tick}, state) do
    ships = state[:ships]
    Enum.each(ships, fn ship -> Ship.update(ship) end)
    state = Map.put(state, :pending_ships, ships)
    {:noreply, state}
  end

  defp send_message_to_players(message, [head|tail]) do
    Player.send_message(head, message)
    send_message_to_players(message, tail)
  end

  defp send_message_to_players(_message, []), do: nil

  defp send_queued_physics_commands_helper(physics, commands) do
    case :queue.out(commands) do
      {:empty, _} ->
        nil
      {{:value, cmd}, remaining} ->
        PhysicsProxy.send_command(physics, cmd)
        send_queued_physics_commands_helper(physics, remaining)
    end
  end

end
