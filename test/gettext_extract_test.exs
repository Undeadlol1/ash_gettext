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
      extensions: [AshGettext.Resource],
      authorizers: [Ash.Policy.Authorizer]

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

    policies do
      policy action(:create) do
        error_message("this shop is closed")
        authorize_if(always())
      end
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

  @annotated """
  defmodule ExtractFixture.Annotated.Parcel do
    use Ash.Resource,
      domain: ExtractFixture.Annotated,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshGettext.Resource]

    def note, do: "written twice"

    actions do
      create :create do
        validate(present(:weight), message: "written twice")
      end
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:weight, :integer, public?: true)
    end
  end

  defmodule ExtractFixture.Annotated do
    use Ash.Domain, extensions: [AshGettext.Domain], validate_config_inclusion?: false

    gettext do
      backend(ExtractFixture.Gettext)
      locale_resolver(AshGettextFixture.ActorLanguage)
    end

    resources do
      resource(ExtractFixture.Annotated.Parcel)
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
    annotated = Path.join(dir, "annotated.ex")
    File.write!(annotated, @annotated)

    Gettext.Extractor.enable()
    debug_info? = Code.get_compiler_option(:debug_info)

    warnings =
      try do
        capture_io(:stderr, fn ->
          Code.put_compiler_option(:debug_info, false)
          Code.compile_file(source)
          Code.compile_file(untranslated)
          Code.put_compiler_option(:debug_info, true)
          Code.compile_file(annotated)

          AshGettext.Extractor.mark(__ENV__, ExtractFixture.Gettext, "ash", [
            %{msgid: "from a sibling app", path: Path.expand("../sibling_app/lib/s.ex"), line: 3}
          ])
        end)
      after
        Code.put_compiler_option(:debug_info, debug_info?)
        Gettext.Extractor.disable()
      end

    pots = Gettext.Extractor.pot_files(:ash_gettext, [])

    %{
      pots: pots,
      warnings: warnings,
      source: Path.relative_to_cwd(source),
      annotated: Path.relative_to_cwd(annotated)
    }
  end

  defp messages(pots, text_domain) do
    {_path, {_, contents}} =
      Enum.find(pots, fn {path, _} -> Path.basename(path) == "#{text_domain}.pot" end)

    {:ok, po} = contents |> IO.iodata_to_binary() |> Expo.PO.parse_string()
    po.messages
  end

  defp references(pots, text_domain \\ "ash", msgid) do
    message = Enum.find(messages(pots, text_domain), &(IO.iodata_to_binary(&1.msgid) == msgid))
    List.flatten(message.references)
  end

  defp line_of(source \\ @app, snippet),
    do: Enum.find_index(String.split(source, "\n"), &(&1 =~ snippet)) + 1

  defp line_at(path, line), do: path |> File.read!() |> String.split("\n") |> Enum.at(line - 1)

  defp msgids(pots, text_domain),
    do: Enum.map(messages(pots, text_domain), &IO.iodata_to_binary(&1.msgid))

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

  test "a policy's own message", %{pots: pots} do
    assert "this shop is closed" in msgids(pots, "ash")
  end

  test "a message inside a validation module the resource uses", %{pots: pots} do
    assert "must weigh at least 30 kg" in msgids(pots, "ash")
  end

  test "the sentences for Ash's own errors, in the built-in catalog", %{pots: pots} do
    ids = msgids(pots, "ash_builtin")
    for msgid <- AshGettext.AshMessages.msgids(), do: assert(msgid in ids)
  end

  test "every sentence Ash ships in its own template, in the built-in catalog", %{pots: pots} do
    ids = msgids(pots, "ash_builtin")
    shipped = AshGettext.AshMessages.ash_sentences()

    assert "must be present" in shipped
    assert "length must be less than or equal to %{max}" in shipped
    assert shipped -- ids == []
  end

  test "no built-in sentence in the app's catalog", %{pots: pots} do
    ids = msgids(pots, "ash")

    refute "must be present" in ids
    refute "could not be found" in ids
    refute "You are not allowed to do this" in ids
  end

  test "no app text in the built-in catalog", %{pots: pots} do
    builtin_ids = msgids(pots, "ash_builtin")

    refute "pick a status" in builtin_ids
    refute "Weight" in builtin_ids
    refute "must weigh at least 30 kg" in builtin_ids
  end

  test "nothing from a domain without a gettext block", %{pots: pots} do
    all =
      pots |> Enum.map(fn {_, {_, contents}} -> IO.iodata_to_binary(contents) end) |> Enum.join()

    refute all =~ "nobody translates this"
    refute all =~ "Untranslated weight"
  end

  describe "where each text is referenced" do
    test "a message in the resource's DSL, at its own line", %{pots: pots, source: source} do
      assert references(pots, "pick a status") == [
               {source, line_of(~s|message: "pick a status"|)}
             ]
    end

    test "a policy's message, at its own line", %{pots: pots, source: source} do
      assert references(pots, "this shop is closed") == [
               {source, line_of(~s|error_message("this shop is closed")|)}
             ]
    end

    test "an attribute label, at its own line", %{pots: pots, source: source} do
      assert references(pots, "Weight") == [{source, line_of(~s|label(:weight, "Weight")|)}]
    end

    test "a message in a validation module, at its own line", %{pots: pots, source: source} do
      assert references(pots, "must weigh at least 30 kg") == [
               {source, line_of(~s|message: "must weigh at least 30 kg"|)}
             ]
    end

    test "a DSL message at the line its compile recorded", %{pots: pots, annotated: annotated} do
      assert references(pots, "written twice") == [
               {annotated, line_of(@annotated, ~s|message: "written twice"|)}
             ]
    end

    test "a sentence Ash writes itself, at its own line in Ash's files", %{pots: pots} do
      places = references(pots, "ash_builtin", "must be present")

      assert places != []

      for {path, line} <- places do
        assert String.starts_with?(path, "deps/ash/")
        assert line_at(path, line) =~ "must be present"
      end
    end

    test "a sentence found in Ash's code is not also sent to Ash's template", %{pots: pots} do
      for message <- messages(pots, "ash_builtin"),
          paths = for({path, _line} <- List.flatten(message.references), do: path),
          Enum.any?(paths, &String.ends_with?(&1, ".ex")) do
        refute "deps/ash/priv/gettext/ash.pot" in paths
      end
    end

    test "a sentence the library writes, at its own line in the library's list", %{pots: pots} do
      assert [{"deps/ash_gettext/lib/ash_gettext/ash_messages.ex", line}] =
               references(pots, "ash_builtin", "could not be found")

      assert line_at("lib/ash_gettext/ash_messages.ex", line) =~ ~s|"could not be found"|
    end

    test "the sentences the library writes, each at a place of its own", %{pots: pots} do
      places =
        for msgid <- AshGettext.AshMessages.msgids(),
            place <- references(pots, "ash_builtin", msgid),
            do: place

      assert places == Enum.uniq(places)
    end

    test "a text from a file outside the project, relative to it", %{pots: pots} do
      assert references(pots, "from a sibling app") == [{"../sibling_app/lib/s.ex", 3}]
    end
  end

  test "an interpolated message is a warning that names its line", %{
    warnings: warnings,
    source: source
  } do
    assert warnings =~ "cannot be a msgid"
    assert warnings =~ Path.basename(source)
  end
end
