defmodule Bbh.BuildInfo do
  @moduledoc """
  Which build is running — shown in the admin sidebar and, in full, on the dashboard.

  `.github/workflows/build.yml` bakes the build into the release image (Dockerfile
  `ARG`s → `BBH_BUILD_*` env); `deploy/compose.yml` adds the image reference the stack
  was started with (`BBH_IMAGE`, from `IMAGE` in `.env`). `runtime.exs` reads them into
  `config :bbh, :build_info`. A dev checkout has none of them and says so.

    * `version` — `git describe` against the `vX.Y.Z` release tags: `1.2.0` for a
      release build, `1.2.0-3-gabc1234` three commits after it.
    * `build_tag` — the immutable image tag (`YYYYMMDD-HHMM-<sha>`, main builds only),
      the one `deploy/update.sh --tag` takes. Together with the weekly no-cache rebuild,
      the commit alone does not identify an image; this tag does.
    * `image` — what the stack pulls, e.g. `…/app:beta` (rolling) or a pinned tag.
  """

  @repo_url "https://github.com/Buterland-Beckerhook/app"

  defstruct [:version, :commit, :ref, :build_tag, :built_at, :run_url, :image]

  @type t :: %__MODULE__{
          version: String.t() | nil,
          commit: String.t() | nil,
          ref: String.t() | nil,
          build_tag: String.t() | nil,
          built_at: DateTime.t() | nil,
          run_url: String.t() | nil,
          image: String.t() | nil
        }

  @doc "The running build. Fields the environment does not provide are `nil`."
  @spec get() :: t()
  def get do
    cfg = Application.get_env(:bbh, :build_info, [])

    %__MODULE__{
      version: present(cfg[:version]),
      commit: present(cfg[:commit]),
      ref: present(cfg[:ref]),
      build_tag: present(cfg[:build_tag]),
      built_at: parse_time(cfg[:built_at]),
      run_url: present(cfg[:run_url]),
      image: present(cfg[:image])
    }
  end

  @doc "Whether this is a CI-built image (as opposed to a dev checkout)."
  def built?(%__MODULE__{commit: commit}), do: commit != nil

  @doc ~s(The commit's first seven characters, as git and the image tags show it.)
  def short_commit(%__MODULE__{commit: nil}), do: nil
  def short_commit(%__MODULE__{commit: commit}), do: String.slice(commit, 0, 7)

  @doc "Link to the commit on GitHub."
  def commit_url(%__MODULE__{commit: nil}), do: nil
  def commit_url(%__MODULE__{commit: commit}), do: "#{@repo_url}/commit/#{commit}"

  @doc "Link to the release, when this build is exactly a release tag."
  def release_url(%__MODULE__{version: version} = info) do
    if release?(info), do: "#{@repo_url}/releases/tag/v#{version}"
  end

  @doc "A release build: the version is a plain `X.Y.Z`, not `X.Y.Z-n-g<sha>`."
  def release?(%__MODULE__{version: nil}), do: false
  def release?(%__MODULE__{version: version}), do: version =~ ~r/^\d+\.\d+\.\d+$/

  @doc "The build time in the club's time zone."
  def built_at_local(%__MODULE__{built_at: nil}), do: nil

  def built_at_local(%__MODULE__{built_at: dt}) do
    DateTime.shift_zone!(dt, Bbh.Time.time_zone())
  end

  @doc "When this BEAM started, in the club's time zone."
  def started_at do
    {ms, _since_last_call} = :erlang.statistics(:wall_clock)

    DateTime.utc_now()
    |> DateTime.add(-ms, :millisecond)
    |> DateTime.truncate(:second)
    |> DateTime.shift_zone!(Bbh.Time.time_zone())
  end

  @doc "Elixir and Erlang/OTP versions of the runtime."
  def runtime_versions do
    %{
      elixir: System.version(),
      otp: System.otp_release(),
      erts: to_string(:erlang.system_info(:version))
    }
  end

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      v -> v
    end
  end

  defp present(_), do: nil

  defp parse_time(value) do
    with v when is_binary(v) <- present(value),
         {:ok, dt, _offset} <- DateTime.from_iso8601(v) do
      dt
    else
      _ -> nil
    end
  end
end
