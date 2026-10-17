defmodule AshGettext.Domain.Verifiers.ResourcesOptIn do
  @moduledoc """
  Reports, at compile time, every resource of a domain that asked for it which
  never added `AshGettext.Resource`.

  A resource without the extension silently answers in English; this turns that
  into a compiler diagnostic (an error under `--warnings-as-errors`, as with any
  Spark verifier) instead of a host-app test with a hand-kept domain list.
  It checks the extension, not each action's `error_handler`: an action that
  declares its own handler is a deliberate choice the transformer already
  respects.
  """

  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    if Verifier.get_option(dsl, [:gettext], :verify_resources?) do
      dsl
      |> Verifier.get_entities([:resources])
      |> Enum.map(& &1.resource)
      |> Enum.reject(&(AshGettext.Resource in Spark.extensions(&1)))
      |> case do
        [] -> :ok
        missing -> {:error, error(dsl, missing)}
      end
    else
      :ok
    end
  end

  defp error(dsl, missing) do
    Spark.Error.DslError.exception(
      module: Verifier.get_persisted(dsl, :module),
      path: [:gettext, :verify_resources?],
      message: """
      These resources do not use the AshGettext.Resource extension, so their errors would not be translated:

      #{Enum.map_join(missing, "\n", &"  * #{inspect(&1)}")}

      Add AshGettext.Resource to each one's `extensions:` (or to the base module it uses).
      """
    )
  end
end
