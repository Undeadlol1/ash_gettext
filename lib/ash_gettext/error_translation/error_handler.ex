defmodule AshGettext.ErrorTranslation.ErrorHandler do
  @moduledoc """
  The `error_handler` that `AshGettext.Resource` installs on write actions.

  Ash calls this with the changeset and each error it collects, and takes the
  return value as the error to keep. The error is translated into the language
  of the action's actor or `context: %{locale: ...}`, else Gettext's current
  language.

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
  @spec translate_error(Ash.Changeset.t(), term()) :: term()
  def translate_error(changeset, error) do
    case Info.settings(changeset.domain) do
      {:ok, settings} ->
        ErrorTranslation.translate(error, translation_options(changeset, settings))

      :error ->
        error
    end
  end

  # Ask the domain's resolvers; Gettext's current language is the fallback.
  defp translation_options(changeset, settings) do
    context = changeset.context || %{}

    locale =
      case Info.language(changeset.domain, %{
             locale: context[:locale],
             actor: get_in(context, [:private, :actor]),
             changeset: changeset
           }) do
        {_backend, locale} -> locale
        nil -> Gettext.get_locale(settings.backend)
      end

    [backend: settings.backend, text_domain: settings.text_domain, locale: locale]
  end
end
