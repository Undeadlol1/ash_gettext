defmodule AshGettext.ErrorTranslation.ErrorHandler do
  @moduledoc """
  The `error_handler` that `AshGettext.Resource` installs on write actions.

  Ash calls this with the changeset and each error it collects, and takes the
  return value as the error to keep. The error is translated into Gettext's current language, which
  `AshGettext.SetLanguage` set when the action started.

  It sits below every transport by design. An error from a custom validation,
  a builtin constraint, a value that does not cast, a missing required value or
  a failed policy all arrive here the same way. Errors the data layer returns
  after the change ran (a stale record) do not pass through it.

  If the domain does not configure `gettext`, the error passes through untouched.
  """

  alias AshGettext.ErrorTranslation
  alias AshGettext.Info

  @doc """
  Translate `error` into Gettext's current language.
  """
  @spec translate_error(Ash.Changeset.t(), term()) :: term()
  def translate_error(changeset, error) do
    case Info.settings(changeset.domain) do
      {:ok, settings} ->
        ErrorTranslation.translate(error, translation_options(settings))

      :error ->
        error
    end
  end

  # The language was set once when the action started (`AshGettext.SetLanguage`).
  defp translation_options(settings) do
    [
      backend: settings.backend,
      text_domain: settings.text_domain,
      locale: Gettext.get_locale(settings.backend)
    ]
  end
end
