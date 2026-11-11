defmodule AshGettext.TransportTextTest do
  @moduledoc """
  Some error text is written by the transport, not by Ash: JSON:API and
  GraphQL each write "is required" themselves. These rules translate such a
  text and belong to no transport, so every adapter gives the same answer.
  """

  use ExUnit.Case, async: true

  alias AshGettext.TransportText
  alias AshGettextFixture.Gettext, as: Backend
  alias AshGettextFixture.Shipping

  defp in_russian(fun), do: Gettext.with_locale(Backend, "ru", fun)

  test "a text the catalog knows comes back translated" do
    assert in_russian(fn -> TransportText.translate("is required", Shipping) end) ==
             "обязательное поле"
  end

  test "a text with values gets them filled in" do
    assert in_russian(fn ->
             TransportText.translate("weight_too_low", Shipping, bindings: [min: 30])
           end) == "Вес должен быть не менее 30 кг"
  end

  test "a text the catalog does not know falls back to the sentence for its code" do
    assert in_russian(fn ->
             TransportText.translate("No note record found with `id: 1`", Shipping,
               code: "not_found"
             )
           end) == "не найдено"
  end

  test "a text and a code nobody knows come back as written" do
    assert in_russian(fn ->
             TransportText.translate("a sentence a later Ash added", Shipping, code: "brand_new")
           end) == "a sentence a later Ash added"
  end

  test "the source language keeps the transport's own text, whatever the code" do
    assert TransportText.translate("No note record found with `id: 1`", Shipping,
             code: "not_found"
           ) == "No note record found with `id: 1`"
  end

  test "a translation the error already carries wins over everything" do
    assert TransportText.translate("is required", Shipping,
             bindings: [translation: "обязательное поле"]
           ) == "обязательное поле"
  end

  test "a carried translation is used even by a domain's adapter with no language set" do
    assert TransportText.translate("is required", Shipping,
             bindings: %{translation: "обязательное поле"},
             code: "required"
           ) == "обязательное поле"
  end

  test "an actor's language wins over Gettext's current one" do
    assert TransportText.translate("is required", Shipping, actor: %{language: "ru"}) ==
             "обязательное поле"
  end

  test "an actor the resolver has no answer for gets Gettext's current language" do
    assert in_russian(fn -> TransportText.translate("is required", Shipping, actor: %{}) end) ==
             "обязательное поле"
  end

  test "a domain that does not translate gives the text back" do
    for domain <- [AshGettextFixture.Untranslated, AshGettextFixture.SwitchedOff, nil] do
      assert in_russian(fn -> TransportText.translate("is required", domain) end) ==
               "is required"
    end
  end

  test "anything that is not text comes back as it was" do
    assert TransportText.translate(nil, Shipping) == nil
  end
end
