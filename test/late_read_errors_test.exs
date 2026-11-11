defmodule AshGettext.LateReadErrorsTest do
  @moduledoc """
  A read whose error comes from an action-level preparation or a read
  validation, both of which Ash runs after the library's own preparation.
  A validation on every read of the resource runs after every preparation;
  that one is pinned in "known gaps".
  """

  use ExUnit.Case, async: true

  alias AshGettextFixture.LateReads.Cabinet
  alias AshGettextFixture.LateReads.Drawer
  alias AshGettextFixture.LateReads.Shelf

  @russian %{language: "ru"}
  @russian_sentence "Вес должен быть не менее 30 кг"

  for action <- [:refused_by_preparation, :refused_by_validation] do
    describe "a read #{action}" do
      test "shows a Russian reader the sentence through the code interface" do
        result = apply(Shelf, unquote(action), [[actor: @russian]])

        assert [@russian_sentence] == leaf_messages(result)
      end

      test "shows a Russian reader the sentence when the query was prepared first" do
        result =
          Shelf
          |> Ash.Query.for_read(unquote(action), %{}, actor: @russian)
          |> Ash.read()

        assert [@russian_sentence] == leaf_messages(result)
      end

      test "shows a Russian reader the sentence when Ash prepares the query" do
        result = Ash.read(Shelf, action: unquote(action), actor: @russian)

        assert [@russian_sentence] == leaf_messages(result)
      end
    end
  end

  describe "actions another extension adds after the library's transformer" do
    test "get the error handler" do
      assert {AshGettext.ErrorTranslation.ErrorHandler, :translate_error, []} ==
               Ash.Resource.Info.action(Drawer, :added_create).error_handler
    end

    test "show a Russian reader a read error from their own preparation" do
      result = Ash.read(Drawer, action: :added_read, actor: @russian)

      assert [@russian_sentence] == leaf_messages(result)
    end
  end

  describe "known gaps" do
    test "a resource-wide read validation leaves a Russian reader the msgid through the code interface" do
      assert ["weight_too_low"] == leaf_messages(Cabinet.read(actor: @russian))
    end

    test "a resource-wide read validation leaves a Russian reader the msgid when the query was prepared first" do
      result =
        Cabinet
        |> Ash.Query.for_read(:read, %{}, actor: @russian)
        |> Ash.read()

      assert ["weight_too_low"] == leaf_messages(result)
    end

    test "a resource-wide read validation leaves a Russian reader the msgid when Ash prepares the query" do
      assert ["weight_too_low"] == leaf_messages(Ash.read(Cabinet, actor: @russian))
    end
  end

  defp leaf_messages({:error, error}) do
    error |> Ash.Error.to_error_class() |> Map.fetch!(:errors) |> Enum.map(& &1.message)
  end
end
