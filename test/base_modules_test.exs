defmodule AshGettext.BaseModulesTest do
  use ExUnit.Case, async: true

  alias AshGettextBase.Parcel

  @ru %{language: "ru"}

  test "a resource from the base resource, in a domain from the base domain, gets a translated label" do
    parcel = Ash.create!(Parcel, %{weight: 100, status: :placed})

    assert Ash.load!(parcel, :status_label, actor: @ru).status_label == "Заказ размещён"
  end

  test "it gets translated errors" do
    assert {:error, %{errors: [error]}} = Ash.create(Parcel, %{weight: 5}, actor: @ru)
    assert error.message == "Вес должен быть не менее 30 кг"
  end

  test "a resource's own extensions are kept next to ours" do
    assert AshJsonApi.Resource in Spark.extensions(Parcel)
    assert AshGettext.Resource in Spark.extensions(Parcel)
  end

  test "a domain can change one setting with its own gettext block" do
    assert {:ok, settings} = AshGettext.Info.locale_settings(AshGettextBase.OtherCatalog)
    assert settings.text_domain == "other"
    assert settings.backend == AshGettextFixture.Gettext
  end
end
