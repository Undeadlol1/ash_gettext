defmodule AshGettext.ResourceTest do
  @moduledoc """
  Guards the notebook's §2.1a promise: adopting the extension must never require
  — or cause — a change to a consumer's resource shape.

  `AshGettextFixture.Parcel` uses the extension. If any of these fail, the
  library has started rewriting the resources it was only supposed to observe,
  and no public consumer could safely adopt it.
  """

  use ExUnit.Case, async: true

  alias Ash.Resource.Info
  alias AshGettextFixture.Parcel

  test "adds no attribute" do
    attributes = Parcel |> Info.attributes() |> Enum.map(& &1.name) |> Enum.sort()

    assert attributes == [:id, :label, :weight]
  end

  test "adds no calculation" do
    assert Info.calculations(Parcel) == []
  end

  test "adds no aggregate" do
    assert Info.aggregates(Parcel) == []
  end

  test "adds no relationship" do
    assert Info.relationships(Parcel) == []
  end

  test "adds no action" do
    actions = Parcel |> Info.actions() |> Enum.map(& &1.name) |> Enum.sort()

    assert actions == [:create, :read, :relabel]
  end

  test "leaves attribute types exactly as declared" do
    assert Info.attribute(Parcel, :weight).type == Ash.Type.Integer
    assert Info.attribute(Parcel, :label).type == Ash.Type.String
  end
end
