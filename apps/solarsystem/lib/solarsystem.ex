require Logger

defmodule Solarsystem do
  @moduledoc """
  Documentation for Solarsystem.
  """

  use GenServer

  def start(name) do
    Logger.debug("Starting #{name}")

    GenServer.start_link(__MODULE__, name, [{:name, {:global, name}}])
  end

  def add_player(pid, player) do
    GenServer.call(pid, {:add_player, player})
  end

  def broadcast(pid, message) do
    GenServer.cast(pid, {:broadcast, message})
  end

  # Server callbacks

  def init(name) do
    Logger.debug("init for #{name}")
    {:ok, %{players: []}}
  end

  def handle_call({:add_player, player}, _from, state) do
    player_id = Player.get_id(player)
    Logger.info "Adding player #{player_id}"
    player_list = state[:players]
    {:reply, :ok, %{players: [player|player_list]}}
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

  defp send_message_to_players(message, [head|tail]) do
    Player.send_message(head, message)
    send_message_to_players(message, tail)
  end

  defp send_message_to_players(_message, []), do: nil

end
