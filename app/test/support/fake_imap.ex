defmodule Bbh.FakeImap do
  @moduledoc """
  A scripted IMAP server for tests: accepts one connection on localhost, sends a
  greeting, then for each step reads a command, checks it against a regex and answers
  with the step's lines (`"TAG"` is replaced by the command's tag).
  """

  @doc "Starts the server; returns the port. `steps`: `[{~r/command/, [lines] | :hang}]`."
  def start(steps) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, packet: :line, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    test = self()

    pid =
      spawn_link(fn ->
        {:ok, socket} = :gen_tcp.accept(listen, 5_000)
        :ok = :gen_tcp.send(socket, "* OK [CAPABILITY IMAP4rev1] Fake ready\r\n")
        result = run(socket, steps)
        send(test, {:fake_imap_done, result})
        :gen_tcp.close(socket)
        :gen_tcp.close(listen)
      end)

    {port, pid}
  end

  @doc "Login + capability steps every connection starts with."
  def login_steps do
    [
      {~r/^LOGIN "tickets" "geheim"$/, ["TAG OK Logged in"]},
      {~r/^CAPABILITY$/, ["* CAPABILITY IMAP4rev1 MOVE UIDPLUS IDLE", "TAG OK done"]}
    ]
  end

  defp run(_socket, []), do: :ok

  # `:hang`: read the command, answer nothing, keep the connection open until the test
  # ends (the server is linked to it) — a fixed sleep made the client see :closed
  # instead of :timeout when the suite ran under load.
  defp run(socket, [{_pattern, :hang} | _]) do
    {:ok, _} = :gen_tcp.recv(socket, 0, 5_000)

    receive do
      :never -> :ok
    end
  end

  defp run(socket, [{pattern, lines} | rest]) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, line} ->
        [tag, command] = line |> String.trim_trailing("\r\n") |> String.split(" ", parts: 2)

        if command =~ pattern do
          Enum.each(lines, fn out ->
            :gen_tcp.send(socket, String.replace(out, "TAG", tag) <> "\r\n")
          end)

          run(socket, rest)
        else
          {:unexpected, command}
        end

      {:error, reason} ->
        {:closed, reason}
    end
  end
end
