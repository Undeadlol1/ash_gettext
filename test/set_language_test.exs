defmodule AshGettext.SetLanguageTest do
  use ExUnit.Case, async: true

  alias AshGettextFixture.Gettext, as: Backend
  alias AshGettextFixture.Parcel
  alias AshGettextFixture.ParcelStatus

  # Each test runs in its own process, so the process locale cannot leak.

  test "an actor sets the language, and enum labels follow" do
    Ash.create!(Parcel, %{weight: 100}, actor: %{language: "ru"})

    assert Gettext.get_locale(Backend) == "ru"
    assert ParcelStatus.label(:placed) == "Заказ размещён"
  end

  test "context locale sets the language" do
    Ash.create!(Parcel, %{weight: 100}, context: %{locale: "ru"})

    assert Gettext.get_locale(Backend) == "ru"
  end

  test "no actor and no locale leaves the process language alone" do
    Gettext.put_locale(Backend, "ru")
    Ash.create!(Parcel, %{weight: 100})

    assert Gettext.get_locale(Backend) == "ru"
  end

  test "a failing create returns a Russian message for an actor" do
    assert {:error, %{errors: [%{message: message}]}} =
             Ash.create(Parcel, %{weight: 5}, actor: %{language: "ru"})

    assert message == "Вес должен быть не менее 30 кг"
  end

  test "a read action sets the language too" do
    Ash.read!(Parcel, actor: %{language: "ru"})

    assert Gettext.get_locale(Backend) == "ru"
  end

  test "an update and a destroy set it" do
    parcel = Ash.create!(Parcel, %{weight: 100})
    Gettext.put_locale(Backend, "en")
    Ash.update!(parcel, %{label: "x"}, actor: %{language: "ru"})
    assert Gettext.get_locale(Backend) == "ru"

    Gettext.put_locale(Backend, "en")
    Ash.destroy!(parcel, actor: %{language: "ru"})
    assert Gettext.get_locale(Backend) == "ru"
  end
end
