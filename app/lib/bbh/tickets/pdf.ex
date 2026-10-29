defmodule Bbh.Tickets.Pdf do
  @moduledoc """
  The membership application of a Postfach ticket as PDF, in the layout of the paper
  form (`priv/pdf/aufnahmeantrag.typ`), rendered by the `typst` CLI (shipped in both
  Docker images).

  Generated on demand and streamed to the browser, **never stored**: the template, the
  logo and the data go into a private temp directory that is removed after the run, so
  personal data neither lands in the uploads nor shows in the process list (as a
  command-line argument would).
  """

  alias Bbh.Membership
  alias Bbh.Tickets.Ticket

  @timeout :timer.seconds(30)

  @doc "Renders the PDF for a decrypted membership ticket; `user` is who downloads it."
  # Every path is built here — a random directory name under the system temp dir and
  # fixed file names from priv/pdf; nothing from the request reaches a file function.
  # sobelow_skip ["Traversal.FileModule"]
  def membership_application(%Ticket{kind: "membership"} = ticket, user) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "bbh-pdf-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
      )

    try do
      with :ok <- File.mkdir(dir),
           :ok <- File.chmod(dir, 0o700),
           :ok <-
             File.cp(template_path("aufnahmeantrag.typ"), Path.join(dir, "aufnahmeantrag.typ")),
           :ok <-
             File.cp(template_path("logo_sv_lng_nb.svg"), Path.join(dir, "logo_sv_lng_nb.svg")),
           :ok <- File.write(Path.join(dir, "data.json"), Jason.encode!(data(ticket, user))) do
        compile(dir)
      end
    after
      File.rm_rf(dir)
    end
  end

  def membership_application(_ticket, _user), do: {:error, :not_membership}

  # `dir` comes from membership_application/2, the binary from config (default
  # "typst"); arguments go to the program as a list, never through a shell.
  # sobelow_skip ["Traversal.FileModule", "CI.System"]
  defp compile(dir) do
    out = Path.join(dir, "antrag.pdf")

    args = [
      "compile",
      "--root",
      dir,
      "--font-path",
      template_path("fonts"),
      "--ignore-system-fonts",
      Path.join(dir, "aufnahmeantrag.typ"),
      out
    ]

    # A missing binary raises inside the task; catch it there, or it takes the caller
    # down with it.
    task =
      Task.async(fn ->
        try do
          System.cmd(typst(), args, stderr_to_stdout: true)
        rescue
          e in ErlangError -> {:missing, e.original}
        end
      end)

    case Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:missing, reason}} -> {:error, {:typst_missing, reason}}
      {:ok, {_output, 0}} -> File.read(out)
      {:ok, {output, status}} -> {:error, {:typst, status, output}}
      nil -> {:error, :timeout}
    end
  end

  @doc false
  # The values the template reads, all as display strings.
  def data(%Ticket{payload: payload} = ticket, user) do
    p = payload || %{}

    %{
      reference: Ticket.reference(ticket),
      nachname: p["nachname"] || "",
      vorname: p["vorname"] || "",
      strasse: p["strasse"] || "",
      geburtsdatum: p["geburtsdatum"] || "",
      plz: p["plz"] || "",
      ort: p["ort"] || "",
      email: p["email"] || "",
      member_number: p["member_number"] || "",
      children:
        for(
          c <- p["children"] || [],
          do: %{vorname: c["vorname"] || "", geburtsdatum: c["geburtsdatum"] || ""}
        ),
      max_child_age: Membership.max_child_age(),
      kontoinhaber: p["kontoinhaber"] || "",
      kreditinstitut: p["kreditinstitut"] || "",
      iban: Membership.format_iban(p["iban"]),
      bic: p["bic"] || "",
      creditor_id: Membership.creditor_id(),
      mandate_reference:
        if(p["member_number"] in [nil, ""],
          do: Membership.mandate_reference(),
          else: p["member_number"]
        ),
      mandate_text: Membership.mandate_text(),
      mandate_note: Membership.mandate_note(),
      privacy_note: Membership.privacy_note(),
      fee_note: Membership.fee_note(),
      flags: p["flags"] || [],
      submitted_at: local_iso(p["submitted_at"]),
      client_ip: p["client_ip"] || "–",
      form_version: p["form_version"] || "–",
      sepa_mandate: if(p["sepa_mandate"] || p["sepa"], do: "ja", else: "nein"),
      altcha_verified: if(p["altcha_verified"], do: "ja", else: "nein"),
      generated_at: local(DateTime.utc_now(:second)),
      generated_by: user.email
    }
  end

  defp local_iso(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> local(dt)
      _ -> iso
    end
  end

  defp local_iso(_), do: "–"

  defp local(dt) do
    dt = DateTime.shift_zone!(dt, Bbh.Time.time_zone())
    Calendar.strftime(dt, "%d.%m.%Y, %H:%M Uhr")
  end

  defp template_path(name), do: Path.join(:code.priv_dir(:bbh), Path.join("pdf", name))

  defp typst, do: Application.get_env(:bbh, :typst_bin, "typst")
end
