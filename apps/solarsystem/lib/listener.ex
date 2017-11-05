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
    Logger.info "Waiting for authentication"
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} -> handle_data(socket, data)
      {:error, :closed} -> :ok
    end
  end

  defp handle_data(socket, data) do
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
    {:ok, solarsystem} = Solarsystem.start("ex1")
    Solarsystem.add_player(solarsystem, player)
    {:ok, pid} = Task.Supervisor.start_child(
      Solarsystem.TaskSupervisor,
      fn -> serve(socket, player) end)
    :ok = :gen_tcp.controlling_process(socket, pid)
  end

  defp handle_login(socket, data) do
    Logger.info "Invalid login"
    IO.inspect(data)
    authentication_loop(socket)
  end

  defp serve(socket, player) do
    {:ok, data} = :gen_tcp.recv(socket, 0)
    Logger.info "serve received #{data}"
    lines = String.split(data, "\n", [:trim])
    IO.inspect(lines)
    Enum.each(lines, fn item -> Player.handle_command(player, item) end)
    serve(socket, player)
  end

end