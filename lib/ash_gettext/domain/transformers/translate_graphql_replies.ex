defmodule AshGettext.Domain.Transformers.TranslateGraphqlReplies do
  @moduledoc """
  Point the domain's GraphQL `error_handler` at `AshGettext.Graphql`.

  A domain with a `gettext` block that also serves GraphQL gets its replies
  translated with nothing to set up. A handler the app wrote keeps running: it
  is called first, and the error it returns is then translated. With none,
  AshGraphql's default handler (which fills in `%{name}` values) runs first.

  A domain without AshGraphql, without a `gettext` backend, or with
  `translate_errors? false` is left as it was.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @handler {AshGettext.Graphql, :translate_error}
  @default {AshGraphql.DefaultErrorHandler, :handle_error, []}

  @doc false
  def after?(_transformer), do: true

  @doc false
  def transform(dsl_state) do
    if translates_graphql?(dsl_state) do
      {:ok, Transformer.set_option(dsl_state, [:graphql], :error_handler, handler(dsl_state))}
    else
      {:ok, dsl_state}
    end
  end

  defp translates_graphql?(dsl_state) do
    AshGraphql.Domain in Transformer.get_persisted(dsl_state, :extensions, []) and
      Transformer.get_option(dsl_state, [:gettext], :backend) != nil and
      Transformer.get_option(dsl_state, [:gettext], :translate_errors?, true)
  end

  defp handler(dsl_state) do
    {module, function} = @handler

    case Transformer.get_option(dsl_state, [:graphql], :error_handler) do
      nil -> {module, function, [@default]}
      {^module, ^function, _arguments} = already_ours -> already_ours
      the_apps_own -> {module, function, [the_apps_own]}
    end
  end
end
