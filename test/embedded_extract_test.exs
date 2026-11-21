defmodule AshGettext.EmbeddedExtractTest do
  # Runs Gettext's own extractor, which is global state, so not async.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  # Compiled the way `mix gettext.extract` compiles an app. The embedded
  # resources are used as an attribute type, an argument type inside an array,
  # and nested inside one another; none is listed in the domain.
  @app """
  defmodule EmbeddedFixture.Gettext do
    use Gettext.Backend, otp_app: :ash_gettext, priv: "PRIV"
  end

  defmodule EmbeddedFixture.Address do
    use Ash.Resource, data_layer: :embedded

    actions do
      defaults([:read])

      create :create do
        accept([:street])
        validate(present(:street), message: "street is needed")
      end
    end

    attributes do
      attribute(:street, :string, public?: true)
    end
  end

  defmodule EmbeddedFixture.Parent do
    use Ash.Resource, data_layer: :embedded

    actions do
      defaults([:read])

      create :create do
        validate(present(:address), message: "parent needs an address")
      end
    end

    attributes do
      attribute(:address, EmbeddedFixture.Address, public?: true)
    end
  end

  defmodule EmbeddedFixture.Stop do
    use Ash.Resource, data_layer: :embedded

    actions do
      defaults([:read])

      create :create do
        validate(present(:name), message: "stop needs a name")
      end
    end

    attributes do
      attribute(:name, :string, public?: true)
    end
  end

  defmodule EmbeddedFixture.Parcel do
    use Ash.Resource,
      domain: EmbeddedFixture.Shop,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshGettext.Resource]

    actions do
      defaults([:read])

      create :create do
        argument(:stops, {:array, EmbeddedFixture.Stop})
      end
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:to, EmbeddedFixture.Parent, public?: true)
    end
  end

  defmodule EmbeddedFixture.Shop do
    use Ash.Domain, extensions: [AshGettext.Domain], validate_config_inclusion?: false

    gettext do
      backend(EmbeddedFixture.Gettext)
      locale_resolver(AshGettextFixture.ActorLanguage)
    end

    resources do
      resource(EmbeddedFixture.Parcel)
    end
  end
  """

  setup_all do
    dir = Path.join(["tmp", inspect(__MODULE__)])
    File.rm_rf!(dir)
    File.mkdir_p!(Path.join(dir, "priv"))
    source = Path.join(dir, "app.ex")
    File.write!(source, String.replace(@app, "PRIV", Path.join(dir, "priv")))

    Gettext.Extractor.enable()
    debug_info? = Code.get_compiler_option(:debug_info)

    try do
      capture_io(:stderr, fn ->
        Code.put_compiler_option(:debug_info, false)
        Code.compile_file(source)
      end)
    after
      Code.put_compiler_option(:debug_info, debug_info?)
      Gettext.Extractor.disable()
    end

    pot = :ash_gettext |> Gettext.Extractor.pot_files([]) |> Enum.find(&ash_pot?/1)

    # No `ash.pot` at all means nothing was marked for the app's text domain.
    msgids =
      with {_path, {_, contents}} <- pot,
           {:ok, po} <- contents |> IO.iodata_to_binary() |> Expo.PO.parse_string() do
        Enum.map(po.messages, &IO.iodata_to_binary(&1.msgid))
      else
        _no_pot -> []
      end

    %{msgids: msgids}
  end

  defp ash_pot?({path, _}), do: Path.basename(path) == "ash.pot"

  test "a message in an embedded resource used as an attribute type", %{msgids: msgids} do
    assert "street is needed" in msgids
  end

  test "a message in an embedded resource used as an argument type inside an array", %{
    msgids: msgids
  } do
    assert "stop needs a name" in msgids
  end

  test "a message in an embedded resource nested in another", %{
    msgids: msgids
  } do
    assert "parent needs an address" in msgids
  end
end
