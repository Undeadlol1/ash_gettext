# Translating text

This page covers translating your own text: enum values, strings,
placeholders, plurals and attribute names.

The text a user reads is written by a person. AshGettext never makes it from
a code name, so `:awaiting_pickup` is not turned into "Awaiting pickup" for
you.

## Translate an enum

`use AshGettext.Enum` takes the values and makes the Ash enum for you:

```elixir
defmodule MyApp.Order.Status do
  use AshGettext.Enum,
    backend: MyApp.Gettext,
    values: [
      placed: [label: "Order placed"],
      awaiting_pickup: [label: "Ready for pickup", description: "Ready at the pickup point"]
    ]
end

MyApp.Order.Status.label(:awaiting_pickup)
#=> "Ожидает выдачи"
```

`label/1` and `description/1` are Ash's own functions. They now return the
translated text. `:backend` and `:values` are required. `:text_domain` is the
catalog file and defaults to `"ash"`.

The key is the `label:` you wrote on the value. Every value needs one: a value
without it fails to compile, and the error lists those values. A description
is optional, and its key is the description:

```po
# priv/gettext/ru/LC_MESSAGES/ash.po
msgid "Ready for pickup"
msgstr "Ожидает выдачи"

msgid "Ready at the pickup point"
msgstr "Готов к выдаче в пункте"
```

The language is Gettext's current locale for the process. Set it with
`Gettext.put_locale/2`, or for one block with `Gettext.with_locale/3`:

```elixir
Gettext.with_locale(MyApp.Gettext, "ru", fn ->
  MyApp.Order.Status.label(:awaiting_pickup)
end)
```

With no translation, you get the label as written. A value without a
description still returns `nil`, and so does an empty value (`nil`). `details/1` is Ash's own and is not
translated.

## Show an enum on a record

Every attribute whose type uses `AshGettext.Enum` gets a field named
`<attribute>_label`. Load it to get the translated label on the record:

```elixir
order = Ash.get!(MyApp.Order, id, load: [:status_label], actor: user)

order.status        #=> :awaiting_pickup
order.status_label  #=> "Ожидает выдачи"
```

An empty value gives `nil`, a list attribute gives a list of labels, and a
field you already named `status_label` is left alone.

## The text is the key

Write the text in your app's own language. Gettext looks it up as written:

```elixir
AshGettext.translate(MyApp.Gettext, "default", "Order shipped", [], "ru")
#=> "Заказ отправлен"
```

```po
# priv/gettext/ru/LC_MESSAGES/default.po
msgid "Order shipped"
msgstr "Заказ отправлен"
```

In your own language the text is also the translation, so that language
needs no `.po` file. Your own language is the backend's default locale, `en`
unless you set another.

With no translation, `translate/5` returns the text as you wrote it.

## Choose the catalog file

The text domain, the second argument, is the name of the `.po` file.
`"default"` reads `default.po`. Use another name to keep a part of the app in
its own file:

```elixir
AshGettext.translate(MyApp.Gettext, "shipping", "Order shipped", [], "ru")
# reads priv/gettext/ru/LC_MESSAGES/shipping.po
```

## Put values in the text

Write `%{name}` in the text and pass the values:

```elixir
AshGettext.translate(MyApp.Gettext, "default", "Hello, %{name}", [name: "Ann"], "ru")
#=> "Привет, Ann"
```

```po
msgid "Hello, %{name}"
msgstr "Привет, %{name}"
```

Do not build the text with `#{...}`. The key has to be the same every time.

## Translate a count

`translate_plural/7` takes the singular, the plural and the count. The count
is always available as `%{count}`:

```elixir
AshGettext.translate_plural(MyApp.Gettext, "default", "%{count} parcel", "%{count} parcels", 3, [], "ru")
#=> "3 посылки"
```

```po
msgid "%{count} parcel"
msgid_plural "%{count} parcels"
msgstr[0] "%{count} посылка"
msgstr[1] "%{count} посылки"
msgstr[2] "%{count} посылок"
```

Each language has its own number of plural forms. Gettext picks the right
one.

## Show an attribute name

Write the text in the resource's `gettext` block:

```elixir
gettext do
  label :date_of_birth, "Date of birth"
end
```

Then ask for it:

```elixir
Gettext.with_locale(MyApp.Gettext, "ru", fn ->
  AshGettext.attribute_label(MyApp.Order, :date_of_birth)
end)
#=> "Дата рождения"
```

The language is Gettext's current one; the backend and text domain come from
the resource's domain.

```po
# priv/gettext/ru/LC_MESSAGES/ash.po
msgid "Date of birth"
msgstr "Дата рождения"
```

The key is the text you wrote. An attribute with no written `label` raises
`ArgumentError`, and so does one the resource does not have. A `label` for an
attribute the resource does not have fails the build.

## Know when a translation is missing

`translate/5` falls back to the text, so a missing translation looks like a
working one. Two ways to find out.

Every miss sends a telemetry event, `[:ash_gettext, :translation, :missing]`,
with the `backend`, `text_domain`, `msgid` and `locale` in its metadata. Log
it, or count it:

```elixir
:telemetry.attach(
  "ash-gettext-missing",
  [:ash_gettext, :translation, :missing],
  &MyApp.Telemetry.log_missing/4,
  nil
)
```

Or ask in code. The pure functions have an `_or_missing` twin that tells you:

```elixir
AshGettext.translate_or_missing(MyApp.Gettext, "default", "Order lost", [], "ru")
#=> {:missing, "Order lost"}
```

The twins are `translate_or_missing/5`, `translate_plural_or_missing/7`
and `attribute_label_or_missing/2`. They send no
event. In your own language nothing is missing. In tests, use
`AshGettext.Testing`. See [How to test with AshGettext](testing.md).

## Get the language from the user

Run an action with `actor:` (or `context: %{locale: "ru"}`) and AshGettext
sets Gettext's language for that process. Enums, errors and attribute names
then come out in it. To turn what a browser sends, such as `ru_RU`, or the
signed-in user into a language your catalogs have, see [Locales](locales.md).

## Add the text to the template

`mix gettext.extract` finds only Gettext macro calls. Text you pass to
`translate/5` is not one, so keep the text in a Gettext macro such as
`dgettext_noop/2`.

Enum labels, enum descriptions and attribute labels are different:
AshGettext shows them to `mix gettext.extract`, so they are collected. See [Extracting messages](extracting-messages.md).
