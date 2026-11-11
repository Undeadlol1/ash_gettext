defmodule AshGettext.ErrorTranslationTest do
  use ExUnit.Case, async: true

  alias Ash.Error.Changes.InvalidAttribute
  alias AshGettext.ErrorTranslation
  alias AshGettextFixture.Gettext, as: Backend

  @opts [backend: Backend, text_domain: "fixture", locale: "ru"]

  defp weight_error(opts \\ []) do
    InvalidAttribute.exception(
      Keyword.merge([field: :weight, message: "weight_too_low", vars: [min: 30]], opts)
    )
  end

  describe "translating an Ash error" do
    test "renders a covered message in the requested locale" do
      assert %{message: "Вес должен быть не менее 30 кг"} =
               ErrorTranslation.translate(weight_error(), @opts)
    end

    test "interpolates the error's vars into the translation" do
      assert %{message: "Вес должен быть не менее 45 кг"} =
               ErrorTranslation.translate(weight_error(vars: [min: 45]), @opts)
    end

    test "renders the same error differently per locale" do
      assert %{message: "Weight must be at least 30 kg"} =
               ErrorTranslation.translate(weight_error(), Keyword.put(@opts, :locale, "en"))
    end

    test "leaves a message no catalog covers exactly as it was" do
      error = InvalidAttribute.exception(field: :label, message: "this label is not allowed")

      assert %{message: "this label is not allowed"} = ErrorTranslation.translate(error, @opts)
    end

    test "keeps every other field on the error untouched" do
      translated = ErrorTranslation.translate(weight_error(), @opts)

      assert translated.field == :weight
      assert translated.class == :invalid
    end

    test "translates each error in a list" do
      assert [%{message: "Вес должен быть не менее 30 кг"}, %{message: "Этот заказ уже размещён"}] =
               ErrorTranslation.translate(
                 [weight_error(), InvalidAttribute.exception(message: "order_already_placed")],
                 @opts
               )
    end

    test "translates errors nested inside a class error" do
      invalid = Ash.Error.to_error_class([weight_error()])

      assert %{errors: [%{message: "Вес должен быть не менее 30 кг"}]} =
               ErrorTranslation.translate(invalid, @opts)
    end

    test "passes through an error carrying no message that no sentence is written for" do
      error = Ash.Error.Changes.StaleRecord.exception(resource: AshGettextFixture.Parcel)

      assert ErrorTranslation.translate(error, @opts) == error
    end

    test "passes through a value that is not an error at all" do
      assert ErrorTranslation.translate(:some_atom, @opts) == :some_atom
    end
  end

  describe "a message with a value already written into it" do
    defp baked(message, vars),
      do: Ash.Error.Changes.InvalidAttribute.exception(field: :slug, message: message, vars: vars)

    defp in_russian(error),
      do:
        AshGettext.ErrorTranslation.translate(error,
          backend: AshGettextFixture.Gettext,
          text_domain: "fixture",
          locale: "ru"
        )

    test "is found by the sentence with the value's name in its place" do
      error = baked("must match ~r/^[a-z]+$/", match: ~r/^[a-z]+$/)

      assert in_russian(error).message == "должно соответствовать ~r/^[a-z]+$/"
    end

    test "stays as written when no sentence fits" do
      error = baked("nothing like 7 is listed", count: 7)

      assert in_russian(error).message == "nothing like 7 is listed"
    end
  end

  describe "the app's catalog and the built-in one" do
    setup do
      id = {__MODULE__, make_ref()}
      test_pid = self()

      :telemetry.attach(
        id,
        [:ash_gettext, :translation, :missing],
        fn _event, _measurements, metadata, _ ->
          if self() == test_pid, do: send(test_pid, {:missing, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(id) end)
    end

    test "a sentence Ash ships is read from the built-in catalog" do
      error = InvalidAttribute.exception(field: :code, message: "must be present")

      assert ErrorTranslation.translate(error, @opts).message == "должно быть заполнено"
    end

    test "a sentence for an error with no message is read from the built-in catalog" do
      error = Ash.Error.Query.NotFound.exception(resource: AshGettextFixture.Parcel)

      assert ErrorTranslation.translate(error, @opts).vars[:translation] == "не найдено"
    end

    test "an app's own text is read from the app's catalog" do
      assert ErrorTranslation.translate(weight_error(), @opts).message ==
               "Вес должен быть не менее 30 кг"
    end

    test "the app's catalog wins when both have the text" do
      error =
        InvalidAttribute.exception(
          field: :size,
          message: "must be less than %{less_than}",
          vars: [less_than: 5]
        )

      assert ErrorTranslation.translate(error, @opts).message == "должно быть строго меньше 5"
    end

    test "a sentence neither catalog has stays English and is reported once" do
      error = Ash.Error.Query.NotFound.exception(resource: AshGettextFixture.Parcel)
      opts = Keyword.merge(@opts, text_domain: "absent", builtin_text_domain: "also_absent")

      assert ErrorTranslation.translate(error, opts).vars[:translation] == "could not be found"
      assert_received {:missing, %{text_domain: "absent", msgid: "could not be found"}}
      refute_received {:missing, _metadata}
    end

    test "a sentence found in the built-in catalog is not reported missing" do
      error = Ash.Error.Query.NotFound.exception(resource: AshGettextFixture.Parcel)

      ErrorTranslation.translate(error, @opts)

      refute_received {:missing, _metadata}
    end
  end
end
