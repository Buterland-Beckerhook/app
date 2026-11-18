defmodule Bbh.BuildInfoTest do
  # Not async: the build info is application env.
  use ExUnit.Case, async: false

  alias Bbh.BuildInfo

  setup do
    prev = Application.get_env(:bbh, :build_info)
    on_exit(fn -> Application.put_env(:bbh, :build_info, prev) end)
  end

  test "a dev checkout has no build" do
    Application.put_env(:bbh, :build_info, version: nil, commit: "", image: nil)
    info = BuildInfo.get()

    refute BuildInfo.built?(info)
    assert info.commit == nil
    assert BuildInfo.short_commit(info) == nil
    assert BuildInfo.built_at_local(info) == nil
  end

  test "reads a CI build" do
    Application.put_env(:bbh, :build_info,
      version: "1.2.0-3-gabcdef1",
      commit: "abcdef1234567890abcdef1234567890abcdef12",
      ref: "main",
      build_tag: "20261118-1015-abcdef1",
      built_at: "2026-11-18T10:15:00Z",
      run_url: "https://github.com/Buterland-Beckerhook/app/actions/runs/1",
      image: "ghcr.io/buterland-beckerhook/app:beta"
    )

    info = BuildInfo.get()

    assert BuildInfo.built?(info)
    assert BuildInfo.short_commit(info) == "abcdef1"
    assert BuildInfo.commit_url(info) =~ "/commit/abcdef1234567890"
    refute BuildInfo.release?(info)
    assert BuildInfo.release_url(info) == nil
    # Shown in the club's time zone (CET in November).
    assert %DateTime{hour: 11, minute: 15} = BuildInfo.built_at_local(info)
  end

  test "a release build links its release" do
    Application.put_env(:bbh, :build_info, version: "1.2.0", commit: "abcdef1")
    info = BuildInfo.get()

    assert BuildInfo.release?(info)
    assert BuildInfo.release_url(info) =~ "/releases/tag/v1.2.0"
  end

  test "an unparsable build time is dropped" do
    Application.put_env(:bbh, :build_info, commit: "abcdef1", built_at: "gestern")
    assert BuildInfo.get().built_at == nil
  end

  test "knows when the VM started" do
    assert DateTime.compare(BuildInfo.started_at(), DateTime.utc_now()) in [:lt, :eq]
  end
end
