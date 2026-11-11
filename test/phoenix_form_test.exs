defmodule AshGettext.PhoenixFormTest do
  @moduledoc """
  A Phoenix app reads errors off an `AshPhoenix.Form`. These build real forms,
  submit them with bad input and read the errors the way a template does.
  """

  use ExUnit.Case, async: true

  alias AshGettextFixture.Delivery
  alias AshGettextFixture.Rules.Entry

  @russian %{language: "ru"}
  @english %{language: "en"}

  defp submitted_create(resource, params, actor) do
    form = AshPhoenix.Form.for_create(resource, :create, actor: actor)
    {:error, form} = AshPhoenix.Form.submit(form, params: params)
    form
  end

  defp submitted_update(record, params, actor) do
    form = AshPhoenix.Form.for_update(record, :update, actor: actor)
    {:error, form} = AshPhoenix.Form.submit(form, params: params)
    form
  end

  defp validated_create(resource, params, actor) do
    resource
    |> AshPhoenix.Form.for_create(:create, actor: actor)
    |> AshPhoenix.Form.validate(params)
  end

  defp stored_entry(attributes) do
    Ash.create!(Entry, Map.merge(%{code: Ash.UUID.generate(), weight: 40}, attributes))
  end

  defp raw_errors(form), do: AshPhoenix.Form.errors(form, format: :raw)

  describe "a required attribute left out" do
    test "gets AshPhoenix's own English sentence as the message, whatever the reader's language" do
      form = submitted_create(Delivery, %{}, @russian)

      assert [delivery_date: "is required"] = AshPhoenix.Form.errors(form)
    end

    test "carries the Russian sentence in the values next to the message" do
      form = submitted_create(Delivery, %{}, @russian)

      assert [delivery_date: {"is required", values}] = raw_errors(form)
      assert values[:translation] == "обязательное поле"
    end

    test "carries the sentence as written for a reader in the source language" do
      form = submitted_create(Delivery, %{}, @english)

      assert [delivery_date: {"is required", values}] = raw_errors(form)
      assert values[:translation] == "is required"
    end

    test "hands a template the same message and values on the Phoenix form field" do
      phoenix_form = Phoenix.HTML.FormData.to_form(submitted_create(Delivery, %{}, @russian), [])

      assert [{"is required", values}] = phoenix_form[:delivery_date].errors
      assert values[:translation] == "обязательное поле"
    end

    test "is the same after validating without submitting" do
      form = validated_create(Delivery, %{"count" => "1"}, @russian)

      assert [delivery_date: {"is required", values}] = raw_errors(form)
      assert values[:translation] == "обязательное поле"
    end
  end

  describe "a value that does not cast" do
    test "shows the Russian sentence as the message" do
      params = %{"delivery_date" => "2026-01-01", "count" => "abc"}

      assert [count: "неверное значение"] =
               AshPhoenix.Form.errors(submitted_create(Delivery, params, @russian))
    end

    test "shows the sentence as written to a reader in the source language" do
      params = %{"delivery_date" => "2026-01-01", "count" => "abc"}

      assert [count: "is invalid"] =
               AshPhoenix.Form.errors(submitted_create(Delivery, params, @english))
    end
  end

  describe "an error with a message and values" do
    test "shows the Russian sentence with the values filled in" do
      params = %{"code" => "c", "quantity" => "1", "slug" => "ok", "weight" => "5"}

      assert [weight: "Вес должен быть не менее 30 кг"] =
               AshPhoenix.Form.errors(submitted_create(Entry, params, @russian))
    end

    test "hands the template the finished sentence and the values it was made from" do
      params = %{"code" => "c", "quantity" => "1", "slug" => "ok", "weight" => "5"}

      assert [weight: {"Вес должен быть не менее 30 кг", [min: 30]}] =
               raw_errors(submitted_create(Entry, params, @russian))
    end
  end

  describe "an update" do
    test "shows the Russian sentence for a rule broken on the stored record" do
      form = submitted_update(stored_entry(%{}), %{"weight" => "5"}, @russian)

      assert [weight: "Вес должен быть не менее 30 кг"] = AshPhoenix.Form.errors(form)
    end

    test "shows the sentence as written to a reader in the source language" do
      form = submitted_update(stored_entry(%{}), %{"weight" => "5"}, @english)

      assert [weight: "Weight must be at least 30 kg"] = AshPhoenix.Form.errors(form)
    end
  end
end
