defmodule Bbh.Media do
  @moduledoc """
  Media storage and on-demand responsive variants (libvips via `Image`).

  Originals live under `:uploads_dir` keyed by `storage_key`. Requesting a size
  produces a cached WebP variant under `:media_cache_dir` (regenerable, so it is
  excluded from backups). Replaces Directus asset transforms.
  """
  alias Bbh.Repo
  alias Bbh.Media.Upload

  @content_types %{
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".png" => "image/png",
    ".webp" => "image/webp",
    ".gif" => "image/gif",
    ".avif" => "image/avif",
    ".svg" => "image/svg+xml"
  }

  def uploads_dir, do: Application.fetch_env!(:bbh, :uploads_dir)
  def cache_dir, do: Application.fetch_env!(:bbh, :media_cache_dir)

  def get_by_key(key), do: Repo.get_by(Upload, storage_key: key)

  @doc """
  Resolve a media request to a servable file. Returns `{:ok, path, content_type}`
  or `:error`. With no dimensions, serves the original; otherwise a cached WebP
  variant (`fit=cover` when both dimensions are given).
  """
  def resolve_variant(key, width, height) do
    with {:ok, source} <- safe_source(key), true <- File.regular?(source) do
      if is_nil(width) and is_nil(height),
        do: {:ok, source, content_type(source)},
        else: variant(source, key, width, height)
    else
      _ -> :error
    end
  end

  @doc """
  Copy a file into the uploads dir and create an `Upload` row (used by the admin
  media library and the one-time import). Extra `attrs` (title, copyright, …) are merged.
  """
  def store_file(source_path, attrs \\ %{}) do
    ext = source_path |> Path.extname() |> String.downcase()
    key = "#{Date.utc_today().year}/#{Ecto.UUID.generate()}#{ext}"
    dest = Path.join(uploads_dir(), key)
    File.mkdir_p!(Path.dirname(dest))
    File.cp!(source_path, dest)

    {width, height} = dimensions(dest)

    attrs
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.merge(%{
      "storage_key" => key,
      "filename" => attrs[:filename] || attrs["filename"] || Path.basename(source_path),
      "content_type" => content_type(dest),
      "byte_size" => File.stat!(dest).size,
      "width" => width,
      "height" => height
    })
    |> then(&Upload.changeset(%Upload{}, &1))
    |> Repo.insert()
  end

  defp variant(source, key, width, height) do
    name = :crypto.hash(:sha256, "#{key}|#{width}|#{height}") |> Base.encode16(case: :lower)
    dest = Path.join(cache_dir(), "#{name}.webp")

    cond do
      File.regular?(dest) ->
        {:ok, dest, "image/webp"}

      generate(source, dest, width, height) == :ok ->
        {:ok, dest, "image/webp"}

      # On any processing failure, fall back to the original so the page still shows.
      true ->
        {:ok, source, content_type(source)}
    end
  end

  defp generate(source, dest, width, height) do
    File.mkdir_p!(Path.dirname(dest))

    with {:ok, img} <- Image.open(source),
         {:ok, thumb} <- thumbnail(img, width, height),
         {:ok, _} <- Image.write(thumb, dest, quality: 82) do
      :ok
    else
      _ -> :error
    end
  end

  defp thumbnail(img, width, nil), do: Image.thumbnail(img, width)
  defp thumbnail(img, nil, height), do: Image.thumbnail(img, "x#{height}")
  defp thumbnail(img, width, height), do: Image.thumbnail(img, width, height: height, crop: :center)

  defp dimensions(path) do
    case Image.open(path) do
      {:ok, img} -> {Image.width(img), Image.height(img)}
      _ -> {nil, nil}
    end
  end

  # Reject path traversal; keys are relative to the uploads dir.
  defp safe_source(key) do
    if String.contains?(key, ".."), do: :error, else: {:ok, Path.join(uploads_dir(), key)}
  end

  defp content_type(path),
    do: Map.get(@content_types, path |> Path.extname() |> String.downcase(), "application/octet-stream")
end
