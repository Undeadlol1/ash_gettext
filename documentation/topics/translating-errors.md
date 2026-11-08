# Translating errors

Ash builds its error messages inside the action, so you cannot wrap them in
a Gettext call yourself. This page shows how AshGettext translates them for
you, which errors it covers, and how to turn it on one domain at a time.

## Turn it on

Add the `AshGettext.Domain` extension and a `gettext` block to the domain:

```elixir
defmodule MyApp.Shipping do
  use Ash.Domain, extensions: [AshGettext.Domain]

  gettext do
    backend(MyApp.Gettext)
  end

  resources do
    resource MyApp.Shipping.Parcel
  end
end
```

`backend` is the only required option. See the
[DSL reference](DSL-AshGettext.Domain.md) for the rest.

Add the `AshGettext.Resource` extension to each resource:

```elixir
use Ash.Resource,
  domain: MyApp.Shipping,
  extensions: [AshGettext.Resource]
```

The domain block says how to translate. The resource extension turns it on
for that resource's create, update and destroy actions.

`mix ash_gettext.install` makes both edits in every domain and resource. Run
it alone to see the edits, and with `--apply` to write them. If the app has
more than one Gettext backend, name one with `--backend MyApp.Gettext`.

## See one error in two languages

```elixir
create :create do
  accept [:weight]
  validate compare(:weight, greater_than_or_equal_to: 30),
    message: "must weigh at least %{greater_than_or_equal_to} kg"
end
```

```po
# priv/gettext/ru/LC_MESSAGES/ash.po
msgid "must weigh at least %{greater_than_or_equal_to} kg"
msgstr "должен весить не меньше %{greater_than_or_equal_to} кг"
```

Run the action with `actor:` or pass the language in the context. The error
comes back in that language:

```elixir
MyApp.Shipping.Parcel
|> Ash.Changeset.for_create(:create, %{weight: 5}, context: %{locale: "ru"})
|> Ash.create()
# {:error, %Ash.Error.Invalid{errors: [%{message: "должен весить не меньше 30 кг"}]}}
```

With no actor and no `locale`, Gettext's current language is used. No action
changes the process language. To take the language from the signed-in user,
see [Locales](locales.md). Resolvers must not query the database.

## No handler on each action

Without AshGettext, each write action needs its own handler, and a new
action ships untranslated if someone forgets it:

```elixir
create :register do
  accept [:email]
  error_handler {MyApp.Errors, :translate, []}
end
```

The resource extension adds the handler to every create, update and destroy
action, including actions you add later. An action that declares its own
`error_handler` keeps it, and is not translated.

## The message is the msgid

An error's `message:` is looked up in the catalog as written:

```elixir
validate present(:email), message: "can't be blank"
```

If the catalog for the reader's locale has an entry, the entry replaces the
message. If it has none, the message is left as it was. Adding AshGettext can
add translations. It never changes a message that has no entry.

Your own language needs no catalog, because the message is already the
text. The `.po` files hold only the other languages.

## Ash's own errors

Some of Ash's errors have no message. Ash prints them from code names: a
missing required value reads "attribute delivery_date is required". AshGettext
gives each one a written English sentence and translates it:

| Error | Sentence |
|---|---|
| `Ash.Error.Changes.Required` | is required |
| `Ash.Error.Changes.InvalidAttribute` | is invalid |
| `Ash.Error.Changes.InvalidArgument` | is invalid |
| `Ash.Error.Forbidden.Policy` | You are not allowed to do this |

```elixir
{:error, error} = Ash.create(MyApp.Order, %{}, actor: user)
error = hd(error.errors)

error.message             #=> "обязательное поле"
Exception.message(error)  # ends with "обязательное поле"
error.field               #=> :delivery_date
error.original            #=> %Ash.Error.Changes.Required{...}
```

The error comes back as an `AshGettext.AshMessages.Translated`. It keeps
Ash's error in `original`, with its field and class. JSON:API renders the
original error with the translated sentence as `detail`.

`mix gettext.extract` adds these sentences to the template. A
policy with its own message keeps it, and that message is its msgid. A stale
record error comes from the data layer after the handler, so it is not
translated.

## Put values in a message

Write `%{name}` in the message and pass the values with `vars`:

```elixir
InvalidAttribute.exception(
  field: :weight,
  message: "must weigh at least %{min} kg",
  vars: [min: 30]
)
```

```po
msgid "must weigh at least %{min} kg"
msgstr "должен весить не меньше %{min} кг"
```

A message built with `#{...}` cannot be a msgid, because the catalog needs a
constant key. `mix gettext.extract` warns about each one so you can rewrite it
with `%{name}` and `vars`.

## Know which actions are translated

Only create, update and destroy actions are translated. Ash gives those three
an `error_handler` and gives read and generic actions none. Errors from a
read or a generic action reach the caller as written. If you need a
translated read error, translate it where you render it, with
`AshGettext.ErrorTranslation.translate/2`.

## Choose the catalog file

`text_domain` names the Gettext domain, which is the `.po` file the messages
live in. It defaults to `"ash"`, the same catalog that holds enum labels and attribute
names:

```elixir
gettext do
  backend(MyApp.Gettext)
  text_domain("shipping")
end
```

Messages are now looked up in `priv/gettext/<locale>/LC_MESSAGES/shipping.po`.

## Roll out one domain at a time

`translate_errors?` switches translation off for a domain that has a
`gettext` block:

```elixir
gettext do
  backend(MyApp.Gettext)
  translate_errors?(false)
end
```

Its resources keep their messages exactly as written. Remove the line when you
are ready.

`require_resource_extension?` is the opposite check. When `true`, compiling
the domain warns about every resource that lacks the `AshGettext.Resource`
extension:

```elixir
gettext do
  backend(MyApp.Gettext)
  require_resource_extension?(true)
end
```

The warning is an error under `mix compile --warnings-as-errors`. It is off by
default, because Ash extensions are opted into.

## Return a coded error

`AshGettext.Error` is an error with a stable `code` the client can branch on
and a `message` that is translated:

```elixir
{:error,
 AshGettext.Error.exception(
   code: :weight_too_low,
   field: :weight,
   message: "must weigh at least %{min} kg",
   vars: [min: 30]
 )}
```

`code` is required. Leaving it out raises `ArgumentError`. `field` and `vars`
are optional. The message is translated like any other, so return the error
from a create, update or destroy action.

With `:ash_json_api` installed, this error renders as:

```json
{
  "code": "weight_too_low",
  "detail": "must weigh at least 30 kg",
  "source": {"pointer": "/data/attributes/weight"},
  "meta": {"min": 30}
}
```

`code` is the atom as a string, `detail` is the translated message and `meta`
holds `vars`. There is no `title`, so no untranslated English reaches the
reader. `source.pointer` appears only when `field` is set.
