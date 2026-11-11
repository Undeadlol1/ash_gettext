defmodule AshGettext.ErrorTranslation.ErrorHandler do
  @moduledoc """
  The `error_handler` that `AshGettext.Resource` installs on every action but reads.

  Ash calls this with the changeset (the action input, for a generic action)
  and each error it collects, and takes the
  return value as the error to keep. The error is translated into the language
  of the action's actor, else Gettext's current language.

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
  @spec translate_error(Ash.Changeset.t() | Ash.ActionInput.t(), term()) :: term()
  def translate_error(changeset, error) do
    case Info.settings(changeset.domain) do
      {:ok, settings} ->
        ErrorTranslation.translate(error, translation_options(changeset, settings))

      :error ->
        error
    end
  end

  defp translation_options(changeset, settings) do
    actor = get_in(changeset.context || %{}, [:private, :actor])

    locale = Info.locale(changeset.domain, actor, settings.backend)

    [backend: settings.backend, text_domain: settings.text_domain, locale: locale]
  end
end
