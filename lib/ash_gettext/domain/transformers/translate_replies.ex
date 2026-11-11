defmodule AshGettext.Domain.Transformers.TranslateReplies do
  @moduledoc """
  Points the domain's JSON:API and GraphQL `error_handler` at
  `AshGettext.JsonApi` and `AshGettext.Graphql`. An `error_handler` the app
  wrote keeps running first.

  Notes for maintainers: maintainers/why-some-errors-are-hard.md in the repository.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @transports [
    {AshJsonApi.Domain, :json_api, AshGettext.JsonApi, []},
    {AshGraphql.Domain, :graphql, AshGettext.Graphql,
     [{AshGraphql.DefaultErrorHandler, :handle_error, []}]}
  ]

  @doc false
  def after?(_transformer), do: true

  @doc false
  def transform(dsl_state) do
    if translates_errors?(dsl_state) do
      extensions = Transformer.get_persisted(dsl_state, :extensions, [])

      {:ok,
       for {extension, section, adapter, default} <- @transports,
           extension in extensions,
           reduce: dsl_state do
         dsl_state ->
           handler = handler(dsl_state, section, adapter, default)
           Transformer.set_option(dsl_state, [section], :error_handler, handler)
       end}
    else
      {:ok, dsl_state}
    end
  end

  defp translates_errors?(dsl_state) do
    Transformer.get_option(dsl_state, [:gettext], :backend) != nil and
      Transformer.get_option(dsl_state, [:gettext], :translate_errors?, true)
  end

  defp handler(dsl_state, section, adapter, default) do
    case Transformer.get_option(dsl_state, [section], :error_handler) do
      nil -> {adapter, :translate_error, default}
      {^adapter, :translate_error, _arguments} = already_ours -> already_ours
      the_apps_own -> {adapter, :translate_error, [the_apps_own]}
    end
  end
end
