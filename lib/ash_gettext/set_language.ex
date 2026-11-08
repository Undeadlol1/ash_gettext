defmodule AshGettext.SetLanguage do
  @moduledoc """
  Sets Gettext's language for the process, once, when an action starts.

  `AshGettext.Resource` installs this as a global change (create, update,
  destroy) and a global preparation (read). It asks the domain's
  `locale_resolvers` for the language, using the action's actor and
  `context: %{locale: ...}`, and calls `Gettext.put_locale/2`. When no resolver
  answers, the process language is left alone. A domain with no `gettext`
  block is skipped.

  Enum labels, error messages and attribute names then all read that language.
  """

  use Ash.Resource.Change

  alias AshGettext.Info
  alias AshGettext.Locale.Normalizer

  @impl true
  def change(changeset, _opts, _context), do: set(changeset)

  @impl true
  def atomic(changeset, _opts, _context), do: {:ok, set(changeset)}

  @doc false
  def set(%{domain: domain, context: context} = subject) do
    context = context || %{}

    case resolve(domain, %{
           locale: context[:locale],
           actor: get_in(context, [:private, :actor]),
           changeset: subject
         }) do
      {backend, locale} -> Gettext.put_locale(backend, locale)
      nil -> :ok
    end

    subject
  end

  @doc false
  # `{backend, locale}` when a resolver of `domain` answers for `resolution`, else nil.
  def resolve(domain, resolution) do
    with {:ok, settings} <- Info.locale_settings(domain),
         answer when is_binary(answer) <-
           Enum.find_value(settings.locale_resolvers, & &1.resolve(resolution)) do
      {settings.backend,
       Normalizer.normalize(answer, settings.supported_locales, settings.default_locale)}
    else
      _no_answer -> nil
    end
  end
end

defmodule AshGettext.SetLanguage.Prepare do
  @moduledoc "The read-action form of `AshGettext.SetLanguage`."

  use Ash.Resource.Preparation

  @impl true
  def prepare(query, _opts, _context), do: AshGettext.SetLanguage.set(query)
end
