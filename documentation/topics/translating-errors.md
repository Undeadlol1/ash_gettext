# Translating errors

This page covers what AshGettext translates, how a message becomes a msgid,
and how to roll translation out one domain at a time.

## Replace a per-action error handler

Without AshGettext, each write action needs its own handler:

```elixir
create :register do
  accept [:email]
  error_handler {MyApp.Errors, :translate, []}
end
```

With the `AshGettext.Resource` extension, delete the handler. The extension
adds it to every create, update and destroy action, including actions you add
later:

```elixir
use Ash.Resource, extensions: [AshGettext.Resource]
```

An action that declares its own `error_handler` keeps it. AshGettext does not
replace it.

## The message is the msgid

An error's `message:` is looked up in the catalog as written:

```elixir
validate present(:email), message: "can't be blank"
```

If the catalog for the reader's locale has an entry, the entry replaces the
message. If it has none, the message is left as it was. Adding AshGettext can
add translations. It never changes a message that has no entry.

The source language needs no catalog. The `.po` files hold only the other
languages. See [Getting started](getting-started.md#write-a-message-in-your-own-language).

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
constant key. `mix ash_gettext.extract` lists each one so you can rewrite it
with `%{name}` and `vars`.

## Know which actions are translated

Only create, update and destroy actions are translated. Ash gives those three
an `error_handler` and gives read and generic actions none. Errors from a
read or a generic action reach the caller as written. If you need a
translated read error, translate it where you render it, with
`AshGettext.ErrorTranslation.translate/2`.

## Choose the catalog file

`text_domain` names the Gettext domain, which is the `.po` file the messages
live in. It defaults to `ash_errors`:

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
   message: "weight too low, the minimum is %{min} kg",
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
  "title": "Rejected",
  "detail": "weight too low, the minimum is 30 kg",
  "source": {"pointer": "/data/attributes/weight"},
  "meta": {"min": 30}
}
```

`code` is the atom as a string, `detail` is the translated message and `meta`
holds `vars`. `source.pointer` appears only when `field` is set.

## Translate a string outside an error

Three functions translate text that is not an error. The locale is an
argument, so they need no process setup:

```elixir
AshGettext.translate(MyApp.Gettext, "ash_errors", "Saved", [], "ru")
#=> "Сохранено"

AshGettext.translate_plural(
  MyApp.Gettext,
  "ash_errors",
  "%{count} parcel",
  "%{count} parcels",
  3,
  [],
  "ru"
)
#=> "3 посылки"

AshGettext.enum_label(MyApp.Gettext, "ash_errors", :status, :awaiting_pickup, "ru")
#=> "Ожидает выдачи"
```

`enum_label/5` looks up the msgid `status.awaiting_pickup`. If the catalog has
no entry, it returns `"Awaiting pickup"`, so a screen never shows a raw key.
`translate_plural/7` takes the same arguments as Gettext's `dngettext`, with
the backend and the locale added.

Each function has an `_or_missing` twin that returns `{:ok, string}` or
`{:missing, string}`. Use it when you need to know whether the catalog covered
the string; `AshGettext.Testing` is built on it.
