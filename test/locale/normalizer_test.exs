defmodule AshGettext.Locale.NormalizerTest do
  use ExUnit.Case, async: true

  alias AshGettext.Locale.Normalizer

  doctest Normalizer

  @supported ["en", "ru"]

  describe "matching a locale to one the backend knows" do
    test "keeps a locale the catalogs cover" do
      assert Normalizer.normalize("ru", @supported, "en") == "ru"
    end

    test "strips an underscore region" do
      assert Normalizer.normalize("ru_RU", @supported, "en") == "ru"
    end

    test "strips a hyphen region" do
      assert Normalizer.normalize("en-US", @supported, "en") == "en"
    end

    test "falls back for a language with no catalog" do
      assert Normalizer.normalize("de_DE", @supported, "en") == "en"
    end

    test "keeps a region catalog the backend ships, with either separator" do
      supported = ["en", "pt", "pt_BR"]

      assert Normalizer.normalize("pt_BR", supported, "en") == "pt_BR"
      assert Normalizer.normalize("pt-BR", supported, "en") == "pt_BR"
      assert Normalizer.normalize("pt_PT", supported, "en") == "pt"
    end

    test "tries the script catalog, then the language" do
      supported = ["en", "pt", "pt_BR", "zh", "zh_Hant"]

      assert Normalizer.normalize("zh-Hant-TW", supported, "en") == "zh_Hant"
      assert Normalizer.normalize("zh-Hans-CN", supported, "en") == "zh"
    end

    test "ignores case and returns the spelling from the supported list" do
      supported = ["en", "pt", "pt_BR"]

      assert Normalizer.normalize("PT-br", supported, "en") == "pt_BR"
      assert Normalizer.normalize("EN", supported, "en") == "en"
    end

    test "drops an encoding or modifier suffix" do
      supported = ["en", "pt", "pt_BR"]

      assert Normalizer.normalize("pt_BR.UTF-8", supported, "en") == "pt_BR"
      assert Normalizer.normalize("pt@euro", supported, "en") == "pt"
    end

    test "falls back for nil" do
      assert Normalizer.normalize(nil, @supported, "en") == "en"
    end

    test "falls back for an empty string" do
      assert Normalizer.normalize("", @supported, "en") == "en"
    end
  end

  describe "taking the language out of a locale" do
    test "returns the language when there is no region" do
      assert Normalizer.language_code("ru") == "ru"
    end

    test "drops everything after the first separator" do
      assert Normalizer.language_code("zh_Hans_CN") == "zh"
    end
  end
end
