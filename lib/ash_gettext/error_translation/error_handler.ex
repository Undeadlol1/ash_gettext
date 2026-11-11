defmodule AshGettext.ErrorTranslation.ErrorHandler do
  @moduledoc """
  The `error_handler` that `AshGettext.Resource` installs on every action.
  Reads have no `error_handler`; a preparation calls this for them.

  Ash calls this with the changeset (the action input, for a generic action)
  and each error it collects. The error is translated into the language of the
  action's actor, else Gettext's current language.

  For a changeset or action input it returns `{subject, translated_error}`, the
  shape Ash accepts from an `error_handler`: the subject keeps the language it
  found in its context, so the other errors of the same action do not ask the
  `locale_resolver` again. A language whose lookup failed is not kept. For a
  query it returns the translated error alone.

  It sits below every transport by design. An error from a custom validation,
  a builtin constraint, a value that does not cast, a missing required value or
  a failed policy all arrive here the same way. Errors the data layer returns
  after the change ran (a stale record) do not pass through it.

  If the domain does not configure `gettext`, the error passes through untouched.
  """

  alias AshGettext.ErrorTranslation
  alias AshGettext.Info

  @doc """
  Translate `error` into the action's language.
  """
  @spec translate_error(Ash.Changeset.t() | Ash.ActionInput.t() | Ash.Query.t(), term()) ::
          {Ash.Changeset.t() | Ash.ActionInput.t(), term()} | term()
  def translate_error(_subject, []), do: []

  def translate_error(subject, error) do
    case Info.settings(subject.domain) do
      {:ok, settings} ->
        remember_refusal(error)
        {subject, locale} = locale(subject, settings.backend)

        translated =
          ErrorTranslation.translate(error,
            backend: settings.backend,
            text_domain: settings.text_domain,
            locale: locale
          )

        kept(subject, translated)

      :error ->
        error
    end
  end

  @answer {__MODULE__, :resolved_language}

  defp kept(%struct{} = subject, error) when struct in [Ash.Changeset, Ash.ActionInput],
    do: {subject, error}

  defp kept(_query, error), do: error

  @json_api AshGettext.JsonApi

  # AshJsonApi passes nothing of a failed policy on, so its reply step is told here.
  defp remember_refusal(error) do
    if Code.ensure_loaded?(@json_api), do: @json_api.remember_refusal(error)
  end

  defp locale(subject, backend) do
    context = subject.context || %{}
    actor = get_in(context, [:private, :actor])

    {subject, answer} =
      case context do
        %{@answer => {^actor, answer}} ->
          {subject, answer}

        _not_asked_yet ->
          case Info.resolved(subject.domain, actor) do
            :failed -> {subject, :failed}
            answer -> {%{subject | context: Map.put(context, @answer, {actor, answer})}, answer}
          end
      end

    {subject, Info.locale_from(subject.domain, answer, backend)}
  end
end
