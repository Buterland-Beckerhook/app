defmodule Bbh.Membership do
  @moduledoc """
  Membership-application ("Aufnahmeantrag") validation and delivery.

  Mirrors `Bbh.Contact`: plain-function validation (no DB persistence) plus Swoosh
  delivery. The form captures the applicant's personal data and an *electronic* SEPA
  direct-debit mandate (valid without a hand-written signature). Two mails go out per
  submission — one to the club inbox, one confirmation copy to the applicant.

  The Satzung's age thresholds (min age for members, max age for listed children) are
  *soft*: they never reject a submission. The form shows a hint and the club mail flags
  an out-of-range entry so the Vorstand can follow up. See `min_age/0` / `max_child_age/0`.
  """
  import Swoosh.Email
  alias Bbh.Mailer

  @type params :: %{optional(String.t()) => term()}

  # SEPA creditor identifier and mandate reference, taken from the paper form.
  @creditor_id "DE39SVB00000430432"
  @mandate_reference "gleich Mitgliedsnummer"

  @doc "Minimum age for a membership (Satzung). Soft: only hinted/flagged, never rejected."
  def min_age, do: Application.get_env(:bbh, :membership_min_age, 16)

  @doc "Children are listed only when younger than this age. Soft: only hinted/flagged."
  def max_child_age, do: Application.get_env(:bbh, :membership_max_child_age, 15)

  @doc "Whether the honeypot field was filled (a bot tell)."
  def honeypot_filled?(params) do
    params |> Map.get("website", "") |> to_string() |> String.trim() != ""
  end

  @doc """
  Validate the application params. Returns `{:ok, data}` or `{:error, errors}` where
  `errors` is a map of field => message.
  """
  def validate(params) do
    fields =
      %{
        nachname: trimmed(params, "nachname"),
        vorname: trimmed(params, "vorname"),
        plz: trimmed(params, "plz"),
        ort: trimmed(params, "ort"),
        strasse: trimmed(params, "strasse"),
        geburtsdatum: trimmed(params, "geburtsdatum"),
        email: trimmed(params, "email"),
        kontoinhaber: trimmed(params, "kontoinhaber"),
        iban: params |> trimmed("iban") |> normalize_iban(),
        bic: params |> trimmed("bic") |> String.upcase(),
        kreditinstitut: trimmed(params, "kreditinstitut"),
        children: children(params)
      }
      |> derive_bank()

    consents = %{
      sepa: consented?(params, "sepa"),
      satzung: consented?(params, "satzung"),
      datenspeicherung: consented?(params, "datenspeicherung"),
      privacy: consented?(params, "privacy")
    }

    errors =
      %{}
      |> put_if(fields.nachname == "", :nachname, "Bitte geben Sie Ihren Namen an.")
      |> put_if(fields.vorname == "", :vorname, "Bitte geben Sie Ihren Vornamen an.")
      |> put_if(fields.plz == "", :plz, "Bitte geben Sie Ihre PLZ an.")
      |> put_if(fields.ort == "", :ort, "Bitte geben Sie Ihren Ort an.")
      |> put_if(fields.strasse == "", :strasse, "Bitte geben Sie Ihre Straße an.")
      |> put_if(fields.geburtsdatum == "", :geburtsdatum, "Bitte geben Sie Ihr Geburtsdatum an.")
      |> put_if(
        not valid_email?(fields.email),
        :email,
        "Bitte geben Sie eine gültige E-Mail-Adresse an."
      )
      |> put_if(fields.kontoinhaber == "", :kontoinhaber, "Bitte geben Sie den Kontoinhaber an.")
      |> put_if(not valid_iban?(fields.iban), :iban, "Bitte geben Sie eine gültige IBAN an.")
      # BIC and Kreditinstitut are optional — both are derivable from the IBAN. Only a
      # non-empty BIC is format-checked.
      |> put_if(
        fields.bic != "" and not valid_bic?(fields.bic),
        :bic,
        "Bitte geben Sie einen gültigen BIC an."
      )
      |> put_if(
        not consents.sepa,
        :sepa,
        "Bitte erteilen Sie das SEPA-Lastschriftmandat."
      )
      |> put_if(not consents.satzung, :satzung, "Bitte erkennen Sie die Vereinssatzung an.")
      |> put_if(
        not consents.datenspeicherung,
        :datenspeicherung,
        "Bitte stimmen Sie der Speicherung Ihrer Daten zu."
      )
      |> put_if(not consents.privacy, :privacy, "Bitte stimmen Sie der Datenschutzerklärung zu.")

    if errors == %{},
      do: {:ok, Map.merge(fields, consents)},
      else: {:error, errors}
  end

  @doc "Send the application to the club inbox and a confirmation copy to the applicant."
  def deliver(data) do
    with {:ok, _} <- deliver_to_club(data),
         {:ok, _} = ok <- deliver_to_applicant(data) do
      ok
    end
  end

  @doc "\"Vorname Nachname\", trimmed."
  def full_name(%{vorname: v, nachname: n}), do: String.trim("#{v} #{n}")

  # Fill an empty BIC / Kreditinstitut from the IBAN's Bankleitzahl when we can.
  # Anything the applicant typed wins; an unknown BLZ just leaves the field blank.
  defp derive_bank(%{bic: bic, kreditinstitut: inst} = fields) when bic == "" or inst == "" do
    case Bbh.Blz.lookup_by_iban(fields.iban) do
      {:ok, %{bic: derived_bic, name: name}} ->
        %{
          fields
          | bic: if(bic == "", do: derived_bic, else: bic),
            kreditinstitut: if(inst == "", do: name, else: inst)
        }

      :error ->
        fields
    end
  end

  defp derive_bank(fields), do: fields

  defp deliver_to_club(%{email: email} = data) do
    name = full_name(data)

    new()
    |> to(recipient())
    |> from({"Website Aufnahmeantrag", Mailer.sender()})
    |> reply_to({name, email})
    |> subject("Aufnahmeantrag von #{name}")
    |> text_body(club_body(data))
    |> Mailer.deliver_logged("membership")
  end

  defp deliver_to_applicant(%{email: email} = data) do
    new()
    |> to({full_name(data), email})
    |> from({Mailer.sender_name(), Mailer.sender()})
    |> subject("Ihr Aufnahmeantrag beim Schützenverein Buterland-Beckerhook e.V.")
    |> text_body(applicant_body(data))
    |> Mailer.deliver_logged("membership-copy")
  end

  defp club_body(data) do
    "Neuer Aufnahmeantrag über die Website:\n\n" <> summary(data) <> age_flags(data)
  end

  defp applicant_body(data) do
    """
    Guten Tag #{full_name(data)},

    vielen Dank für Ihren Aufnahmeantrag beim Schützenverein Buterland-Beckerhook e.V.
    Wir haben Ihre Angaben erhalten und melden uns in Kürze bei Ihnen.

    Zu Ihrer Übersicht sind Ihre übermittelten Angaben nachstehend aufgeführt.

    #{summary(data)}
    Mit freundlichen Grüßen
    Schützenverein Buterland-Beckerhook e.V.
    """
  end

  defp summary(data) do
    """
    Aufnahmeantrag
    --------------
    Name:          #{data.nachname}
    Vorname:       #{data.vorname}
    Straße:        #{data.strasse}
    PLZ / Ort:     #{data.plz} #{data.ort}
    Geburtsdatum:  #{data.geburtsdatum}
    E-Mail:        #{data.email}
    #{children_lines(data.children)}
    SEPA-Lastschriftmandat
    ----------------------
    Kontoinhaber:  #{data.kontoinhaber}
    IBAN:          #{data.iban}
    BIC:           #{data.bic}
    Kreditinstitut: #{data.kreditinstitut}
    Gläubiger-ID:  #{@creditor_id}
    Mandatsreferenz: #{@mandate_reference}

    Erteilte Zustimmungen
    ---------------------
    SEPA-Mandat erteilt:        #{yes_no(data.sepa)}
    Vereinssatzung anerkannt:   #{yes_no(data.satzung)}
    Datenspeicherung zugestimmt: #{yes_no(data.datenspeicherung)}
    Datenschutz zugestimmt:     #{yes_no(data.privacy)}
    """
  end

  defp children_lines([]), do: ""

  defp children_lines(children) do
    lines =
      children
      |> Enum.map(fn %{vorname: v, geburtsdatum: g} -> "  - #{v} (#{g})" end)
      |> Enum.join("\n")

    "\nKinder unter #{max_child_age()} Jahren:\n" <> lines <> "\n"
  end

  # Non-blocking notes for the club: applicant below min age, or a listed child not
  # actually below the child age. Appended only when something is off.
  defp age_flags(data) do
    flags =
      [applicant_age_flag(data) | Enum.map(data.children, &child_age_flag/1)]
      |> Enum.reject(&is_nil/1)

    case flags do
      [] ->
        ""

      lines ->
        "\nHinweise (bitte prüfen)\n-----------------------\n" <> Enum.join(lines, "\n") <> "\n"
    end
  end

  defp applicant_age_flag(data) do
    min = min_age()

    case age(data.geburtsdatum) do
      years when is_integer(years) and years < min ->
        "Antragsteller ist #{years} Jahre alt — unter dem Mindestalter von #{min} Jahren."

      _ ->
        nil
    end
  end

  defp child_age_flag(%{vorname: vorname, geburtsdatum: geburtsdatum}) do
    max = max_child_age()

    case age(geburtsdatum) do
      years when is_integer(years) and years >= max ->
        "Kind #{vorname} ist #{years} Jahre alt — nicht mehr unter #{max} Jahren."

      _ ->
        nil
    end
  end

  defp yes_no(true), do: "ja"
  defp yes_no(false), do: "nein"

  # Every non-empty {vorname, geburtsdatum} row from the (unbounded) array fields.
  defp children(params) do
    vornamen = list_field(params, "kind_vorname")
    geburtsdaten = list_field(params, "kind_geburtsdatum")
    count = max(length(vornamen), length(geburtsdaten))

    0..(count - 1)//1
    |> Enum.map(fn i ->
      %{
        vorname: vornamen |> Enum.at(i, "") |> String.trim(),
        geburtsdatum: geburtsdaten |> Enum.at(i, "") |> String.trim()
      }
    end)
    |> Enum.reject(&(&1.vorname == "" and &1.geburtsdatum == ""))
  end

  defp list_field(params, key) do
    case Map.get(params, key) do
      list when is_list(list) -> Enum.map(list, &to_string/1)
      value when is_binary(value) -> [value]
      _ -> []
    end
  end

  defp trimmed(params, key), do: params |> Map.get(key, "") |> to_string() |> String.trim()

  defp consented?(params, key), do: Map.get(params, key) in ["true", "on", "1"]

  defp valid_email?(email), do: Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, email)

  defp valid_bic?(bic), do: Regex.match?(~r/^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$/, bic)

  # Uppercase and strip all whitespace so validation and the emailed value are canonical.
  defp normalize_iban(iban), do: iban |> String.upcase() |> String.replace(~r/\s/, "")

  # Completed years from a birth date to today, or nil if the string is unparseable.
  # Accepts the German "TT.MM.JJJJ" the flatpickr picker writes as well as ISO dates.
  defp age(birth_str) do
    case parse_date(birth_str) do
      {:ok, birth} ->
        today = Date.utc_today()
        years = today.year - birth.year
        if {today.month, today.day} < {birth.month, birth.day}, do: years - 1, else: years

      :error ->
        nil
    end
  end

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} ->
        {:ok, date}

      _ ->
        with [d, m, y] <- String.split(str, "."),
             {day, ""} <- Integer.parse(d),
             {month, ""} <- Integer.parse(m),
             {year, ""} <- Integer.parse(y) do
          Date.new(year, month, day)
        else
          _ -> :error
        end
    end
  end

  # ISO 13616 check: 15–34 alphanumerics, move the first four chars to the end, map
  # letters to numbers (A=10 … Z=35) and require the whole number ≡ 1 (mod 97).
  defp valid_iban?(iban) do
    with true <- Regex.match?(~r/^[A-Z0-9]{15,34}$/, iban),
         {front, rest} <- String.split_at(iban, 4),
         digits <- rest <> front,
         number when is_binary(number) <- iban_to_number(digits) do
      rem(String.to_integer(number), 97) == 1
    else
      _ -> false
    end
  end

  defp iban_to_number(chars) do
    chars
    |> String.to_charlist()
    |> Enum.map(fn
      c when c in ?0..?9 -> <<c>>
      c when c in ?A..?Z -> Integer.to_string(c - ?A + 10)
    end)
    |> Enum.join()
  end

  defp put_if(map, true, key, msg), do: Map.put(map, key, msg)
  defp put_if(map, false, _key, _msg), do: map

  defp recipient,
    do: Application.get_env(:bbh, :contact_recipient, "info@buterland-beckerhook.de")
end
