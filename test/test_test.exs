defmodule AshGettext.TestTest do
  use ExUnit.Case, async: true

  import AshGettext.Test

  alias AshGettextFixture.Gettext, as: Backend

  @text_domain "fixture"

  describe "assert_translates/6" do
    test "passes and returns the string when the rendering matches" do
      assert assert_translates(Backend, @text_domain, "greeting", "ru", "Привет") == "Привет"
    end

    test "passes with bindings interpolated" do
      assert_translates(
        Backend,
        @text_domain,
        "intake_added",
        "en",
        "Added 25g protein, 150 calories",
        protein: 25,
        calories: 150
      )
    end

    test "fails with both strings in the message when the rendering differs" do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_translates(Backend, @text_domain, "greeting", "ru", "Hello")
        end

      assert error.message =~ "Привет"
      assert error.message =~ "Hello"
    end
  end

  describe "assert_covered/5" do
    test "passes for a msgid the locale's catalog covers" do
      assert assert_covered(Backend, @text_domain, "greeting", "ru") == "Привет"
    end

    test "fails for a msgid the locale's catalog misses" do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_covered(Backend, @text_domain, "translated_in_english_only", "ru")
        end

      assert error.message =~ "no translation"
    end
  end
end
