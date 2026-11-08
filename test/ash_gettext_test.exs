defmodule AshGettextTest do
  use ExUnit.Case, async: true

  alias AshGettextFixture.Gettext, as: Backend

  @text_domain "fixture"

  describe "translating one message" do
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

  describe "translating one message and reporting a gap" do
    test "reports a covered msgid as :ok" do
      assert {:ok, "Привет"} =
               AshGettext.translate_or_missing(Backend, @text_domain, "greeting", [], "ru")
    end

    test "reports an uncovered msgid as :missing so a test can assert coverage" do
      assert {:missing, "translated_in_english_only"} =
               AshGettext.translate_or_missing(
                 Backend,
                 @text_domain,
                 "translated_in_english_only",
                 [],
                 "ru"
               )
    end

    test "reports an unknown text domain as :missing" do
      assert {:missing, "greeting"} =
               AshGettext.translate_or_missing(Backend, "no_such_domain", "greeting", [], "ru")
    end

    test "never reports the source locale as :missing, even with no catalog entry" do
      assert {:ok, "That exact msgid"} =
               AshGettext.translate_or_missing(
                 Backend,
                 @text_domain,
                 "That exact msgid",
                 [],
                 "en"
               )

      assert {:ok, "Hello, Ann"} =
               AshGettext.translate_or_missing(
                 Backend,
                 @text_domain,
                 "Hello, %{name}",
                 [name: "Ann"],
                 "en"
               )
    end

    test "still reports a msgid with no entry as :missing in a translated locale" do
      assert {:missing, "That exact msgid"} =
               AshGettext.translate_or_missing(
                 Backend,
                 @text_domain,
                 "That exact msgid",
                 [],
                 "ru"
               )
    end
  end

  describe "translating a message with a count" do
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

  describe "translating a counted message and reporting a gap" do
    test "reports a covered plural form as :ok" do
      assert {:ok, "5 albums"} =
               AshGettext.translate_plural_or_missing(
                 Backend,
                 @text_domain,
                 "album",
                 "albums",
                 5,
                 [],
                 "en"
               )
    end

    test "reports a locale whose catalog has no plural forms as :missing" do
      assert {:missing, _fallback} =
               AshGettext.translate_plural_or_missing(
                 Backend,
                 @text_domain,
                 "album",
                 "albums",
                 5,
                 [],
                 "ru"
               )
    end

    test "never reports the source locale as :missing, even with no catalog entry" do
      assert {:ok, "files"} =
               AshGettext.translate_plural_or_missing(
                 Backend,
                 @text_domain,
                 "file",
                 "files",
                 2,
                 [],
                 "en"
               )

      assert {:ok, "2 files"} =
               AshGettext.translate_plural_or_missing(
                 Backend,
                 @text_domain,
                 "%{count} file",
                 "%{count} files",
                 2,
                 [],
                 "en"
               )
    end

    test "keeps the count argument authoritative over a conflicting count binding" do
      assert {:ok, "5 albums"} =
               AshGettext.translate_plural_or_missing(
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

  describe "labelling an attribute" do
    alias AshGettextFixture.Parcel

    test "translates the sentence-case attribute name in Gettext's current language" do
      assert Gettext.with_locale(Backend, "ru", fn ->
               AshGettext.attribute_label(Parcel, :weight)
             end) ==
               "Вес"

      assert Gettext.with_locale(Backend, "en", fn ->
               AshGettext.attribute_label(Parcel, :weight)
             end) ==
               "Weight"
    end

    test "reports coverage" do
      Gettext.with_locale(Backend, "ru", fn ->
        assert {:ok, "Вес"} = AshGettext.attribute_label_or_missing(Parcel, :weight)
        assert {:missing, "Label"} = AshGettext.attribute_label_or_missing(Parcel, :label)
      end)
    end

    test "raises for an unknown attribute" do
      assert_raise ArgumentError, ~r/no attribute :nope/, fn ->
        AshGettext.attribute_label(Parcel, :nope)
      end
    end

    test "raises for a resource whose domain has no gettext block" do
      assert_raise ArgumentError, ~r/no gettext block/, fn ->
        AshGettext.attribute_label(AshGettextFixture.Untranslated.Parcel, :weight)
      end
    end

    test "attribute_msgid/1 is sentence case" do
      assert AshGettext.attribute_msgid(:date_of_birth) == "Date of birth"
    end
  end

  describe "missing telemetry from label functions" do
    setup do
      id = {__MODULE__, make_ref()}
      test_pid = self()

      :telemetry.attach(
        id,
        [:ash_gettext, :translation, :missing],
        fn _event, _measurements, metadata, _ -> send(test_pid, {:missing, metadata}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(id) end)
    end

    test "attribute_label fires on a miss" do
      Gettext.with_locale(Backend, "ru", fn ->
        AshGettext.attribute_label(AshGettextFixture.Parcel, :label)
      end)

      assert_receive {:missing, %{msgid: "Label", locale: "ru"}}
    end
  end

  describe "listing the locales a backend knows" do
    test "derives the supported locales from the backend's catalogs" do
      assert Enum.sort(AshGettext.known_locales(Backend)) == ["en", "ru"]
    end
  end
end
