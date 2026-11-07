# Translating text

This page covers translating your own text: strings, placeholders, plurals,
enum labels and attribute names. You call them through a translator module,
so a call site says what to translate and nothing else.

## Set up a translator

```elixir
defmodule MyApp.Translator do
  use AshGettext.Translator,
    backend: MyApp.Gettext,
    locale_resolvers: [MyApp.Locale.FromActor, AshGettext.Locale.FromContext],
    default_locale: "en"
end
```

`backend` is required. `locale_resolvers` defaults to
`[AshGettext.Locale.FromContext]` and `default_locale` to the backend's own
language. The module gets `translate/3`, `translate_plural/5`, `enum_label/3`,
`attribute_label/3` and `locale/1`.

Every function takes options last:

- `locale:` is an explicit language. It beats the resolvers.
- `actor:` is handed to the resolvers.
- `context:` is a map merged into what the resolvers get.
- `text_domain:` is the catalog file. Text defaults to `"default"`. Enum
  labels and attribute names default to `"ash"`.

## The text is the key

Write the text in your app's own language. Gettext looks it up as written:

```elixir
MyApp.Translator.translate("Order shipped", [], locale: "ru")
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

With no translation, `translate/3` returns the text as you wrote it.

## Choose the catalog file

The `text_domain` option is the name of the `.po` file. `"default"` reads
`default.po`. Use another name to keep a part of the app in its own file:

```elixir
MyApp.Translator.translate("Order shipped", [], locale: "ru", text_domain: "shipping")
# reads priv/gettext/ru/LC_MESSAGES/shipping.po
```

## Put values in the text

Write `%{name}` in the text and pass the values:

```elixir
MyApp.Translator.translate("Hello, %{name}", [name: "Ann"], locale: "ru")
#=> "Привет, Ann"
```

```po
msgid "Hello, %{name}"
msgstr "Привет, %{name}"
```

Do not build the text with `#{...}`. The key has to be the same every time.

## Translate a count

`translate_plural/5` takes the singular, the plural and the count. The count
is always available as `%{count}`:

```elixir
MyApp.Translator.translate_plural("%{count} parcel", "%{count} parcels", 3, [], locale: "ru")
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

## Show an enum value

An Ash enum value like `:awaiting_pickup` is not text a user should see.
Pass the enum module and the value:

```elixir
MyApp.Translator.enum_label(MyApp.Status, :awaiting_pickup, actor: user)
#=> "Ожидает выдачи"
```

The key is the enum's own label for the value. By default that is the value
in words, "Awaiting pickup". A `label:` on the value changes it:

```elixir
defmodule MyApp.Status do
  use Ash.Type.Enum,
    values: [
      pending: [],
      awaiting_pickup: [label: "Ready to collect"]
    ]
end
```

```po
# priv/gettext/ru/LC_MESSAGES/ash.po
msgid "Ready to collect"
msgstr "Ожидает выдачи"
```

With no translation, you get the label. A screen never shows the raw value.
A value the enum does not have raises `ArgumentError`.

## Show an attribute name

```elixir
MyApp.Translator.attribute_label(MyApp.Order, :date_of_birth, actor: user)
#=> "Дата рождения"
```

```po
# priv/gettext/ru/LC_MESSAGES/ash.po
msgid "Date of birth"
msgstr "Дата рождения"
```

The key is the attribute name in words. `AshGettext.attribute_msgid/1` gives
it. An attribute the resource does not have raises `ArgumentError`.

## Know when a translation is missing

`translate/3` falls back to the text, so a missing translation looks like a
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

The twins are `translate_or_missing/5`, `translate_plural_or_missing/7`,
`enum_label_or_missing/5` and `attribute_label_or_missing/5`. They send no
event. In your own language nothing is missing. In tests, use
`AshGettext.Testing`. See [How to test with AshGettext](testing.md).

## Use the pure functions

The translator is a thin layer over `AshGettext.translate/5` and its
siblings. They take the backend, the text domain and the language as
arguments, and read nothing from the process:

```elixir
AshGettext.translate(MyApp.Gettext, "default", "Order shipped", [], "ru")
#=> "Заказ отправлен"
```

## Get the language from the user

To turn what a browser sends, such as `ru_RU`, or the signed-in user into a
language your catalogs have, see [Locales](locales.md).

## Add the text to the template

`mix gettext.extract` finds only Gettext macro calls. Text you pass to
`translate/3` is not one, and `mix ash_gettext.extract` does not see it
either. Add it to your `.pot` file by hand, or keep the text in a Gettext
macro such as `dgettext_noop/2`.

Enum labels and attribute names are different: `mix ash_gettext.extract`
collects them. See [Extracting messages](extracting-messages.md).
