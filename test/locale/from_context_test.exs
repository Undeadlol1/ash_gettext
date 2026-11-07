defmodule AshGettext.Locale.FromContextTest do
  use ExUnit.Case, async: true

  alias AshGettext.Locale.FromContext

  describe "reading the locale from the action context" do
    test "reads an atom-keyed locale" do
      assert FromContext.resolve(%{locale: "ru"}) == "ru"
    end

    test "reads a string-keyed locale, as it arrives after a JSON round-trip" do
      assert FromContext.resolve(%{"locale" => "ru"}) == "ru"
    end

    test "declines when the context carries no locale" do
      assert FromContext.resolve(%{actor: :someone}) == nil
    end

    test "declines when the locale is not a string" do
      assert FromContext.resolve(%{locale: :ru}) == nil
    end

    test "declines on an empty context" do
      assert FromContext.resolve(%{}) == nil
    end
  end
end
