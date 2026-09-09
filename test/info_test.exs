defmodule AshGettext.InfoTest do
  use ExUnit.Case, async: true

  alias AshGettext.Info
  alias AshGettext.Locale.Context
  alias AshGettextFixture.Gettext, as: Backend

  describe "settings/1 for a translating domain" do
    test "reports the declared backend and text domain" do
      assert {:ok, settings} = Info.settings(AshGettextFixture.Shipping)
      assert settings.backend == Backend
      assert settings.text_domain == "fixture"
    end

    test "reports the declared default locale and resolvers" do
      assert {:ok, settings} = Info.settings(AshGettextFixture.Shipping)
      assert settings.default_locale == "en"
      assert settings.locale_resolvers == [Context]
    end

    test "derives supported locales from the backend rather than a declared list" do
      assert {:ok, settings} = Info.settings(AshGettextFixture.Shipping)
      assert Enum.sort(settings.supported_locales) == ["en", "ru"]
    end

    test "applies the defaults a domain does not state" do
      assert {:ok, settings} = Info.settings(AshGettextFixture.Opinionated)
      assert settings.default_locale == "en"
      assert settings.locale_resolvers == [Context]
    end
  end

  describe "settings/1 for a domain that does not translate" do
    test "reports :error for a domain without the extension" do
      assert Info.settings(AshGettextFixture.Untranslated) == :error
    end

    test "reports :error for a domain that switched translation off" do
      assert Info.settings(AshGettextFixture.SwitchedOff) == :error
    end
  end
end
