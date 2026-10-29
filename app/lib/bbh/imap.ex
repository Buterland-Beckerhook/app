defmodule Bbh.Imap do
  @moduledoc """
  A minimal IMAP client for exactly one server: mailcow's Dovecot, where the Postfach
  collects its mail (`docs/plans/ticket-system.md` §6.2). It speaks only what the import
  needs — `CAPABILITY`, `LOGIN`, `SELECT`, `CREATE`, `UID SEARCH`, `UID FETCH`,
  `UID MOVE`, `UID STORE` + `UID EXPUNGE`, `LOGOUT` — one command at a time, polling,
  no IDLE.

  Why our own: no Elixir IMAP library with a track record covers move/delete, and the
  general ones carry far more surface than one known server needs.

  Safety:

    * TLS with certificate and hostname verification (OS CA store, SNI); `LOGIN` only
      over TLS. `tls: false` exists for the dev Dovecot and tests only.
    * A timeout on every read; a literal above `:max_literal` aborts the connection
      before it is read into memory.
    * `NO`/`BAD` become `{:error, {:no | :bad, text}}`.

  A connection is a plain struct; every call returns `{:ok, result}` or `{:error, _}`.
  The socket is in line mode, literals are read with an exact byte count, so nothing
  is buffered here.
  """

  defstruct [:socket, :transport, :timeout, :max_literal, capabilities: []]

  @type t :: %__MODULE__{}

  @default_timeout :timer.seconds(30)

  @doc """
  Connects and logs in. Options: `:host`, `:port` (993), `:username`, `:password`,
  `:tls` (true), `:timeout` (ms per read), `:max_literal` (bytes, default 25 MB).
  """
  def connect(opts) do
    host = Keyword.fetch!(opts, :host)
    tls? = Keyword.get(opts, :tls, true)
    port = Keyword.get(opts, :port, if(tls?, do: 993, else: 143))
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    conn = %__MODULE__{
      transport: if(tls?, do: :ssl, else: :gen_tcp),
      timeout: timeout,
      max_literal: Keyword.get(opts, :max_literal, 25 * 1024 * 1024)
    }

    with {:ok, socket} <- open(conn.transport, host, port, timeout) do
      conn = %{conn | socket: socket}

      case login(conn, opts) do
        {:ok, caps} ->
          {:ok, %{conn | capabilities: caps}}

        {:error, _} = error ->
          close(conn)
          error
      end
    end
  end

  defp login(conn, opts) do
    with {:ok, _greeting} <- read_greeting(conn),
         {:ok, _} <- command(conn, login_command(opts)),
         # Asked after login: servers may announce more once authenticated.
         {:ok, caps} <- capabilities(conn),
         :ok <- require_move(caps) do
      {:ok, caps}
    end
  end

  defp open(:ssl, host, port, timeout) do
    host = String.to_charlist(host)

    :ssl.connect(
      host,
      port,
      [
        :binary,
        active: false,
        packet: :line,
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        server_name_indication: host,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ],
        versions: [:"tlsv1.2", :"tlsv1.3"]
      ],
      timeout
    )
  end

  defp open(:gen_tcp, host, port, timeout) do
    :gen_tcp.connect(
      String.to_charlist(host),
      port,
      [:binary, active: false, packet: :line],
      timeout
    )
  end

  defp read_greeting(conn) do
    case read_line(conn) do
      {:ok, "* OK" <> _ = line} -> {:ok, line}
      {:ok, "* PREAUTH" <> _ = line} -> {:ok, line}
      {:ok, line} -> {:error, {:greeting, String.trim(line)}}
      error -> error
    end
  end

  defp capabilities(conn) do
    with {:ok, %{untagged: untagged}} <- command(conn, "CAPABILITY") do
      caps =
        Enum.find_value(untagged, [], fn
          %{text: "CAPABILITY " <> rest} -> rest |> String.upcase() |> String.split()
          _ -> nil
        end)

      {:ok, caps}
    end
  end

  # Dovecot has MOVE; without it the import would need a COPY + EXPUNGE fallback we
  # deliberately don't carry.
  defp require_move(caps) do
    if "MOVE" in caps, do: :ok, else: {:error, {:missing_capability, "MOVE"}}
  end

  defp login_command(opts) do
    "LOGIN #{quoted!(Keyword.fetch!(opts, :username))} #{quoted!(Keyword.fetch!(opts, :password))}"
  end

  @doc "Selects a mailbox: `%{exists:, uidvalidity:, uidnext:}`."
  def select(conn, mailbox) do
    with {:ok, %{untagged: untagged}} <- command(conn, "SELECT #{quoted!(mailbox)}") do
      info =
        Enum.reduce(untagged, %{exists: 0, uidvalidity: nil, uidnext: nil}, fn %{text: text},
                                                                               acc ->
          cond do
            m = Regex.run(~r/^(\d+) EXISTS/i, text) -> %{acc | exists: int(m)}
            m = Regex.run(~r/\[UIDVALIDITY (\d+)\]/i, text) -> %{acc | uidvalidity: int(m)}
            m = Regex.run(~r/\[UIDNEXT (\d+)\]/i, text) -> %{acc | uidnext: int(m)}
            true -> acc
          end
        end)

      {:ok, info}
    end
  end

  @doc "Creates a mailbox; an existing one is fine."
  def create(conn, mailbox) do
    case command(conn, "CREATE #{quoted!(mailbox)}") do
      {:ok, _} ->
        :ok

      {:error, {:no, text}} ->
        if text =~ ~r/ALREADYEXISTS|exists/i, do: :ok, else: {:error, {:no, text}}

      error ->
        error
    end
  end

  @doc "UIDs matching `criteria` (default: all) in the selected mailbox, ascending."
  def uid_search(conn, criteria \\ "ALL") do
    with {:ok, %{untagged: untagged}} <- command(conn, "UID SEARCH #{criteria}") do
      uids =
        untagged
        |> Enum.flat_map(fn
          %{text: "SEARCH" <> rest} -> rest |> String.split() |> Enum.map(&String.to_integer/1)
          _ -> []
        end)
        |> Enum.sort()

      {:ok, uids}
    end
  end

  @doc "The size of a message in bytes (RFC822.SIZE), or nil if it is gone."
  def uid_size(conn, uid) do
    with {:ok, %{untagged: untagged}} <- command(conn, "UID FETCH #{uid} (RFC822.SIZE)") do
      size =
        Enum.find_value(untagged, fn %{text: text} ->
          case Regex.run(~r/RFC822\.SIZE (\d+)/i, text) do
            [_, n] -> String.to_integer(n)
            _ -> nil
          end
        end)

      {:ok, size}
    end
  end

  @doc """
  The raw message, fetched with `BODY.PEEK[]` (leaves `\\Seen` alone). `{:ok, nil}` if
  the UID no longer exists.
  """
  def uid_fetch(conn, uid) do
    with {:ok, %{untagged: untagged}} <- command(conn, "UID FETCH #{uid} (BODY.PEEK[])") do
      {:ok,
       Enum.find_value(untagged, fn
         %{text: text, literals: [body | _]} -> if text =~ ~r/FETCH/i, do: body
         _ -> nil
       end)}
    end
  end

  @doc """
  Moves a message to `mailbox`. Returns its new location if the server reports one
  (`COPYUID`, RFC 4315): `{:ok, %{uidvalidity:, uid:}}`, else `{:ok, nil}`.
  """
  def uid_move(conn, uid, mailbox) do
    with {:ok, %{untagged: untagged, tagged: tagged}} <-
           command(conn, "UID MOVE #{uid} #{quoted!(mailbox)}") do
      texts = [tagged | Enum.map(untagged, & &1.text)]

      {:ok,
       Enum.find_value(texts, fn text ->
         case Regex.run(~r/\[COPYUID (\d+) (\d+) (\d+)\]/i, text) do
           [_, validity, _old, new] ->
             %{uidvalidity: String.to_integer(validity), uid: String.to_integer(new)}

           _ ->
             nil
         end
       end)}
    end
  end

  @doc "Deletes a message for good: `\\Deleted`, then `UID EXPUNGE` of just that UID."
  def uid_delete(conn, uid) do
    with {:ok, _} <- command(conn, "UID STORE #{uid} +FLAGS.SILENT (\\Deleted)"),
         {:ok, _} <- command(conn, "UID EXPUNGE #{uid}") do
      :ok
    end
  end

  @doc "Logs out and closes; never fails."
  def logout(%__MODULE__{} = conn) do
    _ = command(conn, "LOGOUT")
    close(conn)
    :ok
  end

  defp close(%__MODULE__{transport: transport, socket: socket}), do: transport.close(socket)

  ## Protocol

  @doc false
  # Sends one tagged command and reads until its tagged response:
  # `{:ok, %{untagged: [%{text:, literals:}], tagged: text}}`.
  def command(%__MODULE__{} = conn, line) do
    tag = "A" <> Integer.to_string(System.unique_integer([:positive]))

    with :ok <- conn.transport.send(conn.socket, [tag, " ", line, "\r\n"]) do
      read_response(conn, tag, [])
    end
  end

  defp read_response(conn, tag, acc) do
    with {:ok, item} <- read_item(conn) do
      case item.text do
        ^tag <> " OK" <> rest ->
          {:ok, %{untagged: Enum.reverse(acc), tagged: String.trim(rest)}}

        ^tag <> " NO" <> rest ->
          {:error, {:no, String.trim(rest)}}

        ^tag <> " BAD" <> rest ->
          {:error, {:bad, String.trim(rest)}}

        "* " <> rest ->
          read_response(conn, tag, [%{item | text: rest} | acc])

        _continuation ->
          read_response(conn, tag, acc)
      end
    end
  end

  # One logical response line: text with every literal `{n}` replaced by "{}" and the
  # literals' bytes collected in order.
  defp read_item(conn, text \\ "", literals \\ []) do
    with {:ok, line} <- read_line(conn) do
      line = String.trim_trailing(line, "\r\n")

      case Regex.run(~r/\{(\d+)\}$/, line) do
        [marker, size] ->
          size = String.to_integer(size)

          with :ok <- check_size(conn, size),
               {:ok, literal} <- read_bytes(conn, size) do
            prefix = binary_part(line, 0, byte_size(line) - byte_size(marker))
            read_item(conn, text <> prefix <> "{}", [literal | literals])
          end

        nil ->
          {:ok, %{text: text <> line, literals: Enum.reverse(literals)}}
      end
    end
  end

  defp check_size(conn, size) when size > conn.max_literal do
    close(conn)
    {:error, :too_large}
  end

  defp check_size(_conn, _size), do: :ok

  defp read_line(conn), do: conn.transport.recv(conn.socket, 0, conn.timeout)

  defp read_bytes(_conn, 0), do: {:ok, ""}

  defp read_bytes(conn, size) do
    with :ok <- setopts(conn, packet: :raw),
         {:ok, bytes} <- conn.transport.recv(conn.socket, size, conn.timeout),
         :ok <- setopts(conn, packet: :line) do
      {:ok, bytes}
    end
  end

  defp setopts(%{transport: :ssl, socket: socket}, opts), do: :ssl.setopts(socket, opts)
  defp setopts(%{transport: :gen_tcp, socket: socket}, opts), do: :inet.setopts(socket, opts)

  # A quoted string. Only printable ASCII: enough for mailbox names and mailcow's
  # generated credentials, and no literal (continuation) handling needed for login.
  defp quoted!(value) do
    if value =~ ~r/^[\x20-\x7e]*$/ do
      ~s("#{value |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")}")
    else
      raise ArgumentError, "IMAP string must be printable ASCII"
    end
  end

  defp int([_, n]), do: String.to_integer(n)
end
