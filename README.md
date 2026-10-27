# AshGettext

Gettext translation for Ash validation and error messages, opted into per
domain.

## Why AshGettext?

You can't wrap an Ash error in `dgettext`. Ash raises it, somewhere inside the
action, and hands the finished struct to whatever renders it. So translating
Ash errors by hand means catching them on the way out, in every action, in
every process, forever.

**1. Stop wiring translation into every action.**

Today, translating errors means a handler on each write action and a module to
back it:

```elixir
create :register do
  accept [:email]
  error_handler {MyApp.Errors, :translate, []}
end

update :change_email do
  accept [:email]
  # forgot the error_handler — this one ships in English
end
```

```elixir
defmodule MyApp.Errors do
  def translate(changeset, %{message: msg, vars: vars} = error) do
    locale = changeset.context[:locale] || "en"

    Gettext.with_locale(MyApp.Gettext, locale, fn ->
      %{error | message: Gettext.dgettext(MyApp.Gettext, "errors", msg, vars)}
    end)
  end

  def translate(_changeset, error), do: error
end
```

With AshGettext, delete both. Add one block to the domain:

```elixir
defmodule MyApp.Shop do
  use Ash.Domain, extensions: [AshGettext.Domain]

  gettext do
    backend(MyApp.Gettext)
  end
end
```

and the extension to its resources, once, in your base resource:

```elixir
use Ash.Resource, extensions: [AshGettext.Resource]
```

Every create, update and destroy is covered — the ones you have and the ones
your team adds next year. Ash's own messages come through too, once they're in
your catalog: a `min: 30` constraint fails as "muss mindestens 30 sein", number
filled in, in JSON:API, GraphQL and LiveView alike.

**2. Stop setting the locale in every process.**

Gettext's locale lives in the current process. So every controller, channel
and worker that runs an action for a user has to set it first:

```elixir
def perform(%{args: %{"user_id" => id}}) do
  user = Accounts.get_user!(id)
  Gettext.put_locale(MyApp.Gettext, user.locale)   # miss this once: English
  Orders.cancel_stale(actor: user)
end
```

The action already knows who's acting. Say once where their language lives:

```elixir
defmodule MyApp.UserLocale do
  @behaviour AshGettext.Locale.Resolver

  def resolve(%{actor: %{locale: locale}}), do: locale
  def resolve(_), do: nil
end
```

```elixir
gettext do
  backend(MyApp.Gettext)
  locale_resolvers([MyApp.UserLocale])
end
```

Now every error, from any process, comes out in the actor's language.

**3. Stop maintaining your `.pot` by hand.**

`mix gettext.extract` only finds `gettext` calls. Your Ash messages live in
`message:` options, so to get them in front of translators you keep a file
like this in sync by hand:

```elixir
defmodule MyApp.AshMessages do
  use Gettext, backend: MyApp.Gettext

  def noop do
    dgettext_noop("errors", "This email is already registered")
    dgettext_noop("errors", "must be greater than or equal to %{min}")
    # ...every message in every resource, forever
  end
end
```

Delete it:

```
mix ash_gettext.extract          # writes priv/gettext/ash_errors.pot
mix ash_gettext.extract --check  # in CI: fails when the template is out of date
```

It reads your resources and writes the template. In CI, `--check` fails the
build when someone adds a message without its entry.

## Installation

Not on Hex yet:

```elixir
def deps do
  [
    {:ash_gettext, github: "Undeadlol1/ash_gettext"}
  ]
end
```

Then run `mix ash_gettext.install` to preview the edits, and
`mix ash_gettext.install --apply` to write them. It adds the
`AshGettext.Domain` extension and a `gettext do` block to every domain, and the
`AshGettext.Resource` extension to every resource; domains already wired are
skipped, so re-running is safe.

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

A validation writes its message as a sentence in the source language, the
language your code is written in. That sentence is the msgid: gettext's rule is
that the source text *is* the key, so the source language needs no catalog and
the `.po` files hold only the other languages. The source language is the
backend's default locale (`en` unless you configure gettext otherwise). Ids
like `"weight_too_low"` work mechanically but force you to keep a catalog for
the source language by hand and show a raw key whenever an entry is missing.

```elixir
defmodule MyApp.Shipping.MinimumWeight do
  use Ash.Resource.Validation
  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :weight) do
      weight when is_integer(weight) and weight < 30 ->
        {:error, InvalidAttribute.exception(field: :weight, message: "must weigh at least %{min} kg", vars: [min: 30])}

      _ ->
        :ok
    end
  end
end
```

`AshGettext.Resource` looks `"must weigh at least %{min} kg"` up in
`MyApp.Gettext`'s `"shipping"` text domain in the caller's locale. In the
source locale the sentence itself is the answer; in `ru` the catalog entry is:

```po
msgid "must weigh at least %{min} kg"
msgstr "должен весить не меньше %{min} кг"
```

## Configuration

The `gettext` DSL block on an `Ash.Domain` accepts:

- `backend(Module)` — required, the host's `Gettext.Backend` module.
- `default_locale("en")` — locale used when none is resolved from context.
- `text_domain("ash_errors")` — the gettext domain (`.pot`/`.po` file) to look
  translations up in. Defaults to `ash_errors`, the file
  `mix ash_gettext.extract` writes.
- `locale_resolvers([Module, ...])` — modules implementing
  `AshGettext.Locale.Resolver`, tried in order until one picks a locale.
  Defaults to `AshGettext.Locale.Context`, which reads `context[:locale]`.
- `translate_errors?(false)` — keep a domain's `gettext` config without
  translating its errors (mostly for a staged rollout).
- `verify_resources?(false)` — when `true`, compiling the domain reports every
  resource that lacks the `AshGettext.Resource` extension, as a compiler
  warning naming each one (an error under `--warnings-as-errors`, the way any
  Spark verifier reports). Off by default: extensions are opted into, never
  imposed.

An error's `message:` is the msgid, looked up in the domain's `text_domain`.
Errors from write actions (create, update, destroy) are translated; read
actions have no error hook in Ash, so their errors pass through as written.

## Testing your own use of this library

`AshGettext.Test.assert_translates/6` and `assert_covered/5` are for this
library's own suite and for auditing catalog coverage — not for a host
app's tests, which should assert the text through their own API instead.

## Development

```bash
mix deps.get
mix test
```
