defmodule AshGettext.GettextExtractTest do
  # Runs Gettext's own extractor, which is global state, so not async.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @moduletag :tmp_dir

  # The app the fixtures below stand in for, compiled the way
  # `mix gettext.extract` compiles an app: with extraction switched on.
  @app """
  defmodule ExtractFixture.Gettext do
    use Gettext.Backend, otp_app: :ash_gettext, priv: "PRIV"
  end

  defmodule ExtractFixture.Status do
    use AshGettext.Enum,
      backend: ExtractFixture.Gettext,
      values: [
        placed: [label: "Order placed"],
        waiting: [label: "Ready for pickup", description: "Ready at the pickup point"]
      ]
  end

  defmodule ExtractFixture.MinimumWeight do
    use Ash.Resource.Validation

    @impl true
    def validate(changeset, _opts, _context) do
      case Ash.Changeset.get_attribute(changeset, :weight) do
        weight when is_integer(weight) and weight < 30 ->
          {:error, field: :weight, message: "must weigh at least 30 kg"}

        weight when is_integer(weight) and weight > 900 ->
          {:error, field: :weight, message: "too heavy: \#{weight}"}

        _fine ->
          :ok
      end
    end
  end

  defmodule ExtractFixture.Parcel do
    use Ash.Resource,
      domain: ExtractFixture.Shop,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshGettext.Resource]

    actions do
      defaults([:read])

      create :create do
        accept([:weight, :status])
        validate({ExtractFixture.MinimumWeight, []})
        validate(present(:status), message: "pick a status")
      end
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:weight, :integer, public?: true)
      attribute(:status, ExtractFixture.Status, public?: true)
    end

    gettext do
      label(:weight, "Weight")
    end
  end

  defmodule ExtractFixture.Shop do
    use Ash.Domain, extensions: [AshGettext.Domain], validate_config_inclusion?: false

    gettext do
      backend(ExtractFixture.Gettext)
      locale_resolver(AshGettextFixture.ActorLanguage)
    end

    resources do
      resource(ExtractFixture.Parcel)
    end
  end
  """

  # In a file of its own: a validation module's whole source file is read.
  @untranslated """
  defmodule ExtractFixture.Untranslated.Parcel do
    use Ash.Resource,
      domain: ExtractFixture.Untranslated,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshGettext.Resource]

    actions do
      defaults([:read])

      create :create do
        validate(present(:weight), message: "nobody translates this")
      end
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:weight, :integer, public?: true)
    end

    gettext do
      label(:weight, "Untranslated weight")
    end
  end

  defmodule ExtractFixture.Untranslated do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource(ExtractFixture.Untranslated.Parcel)
    end
  end
  """

  setup_all do
    dir = Path.join(["tmp", inspect(__MODULE__)])
    File.rm_rf!(dir)
    File.mkdir_p!(Path.join(dir, "priv"))
    source = Path.join(dir, "app.ex")
    File.write!(source, String.replace(@app, "PRIV", Path.join(dir, "priv")))
    untranslated = Path.join(dir, "untranslated.ex")
    File.write!(untranslated, @untranslated)

    Gettext.Extractor.enable()

    warnings =
      try do
        capture_io(:stderr, fn ->
          Code.compile_file(source)
          Code.compile_file(untranslated)
        end)
      after
        Gettext.Extractor.disable()
      end

    pots = Gettext.Extractor.pot_files(:ash_gettext, [])
    %{pots: pots, warnings: warnings, source: source}
  end

  defp msgids(pots, text_domain) do
    {_path, {_, contents}} =
      Enum.find(pots, fn {path, _} -> Path.basename(path) == "#{text_domain}.pot" end)

    {:ok, po} = contents |> IO.iodata_to_binary() |> Expo.PO.parse_string()
    Enum.map(po.messages, &IO.iodata_to_binary(&1.msgid))
  end

  test "an enum's labels and descriptions", %{pots: pots} do
    ids = msgids(pots, "ash")
    assert "Order placed" in ids
    assert "Ready for pickup" in ids
    assert "Ready at the pickup point" in ids
  end

  test "an attribute label", %{pots: pots} do
    assert "Weight" in msgids(pots, "ash")
  end

  test "a message written in the resource's DSL", %{pots: pots} do
    assert "pick a status" in msgids(pots, "ash")
  end

  test "a message inside a validation module the resource uses", %{pots: pots} do
    assert "must weigh at least 30 kg" in msgids(pots, "ash")
  end

  test "the sentences for Ash's own errors", %{pots: pots} do
    ids = msgids(pots, "ash")
    for msgid <- AshGettext.AshMessages.msgids(), do: assert(msgid in ids)
  end

  test "nothing from a domain without a gettext block", %{pots: pots} do
    all =
      pots |> Enum.map(fn {_, {_, contents}} -> IO.iodata_to_binary(contents) end) |> Enum.join()

    refute all =~ "nobody translates this"
    refute all =~ "Untranslated weight"
  end

  test "an interpolated message is a warning that names its line", %{
    warnings: warnings,
    source: source
  } do
    assert warnings =~ "cannot be a msgid"
    assert warnings =~ Path.basename(source)
  end
end
