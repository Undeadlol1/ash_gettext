defmodule AshGettext.Locale.Resolver do
  @moduledoc """
  How a host application answers "what language is this request in?".

  The library ships only resolvers that can work without knowing anything about
  the host — `AshGettext.Locale.Context` reads a locale someone already put on
  the action context. Anything that needs to know what a *user* is, or where
  their preference is stored, is the host's job: implement this behaviour in the
  host application and name the module in the domain DSL.

  A resolver returns `nil` to mean "I have no opinion", which lets the next
  resolver in the chain answer.

      defmodule MyApp.Localization.AshGettextAdapter do
        @behaviour AshGettext.Locale.Resolver

        @impl true
        def resolve(%{actor: actor}) when not is_nil(actor) do
          MyApp.Accounts.locale_for(actor)
        end

        def resolve(_context), do: nil
      end
  """

  @doc """
  Return the locale this resolver reads from `context`, or `nil` to defer.
  """
  @callback resolve(context :: map()) :: String.t() | nil
end
