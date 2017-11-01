require Logger

:user
:token

defmodule Listener do
  @moduledoc false
  def accept(port) do
    {:ok, socket} = :gen_tcp.listen(port,
                      [:binary, packet: :line, active: false, reuseaddr: true])
    Logger.info "Accepting connections on port #{port}"
    loop_acceptor(socket)
  end

  defp loop_acceptor(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    Logger.info "Connection established"
    {:ok, pid} = Task.Supervisor.start_child(
        Solarsystem.TaskSupervisor,
        fn -> authentication_loop(client) end)
    :ok = :gen_tcp.controlling_process(client, pid)
    loop_acceptor(socket)
  end

  def authentication_loop(socket) do
    {:ok, data} = :gen_tcp.recv(socket, 0)
    Logger.info data
    json = Poison.decode(data, keys: :atoms!)
    case json do
      {:ok, %{} = details} -> handle_login(socket, details)
      _ ->
        Logger.info "Invalid login"
        authentication_loop(socket)
    end
  end

  defp handle_login(socket, %{:user => user}) do
    {:ok, player} = Player.start_link(user, socket)
    {:ok, pid} = Task.Supervisor.start_child(
      Solarsystem.TaskSupervisor,
      fn -> serve(socket, player) end)
    :ok = :gen_tcp.controlling_process(socket, pid)
  end

  defp serve(socket, player) do
    {:ok, data} = :gen_tcp.recv(socket, 0)
    Player.handle_data(player, data)
    serve(socket, player)
  end

end