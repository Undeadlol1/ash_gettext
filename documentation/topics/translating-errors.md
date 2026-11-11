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
for that resource's create, update, destroy and generic actions.

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

Run the action with `actor:`. The error comes back in the actor's language:

```elixir
MyApp.Shipping.Parcel
|> Ash.Changeset.for_create(:create, %{weight: 5}, actor: user)
|> Ash.create()
# {:error, %Ash.Error.Invalid{errors: [%{message: "должен весить не меньше 30 кг"}]}}
```

With no actor, Gettext's current language is used, so wrap the call in
`Gettext.with_locale/3`. No action changes the process language. The
domain's resolver reads the language off the actor; see [Locales](locales.md).
A resolver must not query the database.

## No handler on each action

Without AshGettext, each write action needs its own handler, and a new
action ships untranslated if someone forgets it:

```elixir
create :register do
  accept [:email]
  error_handler {MyApp.Errors, :translate, []}
end
```

The resource extension adds the handler to every create, update, destroy
and generic action, including actions you add later. An action that declares its own
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
value that does not cast reads "Invalid value provided for count". AshGettext
gives each one a written English sentence and translates it into the error's
own text field, so the error stays Ash's own struct:

| Error | Sentence |
|---|---|
| `Ash.Error.Changes.Required` | is required |
| `Ash.Error.Changes.InvalidAttribute` | is invalid |
| `Ash.Error.Changes.InvalidArgument` | is invalid |
| `Ash.Error.Forbidden.Policy` | You are not allowed to do this |

```elixir
{:error, error} = Ash.create(MyApp.Order, %{count: "abc"}, actor: user)

hd(error.errors)
#=> %Ash.Error.Changes.InvalidAttribute{field: :count, message: "неверное значение"}
```

The sentence goes into `message`, or into `custom_message` for a policy.
JSON:API, GraphQL and AshPhoenix forms read that field, and code that matches
on Ash's structs keeps working.

`Ash.Error.Changes.Required` has no text field. It stays Ash's own struct
and carries the sentence in its `vars`, next to any values of yours:

```elixir
%Ash.Error.Changes.Required{field: :delivery_date, vars: [translation: "обязательное поле"]}
```

AshPhoenix passes `vars` on, so a Phoenix form can show it. See
[Why some errors are hard to translate](why-some-errors-are-hard.md).

`mix gettext.extract` adds these sentences to the template. A
policy with its own message keeps it, and that message is its msgid. A stale
record error comes from the data layer after the handler, so it is not
translated.

## Translate what JSON:API writes

AshJsonApi writes the text of some errors itself, after every error handler
has run: "is required" for a missing value, "No note record found with ..."
for a record that is not there. Errors from reads never reach an action's
error handler at all. So the reply is translated in one more place.

There is nothing to add to the domain. One with a `gettext` block that also
uses `AshJsonApi.Domain` gets `AshGettext.JsonApi` as its `error_handler`.

The reply is written in the actor's language. AshJsonApi does not tell an
error handler who the actor is, so the library notes it when the request
enters your router, and your `locale_resolver` picks the language. There is
nothing to add. With no actor, Gettext's current language is used.

Only `detail` changes. `code`, `title`, `meta`, the source pointer and the
status stay as they were. The `detail` is looked up as a msgid. If your
catalog has no entry, the written sentence for the error's `code` is tried
(see `AshGettext.AshMessages`). With neither, the reply goes out as
AshJsonApi wrote it. A reader in your own language always gets AshJsonApi's
text unchanged.

An `error_handler` you wrote keeps running. It is called first, and the
error it returns is then translated. `translate_errors? false` switches all
of this off for the domain.

### GraphQL

A domain with a `gettext` block that also uses `AshGraphql.Domain` gets
`AshGettext.Graphql` as its `error_handler`, with nothing to add. It translates
`message` and `short_message` of every error in the reply. Unlike JSON:API,
AshGraphql hands the handler the request's context, so the actor is known and
the domain's `locale_resolver` picks the language. A handler
you wrote still runs first. Errors Absinthe raises before Ash runs ("Argument
... has invalid value") are not Ash's and are not translated.

### Phoenix forms

An AshPhoenix form reads the error's own text field, so the translated
`message` shows with nothing to set up. For "is required" AshPhoenix writes
the text itself and passes `vars`, which hold the translated sentence under
`:translation`. A failed policy shows no error in a form: AshPhoenix drops it.

### Another transport

The rules are not JSON:API's. They live in `AshGettext.TransportText`, and
any transport that writes its own error text can use them from its error
hook:

```elixir
AshGettext.TransportText.translate(error.message, domain,
  code: error.code,
  bindings: error.vars,
  actor: context[:actor]
)
```

A transport that sends the error's own `message` needs nothing: that message
is already translated in the error.

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

Create, update, destroy and generic (`action`) actions are translated. Ash
gives those an `error_handler` and gives read actions none, so an error from
a read reaches the caller as written. Over JSON:API the reply is translated
anyway (see above). Elsewhere, translate a read error where you render it,
with `AshGettext.ErrorTranslation.translate/2`.

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
from any action but a read.

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
