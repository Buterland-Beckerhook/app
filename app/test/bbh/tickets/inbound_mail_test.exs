defmodule Bbh.Tickets.InboundMailTest do
  use ExUnit.Case, async: true

  alias Bbh.Tickets.InboundMail

  defp crlf(text), do: String.replace(text, "\n", "\r\n")

  test "a Latin-1, quoted-printable mail with an attachment" do
    raw =
      crlf("""
      X-Original-To: vorstand@buterland-beckerhook.de
      X-Original-To: offiziere@buterland-beckerhook.de
      Delivered-To: tickets@buterland-beckerhook.de
      From: =?ISO-8859-1?Q?J=FCrgen_M=FCller?= <Juergen@Example.com>
      To: vorstand@buterland-beckerhook.de, "Offiziere" <offiziere@buterland-beckerhook.de>
      Cc: dritter@example.com
      Subject: =?UTF-8?B?w4RyZ2VyIG1pdCBkZW0gWmVsdA==?=
      Message-ID: <abc@example.com>
      In-Reply-To: <x1@buterland-beckerhook.de>
      References: <x0@buterland-beckerhook.de> <x1@buterland-beckerhook.de>
      X-Rspamd-Score: 2.75
      MIME-Version: 1.0
      Content-Type: multipart/mixed; boundary=XX

      --XX
      Content-Type: text/plain; charset=iso-8859-1
      Content-Transfer-Encoding: quoted-printable

      Gr=FC=DFe aus Gronau
      --XX
      Content-Type: application/pdf; name="a.pdf"
      Content-Disposition: attachment; filename="=?UTF-8?Q?Anh=C3=A4ng.pdf?="
      Content-Transfer-Encoding: base64

      JVBERi0xLjQK
      --XX--
      """)

    assert {:ok, mail} = InboundMail.parse(raw)
    assert mail.from_name == "Jürgen Müller"
    assert mail.from_email == "juergen@example.com"
    assert mail.subject == "Ärger mit dem Zelt"
    assert mail.text == "Grüße aus Gronau"
    # The top-most X-Original-To is the one Postfix added.
    assert mail.original_to == "vorstand@buterland-beckerhook.de"
    assert mail.delivered_to == ["tickets@buterland-beckerhook.de"]
    assert mail.to == ["vorstand@buterland-beckerhook.de", "offiziere@buterland-beckerhook.de"]
    assert mail.cc == ["dritter@example.com"]
    assert mail.message_id == "<abc@example.com>"
    assert mail.message_id_hash == InboundMail.sha256("<abc@example.com>")

    assert mail.reply_ids == [
             "<x1@buterland-beckerhook.de>",
             "<x0@buterland-beckerhook.de>",
             "<x1@buterland-beckerhook.de>"
           ]

    assert mail.spam_score == 2.75

    assert [
             %{
               filename: "Anhäng.pdf",
               content_type: "application/pdf",
               data: "%PDF-1.4\n",
               size: 9
             }
           ] = mail.attachments
  end

  test "HTML only becomes text, links kept, scripts gone" do
    raw =
      crlf("""
      From: a@example.com
      Subject: Hallo
      MIME-Version: 1.0
      Content-Type: text/html; charset=utf-8

      <html><head><style>p{}</style></head><body><p>Hallo &amp; willkommen</p><script>alert(1)</script><p>Siehe <a href="https://example.com/x">hier</a>.<br>Gruß</p></body></html>
      """)

    assert {:ok, mail} = InboundMail.parse(raw)
    assert mail.text == "Hallo & willkommen\nSiehe hier (https://example.com/x).\nGruß"
  end

  test "prefers text/plain in multipart/alternative" do
    raw =
      crlf("""
      From: a@example.com
      Subject: Alt
      MIME-Version: 1.0
      Content-Type: multipart/alternative; boundary=B

      --B
      Content-Type: text/plain; charset=utf-8

      Klartext
      --B
      Content-Type: text/html; charset=utf-8

      <p>HTML</p>
      --B--
      """)

    assert {:ok, %{text: "Klartext", attachments: []}} = InboundMail.parse(raw)
  end

  test "Outlook's blank and non-breaking-space lines collapse to one blank line" do
    raw =
      crlf("""
      From: a@example.com
      Subject: Outlook
      MIME-Version: 1.0
      Content-Type: text/plain; charset=utf-8

      Hallo zusammen!

      \u00A0

      Anmeldungen bitte an:

      a@example.com \t

      \u00A0

      \u00A0

      Gruß
      Rainer
      """)

    assert {:ok, %{text: text}} = InboundMail.parse(raw)
    assert text == "Hallo zusammen!\n\nAnmeldungen bitte an:\n\na@example.com\n\nGruß\nRainer"
  end

  test "placeholder sender names are dropped" do
    for name <- ["undefined", "null", "NaN"] do
      raw = crlf("From: \"#{name}\" <a@example.com>\nSubject: X\n\nText\n")
      assert {:ok, %{from_name: nil, from_email: "a@example.com"}} = InboundMail.parse(raw)
    end
  end

  test "auto replies, bulk mail, reports and the spamd header" do
    raw =
      crlf("""
      From: MAILER-DAEMON@mail.example.com
      Subject: Undelivered Mail Returned to Sender
      Auto-Submitted: auto-replied
      Precedence: Bulk
      X-Spamd-Result: default: False [7.10 / 15.00];
      MIME-Version: 1.0
      Content-Type: multipart/report; report-type=delivery-status; boundary=R

      --R
      Content-Type: text/plain

      Could not deliver <a1b2@buterland-beckerhook.de>
      --R--
      """)

    assert {:ok, mail} = InboundMail.parse(raw)
    assert mail.auto_submitted == "auto-replied"
    assert mail.precedence == "bulk"
    assert mail.report?
    assert mail.spam_score == 7.1
    assert mail.message_id == nil
    assert mail.message_id_hash == InboundMail.sha256(raw)
  end

  test "Windows-1252 and broken UTF-8 do not fail the mail" do
    raw =
      "From: a@example.com\r\nSubject: x\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=windows-1252\r\nContent-Transfer-Encoding: 8bit\r\n\r\nPreis: 30 \x80 \x84quoted\x93\r\n"

    assert {:ok, %{text: "Preis: 30 € „quoted“"}} = InboundMail.parse(raw)

    raw =
      "From: a@example.com\r\nSubject: x\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nkaputt \xff ende\r\n"

    assert {:ok, %{text: text}} = InboundMail.parse(raw)
    assert text =~ "kaputt"
    assert text =~ "ende"
  end

  test "raw UTF-8 in headers (SMTPUTF8) survives" do
    raw =
      "From: Jürgen Müller <juergen@example.com>\r\nSubject: Grüße vom Schützenfest\r\n" <>
        "Content-Type: text/plain; charset=utf-8\r\n\r\nHallo\r\n"

    assert {:ok, %{from_name: "Jürgen Müller", subject: "Grüße vom Schützenfest"}} =
             InboundMail.parse(raw)
  end

  test "mailcow's folded X-Spamd-Result and X-Spam-Flag" do
    raw =
      crlf("""
      From: "Fuugu" <azyodzw@coust-wels.baby>
      To: <fiesel@bussenstueble.de>
      Subject: *** SPAM *** Schluss mit dem Schrubben!
      X-Rspamd-Queue-Id: 5B9E9140B4D
      X-Spamd-Result: default: False [10.72 / 15.00];
          IP_REPUTATION_SPAM(4.17)[asn: 60781(0.39), country: NL(0.01)];
          FORGED_RECIPIENTS(3.00)[m:fiesel@bussenstueble.de,s:offiziere@buterland-beckerhook.de];
          FROM_HAS_DN(0.00)[]
      X-Spam-Flag: YES
      Content-Type: text/plain; charset=utf-8

      Kaufen!
      """)

    assert {:ok, %{spam_score: 10.72, spam_flag?: true}} = InboundMail.parse(raw)
  end
end
