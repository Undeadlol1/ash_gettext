defmodule AshGettext.Locale.NormalizerTest do
  use ExUnit.Case, async: true

  alias AshGettext.Locale.Normalizer

  doctest Normalizer

  @supported ["en", "ru"]

  describe "normalize/3" do
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

    test "falls back for nil" do
      assert Normalizer.normalize(nil, @supported, "en") == "en"
    end

    test "falls back for an empty string" do
      assert Normalizer.normalize("", @supported, "en") == "en"
    end
  end

  describe "language_subtag/1" do
    test "returns the language when there is no region" do
      assert Normalizer.language_subtag("ru") == "ru"
    end

    test "drops everything after the first separator" do
      assert Normalizer.language_subtag("zh_Hans_CN") == "zh"
    end
  end
end
