defmodule AshGettext.ProcessLanguageTest do
  use ExUnit.Case, async: true

  alias AshGettextFixture.Gettext, as: Backend
  alias AshGettextFixture.Parcel

  @ru %{language: "ru"}

  defp placed_parcel do
    Parcel
    |> Ash.Changeset.for_create(:create, %{weight: 100})
    |> Ash.Changeset.force_change_attributes(status: :placed)
    |> Ash.create!()
  end

  test "a create, read, update and destroy leave the process language alone" do
    default = Gettext.get_locale(Backend)

    parcel = Ash.create!(Parcel, %{weight: 100}, actor: @ru)
    assert Gettext.get_locale(Backend) == default

    Ash.read!(Parcel, actor: @ru)
    assert Gettext.get_locale(Backend) == default

    parcel = Ash.update!(parcel, %{label: "x"}, actor: @ru)
    assert Gettext.get_locale(Backend) == default

    Ash.destroy!(parcel, actor: @ru)
    assert Gettext.get_locale(Backend) == default
  end

  test "a loaded label comes back in the actor's language" do
    parcel = placed_parcel()

    assert Ash.get!(Parcel, parcel.id, load: [:status_label], actor: @ru).status_label ==
             "Заказ размещён"
  end

  test "with no actor, a loaded label comes back in Gettext's current language" do
    parcel = placed_parcel()

    Gettext.with_locale(Backend, "ru", fn ->
      assert Ash.get!(Parcel, parcel.id, load: [:status_label]).status_label == "Заказ размещён"
    end)
  end

  test "an error comes back in the actor's language" do
    assert {:error, %{errors: [%{message: "Вес должен быть не менее 30 кг"}]}} =
             Ash.create(Parcel, %{weight: 5}, actor: @ru)
  end

  test "with no actor, an error comes back in Gettext's current language" do
    Gettext.with_locale(Backend, "ru", fn ->
      assert {:error, %{errors: [%{message: "Вес должен быть не менее 30 кг"}]}} =
               Ash.create(Parcel, %{weight: 5})
    end)
  end
end
