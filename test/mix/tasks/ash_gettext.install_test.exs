defmodule Mix.Tasks.AshGettext.InstallTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.AshGettext.Install

  @moduletag :tmp_dir

  @backend """
  defmodule MyApp.Gettext do
    use Gettext.Backend, otp_app: :my_app
  end
  """

  @domain """
  defmodule MyApp.Shop do
    use Ash.Domain
  end
  """

  @resource """
  defmodule MyApp.Shop.Order do
    use Ash.Resource, domain: MyApp.Shop
  end
  """

  setup %{tmp_dir: dir} do
    Mix.shell(Mix.Shell.IO)
    File.mkdir_p!(Path.join(dir, "lib"))

    for {name, source} <- [backend: @backend, shop: @domain, order: @resource] do
      File.write!(Path.join(dir, "lib/#{name}.ex"), source)
    end

    %{dir: dir}
  end

  # The task reads `lib/` relative to the working directory, as a real run does.
  defp run_in(dir, args) do
    File.cd!(dir, fn ->
      capture_io(:stderr, fn ->
        send(self(), {:out, capture_io(fn -> Install.run(args) end)})
      end)
    end)

    assert_received {:out, out}
    out
  end

  defp read(dir, name), do: File.read!(Path.join(dir, "lib/#{name}.ex"))

  test "previews by default and writes nothing", %{dir: dir} do
    out = run_in(dir, [])

    assert out =~ "Backend: MyApp.Gettext"
    assert out =~ "Domains: 1 to wire"
    assert out =~ "Nothing written"
    assert read(dir, "shop") == @domain
    assert read(dir, "order") == @resource
  end

  test "--apply wires the domain and the resource", %{dir: dir} do
    run_in(dir, ["--apply"])

    shop = read(dir, "shop")
    assert shop =~ "extensions: [AshGettext.Domain]"
    assert shop =~ "gettext do"
    assert shop =~ "backend MyApp.Gettext"
    refute shop =~ "locale_resolvers"
    assert read(dir, "order") =~ "extensions: [AshGettext.Resource]"
  end

  test "reports a domain that is already wired and leaves it alone", %{dir: dir} do
    run_in(dir, ["--apply"])
    wired = read(dir, "shop")

    out = run_in(dir, ["--apply"])

    assert out =~ "Domains: 0 to wire, 1 already done"
    assert read(dir, "shop") == wired
  end

  test "raises when no backend can be found", %{dir: dir} do
    File.rm!(Path.join(dir, "lib/backend.ex"))

    assert_raise Mix.Error, ~r/No Gettext backend found/, fn -> run_in(dir, []) end
  end

  test "raises when two backends are found", %{dir: dir} do
    File.write!(Path.join(dir, "lib/other.ex"), String.replace(@backend, "MyApp", "Other"))

    assert_raise Mix.Error, ~r/Found 2 Gettext backends/, fn -> run_in(dir, []) end
  end

  test "--backend skips detection", %{dir: dir} do
    File.rm!(Path.join(dir, "lib/backend.ex"))

    out = run_in(dir, ["--backend", "Other.Gettext"])

    assert out =~ "Backend: Other.Gettext"
  end

  test "reports a domain it cannot wire", %{dir: dir} do
    File.write!(
      Path.join(dir, "lib/odd.ex"),
      "defmodule Odd do\n  # use Ash.Domain\n  use Ash.Domain,\nend\n"
    )

    stderr =
      capture_io(:stderr, fn -> File.cd!(dir, fn -> capture_io(fn -> Install.run([]) end) end) end)

    assert stderr =~ "could not be wired"
  end
end
