defmodule BbhWeb.SiteComponents do
  @moduledoc "Reusable public-site function components (cards, tables, block renderer)."
  use Phoenix.Component
  use BbhWeb, :verified_routes

  import BbhWeb.Format
  alias Bbh.Club.Person
  alias Bbh.Content.Throne

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
      class={["bg-white object-contain p-6 dark:bg-zinc-700", @class]}
    />
    """
  end

  @doc "Preview card for an article in a listing."
  attr :article, :map, required: true

  def article_card(assigns) do
    ~H"""
    <a
      href={~p"/aktuell/#{@article.year}/#{@article.slug}"}
      class="group flex flex-col overflow-hidden rounded-lg border border-gray-200 bg-white transition-shadow hover:shadow-md dark:border-zinc-700 dark:bg-zinc-800"
    >
      <div class="aspect-video overflow-hidden bg-gray-100 dark:bg-zinc-700">
        <.hero_image
          article={@article}
          width={640}
          height={360}
          class="h-full w-full transition-transform group-hover:scale-105"
        />
      </div>
      <div class="flex flex-1 flex-col p-4">
        <time class="text-sm text-gray-500 dark:text-gray-400">{de_date(@article.date_published)}</time>
        <h3 class="mt-1 font-semibold text-gray-900 group-hover:text-primary dark:text-gray-100">
          {@article.title}
        </h3>
        <p :if={@article.subtitle} class="mt-1 text-sm text-gray-600 dark:text-gray-300">
          {@article.subtitle}
        </p>
        <div :if={@article.tags != []} class="mt-3 flex flex-wrap gap-1">
          <span
            :for={tag <- @article.tags}
            class="rounded bg-primary/10 px-2 py-0.5 text-xs font-medium text-primary"
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
      class="flex flex-col rounded-lg border border-gray-200 bg-white p-4 transition-shadow hover:shadow-md dark:border-zinc-700 dark:bg-zinc-800"
    >
      <div class="flex items-center gap-2">
        <h3 class="font-semibold text-gray-900 dark:text-gray-100">{@event.title}</h3>
        <span
          :if={@event.status == "canceled"}
          class="rounded bg-error/10 px-2 py-0.5 text-xs font-medium text-error"
        >
          Abgesagt
        </span>
      </div>
      <time class="mt-1 text-sm text-gray-600 dark:text-gray-300">
        {de_range(@event.starts_at, @event.ends_at, @event.all_day)}
      </time>
      <p :if={@event.location} class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {@event.location.name}
      </p>
    </a>
    """
  end

  @doc "Throne detail table (König/Kaiser + court)."
  attr :throne, :map, required: true

  def throne_table(assigns) do
    ~H"""
    <table class="w-full text-left text-sm">
      <caption class="mb-2 text-lg font-semibold text-primary">
        {throne_caption(@throne)}
      </caption>
      <tbody class="divide-y divide-gray-200 dark:divide-zinc-700">
        <tr>
          <th class="py-2 pr-4 font-medium text-gray-600 dark:text-gray-300">König</th>
          <td class="py-2">
            {[@throne.king_title, @throne.king] |> Enum.reject(&is_nil/1) |> Enum.join(" – ")}
          </td>
        </tr>
        <tr>
          <th class="py-2 pr-4 font-medium text-gray-600 dark:text-gray-300">Königin</th>
          <td class="py-2">{@throne.queen}</td>
        </tr>
        <tr :if={@throne.moh1 || @throne.moh2}>
          <th class="py-2 pr-4 font-medium text-gray-600 dark:text-gray-300">Ehrenpaare</th>
          <td class="py-2">
            {[@throne.loh1, @throne.moh1] |> Enum.reject(&is_nil/1) |> Enum.join(" und ")}
          </td>
        </tr>
        <tr :if={@throne.loh1 || @throne.loh2}>
          <th class="py-2 pr-4 font-medium text-gray-600 dark:text-gray-300"></th>
          <td class="py-2">
            {[@throne.loh2, @throne.moh2] |> Enum.reject(&is_nil/1) |> Enum.join(" und ")}
          </td>
        </tr>
        <tr :if={@throne.cupbearer}>
          <th class="py-2 pr-4 font-medium text-gray-600 dark:text-gray-300">Mundschenk</th>
          <td class="py-2">{@throne.cupbearer}</td>
        </tr>
        <tr :if={@throne.courtmarshal}>
          <th class="py-2 pr-4 font-medium text-gray-600 dark:text-gray-300">Oberhofmarschall</th>
          <td class="py-2">{@throne.courtmarshal}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp throne_caption(%Throne{} = t) do
    kind =
      case t.type do
        "kaiser" -> "Kaiser"
        "stadtkaiser" -> "Stadtkaiser"
        _ -> "König"
      end

    years =
      if t.end_year && t.end_year != t.begin_year,
        do: "#{t.begin_year}–#{t.end_year}",
        else: "#{t.begin_year}"

    "#{kind} #{years}"
  end

  @doc "Simple role → name table (Vorstand / Offiziere)."
  attr :people, :list, required: true
  attr :show_address, :boolean, default: false

  def person_table(assigns) do
    ~H"""
    <table class="w-full text-left text-sm">
      <tbody class="divide-y divide-gray-200 dark:divide-zinc-700">
        <tr :for={p <- @people}>
          <th class="py-2 pr-4 font-medium text-gray-600 dark:text-gray-300">
            {Person.role_label(p.role)}
          </th>
          <td class="py-2">
            {p.name}
            <span
              :if={@show_address && (p.street || p.city)}
              class="block text-gray-500 dark:text-gray-400"
            >
              {[p.street, p.city] |> Enum.reject(&is_nil/1) |> Enum.join(", ")}
            </span>
          </td>
        </tr>
      </tbody>
    </table>
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
    <div class="prose max-w-none dark:prose-invert">{Phoenix.HTML.raw(@block.body)}</div>
    """
  end

  def block(%{type: "alert"} = assigns) do
    ~H"""
    <div class={["rounded-lg border-l-4 p-4", alert_classes(@block.icon)]}>
      <div class="prose prose-sm max-w-none dark:prose-invert">{Phoenix.HTML.raw(@block.body)}</div>
    </div>
    """
  end

  def block(%{type: "media_card"} = assigns) do
    ~H"""
    <div class={[
      "flex flex-col gap-4 md:items-center",
      @block.image_position == "left" && "md:flex-row",
      @block.image_position != "left" && "md:flex-row-reverse"
    ]}>
      <img
        :if={@block.image}
        src={media_url(@block.image, width: 480)}
        alt={@block.title || ""}
        class="w-full rounded-lg object-cover md:w-1/2"
      />
      <div class="md:w-1/2">
        <h3 :if={@block.title} class="text-lg font-semibold">{@block.title}</h3>
        <p :if={@block.subtitle} class="text-sm text-gray-500 dark:text-gray-400">
          {@block.subtitle}
        </p>
        <div :if={@block.body} class="prose prose-sm mt-2 max-w-none dark:prose-invert">
          {Phoenix.HTML.raw(@block.body)}
        </div>
      </div>
    </div>
    """
  end

  def block(%{type: "image_gallery"} = assigns) do
    ~H"""
    <figure>
      <figcaption :if={@block.title} class="mb-2 font-semibold">{@block.title}</figcaption>
      <div class="grid grid-cols-2 gap-2 md:grid-cols-3">
        <%= for f <- @block.files do %>
          <button
            :if={@block.lightbox}
            type="button"
            data-lightbox-src={media_url(f.media, width: 1600)}
            data-lightbox-alt={f.title || ""}
            data-lightbox-group={"gallery-#{@block.id}"}
            class="block cursor-zoom-in"
            aria-label="Bild vergrößern"
          >
            <img
              src={media_url(f.media, width: 400, height: 400)}
              alt={f.title || ""}
              loading="lazy"
              class="aspect-square w-full rounded object-cover"
            />
          </button>
          <img
            :if={!@block.lightbox}
            src={media_url(f.media, width: 400, height: 400)}
            alt={f.title || ""}
            loading="lazy"
            class="aspect-square w-full rounded object-cover"
          />
        <% end %>
      </div>
    </figure>
    """
  end

  def block(%{type: "person_list"} = assigns) do
    assigns =
      assign(
        assigns,
        :people,
        Bbh.Club.list_people(assigns.block.filter_roles, assigns.block.filter_honorary)
      )

    ~H"""
    <div>
      <h3 :if={@block.title} class="mb-2 text-lg font-semibold">{@block.title}</h3>
      <.person_table people={@people} show_address={@block.show_address} />
    </div>
    """
  end

  def block(assigns), do: ~H""

  defp alert_classes("warning"), do: "border-warning bg-warning/10"
  defp alert_classes("success"), do: "border-success bg-success/10"
  defp alert_classes("danger"), do: "border-error bg-error/10"
  defp alert_classes(_info), do: "border-info bg-info/10"

  @doc "Page navigation using the German ?seite= query param."
  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :base_path, :string, required: true

  def pagination(assigns) do
    ~H"""
    <nav :if={@total_pages > 1} class="mt-8 flex items-center justify-center gap-1">
      <a
        :if={@page > 1}
        href={"#{@base_path}?seite=#{@page - 1}"}
        class="rounded border border-gray-200 px-3 py-1 text-sm hover:border-primary hover:text-primary dark:border-zinc-700"
      >
        Zurück
      </a>
      <a
        :for={n <- 1..@total_pages}
        href={"#{@base_path}?seite=#{n}"}
        class={[
          "rounded border px-3 py-1 text-sm",
          n == @page && "border-primary bg-primary text-primary-content",
          n != @page && "border-gray-200 hover:border-primary hover:text-primary dark:border-zinc-700"
        ]}
      >
        {n}
      </a>
      <a
        :if={@page < @total_pages}
        href={"#{@base_path}?seite=#{@page + 1}"}
        class="rounded border border-gray-200 px-3 py-1 text-sm hover:border-primary hover:text-primary dark:border-zinc-700"
      >
        Weiter
      </a>
    </nav>
    """
  end
end
