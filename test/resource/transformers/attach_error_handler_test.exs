defmodule AshGettext.Resource.Transformers.AttachErrorHandlerTest do
  use ExUnit.Case, async: true

  alias Ash.Resource.Info
  alias AshGettext.ErrorTranslation.ErrorHandler
  alias AshGettext.Resource.Transformers.AttachErrorHandler
  alias AshGettextFixture.Opinionated
  alias AshGettextFixture.Parcel

  defp handler_for(resource, action) do
    Info.action(resource, action).error_handler
  end

  describe "attaching the error handler" do
    test "points a create action at the library's handler" do
      assert handler_for(Parcel, :create) == {ErrorHandler, :translate_error, []}
    end

    test "points an update action at it too" do
      assert handler_for(Parcel, :relabel) == {ErrorHandler, :translate_error, []}
    end

    test "installs it on a resource whose domain switched translation off, so the flag stays runtime" do
      assert handler_for(AshGettextFixture.SwitchedOff.Parcel, :create) ==
               {ErrorHandler, :translate_error, []}
    end
  end

  describe "deferring to the application" do
    test "leaves an action that already declares an error handler alone" do
      assert handler_for(Opinionated.Parcel, :create) ==
               {AshGettextFixture.CustomHandler, :handle, []}
    end

    test "the app's handler is what actually runs" do
      result = Ash.create(Opinionated.Parcel, %{weight: 5}, actor: %{language: "ru"})

      assert {:error, %{errors: [%{message: "handled by the app"}]}} = result
    end
  end

  describe "actions Ash gives no error hook" do
    test "a read action keeps no handler, since Ash exposes none for reads" do
      refute Map.has_key?(Info.action(Parcel, :read), :error_handler)
    end
  end

  describe "running the transformer" do
    test "is idempotent, so recompiling never stacks handlers" do
      {:ok, once} = AttachErrorHandler.transform(Parcel.spark_dsl_config())
      {:ok, twice} = AttachErrorHandler.transform(once)

      assert twice == once
    end
  end

  describe "ordering against other transformers" do
    test "runs last, so it sees actions other transformers added" do
      assert AttachErrorHandler in AshGettext.Resource.persisters()
    end
  end
end
