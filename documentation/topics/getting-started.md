# Getting started

This page takes you from a fresh dependency to one validation error shown in
English and in Russian. It assumes an app that already uses Ash and Gettext.

## Add the dependency

```elixir
# mix.exs
def deps do
  [
    {:ash_gettext, "~> 0.1"}
  ]
end
```

Add `:ash_json_api` too if you want `AshGettext.Error` to render in JSON:API
responses. It is optional.

## Have a Gettext backend

AshGettext translates against the catalogs your app already has. If you have no
backend yet, make one:

```elixir
defmodule MyApp.Gettext do
  use Gettext.Backend, otp_app: :my_app
end
```

Catalogs live in `priv/gettext`, as with any Gettext app.

## Wire the app with the install task

Run the task to preview every edit. It writes nothing:

```
mix ash_gettext.install
```

Run it again with `--apply` to write the edits:

```
mix ash_gettext.install --apply
```

The task adds the `AshGettext.Domain` extension and a `gettext do` block to
every domain, and the `AshGettext.Resource` extension to every resource. A
file that is already wired is skipped, so re-running is safe. If the app has
more than one backend, name one with `--backend MyApp.Gettext`.

## Or wire it by hand

Add the extension and one block to each domain:

```elixir
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
```

`backend` is the only required option. `text_domain` names the catalog file
the messages live in; it defaults to `ash_errors`. See the
[DSL reference](DSL-AshGettext.Domain.md) for every option.

Add the extension to each resource:

```elixir
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

The domain block says how to translate. The resource extension turns it on for
that resource's create, update and destroy actions.

## Write a message in your own language

A validation writes its message as a sentence in the language your code is
written in:

```elixir
defmodule MyApp.Shipping.MinimumWeight do
  use Ash.Resource.Validation
  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :weight) do
      weight when is_integer(weight) and weight < 30 ->
        {:error,
         InvalidAttribute.exception(
           field: :weight,
           message: "must weigh at least %{min} kg",
           vars: [min: 30]
         )}

      _ ->
        :ok
    end
  end
end
```

That sentence is the msgid, the key a catalog looks up. In the source
language it is also the text, so you keep no catalog for it. The source
language is the backend's default locale, `en` unless you set another.

## Add the other languages

Write the sentence once in each other language's `.po` file:

```po
# priv/gettext/ru/LC_MESSAGES/shipping.po
msgid "must weigh at least %{min} kg"
msgstr "должен весить не меньше %{min} кг"
```

The `.po` files hold only the other languages. To create the template those
files start from, see [Extracting messages](extracting-messages.md).

## See one error in two languages

Pass the locale in the action context:

```elixir
changeset = Ash.Changeset.for_create(MyApp.Shipping.Parcel, :create, %{weight: 5})

{:error, error} = Ash.create(changeset)
Enum.map(error.errors, & &1.message)
#=> ["must weigh at least 30 kg"]

changeset =
  Ash.Changeset.for_create(MyApp.Shipping.Parcel, :create, %{weight: 5},
    context: %{locale: "ru"}
  )

{:error, error} = Ash.create(changeset)
Enum.map(error.errors, & &1.message)
#=> ["должен весить не меньше 30 кг"]
```

The default resolver reads `context[:locale]`. To take the locale from the
signed-in user instead, see [Locales](locales.md).

## Next steps

- [Translating errors](translating-errors.md): placeholders, coded errors and
  what is translated.
- [Locales](locales.md): choose the language from the user, not the process.
- [Extracting messages](extracting-messages.md): write the `.pot` template.
- [How to test with AshGettext](testing.md): check that a message is
  translated.
