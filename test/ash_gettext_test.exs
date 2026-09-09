defmodule AshGettextTest do
  use ExUnit.Case, async: true

  alias AshGettextFixture.Gettext, as: Backend

  @text_domain "fixture"

  describe "translate/5" do
    test "renders a msgid in the requested locale" do
      assert AshGettext.translate(Backend, @text_domain, "greeting", [], "en") == "Hello"
      assert AshGettext.translate(Backend, @text_domain, "greeting", [], "ru") == "Привет"
    end

    test "interpolates bindings given as a keyword list" do
      assert AshGettext.translate(
               Backend,
               @text_domain,
               "intake_added",
               [protein: 25, calories: 150],
               "ru"
             ) == "Добавлено 25г белка, 150 калорий"
    end

    test "interpolates bindings given as a map" do
      assert AshGettext.translate(
               Backend,
               @text_domain,
               "intake_added",
               %{protein: 30, calories: 200},
               "en"
             ) == "Added 30g protein, 200 calories"
    end

    test "accepts an atom msgid" do
      assert AshGettext.translate(Backend, @text_domain, :greeting, [], "ru") == "Привет"
    end

    test "falls back to the msgid when the catalog has no translation" do
      assert AshGettext.translate(Backend, @text_domain, "translated_in_english_only", [], "ru") ==
               "translated_in_english_only"
    end

    test "leaves each locale's rendering independent of the call before it" do
      assert AshGettext.translate(Backend, @text_domain, "greeting", [], "ru") == "Привет"
      assert AshGettext.translate(Backend, @text_domain, "greeting", [], "en") == "Hello"
    end
  end

  describe "fetch/5" do
    test "reports a covered msgid as :ok" do
      assert {:ok, "Привет"} = AshGettext.fetch(Backend, @text_domain, "greeting", [], "ru")
    end

    test "reports an uncovered msgid as :missing so a test can assert coverage" do
      assert {:missing, "translated_in_english_only"} =
               AshGettext.fetch(Backend, @text_domain, "translated_in_english_only", [], "ru")
    end

    test "reports an unknown text domain as :missing" do
      assert {:missing, "greeting"} =
               AshGettext.fetch(Backend, "no_such_domain", "greeting", [], "en")
    end
  end

  describe "translate_plural/7" do
    test "picks the singular and plural forms for the count" do
      assert AshGettext.translate_plural(Backend, @text_domain, "album", "albums", 1, [], "en") ==
               "1 album"

      assert AshGettext.translate_plural(Backend, @text_domain, "album", "albums", 5, [], "en") ==
               "5 albums"
    end

    test "exposes count as a binding without the caller passing it" do
      assert AshGettext.translate_plural(Backend, @text_domain, "album", "albums", 3, [], "en") =~
               "3"
    end

    test "falls back to a msgid when the catalog has no plural forms for the locale" do
      assert AshGettext.translate_plural(Backend, @text_domain, "album", "albums", 5, [], "ru") in [
               "album",
               "albums"
             ]
    end
  end

  describe "fetch_plural/7" do
    test "reports a covered plural form as :ok" do
      assert {:ok, "5 albums"} =
               AshGettext.fetch_plural(Backend, @text_domain, "album", "albums", 5, [], "en")
    end

    test "reports a locale whose catalog has no plural forms as :missing" do
      assert {:missing, _fallback} =
               AshGettext.fetch_plural(Backend, @text_domain, "album", "albums", 5, [], "ru")
    end

    test "keeps the count argument authoritative over a conflicting count binding" do
      assert {:ok, "5 albums"} =
               AshGettext.fetch_plural(
                 Backend,
                 @text_domain,
                 "album",
                 "albums",
                 5,
                 [count: 12],
                 "en"
               )
    end
  end

  describe "enum_label/5" do
    test "renders the label a catalog gives an enum value, per locale" do
      assert AshGettext.enum_label(Backend, @text_domain, :status, :placed, "en") == "Placed"
      assert AshGettext.enum_label(Backend, @text_domain, :status, :placed, "ru") == "Размещён"
    end

    test "accepts the value as a string, as it arrives from a payload" do
      assert AshGettext.enum_label(Backend, @text_domain, :status, "placed", "ru") == "Размещён"
    end

    test "accepts the attribute as a string too" do
      assert AshGettext.enum_label(Backend, @text_domain, "status", :placed, "ru") == "Размещён"
    end

    test "renders a multi-word value from the catalog" do
      assert AshGettext.enum_label(Backend, @text_domain, :status, :awaiting_pickup, "en") ==
               "Awaiting pickup"
    end

    test "humanizes an uncovered value rather than putting the msgid on screen" do
      assert AshGettext.enum_label(Backend, @text_domain, :status, :awaiting_refund, "ru") ==
               "Awaiting refund"
    end

    test "humanizes an uncovered value of an attribute no catalog mentions at all" do
      assert AshGettext.enum_label(Backend, @text_domain, :shipping_speed, :next_day, "en") ==
               "Next day"
    end
  end

  describe "fetch_enum_label/5" do
    test "reports a covered value as :ok" do
      assert {:ok, "Размещён"} =
               AshGettext.fetch_enum_label(Backend, @text_domain, :status, :placed, "ru")
    end

    test "reports an uncovered value as :missing, with the humanized fallback" do
      assert {:missing, "Awaiting refund"} =
               AshGettext.fetch_enum_label(Backend, @text_domain, :status, :awaiting_refund, "ru")
    end
  end

  describe "enum_msgid/2" do
    test "is the convention a catalog author has to know" do
      assert AshGettext.enum_msgid(:status, :placed) == "status.placed"
      assert AshGettext.enum_msgid("status", "awaiting_pickup") == "status.awaiting_pickup"
    end
  end

  describe "known_locales/1" do
    test "derives the supported locales from the backend's catalogs" do
      assert Enum.sort(AshGettext.known_locales(Backend)) == ["en", "ru"]
    end
  end
end
