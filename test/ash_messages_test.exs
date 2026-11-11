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

    test "stays Ash's own Required error", %{error: error} do
      assert %Ash.Error.Changes.Required{field: :delivery_date, type: :attribute} = error
      assert Exception.message(error) =~ "attribute delivery_date is required"
    end

    test "carries the Russian sentence next to its own values", %{error: error} do
      assert error.vars[:translation] == "обязательное поле"
    end

    test "hands the Russian sentence to JSON:API in meta", %{error: error} do
      assert %{meta: %{translation: "обязательное поле"}, code: "required"} =
               AshJsonApi.ToJsonApiError.to_json_api_error(error)
    end

    test "hands the Russian sentence to an AshPhoenix form with the error", %{error: error} do
      assert {:delivery_date, "is required", values} =
               AshPhoenix.FormData.Error.to_form_error(error)

      assert values[:translation] == "обязательное поле"
    end
  end

  describe "a required attribute left out by a reader in the source language" do
    test "carries the sentence as it was written" do
      error = error_for(Ash.create(Delivery, %{}, actor: %{language: "en"}), :delivery_date)

      assert error.vars[:translation] == "is required"
    end
  end

  describe "a value that does not cast" do
    setup do
      result =
        Ash.create(Delivery, %{delivery_date: ~D[2026-01-01], count: "abc"}, actor: @russian)

      %{error: error_for(result, :count)}
    end

    test "stays Ash's own InvalidAttribute, its message the Russian sentence", %{error: error} do
      assert %Ash.Error.Changes.InvalidAttribute{field: :count, message: "неверное значение"} =
               error
    end

    test "renders the Russian sentence as the JSON:API detail", %{error: error} do
      [rendered] = AshJsonApi.Error.to_json_api_errors(nil, Delivery, error, :create)

      assert rendered.detail == "неверное значение"
    end

    test "shows the Russian sentence as the Phoenix form error", %{error: error} do
      assert {:count, "неверное значение", _vars} = AshPhoenix.FormData.Error.to_form_error(error)
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

      assert "is invalid" in msgids
      assert msgids == Enum.uniq(msgids)
    end

    test "an invalid argument stays Ash's own error, its message the Russian sentence" do
      error = Ash.Error.Changes.InvalidArgument.exception(field: :count)

      assert %Ash.Error.Changes.InvalidArgument{field: :count, message: "неверное значение"} =
               translate(error)
    end

    test "a failed policy stays Ash's own Policy error and prints the Russian sentence" do
      translated = translate(Ash.Error.Forbidden.Policy.exception([]))

      assert %Ash.Error.Forbidden.Policy{custom_message: "Вам нельзя это делать"} = translated
      assert Exception.message(translated) == "Вам нельзя это делать"
    end

    test "a policy's own message is its msgid" do
      error = Ash.Error.Forbidden.Policy.exception(custom_message: "order_already_placed")

      assert %Ash.Error.Forbidden.Policy{custom_message: "Этот заказ уже размещён"} =
               translate(error)
    end

    test "an error Ash gives no listed sentence passes through untouched" do
      error = Ash.Error.Changes.StaleRecord.exception(resource: Delivery)

      assert translate(error) == error
    end

    test "a required error changes in nothing but the sentence it carries" do
      error = Ash.Error.Changes.Required.exception(field: :delivery_date, type: :attribute)

      assert translate(error) == %{error | vars: [translation: "обязательное поле"]}
    end

    test "a required error keeps the values the app gave it" do
      error = Ash.Error.Changes.Required.exception(field: :delivery_date, vars: [row: 7])

      assert Enum.sort(translate(error).vars) == [row: 7, translation: "обязательное поле"]
    end

    test "translating a required error twice changes nothing more" do
      error = Ash.Error.Changes.Required.exception(field: :delivery_date)

      assert translate(translate(error)) == translate(error)
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
