defmodule Mix.Tasks.Bbh.Import do
  @shortdoc "One-time import of the legacy Hugo content into the database"
  @moduledoc """
  Imports locations, people, events, articles (+thrones +images) and pages from the
  Hugo content repo. THROWAWAY — run once at cutover, then delete this task.

      mix bbh.import [path-to-hugo-repo]   # default: ../../buterland-beckerhook

  Per-item failures are logged and skipped so one bad file can't abort the run.
  Best run against a fresh DB (mix ecto.reset).
  """
  use Mix.Task

  alias Bbh.Repo
  alias Bbh.Calendar.{Event, Location}
  alias Bbh.Club.Person
  alias Bbh.Content.{Article, ArticleImage, Throne, Page, PageBlock}
  alias Bbh.Content.Blocks

  @counts :bbh_import_counts

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    src = List.first(args) || "../../buterland-beckerhook"
    unless File.dir?(Path.join(src, "content")), do: Mix.raise("Hugo content not found at #{src}")

    :ets.new(@counts, [:named_table, :public])

    import_locations(src)
    import_people(src)
    import_events(src)
    import_articles(src)
    import_pages(src)

    IO.puts("\n=== Import summary ===")
    for {k, v} <- Enum.sort(:ets.tab2list(@counts)), do: IO.puts("  #{k}: #{v}")
  end

  ## Locations

  defp import_locations(src) do
    src
    |> Path.join("data/locations/*.yaml")
    |> Path.wildcard()
    |> Enum.reject(&(Path.basename(&1, ".yaml") in ["none", "unknown"]))
    |> Enum.each(fn file ->
      safe("location", fn ->
        y = YamlElixir.read_from_file!(file)

        attrs = %{
          "key" => Path.basename(file, ".yaml"),
          "name" => y["name"],
          "street" => y["street"],
          "zip" => to_string_or_nil(y["zip"]),
          "city" => y["city"],
          # Source swaps lat/lng (lat holds the longitude); correct it here.
          "lat" => y["lng"],
          "lng" => y["lat"],
          "maps_url" => y["maps"]
        }

        upsert(Location, [key: attrs["key"]], &Location.changeset(&1, attrs))
      end)
    end)
  end

  ## People

  @role_map %{
    "praesident" => "praesident",
    "vizepraesident" => "vizepraesident",
    "geschaeftsfuehrer" => "geschaeftsfuehrer",
    "schriftfuehrer" => "schriftfuehrer",
    "kassierer" => "kassierer",
    "oberst" => "oberst",
    "oberstleutnant" => "oberstleutnant",
    "major" => "major"
  }

  defp import_people(src) do
    for {file, default} <- [{"vorstand.yaml", "vorstand"}, {"offiziere.yaml", "offiziere"}] do
      path = Path.join([src, "data", file])

      if File.exists?(path) do
        path
        |> YamlElixir.read_from_file!()
        |> Enum.with_index()
        |> Enum.each(fn {{role_key, val}, i} -> import_person(role_key, val, default, i) end)
      end
    end
  end

  defp import_person(role_key, %{} = val, default, i) do
    safe("person", fn ->
      role =
        Map.get(
          @role_map,
          String.downcase(role_key),
          if(default == "offiziere", do: "offizier", else: "vorstand")
        )

      %Person{}
      |> Person.changeset(%{
        "name" => val["name"],
        "role" => role,
        "street" => nil_if_blank(val["street"]),
        "city" => nil_if_blank(val["city"]),
        "sort_order" => i
      })
      |> Repo.insert!()
    end)
  end

  defp import_person(_role_key, _val, _default, _i), do: :ok

  ## Events

  defp import_events(src) do
    src
    |> Path.join("content/termine/**/*.md")
    |> Path.wildcard()
    |> Enum.reject(&(Path.basename(&1) == "_index.md"))
    |> Enum.each(fn file ->
      safe("event", fn ->
        {fm, body} = parse_md(file)
        start = parse_dt(fm["start"] || fm["date"])
        if is_nil(start), do: throw(:no_start)
        location_id = location_id_for(fm["location"])

        %Event{}
        |> Event.changeset(%{
          "title" => fm["title"],
          "slug" => Path.basename(file, ".md") |> slugify(),
          "status" =>
            if(truthy(fm["canceled"]),
              do: "canceled",
              else: if(truthy(fm["draft"]), do: "draft", else: "published")
            ),
          "starts_at" => start,
          "ends_at" => parse_dt(fm["end"]),
          "location_id" => location_id,
          "announce" => not truthy(fm["hideOnHome"]),
          "body" => to_html(body)
        })
        |> Repo.insert!()
      end)
    end)
  end

  ## Articles (+ thrones + images)

  defp import_articles(src) do
    src
    |> Path.join("content/aktuell/*/*/index.md")
    |> Path.wildcard()
    |> Enum.each(fn file -> safe("article", fn -> import_article(file) end) end)
  end

  defp import_article(file) do
    {fm, body} = parse_md(file)
    dir = Path.dirname(file)
    year = dir |> Path.dirname() |> Path.basename() |> String.to_integer()
    date = parse_dt(fm["date"]) || DateTime.new!(Date.new!(year, 1, 1), ~T[12:00:00], "Etc/UTC")

    article =
      %Article{}
      |> Article.changeset(%{
        "status" => "published",
        "title" => fm["title"],
        "subtitle" => fm["subtitle"],
        "slug" => Path.basename(dir) |> slugify(),
        "date_published" => date,
        "author" => fm["author"],
        "tags" => List.wrap(fm["tags"]),
        "no_article" => truthy(fm["noarticle"]),
        "aliases" => List.wrap(fm["aliases"]),
        "body" => to_html(body)
      })
      |> Repo.insert!()

    if match?(%{"throne" => %{}}, fm), do: safe("throne", fn -> import_throne(article, fm) end)
    import_resources(article, dir, fm["resources"])
  end

  defp import_throne(article, %{"throne" => %{} = t}) do
    {b, e} = parse_years(t["years"])
    tags = List.wrap(article.tags)

    type =
      cond do
        "Stadtkaiser" in tags -> "stadtkaiser"
        "Kaiser" in tags -> "kaiser"
        true -> "koenig"
      end

    %Throne{}
    |> Throne.changeset(%{
      "article_id" => article.id,
      "type" => type,
      "begin_year" => b,
      "end_year" => e,
      "king_title" => t["king_title"],
      "king" => t["king"] || "?",
      "queen" => t["queen"] || "?",
      "moh1" => t["moh1"],
      "moh2" => t["moh2"],
      "loh1" => t["loh1"],
      "loh2" => t["loh2"],
      "cupbearer" => t["cupbearer"],
      "courtmarshal" => t["courtmarshal"]
    })
    |> Repo.insert!()
  end

  defp import_throne(_article, _fm), do: :ok

  defp import_resources(_article, _dir, nil), do: :ok

  defp import_resources(article, dir, resources) when is_list(resources) do
    resources
    |> Enum.with_index()
    |> Enum.each(fn {res, i} ->
      safe("image", fn ->
        path = Path.join(dir, res["src"])
        name = res["name"] || ""

        if File.exists?(path) do
          {:ok, upload} =
            Bbh.Media.store_file(path, %{
              filename: res["src"],
              title: res["title"],
              copyright: get_in(res, ["params", "copy"]) || "Buterland-Beckerhook e.V."
            })

          %ArticleImage{}
          |> ArticleImage.changeset(%{
            "article_id" => article.id,
            "media_id" => upload.id,
            "logical_name" => name,
            "title" => res["title"],
            "copyright" => get_in(res, ["params", "copy"]) || "Buterland-Beckerhook e.V.",
            "sort" => i,
            "use_as_throne_picture" => String.starts_with?(name, "thron"),
            "use_as_article_image" =>
              String.starts_with?(name, "bild") or
                (i == 0 and not String.starts_with?(name, "thron"))
          })
          |> Repo.insert!()
        end
      end)
    end)
  end

  ## Pages

  @page_map %{
    "impressum" => {"impressum", "Impressum"},
    "datenschutzerklaerung" => {"datenschutz", "Datenschutz"}
  }

  defp import_pages(src) do
    ["impressum.md", "datenschutzerklaerung.md"]
    |> Enum.each(fn file ->
      path = Path.join([src, "content", file])

      if File.exists?(path) do
        safe("page", fn ->
          {fm, body} = parse_md(path)
          {slug, default_title} = Map.fetch!(@page_map, Path.basename(file, ".md"))

          page =
            %Page{}
            |> Page.changeset(%{
              "status" => "published",
              "title" => fm["title"] || fm["headline"] || default_title,
              "slug" => slug
            })
            |> Repo.insert!()

          block = Repo.insert!(%Blocks.RichText{body: to_html(body)})

          Repo.insert!(%PageBlock{
            page_id: page.id,
            position: 0,
            block_type: "richtext",
            block_id: block.id
          })
        end)
      end
    end)
  end

  ## Helpers

  defp parse_md(path) do
    content = File.read!(path)

    case String.split(content, ~r/^---\s*$/m, parts: 3) do
      ["", fm, body] -> {YamlElixir.read_from_string!(fm) || %{}, String.trim(body)}
      _ -> {%{}, content}
    end
  end

  defp to_html(body) do
    body
    |> strip_shortcodes()
    |> Earmark.as_html!(compact_output: true)
  end

  defp strip_shortcodes(body), do: Regex.replace(~r/\{\{[<%].*?[%>]\}\}/s, body, "")

  defp parse_dt(nil), do: nil

  defp parse_dt(%DateTime{} = dt), do: DateTime.truncate(dt, :second)

  defp parse_dt(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp parse_dt(_), do: nil

  # "1909/1910" | "2023-2024" | "2024" -> {begin, end}
  defp parse_years(nil), do: {nil, nil}
  defp parse_years(y) when is_integer(y), do: {y, nil}

  defp parse_years(y) when is_binary(y) do
    case Regex.run(~r/(\d{4})\s*[\/\-]\s*(\d{4})/, y) do
      [_, a, b] ->
        {String.to_integer(a), String.to_integer(b)}

      _ ->
        case Regex.run(~r/(\d{4})/, y) do
          [_, a] -> {String.to_integer(a), nil}
          _ -> {nil, nil}
        end
    end
  end

  defp location_id_for(nil), do: nil
  defp location_id_for(key), do: Repo.get_by(Location, key: key) |> then(&(&1 && &1.id))

  defp slugify(s) do
    s
    |> String.downcase()
    |> String.replace(~r/[äöüß]/u, fn c ->
      %{"ä" => "ae", "ö" => "oe", "ü" => "ue", "ß" => "ss"}[c]
    end)
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp truthy(true), do: true
  defp truthy("true"), do: true
  defp truthy(_), do: false

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(v), do: to_string(v)

  defp nil_if_blank(v) when v in [nil, ""], do: nil
  defp nil_if_blank(v), do: v

  defp upsert(schema, clauses, changeset_fun) do
    (Repo.get_by(schema, clauses) || struct(schema))
    |> changeset_fun.()
    |> Repo.insert_or_update!()
  end

  defp safe(kind, fun) do
    fun.()
    bump(kind)
  rescue
    e -> IO.puts("  ! #{kind} failed: #{Exception.message(e)}")
  catch
    thrown -> IO.puts("  ! #{kind} skipped: #{inspect(thrown)}")
  end

  defp bump(kind) do
    :ets.update_counter(@counts, kind, {2, 1}, {kind, 0})
  end
end
