defmodule AshGettext.TranslatorTest do
  use ExUnit.Case, async: true

  defmodule ActorLocale do
    @moduledoc false
    @behaviour AshGettext.Locale.Resolver

    @impl true
    def resolve(%{actor: %{locale: locale}}), do: locale
    def resolve(_context), do: nil
  end

  defmodule Translator do
    @moduledoc false
    use AshGettext.Translator,
      backend: AshGettextFixture.Gettext,
      locale_resolvers: [ActorLocale, AshGettext.Locale.FromContext],
      default_locale: "en"
  end

  @opts [text_domain: "fixture"]

  describe "locale/1" do
    test "an explicit locale wins over the actor" do
      assert Translator.locale(locale: "ru", actor: %{locale: "en"}) == "ru"
    end

    test "reads the locale off the actor through a resolver" do
      assert Translator.locale(actor: %{locale: "ru"}) == "ru"
    end

    test "reads the locale from the :context map" do
      assert Translator.locale(context: %{locale: "ru"}) == "ru"
    end

    test "falls back to the default" do
      assert Translator.locale() == "en"
      assert Translator.locale(actor: %{locale: nil}) == "en"
    end

    test "normalises ru_RU" do
      assert Translator.locale(locale: "ru_RU") == "ru"
    end
  end

  describe "translate/3" do
    test "translates in the explicit locale" do
      assert Translator.translate("greeting", [], [locale: "ru"] ++ @opts) == "Привет"
    end

    test "translates in the actor's locale" do
      assert Translator.translate("greeting", [], [actor: %{locale: "ru"}] ++ @opts) == "Привет"
    end

    test "uses the default locale" do
      assert Translator.translate("greeting", [], @opts) == "Hello"
    end

    test "interpolates bindings" do
      assert Translator.translate(
               "intake_added",
               [protein: 25, calories: 150],
               [locale: "ru"] ++ @opts
             ) == "Добавлено 25г белка, 150 калорий"
    end

    test "text domain defaults to \"default\"" do
      assert Translator.translate("anything") == "anything"
    end
  end

  describe "translate_plural/5" do
    test "picks the plural form" do
      assert Translator.translate_plural("album", "albums", 5, [], @opts) == "5 albums"
      assert Translator.translate_plural("album", "albums", 1, [], @opts) == "1 album"
    end
  end

  describe "missing-translation telemetry" do
    setup do
      id = {__MODULE__, make_ref()}
      test_pid = self()

      :telemetry.attach(
        id,
        [:ash_gettext, :translation, :missing],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:missing, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(id) end)
    end

    test "fires on a miss" do
      Translator.translate("translated_in_english_only", [], [locale: "ru"] ++ @opts)

      assert_receive {:missing, %{count: 1},
                      %{
                        backend: AshGettextFixture.Gettext,
                        text_domain: "fixture",
                        msgid: "translated_in_english_only",
                        locale: "ru"
                      }}
    end

    test "fires on a plural miss" do
      Translator.translate_plural("album", "albums", 2, [], [locale: "ru"] ++ @opts)
      assert_receive {:missing, %{count: 1}, %{msgid: "album", locale: "ru"}}
    end

    test "does not fire on a hit" do
      Translator.translate("greeting", [], [locale: "ru"] ++ @opts)
      refute_receive {:missing, _, _}
    end

    test "does not fire in the source locale" do
      Translator.translate("not in any catalog", [], [locale: "en"] ++ @opts)
      refute_receive {:missing, _, _}
    end
  end

  describe "known_locales/1" do
    defmodule OddSourceBackend do
      @moduledoc false
      use Gettext.Backend,
        otp_app: :ash_gettext,
        priv: "priv/test_gettext",
        default_locale: "zz"
    end

    test "includes the source locale first, once" do
      assert AshGettext.known_locales(OddSourceBackend) |> hd() == "zz"
      locales = AshGettext.known_locales(AshGettextFixture.Gettext)
      assert "en" in locales and "ru" in locales
      assert locales == Enum.uniq(locales)
    end
  end

  describe "use options" do
    test "a missing backend raises" do
      assert_raise ArgumentError, ~r/:backend/, fn ->
        Code.compile_string("defmodule NoBackend do use AshGettext.Translator, [] end")
      end
    end

    test "an unknown option raises" do
      assert_raise ArgumentError, ~r/bogus/, fn ->
        Code.compile_string("""
        defmodule BogusOpt do
          use AshGettext.Translator, backend: AshGettextFixture.Gettext, bogus: 1
        end
        """)
      end
    end
  end
end
