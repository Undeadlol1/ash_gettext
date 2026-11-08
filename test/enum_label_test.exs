defmodule AshGettext.EnumLabelTest do
  use ExUnit.Case, async: true

  alias AshGettextFixture.Crate
  alias AshGettextFixture.Parcel

  @ru %{language: "ru"}

  defp parcel(attrs) do
    Parcel
    |> Ash.Changeset.for_create(:create, %{weight: 100})
    |> Ash.Changeset.force_change_attributes(attrs)
    |> Ash.create!()
  end

  test "an actor's language gives the Russian label" do
    parcel = parcel(status: :placed)

    assert Ash.get!(Parcel, parcel.id, load: [:status_label], actor: @ru).status_label ==
             "Размещён"
  end

  test "the source language gives the English label" do
    parcel = parcel(status: :shipped)
    assert Ash.get!(Parcel, parcel.id, load: [:status_label]).status_label == "On its way"
  end

  test "a nil attribute gives nil" do
    parcel = parcel([])
    assert Ash.get!(Parcel, parcel.id, load: [:status_label], actor: @ru).status_label == nil
  end

  test "an array attribute gives a list of labels" do
    parcel = parcel(past_statuses: [:placed, :shipped])

    assert Ash.get!(Parcel, parcel.id, load: [:past_statuses_label], actor: @ru).past_statuses_label ==
             ["Размещён", "В пути"]
  end

  test "an existing field with that name is not overwritten" do
    crate = Ash.create!(Crate, %{status: :placed})
    assert Ash.load!(crate, :status_label).status_label == "mine"
  end

  test "an enum that is not an AshGettext.Enum gets no calculation" do
    refute Ash.Resource.Info.calculation(Crate, :kind_label)
  end
end
