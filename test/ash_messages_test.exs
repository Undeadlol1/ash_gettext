defmodule AshGettext.AshMessagesTest do
  @moduledoc """
  Ash's own errors carry no message of their own: their text is built from the
  field's code name ("attribute delivery_date is required"). These run real
  actions and check that a Russian reader gets the written sentence instead.
  """

  use ExUnit.Case, async: true

  alias AshGettextFixture.Delivery

  @russian %{language: "ru"}

  defp error_for(result, field) do
    {:error, %{errors: errors}} = result
    Enum.find(errors, &(Map.get(&1, :field) == field))
  end

  describe "a required attribute left out" do
    setup do
      %{error: error_for(Ash.create(Delivery, %{}, actor: @russian), :delivery_date)}
    end

    test "reads as the Russian sentence", %{error: error} do
      assert error.message == "обязательное поле"
    end

    test "prints as the Russian sentence, with no code name", %{error: error} do
      assert Exception.message(error) =~ ~r/обязательное поле\z/
      refute Exception.message(error) =~ "delivery_date"
    end

    test "keeps Ash's field, class and the original error", %{error: error} do
      assert error.field == :delivery_date
      assert error.class == :invalid
      assert %Ash.Error.Changes.Required{field: :delivery_date} = error.original
    end

    test "renders the Russian sentence as the JSON:API detail", %{error: error} do
      [rendered] = AshJsonApi.Error.to_json_api_errors(nil, Delivery, error, :create)

      assert %AshJsonApi.Error{code: "required", detail: "обязательное поле", status_code: 400} =
               rendered
    end
  end

  describe "a value that does not cast" do
    setup do
      result =
        Ash.create(Delivery, %{delivery_date: ~D[2026-01-01], count: "abc"}, actor: @russian)

      %{error: error_for(result, :count)}
    end

    test "reads as the Russian sentence", %{error: error} do
      assert error.message == "неверное значение"
    end

    test "renders the Russian sentence as the JSON:API detail", %{error: error} do
      [rendered] = AshJsonApi.Error.to_json_api_errors(nil, Delivery, error, :create)

      assert rendered.detail == "неверное значение"
    end
  end

  describe "an error that brings its own message" do
    test "keeps its own struct and message" do
      result = Ash.create(AshGettextFixture.Parcel, %{label: "reject me"}, actor: @russian)

      assert %Ash.Error.Changes.InvalidAttribute{message: "this label is not allowed"} =
               error_for(result, :label)
    end
  end

  describe "the messages" do
    test "are written sentences, each listed once" do
      msgids = AshGettext.AshMessages.msgids()

      assert "is required" in msgids
      assert msgids == Enum.uniq(msgids)
    end

    test "a failed policy reads as the Russian sentence and stays forbidden" do
      translated = translate(Ash.Error.Forbidden.Policy.exception([]))

      assert %{message: "Вам нельзя это делать", class: :forbidden} = translated
      assert %Ash.Error.Forbidden{} = Ash.Error.to_error_class(translated)
    end

    test "a policy's own message is its msgid" do
      error = Ash.Error.Forbidden.Policy.exception(custom_message: "order_already_placed")

      assert translate(error).message == "Этот заказ уже размещён"
    end

    test "an error Ash gives no listed sentence passes through untouched" do
      error = Ash.Error.Changes.StaleRecord.exception(resource: Delivery)

      assert translate(error) == error
    end
  end

  defp translate(error) do
    AshGettext.ErrorTranslation.translate(error,
      backend: AshGettextFixture.Gettext,
      text_domain: "fixture",
      locale: "ru"
    )
  end
end
