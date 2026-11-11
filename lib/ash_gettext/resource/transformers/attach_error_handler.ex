defmodule AshGettext.Resource.Transformers.AttachErrorHandler do
  @moduledoc """
  Point every action's `error_handler` at `AshGettext.ErrorTranslation.ErrorHandler`.

  Doing this at compile time is what makes translation a property of the resource
  rather than a thing each action has to remember. Adding an action to a resource
  that uses `AshGettext.Resource` cannot forget to translate.

  * **Read actions** have no `error_handler` in Ash. The resource gets one
    preparation, `AshGettext.Resource.Preparations.TranslateErrors`, instead.
  * **An action that already declares an `error_handler` is left alone.** The
    app asked for that handler explicitly; silently replacing it would be a worse
    surprise than an untranslated message.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @with_an_error_handler [:create, :update, :destroy, :action]
  @read_preparation {AshGettext.Resource.Preparations.TranslateErrors, []}
  @handler {AshGettext.ErrorTranslation.ErrorHandler, :translate_error, []}

  @doc false
  def after?(_transformer), do: true

  @doc false
  def transform(dsl_state) do
    dsl_state
    |> Transformer.get_entities([:actions])
    |> Enum.filter(&translatable?/1)
    |> Enum.reduce(dsl_state, &install/2)
    |> translate_read_errors()
  end

  defp translate_read_errors(dsl_state) do
    if Enum.any?(Transformer.get_entities(dsl_state, [:preparations]), &read_preparation?/1) do
      {:ok, dsl_state}
    else
      {:ok, preparation} = Ash.Resource.Builder.build_preparation(@read_preparation)

      {:ok, Transformer.add_entity(dsl_state, [:preparations], preparation)}
    end
  end

  defp read_preparation?(%{preparation: @read_preparation}), do: true
  defp read_preparation?(_other), do: false

  defp translatable?(%{type: type, error_handler: nil}) when type in @with_an_error_handler,
    do: true

  defp translatable?(_action), do: false

  defp install(action, dsl_state) do
    Transformer.replace_entity(
      dsl_state,
      [:actions],
      %{action | error_handler: @handler},
      &same_action?(&1, action)
    )
  end

  defp same_action?(%{name: name, type: type}, %{name: name, type: type}), do: true
  defp same_action?(_candidate, _action), do: false
end
