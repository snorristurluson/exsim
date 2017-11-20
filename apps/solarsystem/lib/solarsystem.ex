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

  def add_ship(pid, ship) do
    GenServer.call(pid, {:add_ship, ship})
  end

  def remove_ship(pid, ship) do
    GenServer.call(pid, {:remove_ship, ship})
  end

  def broadcast(pid, message) do
    GenServer.cast(pid, {:broadcast, message})
  end

  def notify_ship_update_done(pid, ship) do
    GenServer.cast(pid, {:notify_ship_update_done, ship})
  end

  def notify_ship_state_delivered(pid, ship) do
    GenServer.cast(pid, {:notify_ship_state_delivered, ship})
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
    case PhysicsProxy.start_link(self(), name, 4041) do
      {:ok, pid} ->
        {:ok, %{
          name: name,
          ships: [],
          pending_ships: [],
          pending_ships_state: [],
          physics: pid}
        }
      {:error, reason} ->
        Logger.info "Failed to start physics proxy for #{name}: #{reason}"
        {:stop, "Failed to start physics proxy"}
      _ ->
        Logger.info "Failed to start physics proxy for #{name}"
        {:stop, "Failed to start physics proxy"}
    end
  end

  def handle_call({:add_ship, ship}, _from, state) do
    Logger.info "Adding ship to solarsystem #{state[:name]}"
    Ship.set_solarsystem(ship, self())
    owner = Ship.get_owner(ship)
    typeid = Ship.get_typeid(ship)
    pos = Ship.get_position(ship)
    command = %{command: "addship", params: %{owner: owner, typeid: typeid, position: pos}}
    PhysicsProxy.send_command(state[:physics], command)

    {prevShips, state} = Map.get_and_update(state, :ships, fn current -> {current, [ship | current]} end)

    # If this is the first ship, start ticking
    case prevShips do
      [] ->
        Process.send_after(self(), {:start_tick}, 250)
      _ ->
        nil
    end

    {:reply, :ok, state}
  end

  def handle_call({:remove_ship, ship}, _from, state) do
    Logger.info "Removing ship from solarsystem #{state[:name]}"
    owner = Ship.get_owner(ship)
    command = %{command: "removeship", params: %{owner: owner}}
    PhysicsProxy.send_command(state[:physics], command)

    {_, state} = Map.get_and_update(state, :ships, fn current -> {current, List.delete(current, ship)} end)

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
    {_, newstate} = Map.get_and_update(state, :pending_ships, fn current -> {current, List.delete(current, ship)} end)
    case newstate[:pending_ships] do
      [] -> GenServer.cast(self(), {:end_update})
      _ -> nil
    end
    {:noreply, newstate}
  end

  def handle_cast({:notify_ship_state_delivered, ship}, state) do
#    {_, newstate} = Map.get_and_update(state, :pending_ships_state, fn current -> {current, List.delete(current, ship)} end)
#    case newstate[:pending_ships_state] do
#      [] -> GenServer.cast(self(), {:end_tick})
#      _ -> nil
#    end
    {:noreply, state}
  end

  def handle_cast({:end_update}, state) do
    ships = state[:ships]
    state = Map.put(state, :pending_ships_state, ships)

    PhysicsProxy.send_command(state[:physics], %{command: "stepsimulation", params: %{timestep: 0.250}})
    PhysicsProxy.send_command(state[:physics], %{command: "getstate"})

    tick_duration = System.monotonic_time(:millisecond) - state[:tick_start_time]
    Logger.info "Tick duration: #{tick_duration}"
    tick_duration = if tick_duration > 250 do
      250
    else
      tick_duration
    end
    Process.send_after(self(), {:start_tick}, 250 - tick_duration)
    {:noreply, state}
  end

  def handle_cast({:end_tick}, state) do
    {:noreply, state}
  end

  def handle_cast({:distribute_state, solarsystem_state}, state) do
    start = System.monotonic_time(:millisecond)
    Enum.each(state[:ships], fn ship -> Ship.send_solarsystem_state(ship, solarsystem_state) end)
    duration = System.monotonic_time(:millisecond) - start
    Logger.info "Distribute state: #{duration}"
    {:noreply, state}
  end

  def handle_cast({:send_queued_physics_commands, commands}, state) do
    send_queued_physics_commands_helper(state[:physics], commands)
    {:noreply, state}
  end

  def handle_info({:start_tick}, state) do
    state = Map.put(state, :tick_start_time, System.monotonic_time(:millisecond))
    ships = state[:ships]
    state = Map.put(state, :pending_ships, ships)
    start_update(ships)
    {:noreply, state}
  end

  def handle_info({:end_update}, state) do
    {:noreply, state}
  end

  def handle_info({:end_tick}, state) do
    # This code path applies when there are no ships in the system.
    # As the system is empty, there is no reason to tick it - we'll
    # start doing that again when a ship is added.
    {:noreply, state}
  end

  defp start_update([]) do
    Process.send(self(), {:end_update}, [])
  end

  defp start_update(ships) do
    Enum.each(ships, fn ship -> Ship.update(ship) end)
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
