defmodule AshGettext.Domain.Transformers.TranslateJsonApiReplies do
  @moduledoc """
  Point the domain's JSON:API `error_handler` at `AshGettext.JsonApi`.

  A domain with a `gettext` block that also serves JSON:API gets its replies
  translated with nothing to set up. A handler the app wrote keeps running:
  it is called first, and the error it returns is then translated.

  A domain without AshJsonApi, without a `gettext` backend, or with
  `translate_errors? false` is left as it was.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @handler {AshGettext.JsonApi, :translate_error}

  @doc false
  def after?(_transformer), do: true

  @doc false
  def transform(dsl_state) do
    if translates_json_api?(dsl_state) do
      {:ok, Transformer.set_option(dsl_state, [:json_api], :error_handler, handler(dsl_state))}
    else
      {:ok, dsl_state}
    end
  end

  defp translates_json_api?(dsl_state) do
    AshJsonApi.Domain in Transformer.get_persisted(dsl_state, :extensions, []) and
      Transformer.get_option(dsl_state, [:gettext], :backend) != nil and
      Transformer.get_option(dsl_state, [:gettext], :translate_errors?, true)
  end

  defp handler(dsl_state) do
    {module, function} = @handler

    case Transformer.get_option(dsl_state, [:json_api], :error_handler) do
      nil -> {module, function, []}
      {^module, ^function, _arguments} = already_ours -> already_ours
      the_apps_own -> {module, function, [the_apps_own]}
    end
  end
end
