defmodule AshGettext.Resource.Transformers.InstallErrorHandler do
  @moduledoc """
  Point every write action's `error_handler` at `AshGettext.Errors.Handler`.

  Doing this at compile time is what makes translation a property of the resource
  rather than a thing each action has to remember. Adding an action to a resource
  that uses `AshGettext.Resource` cannot forget to translate.

  Two deliberate limits:

  * **Write actions only.** Ash 3.29 exposes `error_handler` on `create`,
    `update` and `destroy` — the changeset-based actions. Read and generic
    actions have no equivalent hook, so their errors are not translated here.
  * **An action that already declares an `error_handler` is left alone.** The
    app asked for that handler explicitly; silently replacing it would be a worse
    surprise than an untranslated message.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @writes [:create, :update, :destroy]
  @handler {AshGettext.Errors.Handler, :handle, []}

  @doc false
  def after?(_transformer), do: true

  @doc false
  def transform(dsl_state) do
    dsl_state
    |> Transformer.get_entities([:actions])
    |> Enum.filter(&translatable?/1)
    |> Enum.reduce(dsl_state, &install/2)
    |> then(&{:ok, &1})
  end

  defp translatable?(%{type: type, error_handler: nil}) when type in @writes, do: true
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
