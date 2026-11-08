defmodule AshGettext.InfoTest do
  use ExUnit.Case, async: true

  alias AshGettext.Info
  alias AshGettextFixture.Gettext, as: Backend

  describe "reading the settings of a translating domain" do
    test "reports the declared backend and text domain" do
      assert {:ok, settings} = Info.settings(AshGettextFixture.Shipping)
      assert settings.backend == Backend
      assert settings.text_domain == "fixture"
    end

    test "reports the declared default locale and resolver" do
      assert {:ok, settings} = Info.settings(AshGettextFixture.Shipping)
      assert settings.default_locale == "en"
      assert settings.locale_resolver == AshGettextFixture.ActorLanguage
    end

    test "derives supported locales from the backend rather than a declared list" do
      assert {:ok, settings} = Info.settings(AshGettextFixture.Shipping)
      assert Enum.sort(settings.supported_locales) == ["en", "ru"]
    end

    test "applies the defaults a domain does not state" do
      assert {:ok, settings} = Info.settings(AshGettextFixture.Opinionated)
      assert settings.default_locale == "en"
    end
  end

  describe "finding the language of an actor" do
    test "asks the resolver and fits the answer to the catalogs" do
      assert Info.language(AshGettextFixture.Shipping, %{language: "ru_RU"}) == {Backend, "ru"}
    end

    test "falls back to the default locale for a language with no catalog" do
      assert Info.language(AshGettextFixture.Shipping, %{language: "de"}) == {Backend, "en"}
    end

    test "has no answer without an actor" do
      assert Info.language(AshGettextFixture.Shipping, nil) == nil
    end

    test "has no answer when the resolver declines" do
      assert Info.language(AshGettextFixture.Shipping, %{}) == nil
    end
  end

  describe "reading the settings of a domain that does not translate" do
    test "reports :error for a domain without the extension" do
      assert Info.settings(AshGettextFixture.Untranslated) == :error
    end

    test "reports :error for a domain that switched translation off" do
      assert Info.settings(AshGettextFixture.SwitchedOff) == :error
    end
  end
end
