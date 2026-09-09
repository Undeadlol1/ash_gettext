defmodule AshGettext.LocaleTest do
  use ExUnit.Case, async: true

  alias AshGettext.Locale
  alias AshGettext.Locale.Resolver

  defmodule AlwaysRussian do
    @moduledoc false
    @behaviour Resolver

    @impl true
    def resolve(_context), do: "ru"
  end

  defmodule NoOpinion do
    @moduledoc false
    @behaviour Resolver

    @impl true
    def resolve(_context), do: nil
  end

  @supported ["en", "ru"]

  describe "resolve/2" do
    test "reads a locale placed on the context" do
      assert Locale.resolve(%{locale: "ru"}, default: "en", supported: @supported) == "ru"
    end

    test "normalises a regional locale down to the catalog's language" do
      assert Locale.resolve(%{locale: "ru_RU"}, default: "en", supported: @supported) == "ru"
    end

    test "falls back to the default when nothing has an opinion" do
      assert Locale.resolve(%{}, default: "en", supported: @supported) == "en"
    end

    test "falls back to the default for a locale with no catalog" do
      assert Locale.resolve(%{locale: "de"}, default: "en", supported: @supported) == "en"
    end

    test "takes the first resolver with an opinion" do
      assert Locale.resolve(%{},
               resolvers: [NoOpinion, AlwaysRussian],
               default: "en",
               supported: @supported
             ) == "ru"
    end

    test "skips past resolvers that decline" do
      assert Locale.resolve(%{},
               resolvers: [NoOpinion, NoOpinion],
               default: "en",
               supported: @supported
             ) == "en"
    end

    test "uses the context resolver when none is named" do
      assert Locale.resolve(%{locale: "ru"}, default: "en", supported: @supported) == "ru"
    end

    test "treats the default as the only supported locale when none are given" do
      assert Locale.resolve(%{locale: "ru"}, default: "en") == "en"
    end
  end
end
