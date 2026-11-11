defmodule AshGettext.MissingCallbackTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  defmodule Backend do
    use Gettext.Backend, otp_app: :ash_gettext, priv: "priv/test_gettext"

    def handle_missing_translation(locale, domain, msgctxt, msgid, bindings) do
      send(self(), {:missing_callback, domain, msgid})
      super(locale, domain, msgctxt, msgid, bindings)
    end

    def handle_missing_plural_translation(locale, domain, msgctxt, msgid, plural, n, bindings) do
      send(self(), {:missing_callback, domain, msgid})
      super(locale, domain, msgctxt, msgid, plural, n, bindings)
    end
  end

  defp missing_callbacks do
    receive do
      {:missing_callback, domain, msgid} -> [{domain, msgid} | missing_callbacks()]
    after
      0 -> []
    end
  end

  describe "a hit never calls the backend's missing callbacks" do
    test "in the app catalog" do
      assert {:ok, "Привет"} =
               AshGettext.translate_or_missing(Backend, "fixture", "greeting", [], "ru")

      assert missing_callbacks() == []
    end

    test "in the built-in catalog" do
      assert {:ok, "обязательное поле"} =
               AshGettext.translate_or_missing(Backend, "ash_builtin", "is required", [], "ru")

      assert missing_callbacks() == []
    end

    test "with a binding the catalog entry needs left out" do
      assert {:ok, "Добавлено 25г белка, %{calories} калорий"} =
               AshGettext.translate_or_missing(
                 Backend,
                 "fixture",
                 "intake_added",
                 [protein: 25],
                 "ru"
               )

      assert missing_callbacks() == []
    end

    test "for a plural in a translated locale" do
      assert {:ok, "5 яблок"} =
               AshGettext.translate_plural_or_missing(
                 Backend,
                 "plurals",
                 "%{count} apple",
                 "%{count} apples",
                 5,
                 [],
                 "ru"
               )

      assert missing_callbacks() == []
    end

    test "for a plural in the source locale" do
      assert {:ok, "5 albums"} =
               AshGettext.translate_plural_or_missing(
                 Backend,
                 "fixture",
                 "album",
                 "albums",
                 5,
                 [],
                 "en"
               )

      assert missing_callbacks() == []
    end
  end

  describe "a miss calls the backend's missing callback once" do
    test "for a msgid the catalog lacks" do
      assert {:missing, "translated_in_english_only"} =
               AshGettext.translate_or_missing(
                 Backend,
                 "fixture",
                 "translated_in_english_only",
                 [],
                 "ru"
               )

      assert missing_callbacks() == [{"fixture", "translated_in_english_only"}]
    end

    test "for a msgid the catalog lacks with a binding left out" do
      assert {:missing, "Hello, %{name}"} =
               AshGettext.translate_or_missing(Backend, "fixture", "Hello, %{name}", [], "ru")

      assert missing_callbacks() == [{"fixture", "Hello, %{name}"}]
    end

    test "for a locale with no catalog" do
      assert {:missing, "greeting"} =
               AshGettext.translate_or_missing(Backend, "fixture", "greeting", [], "de")

      assert missing_callbacks() == [{"fixture", "greeting"}]
    end

    test "for a plural the catalog lacks" do
      assert {:missing, "2 files"} =
               AshGettext.translate_plural_or_missing(
                 Backend,
                 "fixture",
                 "%{count} file",
                 "%{count} files",
                 2,
                 [],
                 "ru"
               )

      assert missing_callbacks() == [{"fixture", "%{count} file"}]
    end
  end

  describe "an error text found in the built-in catalog" do
    test "calls the missing callback only for the app catalog it skipped" do
      assert {:ok, "обязательное поле"} =
               AshGettext.translate_error_text(
                 Backend,
                 ["fixture", "ash_builtin"],
                 "is required",
                 [],
                 "ru"
               )

      assert missing_callbacks() == [{"fixture", "is required"}]
    end

    test "found in the app catalog calls no missing callback" do
      assert {:ok, "Привет"} =
               AshGettext.translate_error_text(
                 Backend,
                 ["fixture", "ash_builtin"],
                 "greeting",
                 [],
                 "ru"
               )

      assert missing_callbacks() == []
    end
  end
end
