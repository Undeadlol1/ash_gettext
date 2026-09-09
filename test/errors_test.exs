defmodule AshGettext.ErrorsTest do
  use ExUnit.Case, async: true

  alias Ash.Error.Changes.InvalidAttribute
  alias AshGettext.Errors
  alias AshGettextFixture.Gettext, as: Backend

  @opts [backend: Backend, text_domain: "fixture", locale: "ru"]

  defp weight_error(opts \\ []) do
    InvalidAttribute.exception(
      Keyword.merge([field: :weight, message: "weight_too_low", vars: [min: 30]], opts)
    )
  end

  describe "translate/2" do
    test "renders a covered message in the requested locale" do
      assert %{message: "Вес должен быть не менее 30 кг"} =
               Errors.translate(weight_error(), @opts)
    end

    test "interpolates the error's vars into the translation" do
      assert %{message: "Вес должен быть не менее 45 кг"} =
               Errors.translate(weight_error(vars: [min: 45]), @opts)
    end

    test "renders the same error differently per locale" do
      assert %{message: "Weight must be at least 30 kg"} =
               Errors.translate(weight_error(), Keyword.put(@opts, :locale, "en"))
    end

    test "leaves a message no catalog covers exactly as it was" do
      error = InvalidAttribute.exception(field: :label, message: "this label is not allowed")

      assert %{message: "this label is not allowed"} = Errors.translate(error, @opts)
    end

    test "keeps every other field on the error untouched" do
      translated = Errors.translate(weight_error(), @opts)

      assert translated.field == :weight
      assert translated.class == :invalid
    end

    test "translates each error in a list" do
      assert [%{message: "Вес должен быть не менее 30 кг"}, %{message: "Этот заказ уже размещён"}] =
               Errors.translate(
                 [weight_error(), InvalidAttribute.exception(message: "order_already_placed")],
                 @opts
               )
    end

    test "translates errors nested inside a class error" do
      invalid = Ash.Error.to_error_class([weight_error()])

      assert %{errors: [%{message: "Вес должен быть не менее 30 кг"}]} =
               Errors.translate(invalid, @opts)
    end

    test "passes through an error carrying no message" do
      error = InvalidAttribute.exception(field: :weight)

      assert Errors.translate(error, @opts) == error
    end

    test "passes through a value that is not an error at all" do
      assert Errors.translate(:some_atom, @opts) == :some_atom
    end
  end
end
