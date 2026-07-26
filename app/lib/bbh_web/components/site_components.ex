defmodule BbhWeb.SiteComponents do
  @moduledoc "Reusable public-site function components (cards, tables, block renderer)."
  use Phoenix.Component
  use BbhWeb, :verified_routes

  import BbhWeb.Format
  # For the heroicon stand-in a person without a portrait gets.
  import BbhWeb.CoreComponents, only: [icon: 1]
  alias Bbh.Club.Person
  alias Bbh.Content.Throne
  alias BbhWeb.EmailObfuscation

  # --- Gallery block, "Diashow" layout (see docs/adr/0008) ---

  # The frame a slide falls back to when its stored ratio is unreadable.
  @default_ratio {16, 9}

  # How large a variant a slide asks the media pipeline for, on its longer edge.
  @slide_long_edge 1600

  # How long a slide stays before autoplay moves on. Long enough to read a caption and
  # look at the picture; short enough that a visitor waiting for the next one does not
  # give up. Only ever used when the editor turned autoplay on.
  @autoplay_interval_ms 6000

  @doc """
  An article's hero image, sized as requested. Falls back to the club logo
  (contained, not cropped) when the article has no images.
  """
  attr :article, :map, required: true
  attr :width, :integer, default: nil
  attr :height, :integer, default: nil
  attr :class, :string, default: ""

  def hero_image(assigns) do
    assigns = assign(assigns, :hero, article_hero(assigns.article))

    ~H"""
    <img
      :if={@hero}
      src={media_url(@hero.media, width: @width, height: @height)}
      alt={image_alt(@hero)}
      loading="lazy"
      class={["object-cover", @class]}
    />
    <img
      :if={!@hero}
      src={~p"/images/logo.svg"}
      alt="Buterland-Beckerhook"
      loading="lazy"
      class={["bg-tag object-contain p-6", @class]}
    />
    """
  end

  @doc """
  The credit line under an image: Bildunterschrift left, Copyright right — muted, one
  line, as little room as it can take.

  The row wraps rather than squeezes: when both do not fit side by side (a long caption,
  a narrow phone), the copyright moves to its own right-aligned line. It is never
  overlapped and never dropped — a rights notice you hide is worse than one extra line.

  Renders nothing when there is neither caption nor copyright.
  """
  attr :caption, :string, default: nil
  attr :copyright, :string, default: nil
  attr :class, :any, default: nil

  def image_credit(assigns) do
    assigns = assign(assigns, :copyright, copyright_label(assigns.copyright))

    ~H"""
    <figcaption
      :if={@caption || @copyright}
      class={[
        "mt-1 flex flex-wrap items-baseline justify-between gap-x-3 text-xs leading-snug text-muted",
        @class
      ]}
    >
      <span :if={@caption} class="min-w-0">{@caption}</span>
      <span :if={@copyright} class="ml-auto shrink-0 whitespace-nowrap">{@copyright}</span>
    </figcaption>
    """
  end

  @doc """
  Ein E-Mail-Link, der für Harvester unlesbar ist (siehe `BbhWeb.EmailObfuscation`).

  Für fest im Template gesetzte Adressen. Adressen im Redaktionstext werden beim
  Rendern automatisch verschleiert und brauchen diese Komponente nicht.

  Ohne JavaScript zeigt der Link die Adresse und führt zum Kontaktformular;
  `assets/js/mail.js` macht bei der ersten Interaktion ein `mailto:` daraus.
  """
  attr :address, :string, required: true

  attr :label, :string,
    default: nil,
    doc:
      "Linktext statt der Adresse. Versteckt die Adresse komplett — ohne JS gar nicht " <>
        "erreichbar, deshalb nicht im Impressum verwenden (siehe docs/adr/0005)."

  attr :class, :any, default: nil
  attr :subject, :string, default: nil

  def email_link(assigns) do
    ~H"""
    {EmailObfuscation.link(@address, label: @label, class: @class, query: subject_query(@subject))}
    """
  end

  defp subject_query(nil), do: ""
  defp subject_query(subject), do: "?subject=" <> URI.encode_www_form(subject)

  @doc "Preview card for an article in a listing."
  attr :article, :map, required: true

  def article_card(assigns) do
    ~H"""
    <a
      href={~p"/aktuell/#{@article.year}/#{@article.slug}"}
      class="group flex flex-col overflow-hidden rounded-[18px] border border-base-300 bg-card transition-shadow hover:shadow-md"
    >
      <div class="h-[190px] overflow-hidden bg-tag">
        <%!-- 2× the 190px box for retina displays --%>
        <.hero_image
          article={@article}
          width={640}
          height={380}
          class="h-full w-full transition-transform group-hover:scale-105"
        />
      </div>
      <div class="flex flex-1 flex-col p-5.5">
        <time class="text-[13px] font-medium text-muted">{de_date(@article.date_published)}</time>
        <h3 class="font-logo mt-1.5 text-[22px] leading-snug group-hover:text-primary">
          {@article.title}
        </h3>
        <p :if={@article.subtitle} class="mt-1.5 text-[15px] leading-relaxed text-muted">
          {@article.subtitle}
        </p>
        <div :if={@article.tags != []} class="mt-4 flex flex-wrap gap-2">
          <span
            :for={tag <- @article.tags}
            class="rounded-full bg-tag px-2.75 py-1 text-xs font-semibold text-primary"
          >
            {tag}
          </span>
        </div>
      </div>
    </a>
    """
  end

  @doc "Preview card for an event in a listing."
  attr :event, :map, required: true

  def event_card(assigns) do
    ~H"""
    <a
      href={~p"/termine/#{@event.year}/#{@event.slug}"}
      class="flex flex-col rounded-lg border border-base-300 bg-card p-4 transition-shadow hover:shadow-md"
    >
      <div class="flex items-center gap-2">
        <h3 class="text-base-content">{@event.title}</h3>
        <span
          :if={@event.status == "canceled"}
          class="rounded bg-error/10 px-2 py-0.5 text-xs font-medium text-error"
        >
          Abgesagt
        </span>
      </div>
      <time class="mt-1 text-sm text-muted">
        {de_range(@event.starts_at, @event.ends_at, @event.all_day)}
      </time>
      <p :if={@event.location} class="mt-1 text-sm text-muted">
        {@event.location.name}
      </p>
    </a>
    """
  end

  @doc "A single full-text search hit (article, event or page)."
  attr :doc, :map, required: true

  def search_result(assigns) do
    ~H"""
    <a
      href={@doc.url}
      class="block rounded-lg border border-base-300 bg-card p-4 transition-shadow hover:shadow-md"
    >
      <div class="flex flex-wrap items-center gap-2">
        <span class="rounded-full bg-tag px-2.5 py-0.5 text-xs font-semibold text-primary">
          {source_label(@doc.source_type)}
        </span>
        <time :if={@doc.document_date} class="text-[13px] text-muted">
          {de_date(@doc.document_date)}
        </time>
      </div>
      <h3 class="font-logo mt-1.5 text-[20px] leading-snug text-base-content group-hover:text-primary">
        {@doc.title}
      </h3>
      <p
        :if={@doc.headline not in [nil, ""]}
        class="mt-1.5 text-[15px] leading-relaxed text-muted [&_mark]:bg-accent/30 [&_mark]:text-base-content"
      >
        {mark_headline(@doc.headline)}
      </p>
    </a>
    """
  end

  defp source_label("article"), do: "Artikel"
  defp source_label("event"), do: "Termin"
  defp source_label("page"), do: "Seite"
  defp source_label(other), do: other

  # The snippet arrives with neutral @@M@@/@@E@@ markers around matches. Escape
  # the (plain-text) content first, then reinstate <mark> — so nothing in the
  # indexed text can inject markup.
  #
  # The index is built from the stored body (before placeholders resolve), so an
  # address hardcoded in the copy would otherwise surface here in the clear — this
  # is the second way out onto a public page besides `Format.render_richtext/1`.
  # Known gap: a match marker landing inside an address keeps it in the clear,
  # because the pattern no longer matches. Rare enough to live with.
  # sobelow_skip ["XSS.Raw"]
  defp mark_headline(text) when is_binary(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> String.replace("@@M@@", "<mark>")
    |> String.replace("@@E@@", "</mark>")
    |> EmailObfuscation.rewrite()
    |> Phoenix.HTML.raw()
  end

  @doc "Throne detail table (König/Kaiser + court)."
  attr :throne, :map, required: true
  attr :show_caption, :boolean, default: true, doc: "hide when the caption is shown elsewhere"

  def throne_table(assigns) do
    {king_label, queen_label} = throne_roles(assigns.throne.type)
    # Stadtkaiser = bewusst nur das (Stadt-)Kaiserpaar. Sonst ist die Anzeige
    # datengesteuert: Königin und Hofstaat erscheinen, wenn sie eingetragen sind
    # (der Jungschützenkönig hatte früher vollen Hofstaat, dann nur eine Königin,
    # heute nur den König).
    full_court? = assigns.throne.type != "stadtkaiser"

    assigns =
      assign(assigns, king_label: king_label, queen_label: queen_label, full_court?: full_court?)

    ~H"""
    <table class="w-full text-left text-[15px]">
      <caption :if={@show_caption} class="mb-2 text-left">
        <span class="flex items-baseline justify-between gap-3">
          <span class="font-logo text-lg font-bold text-primary">{throne_name(@throne)}</span>
          <span class="text-sm font-semibold whitespace-nowrap text-muted">
            {throne_years(@throne)}
          </span>
        </span>
      </caption>
      <tbody class="divide-y divide-base-300">
        <tr>
          <th class="py-3.5 pr-4 font-medium text-muted">{@king_label}</th>
          <td class="py-3.5 text-right font-semibold">{@throne.king}</td>
        </tr>
        <tr :if={@throne.queen}>
          <th class="py-3.5 pr-4 font-medium text-muted">{@queen_label}</th>
          <td class="py-3.5 text-right font-semibold">{@throne.queen}</td>
        </tr>
        <tr :if={@full_court? && (@throne.moh1 || @throne.loh1)}>
          <th class="py-3.5 pr-4 font-medium text-muted">Ehrenpaare</th>
          <td class="py-3.5 text-right font-semibold">
            {[@throne.loh1, @throne.moh1] |> Enum.reject(&is_nil/1) |> Enum.join(" und ")}
          </td>
        </tr>
        <tr :if={@full_court? && (@throne.moh2 || @throne.loh2)}>
          <th class="py-3.5 pr-4 font-medium text-muted"></th>
          <td class="py-3.5 text-right font-semibold">
            {[@throne.loh2, @throne.moh2] |> Enum.reject(&is_nil/1) |> Enum.join(" und ")}
          </td>
        </tr>
        <tr :if={@full_court? && @throne.cupbearer}>
          <th class="py-3.5 pr-4 font-medium text-muted">Mundschenk</th>
          <td class="py-3.5 text-right font-semibold">{@throne.cupbearer}</td>
        </tr>
        <tr :if={@full_court? && @throne.courtmarshal}>
          <th class="py-3.5 pr-4 font-medium text-muted">Oberhofmarschall</th>
          <td class="py-3.5 text-right font-semibold">{@throne.courtmarshal}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  # Row labels for the royal couple, by throne type. The queen row itself is only
  # rendered when a queen is set (see the table), so a king-only throne shows just
  # the king.
  defp throne_roles("kaiser"), do: {"Kaiser", "Kaiserin"}
  defp throne_roles("stadtkaiser"), do: {"Stadtkaiser", "Stadtkaiserin"}
  defp throne_roles("jungschuetzenkoenig"), do: {"Jungschützenkönig", "Königin"}
  defp throne_roles(_), do: {"König", "Königin"}

  @doc ~S(Heading name for a throne: title + regency name, e.g. "König Jan-Bernd I." or "Jungschützenkönig".)
  def throne_name(%Throne{} = t) do
    {kind, _} = throne_roles(t.type)
    [kind, t.king_title] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" ")
  end

  @doc "Simple role → name table (Vorstand / Offiziere)."
  attr :people, :list, required: true
  attr :show_address, :boolean, default: false

  def person_table(assigns) do
    ~H"""
    <table class="w-full text-left text-sm">
      <tbody class="divide-y divide-base-300">
        <tr :for={p <- @people}>
          <th class="py-2 pr-4 font-medium text-muted">
            {Person.role_label(p.role)}
          </th>
          <td class="py-2">
            {p.name}
            <span
              :if={@show_address && (p.street || p.city)}
              class="block text-muted"
            >
              {[p.street, p.city] |> Enum.reject(&is_nil/1) |> Enum.join(", ")}
            </span>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  One card per person: portrait beside a Name / born / died / biography column.

  Laid out like a `media_card` with the image on the right, but at 60/40 rather than
  50/50 — the biography needs the room more than the portrait does. The portrait comes
  first in the DOM and the row is reversed on `md+`, which is what puts it to the right on
  a wide screen and above the text on a narrow one.

  Those four fields are the **whole** set, by request. In particular the role label that
  leads every `person_table/1` row is deliberately absent — a Karten block is for portraits
  and biographies, and `person_table/1` remains the view that answers "who holds which
  office". `show_address` is likewise table-only. The portrait shows no caption or copyright
  line either, unlike every other public image surface (see `docs/adr/0004`); add one via
  `image_credit/1` if a historical photo ever needs the credit.
  """
  attr :people, :list, required: true

  def person_cards(assigns) do
    ~H"""
    <ul class="space-y-6">
      <%!-- A list, so a screen reader announces how many people are in it. The name is
            deliberately not a heading: the block's own title is an `h3` and it is optional,
            so a heading here would skip a level on a titleless block. The table this
            mirrors labels its rows with `th`, not headings, either. --%>
      <%!-- `bbh-person-card` carries no CSS of its own (unlike the other `bbh-*` classes);
            it is the stable hook the public-render tests scope their queries to. --%>
      <li
        :for={p <- @people}
        class="bbh-person-card rounded-[18px] border border-base-300 bg-card p-6 sm:p-8"
      >
        <div class="flex flex-col gap-4 md:flex-row-reverse md:items-start">
          <.person_portrait person={p} />
          <div class="md:w-3/5">
            <p class="text-lg font-semibold">{p.name}</p>
            <%!-- Both dates are free text ("1920 in Buterland"), and plenty of people are
                  still alive — hence two independent lines rather than one formatted
                  string. „*" and „†" are the German convention but announce as "asterisk"
                  and "dagger", so the label a screen reader needs is carried alongside. --%>
            <p :if={p.birth_date} class="text-sm text-muted">
              <span aria-hidden="true">*</span><span class="sr-only">geboren</span>
              {p.birth_date}
            </p>
            <p :if={p.death_date} class="text-sm text-muted">
              <span aria-hidden="true">†</span><span class="sr-only">gestorben</span>
              {p.death_date}
            </p>
            <div :if={biography?(p.biography)}>
              <div class="mt-3 h-px bg-base-300"></div>
              <div class="prose prose-sm mt-3 max-w-none dark:prose-invert">
                {BbhWeb.Format.render_richtext(p.biography)}
              </div>
            </div>
          </div>
        </div>
      </li>
    </ul>
    """
  end

  # Quill leaves an emptied editor as `<p></p>`: truthy, but nothing to show — and it would
  # draw the divider above a blank box. An `<img>` carries no text yet is still content, and
  # `Bbh.Html.sanitize/1` deliberately keeps images (that is what the media picker inserts),
  # so text-emptiness alone would silently drop a biography that is a scanned document.
  # `to_text/1` already trims.
  defp biography?(html) do
    Bbh.Html.to_text(html) != "" or String.contains?(html || "", "<img")
  end

  # The portrait frame, or a generic stand-in when nobody picked a picture. Asking for
  # both dimensions is the point: `media_url/2` only carries the focal point on a URL that
  # requests a cover crop, and that is what keeps a face in frame rather than the middle
  # of the photo.
  attr :person, :any, required: true

  defp person_portrait(%{person: %{portrait: %Bbh.Media.Upload{}}} = assigns) do
    ~H"""
    <img
      src={media_url(@person.portrait, width: 400, height: 500)}
      alt={image_alt(@person.portrait)}
      loading="lazy"
      class="aspect-[4/5] w-full rounded-lg object-cover md:w-2/5"
    />
    """
  end

  defp person_portrait(assigns) do
    ~H"""
    <div class="flex aspect-[4/5] w-full items-center justify-center rounded-lg bg-base-200 md:w-2/5">
      <.icon name="hero-user" class="size-16 text-base-content/30" />
    </div>
    """
  end

  @doc "Render an ordered list of resolved page blocks (`{page_block, struct}` tuples)."
  attr :blocks, :list, required: true

  def blocks(assigns) do
    ~H"""
    <div class="space-y-8">
      <.block :for={{pb, block} <- @blocks} type={pb.block_type} block={block} />
    </div>
    """
  end

  @doc "Render a single content block by type."
  attr :type, :string, required: true
  attr :block, :any, required: true

  def block(%{type: "richtext"} = assigns) do
    ~H"""
    <div class="prose max-w-none dark:prose-invert">
      {BbhWeb.Format.render_richtext(@block.body)}
    </div>
    """
  end

  def block(%{type: "alert"} = assigns) do
    ~H"""
    <div class={["rounded-lg border-l-4 p-4", alert_classes(@block.icon)]}>
      <div class="prose prose-sm max-w-none dark:prose-invert">
        {BbhWeb.Format.render_richtext(@block.body)}
      </div>
    </div>
    """
  end

  def block(%{type: "media_card"} = assigns) do
    ~H"""
    <div class={@block.shadow && "rounded-[18px] border border-base-300 bg-card p-6 shadow-lg sm:p-8"}>
      <%!-- With "Titel über dem Bild" on, title/subtitle span the full width above the
            image row (like the first card in the design). No left/right flip here — that
            only applies to the inline header below. --%>
      <div :if={@block.title_above && (@block.title || @block.subtitle)} class="mb-4">
        <h3 :if={@block.title} class="text-lg font-semibold">{@block.title}</h3>
        <p :if={@block.subtitle} class="text-sm text-muted">{@block.subtitle}</p>
        <div class="mt-3 h-px bg-base-300"></div>
      </div>
      <div class={[
        "flex flex-col gap-4 md:items-center",
        @block.image_position == "left" && "md:flex-row",
        @block.image_position != "left" && "md:flex-row-reverse"
      ]}>
        <figure :if={@block.image} class="w-full md:w-1/2">
          <img
            src={media_url(@block.image, width: 480)}
            alt={image_alt(@block.image)}
            class="w-full rounded-lg object-cover"
          />
          <.image_credit
            :if={@block.show_credit}
            caption={image_caption(@block.image)}
            copyright={image_copyright(@block.image)}
          />
        </figure>
        <%!-- Inline layout (image left/right): the text column stretches to the image
              height (md:self-stretch overrides the parent's md:items-center for this
              item only) and a capped, collapsible spacer sits between the header and
              body. The spacer grows to give the title/body room when the body is short,
              and shrinks back to the mt-2 baseline when the body fills the column. --%>
        <div class="md:flex md:w-1/2 md:flex-col md:self-stretch">
          <%!-- Inline header (title not above): aligned to the side opposite the image. --%>
          <div
            :if={!@block.title_above && (@block.title || @block.subtitle)}
            class={["md:shrink-0", @block.image_position == "left" && "text-right"]}
          >
            <h3 :if={@block.title} class="text-lg">{@block.title}</h3>
            <p :if={@block.subtitle} class="text-sm text-muted">{@block.subtitle}</p>
            <div class="mt-3 h-px bg-base-300"></div>
          </div>
          <div :if={!@block.title_above} class="hidden md:block md:max-h-10 md:grow"></div>
          <div
            :if={@block.body}
            class={[
              "prose prose-sm max-w-none dark:prose-invert md:shrink-0",
              !@block.title_above && "mt-2"
            ]}
          >
            {BbhWeb.Format.render_richtext(@block.body)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  def block(%{type: "image_gallery"} = assigns) do
    ~H"""
    <figure>
      <figcaption :if={@block.title} class="mb-2 font-semibold">{@block.title}</figcaption>
      <%!-- Files arrive in the editor's order (ImageGallery.has_many :preload_order). --%>
      <.gallery_slideshow :if={@block.layout == "slideshow"} block={@block} />
      <.gallery_grid :if={@block.layout != "slideshow"} block={@block} />
    </figure>
    """
  end

  def block(%{type: "person_list"} = assigns) do
    assigns =
      assign(
        assigns,
        :people,
        Bbh.Club.list_people(assigns.block.filter_roles,
          honorary: assigns.block.filter_honorary,
          only_active: assigns.block.only_active,
          sort: assigns.block.sort_by
        )
      )

    ~H"""
    <div>
      <h3 :if={@block.title} class="mb-2 text-lg font-semibold">{@block.title}</h3>
      <.person_cards :if={@block.display_style == "cards"} people={@people} />
      <.person_table
        :if={@block.display_style != "cards"}
        people={@people}
        show_address={@block.show_address}
      />
    </div>
    """
  end

  def block(%{type: "separator"} = assigns) do
    ~H"""
    <hr class="border-t border-base-300" />
    """
  end

  def block(assigns), do: ~H""

  # Thumbnails stay bare; caption and copyright appear on enlarging.
  attr :block, :any, required: true

  defp gallery_grid(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-2 md:grid-cols-3">
      <.gallery_image
        :for={f <- @block.files}
        file={f}
        block={@block}
        size={{400, 400}}
        class="aspect-square w-full rounded object-cover"
      />
    </div>
    """
  end

  # One horizontal strip of slides, one slide wide, snapping to each. The strip is a
  # plain scroll container: without JavaScript it still swipes and still shows every
  # picture, and `scroll-behavior: smooth` (app.css) is what makes the arrows push the
  # next picture in instead of cutting to it. assets/js/slideshow.js adds the arrows'
  # behaviour, keyboard control and autoplay on top.
  #
  # Every slide is cropped to the block's ratio, so the frame stays put from picture to
  # picture — a slideshow that resizes itself around each photo is what the fixed ratio
  # exists to prevent. Unlike the grid, the credit line is shown right here: a Diashow
  # *is* the enlarged view, so hiding the Bildunterschrift behind the lightbox would
  # mean it is never read.
  attr :block, :any, required: true

  defp gallery_slideshow(assigns) do
    ratio = parse_ratio(assigns.block.aspect_ratio)

    assigns =
      assigns
      |> assign(:ratio, ratio)
      |> assign(:css_ratio, css_ratio(ratio))
      |> assign(:count, length(assigns.block.files))
      |> assign(:interval, @autoplay_interval_ms)

    ~H"""
    <div
      class="relative"
      data-slideshow
      data-slideshow-interval={@block.autoplay && to_string(@interval)}
      role="region"
      aria-roledescription="Diashow"
      aria-label={@block.title || "Bildergalerie"}
    >
      <%!-- `tabindex` so the strip is reachable and arrow-scrollable by keyboard even
            with the lightbox off, when no slide contains anything focusable. The live
            region announces the slide a reader scrolled to — silenced while autoplay
            runs, where it would interrupt them every few seconds instead. --%>
      <div
        class="bbh-slideshow-track"
        data-slideshow-track
        tabindex="0"
        aria-live={if @block.autoplay, do: "off", else: "polite"}
      >
        <figure
          :for={{f, i} <- Enum.with_index(@block.files)}
          class="bbh-slideshow-slide"
          role="group"
          aria-roledescription="Bild"
          aria-label={"#{i + 1} von #{@count}"}
        >
          <.gallery_image
            file={f}
            block={@block}
            size={slide_size(@ratio, f.media)}
            class="w-full rounded object-cover"
            style={"aspect-ratio: #{@css_ratio}"}
            eager={i == 0}
          />
          <.image_credit caption={image_caption(f)} copyright={image_copyright(f)} />
        </figure>
      </div>

      <%!-- Overlaid on the picture, not on the whole slide: sharing the slide's ratio
            makes this layer end exactly where the credit line begins, so the arrows sit
            in the middle of the photo rather than the middle of the photo plus its
            caption. Click-through everywhere except on the arrows themselves. --%>
      <div
        :if={@count > 1}
        class="pointer-events-none absolute inset-x-0 top-0"
        style={"aspect-ratio: #{@css_ratio}"}
      >
        <button
          type="button"
          data-slideshow-prev
          class="bbh-slideshow-arrow pointer-events-auto left-2"
          aria-label="Vorheriges Bild"
        >
          ‹
        </button>
        <button
          type="button"
          data-slideshow-next
          class="bbh-slideshow-arrow pointer-events-auto right-2"
          aria-label="Nächstes Bild"
        >
          ›
        </button>
      </div>

      <%!-- `aria-current` carries the string, not the boolean: it is an enumerated
            attribute, and HEEx renders `true` as a valueless `aria-current`, which the
            spec reads as "false" and `.bbh-slideshow-dot[aria-current="true"]` does not
            match — leaving no dot marked until the first scroll. --%>
      <div :if={@count > 1} class="mt-2 flex justify-center gap-1.5">
        <button
          :for={{_f, i} <- Enum.with_index(@block.files)}
          type="button"
          class="bbh-slideshow-dot"
          data-slideshow-dot={i}
          aria-current={to_string(i == 0)}
          aria-label={"Bild #{i + 1} anzeigen"}
        ></button>
      </div>
    </div>
    """
  end

  # The image itself, with the lightbox trigger around it when the block asks for one.
  attr :file, :any, required: true
  attr :block, :any, required: true
  attr :size, :any, required: true, doc: "{width, height} of the variant to request"
  attr :class, :any, required: true
  attr :style, :any, default: nil

  attr :eager, :boolean,
    default: false,
    doc: "the slide showing on load — the gallery's LCP candidate, so never lazy"

  defp gallery_image(assigns) do
    {width, height} = assigns.size
    assigns = assigns |> assign(:width, width) |> assign(:height, height)

    ~H"""
    <button
      :if={@block.lightbox}
      type="button"
      data-lightbox-src={media_url(@file.media, width: 1600)}
      data-lightbox-alt={image_alt(@file)}
      data-lightbox-caption={image_caption(@file)}
      data-lightbox-copyright={copyright_label(image_copyright(@file))}
      data-lightbox-group={"gallery-#{@block.id}"}
      class="block w-full cursor-zoom-in"
      aria-label="Bild vergrößern"
    >
      <img
        src={media_url(@file.media, width: @width, height: @height)}
        alt={image_alt(@file)}
        loading={if @eager, do: "eager", else: "lazy"}
        fetchpriority={@eager && "high"}
        class={@class}
        style={@style}
      />
    </button>
    <img
      :if={!@block.lightbox}
      src={media_url(@file.media, width: @width, height: @height)}
      alt={image_alt(@file)}
      loading={if @eager, do: "eager", else: "lazy"}
      fetchpriority={@eager && "high"}
      class={@class}
      style={@style}
    />
    """
  end

  # `ImageGallery.aspect_ratios/0` stores "W:H"; everything downstream wants the two
  # numbers. Parsed once, here, so a value that somehow got past `validate_inclusion`
  # (a hand-written UPDATE, a nil slipping through) costs the crop rather than the
  # page — every other dispatch in this module is total, and this one reads straight
  # from the database into a `style` attribute.
  defp parse_ratio(aspect_ratio) do
    case aspect_ratio |> to_string() |> String.split(":") |> Enum.map(&Integer.parse/1) do
      [{w, ""}, {h, ""}] when w > 0 and h > 0 -> {w, h}
      _ -> @default_ratio
    end
  end

  defp css_ratio({w, h}), do: "#{w}/#{h}"

  # The variant to ask the media pipeline for: the block's ratio scaled until its longer
  # edge reaches @slide_long_edge. Requesting both dimensions is the point —
  # `media_url/2` only carries the focal point on a URL that asks for a cover crop, so
  # this is what makes a portrait frame keep the face instead of the middle of the
  # picture. Derived from the ratio rather than tabulated, so adding one to
  # `ImageGallery.aspect_ratios/0` needs no second edit here.
  #
  # Never larger than the picture actually is: the resize step upscales on request, and
  # a 640px club photo blown up to 1600 is a soft image that also costs more bytes than
  # the original. The frame is held by CSS either way, so a smaller variant only means
  # less zoom headroom on a wide screen.
  defp slide_size({w, h}, media) do
    scale = source_long_edge(media) / max(w, h)
    {round(w * scale), round(h * scale)}
  end

  defp source_long_edge(%{width: w, height: h}) when is_integer(w) and is_integer(h),
    do: min(@slide_long_edge, max(w, h))

  defp source_long_edge(_media), do: @slide_long_edge

  defp alert_classes("warning"), do: "border-warning bg-warning/10"
  defp alert_classes("success"), do: "border-success bg-success/10"
  defp alert_classes("danger"), do: "border-error bg-error/10"
  defp alert_classes(_info), do: "border-info bg-info/10"

  @doc "Page navigation using the German ?seite= query param."
  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :base_path, :string, required: true
  attr :query, :map, default: %{}, doc: "extra query params to preserve, e.g. %{\"q\" => term}"

  def pagination(assigns) do
    assigns = assign(assigns, :items, pagination_items(assigns.page, assigns.total_pages))

    ~H"""
    <nav :if={@total_pages > 1} class="mt-8 flex flex-wrap items-center justify-center gap-1">
      <a
        :if={@page > 1}
        href={page_href(@base_path, @query, @page - 1)}
        rel="prev"
        aria-label="Zurück"
        class="rounded border border-base-300 px-3 py-1 text-sm hover:border-primary hover:text-primary"
      >
        <span class="sr-only sm:not-sr-only">Zurück</span>
        <span aria-hidden="true" class="sm:hidden">‹</span>
      </a>
      <%= for item <- @items do %>
        <span :if={item == :gap} class="px-2 py-1 text-sm text-muted">…</span>
        <a
          :if={item != :gap}
          href={page_href(@base_path, @query, item)}
          aria-current={item == @page && "page"}
          class={[
            "rounded border px-3 py-1 text-sm",
            item == @page && "border-primary bg-primary text-primary-content",
            item != @page && "border-base-300 hover:border-primary hover:text-primary"
          ]}
        >
          {item}
        </a>
      <% end %>
      <a
        :if={@page < @total_pages}
        href={page_href(@base_path, @query, @page + 1)}
        rel="next"
        aria-label="Weiter"
        class="rounded border border-base-300 px-3 py-1 text-sm hover:border-primary hover:text-primary"
      >
        <span class="sr-only sm:not-sr-only">Weiter</span>
        <span aria-hidden="true" class="sm:hidden">›</span>
      </a>
    </nav>
    """
  end

  # Build "?…&seite=N", URL-encoding any preserved params (e.g. the search query).
  defp page_href(base_path, query, seite) do
    qs = query |> Map.put("seite", seite) |> URI.encode_query()
    "#{base_path}?#{qs}"
  end

  # Windowed page list: always first/last + current ±1, with :gap markers for
  # the elided stretches, so the pager stays narrow even with many pages.
  defp pagination_items(page, total) do
    [1, total, page - 1, page, page + 1]
    |> Enum.filter(&(&1 >= 1 and &1 <= total))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.reduce([], fn n, acc ->
      case acc do
        [prev | _] when is_integer(prev) and n - prev > 1 -> [n, :gap | acc]
        _ -> [n | acc]
      end
    end)
    |> Enum.reverse()
  end

  @doc "Kompakter Jahr–König-Pager für /thron (nur ?seite= Navigation)."
  attr :page, :integer, required: true
  attr :nav, :list, required: true
  attr :base_path, :string, required: true

  def throne_pager(assigns) do
    total = length(assigns.nav)

    assigns =
      assign(assigns,
        total: total,
        newer: assigns.page > 1 && Enum.at(assigns.nav, assigns.page - 2),
        older: assigns.page < total && Enum.at(assigns.nav, assigns.page)
      )

    ~H"""
    <nav :if={@total > 1} class="mt-8 grid grid-cols-1 items-center gap-2 sm:grid-cols-[1fr_auto_1fr]">
      <div class="hidden justify-self-start sm:block">
        <a
          :if={@newer}
          href={"#{@base_path}?seite=#{@page - 1}"}
          class="text-sm hover:text-primary"
        >
          ‹ {throne_nav_label(@newer)}
        </a>
      </div>

      <select
        data-nav-select
        class="select w-full max-w-full justify-self-center sm:max-w-[16rem]"
        aria-label="Thron auswählen"
      >
        <option
          :for={{t, i} <- Enum.with_index(@nav)}
          value={"#{@base_path}?seite=#{i + 1}"}
          selected={i + 1 == @page}
        >
          {throne_nav_label(t)}
        </option>
      </select>

      <div class="hidden justify-self-end text-right sm:block">
        <a
          :if={@older}
          href={"#{@base_path}?seite=#{@page + 1}"}
          class="text-sm hover:text-primary"
        >
          {throne_nav_label(@older, :king_first)} ›
        </a>
      </div>
    </nav>
    """
  end

  @doc "Breadcrumb trail for a Verein sub-page, from its root → leaf ancestor chain."
  attr :ancestors, :list, required: true, doc: "root → leaf list of pages"

  def breadcrumbs(assigns) do
    crumbs =
      assigns.ancestors
      |> Enum.with_index(1)
      |> Enum.map(fn {p, i} ->
        %{title: p.title, path: Bbh.Content.page_path(Enum.take(assigns.ancestors, i))}
      end)

    assigns = assign(assigns, :crumbs, crumbs)

    ~H"""
    <nav aria-label="Brotkrümel" class="mb-4 text-sm text-muted">
      <ol class="flex flex-wrap items-center gap-x-1.5 gap-y-1">
        <li><a href="/verein" class="hover:text-primary">Verein</a></li>
        <li :for={{c, i} <- Enum.with_index(@crumbs)} class="flex items-center gap-x-1.5">
          <span aria-hidden="true" class="text-base-content/40">/</span>
          <a :if={i < length(@crumbs) - 1} href={c.path} class="hover:text-primary">{c.title}</a>
          <span
            :if={i == length(@crumbs) - 1}
            class="font-medium text-base-content"
            aria-current="page"
          >
            {c.title}
          </span>
        </li>
      </ol>
    </nav>
    """
  end

  @doc "Desktop sidebar listing a section's pages (root first, then descendants), current highlighted."
  attr :links, :list,
    required: true,
    doc: "flat `%{path, title, depth}` list from Content.section_links/1"

  attr :current_path, :string, required: true

  def page_sidebar(assigns) do
    ~H"""
    <nav aria-label="Bereichsnavigation" class="text-sm">
      <ul class="space-y-0.5">
        <li :for={l <- @links}>
          <a
            href={l.path}
            style={"padding-left: #{0.75 + l.depth * 0.75}rem"}
            class={[
              "block rounded-md py-1.5 pr-3 transition-colors",
              l.path == @current_path && "bg-base-200 font-semibold text-primary",
              l.path != @current_path && "text-muted hover:bg-base-200 hover:text-primary"
            ]}
            aria-current={l.path == @current_path && "page"}
          >
            {l.title}
          </a>
        </li>
      </ul>
    </nav>
    """
  end

  @doc "Mobile section navigation: a native <select> that jumps to the chosen page (reuses data-nav-select)."
  attr :links, :list, required: true
  attr :current_path, :string, required: true

  def page_submenu_select(assigns) do
    ~H"""
    <select
      data-nav-select
      class="select select-bordered w-full"
      aria-label="Seite im Bereich wählen"
    >
      <option
        :for={l <- @links}
        value={l.path}
        selected={l.path == @current_path}
      >
        {String.duplicate("– ", l.depth) <> l.title}
      </option>
    </select>
    """
  end

  @doc ~S(Reign years for a throne, e.g. "2025–2026" or "2009".)
  def throne_years(t) do
    if t.end_year && t.end_year != t.begin_year,
      do: "#{t.begin_year}–#{t.end_year}",
      else: "#{t.begin_year}"
  end

  # Standard: „Jahr – König" (Select + linker Pfeil).
  defp throne_nav_label(t), do: throne_nav_label(t, :year_first)

  defp throne_nav_label(t, :king_first),
    do: [t.king, throne_years(t)] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" – ")

  defp throne_nav_label(t, :year_first),
    do: [throne_years(t), t.king] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" – ")
end
