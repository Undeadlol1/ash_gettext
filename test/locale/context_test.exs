defmodule AshGettext.Locale.ContextTest do
  use ExUnit.Case, async: true

  alias AshGettext.Locale.Context

  describe "resolve/1" do
    test "reads an atom-keyed locale" do
      assert Context.resolve(%{locale: "ru"}) == "ru"
    end

    test "reads a string-keyed locale, as it arrives after a JSON round-trip" do
      assert Context.resolve(%{"locale" => "ru"}) == "ru"
    end

    test "declines when the context carries no locale" do
      assert Context.resolve(%{actor: :someone}) == nil
    end

    test "declines when the locale is not a string" do
      assert Context.resolve(%{locale: :ru}) == nil
    end

    test "declines on an empty context" do
      assert Context.resolve(%{}) == nil
    end
  end
end
