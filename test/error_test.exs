defmodule AshGettext.ErrorTest do
  use ExUnit.Case, async: true

  alias AshGettext.Error
  alias AshGettext.ErrorTranslation
  alias AshGettextFixture.Gettext, as: Backend

  defp weight_error(opts \\ []) do
    Error.exception(
      Keyword.merge([code: :weight_too_low, message: "weight_too_low", vars: [min: 30]], opts)
    )
  end

  describe "building a coded error" do
    test "raises when no code is given" do
      assert_raise ArgumentError, ~r/code/, fn -> Error.exception(message: "weight_too_low") end
    end

    test "is an :invalid error" do
      assert weight_error().class == :invalid
    end

    test "reading the message gives it untranslated" do
      assert Exception.message(weight_error()) == "weight_too_low"
    end
  end

  describe "translating a coded error" do
    test "translates the message and keeps the code" do
      translated =
        ErrorTranslation.translate(weight_error(),
          backend: Backend,
          text_domain: "fixture",
          locale: "ru"
        )

      assert %{message: "Вес должен быть не менее 30 кг", code: :weight_too_low} = translated
    end
  end

  describe "rendering as a JSON:API error" do
    test "renders code, detail, meta and status" do
      rendered = AshJsonApi.ToJsonApiError.to_json_api_error(weight_error(field: :weight))

      assert %AshJsonApi.Error{
               code: "weight_too_low",
               detail: "weight_too_low",
               meta: %{min: 30},
               status_code: 400,
               source_pointer: "/data/attributes/weight"
             } = rendered
    end

    test "has no source pointer without a field" do
      rendered = AshJsonApi.ToJsonApiError.to_json_api_error(weight_error())

      assert rendered.source_pointer == nil
    end
  end
end
