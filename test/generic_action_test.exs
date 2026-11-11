defmodule AshGettext.GenericActionTest do
  @moduledoc """
  A generic action (`action :name, :type`) fails below every transport, like a
  create does. Its errors are translated in the error itself, so whatever
  sends them on has the reader's sentence already.
  """

  use ExUnit.Case, async: true

  alias AshGettextFixture.Parcel

  @russian %{language: "ru"}

  defp weigh(action \\ :weigh, weight, opts) do
    Parcel
    |> Ash.ActionInput.for_action(action, %{weight: weight}, opts)
    |> Ash.run_action()
  end

  test "an error it returns comes back in the actor's language" do
    assert {:error, %{errors: [%{message: "Вес должен быть не менее 30 кг"}]}} =
             weigh(5, actor: @russian)
  end

  test "the error keeps its Ash type and field" do
    assert {:error, %{errors: [%Ash.Error.Changes.InvalidArgument{field: :weight}]}} =
             weigh(5, actor: @russian)
  end

  test "with no actor, the error comes back in Gettext's current language" do
    Gettext.with_locale(AshGettextFixture.Gettext, "ru", fn ->
      assert {:error, %{errors: [%{message: "Вес должен быть не менее 30 кг"}]}} = weigh(5, [])
    end)
  end

  test "a run that succeeds is untouched" do
    assert weigh(40, actor: @russian) == {:ok, 40}
  end

  test "an action with its own error handler keeps it" do
    assert {:error, %{errors: [%{message: "weight_too_low"}]}} =
             weigh(:weigh_the_apps_way, 5, actor: @russian)
  end
end
