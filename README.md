# AshGettext

Gettext translation for Ash validation and error messages, opted into per
domain. `Ash.Domain` and `Ash.Resource` extensions let a translatable message
travel as a plain msgid all the way to your host's own Gettext backend,
without every resource author writing `Gettext.dgettext/3` by hand.

## Design constraints

- **No host dependency.** This library depends only on `ash`, `spark`,
  `gettext` and the standard library. It never imports, aliases, or calls
  into an application that uses it. See `docs/ASH_GETTEXT_RESEARCH.livemd` in
  the parent repository for the design notebook this library came out of.
- **Opt-in per domain.** A domain with no `gettext` block is untouched;
  nothing about adopting this library changes behavior for a resource that
  doesn't ask for it.
- **Missing translations are observable.** `AshGettext.fetch/5` reports
  `{:missing, fallback}` rather than silently returning the msgid, so a
  missing catalog entry is something a test can catch.

## Installation

Add to `mix.exs` (once published) or via a `path:` dependency from within
this monorepo:

Not on Hex yet:

```elixir
def deps do
  [
    {:ash_gettext, github: "Undeadlol1/ash_gettext"}
  ]
end
```

## A complete example

```elixir
defmodule MyApp.Gettext do
  use Gettext.Backend, otp_app: :my_app
end

defmodule MyApp.Shipping do
  use Ash.Domain, extensions: [AshGettext.Domain]

  gettext do
    backend(MyApp.Gettext)
    text_domain("shipping")
  end

  resources do
    resource MyApp.Shipping.Parcel
  end
end

defmodule MyApp.Shipping.Parcel do
  use Ash.Resource,
    domain: MyApp.Shipping,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGettext.Resource]

  actions do
    defaults [:read]

    create :create do
      accept [:weight]
      validate {MyApp.Shipping.MinimumWeight, []}
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :weight, :integer, public?: true
  end
end
```

A validation returns a msgid instead of a rendered sentence:

```elixir
defmodule MyApp.Shipping.MinimumWeight do
  use Ash.Resource.Validation
  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :weight) do
      weight when is_integer(weight) and weight < 30 ->
        {:error, InvalidAttribute.exception(field: :weight, message: "weight_too_low", vars: [min: 30])}

      _ ->
        :ok
    end
  end
end
```

`AshGettext.Resource` renders `"weight_too_low"` through
`MyApp.Gettext`'s `"shipping"` text domain in the caller's locale.

## Configuration

The `gettext` DSL block on an `Ash.Domain` accepts:

- `backend(Module)` — required, the host's `Gettext.Backend` module.
- `default_locale("en")` — locale used when none is resolved from context.
- `text_domain("name")` — the gettext domain (`.pot`/`.po` file) to look
  translations up in.
- `locale_resolvers([Module, ...])` — modules implementing
  `AshGettext.Locale.Resolver` to pick a locale from the action context.
- `translate_errors?(false)` — opt a domain's `gettext` config in without
  translating errors (rare; mostly for staged rollout).

An `Ash.Resource.Validation`'s error `message:` becomes the msgid looked up
in the domain's configured `text_domain`. Use `AshGettext.Extractor` (see
`mix ash_gettext.extract`) to keep the `.pot` template in sync with every
`message:` your resources declare.

## Testing your own use of this library

`AshGettext.Test.assert_translates/6` and `assert_covered/5` are for this
library's own suite and for auditing catalog coverage — not for a host
app's tests, which should assert the text through their own API instead.

## Development

```bash
cd lib/ash_gettext   # from the parent repository's back-end/elixir
mix deps.get
mix test
```
