defmodule AshGettext.Errors.HandlerTest do
  @moduledoc """
  End-to-end proof that running a real Ash action returns translated errors.

  These go through `Ash.create/2` rather than calling the handler directly,
  because the thing worth guaranteeing is not "the handler works" — it is "a user
  who set their language to Russian reads Russian."
  """

  use ExUnit.Case, async: true

  alias Ash.Error.Changes.InvalidAttribute
  alias AshGettext.Errors.Handler
  alias AshGettextFixture.Parcel
  alias AshGettextFixture.Untranslated

  defp message_of({:error, %{errors: errors}}), do: hd(errors).message

  describe "a write action on a translating domain" do
    test "returns the error in the locale on the action context" do
      result = Ash.create(Parcel, %{weight: 5}, context: %{locale: "ru"})

      assert message_of(result) == "Вес должен быть не менее 30 кг"
    end

    test "returns the error in English when English is asked for" do
      result = Ash.create(Parcel, %{weight: 5}, context: %{locale: "en"})

      assert message_of(result) == "Weight must be at least 30 kg"
    end

    test "falls back to the domain's default locale when none is given" do
      result = Ash.create(Parcel, %{weight: 5})

      assert message_of(result) == "Weight must be at least 30 kg"
    end

    test "falls back to the default for a locale the catalogs do not cover" do
      result = Ash.create(Parcel, %{weight: 5}, context: %{locale: "de"})

      assert message_of(result) == "Weight must be at least 30 kg"
    end

    test "normalises a regional locale to the catalog's language" do
      result = Ash.create(Parcel, %{weight: 5}, context: %{locale: "ru_RU"})

      assert message_of(result) == "Вес должен быть не менее 30 кг"
    end

    test "leaves a message no catalog covers unchanged" do
      result = Ash.create(Parcel, %{label: "reject me"}, context: %{locale: "ru"})

      assert message_of(result) == "this label is not allowed"
    end

    test "translates errors from update actions too, not only creates" do
      {:ok, parcel} = Ash.create(Parcel, %{weight: 100, label: "fine"})

      result = Ash.update(parcel, %{label: "reject me"}, context: %{locale: "ru"})

      assert message_of(result) == "this label is not allowed"
    end

    test "leaves a successful action completely alone" do
      assert {:ok, %Parcel{weight: 100}} = Ash.create(Parcel, %{weight: 100})
    end
  end

  describe "handle/2 called directly" do
    test "translates the error using the locale on the changeset context" do
      changeset =
        Parcel
        |> Ash.Changeset.for_create(:create, %{weight: 5})
        |> Ash.Changeset.set_context(%{locale: "ru"})

      error = InvalidAttribute.exception(message: "weight_too_low", vars: [min: 30])

      assert %{message: "Вес должен быть не менее 30 кг"} = Handler.handle(changeset, error)
    end

    test "passes the error through for a domain that does not translate" do
      changeset = Ash.Changeset.for_create(Untranslated.Parcel, :create, %{weight: 5})
      error = InvalidAttribute.exception(message: "weight_too_low", vars: [min: 30])

      assert %{message: "weight_too_low"} = Handler.handle(changeset, error)
    end
  end

  describe "a write action on a domain that does not configure gettext" do
    test "returns the message untranslated, proving the opt-in is real" do
      result = Ash.create(Untranslated.Parcel, %{weight: 5}, context: %{locale: "ru"})

      assert message_of(result) == "weight_too_low"
    end
  end
end
