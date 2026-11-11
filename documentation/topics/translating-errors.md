# Translating errors

## Turn it on

Add `AshGettext.Domain` with a `gettext` block to the domain, and
`AshGettext.Resource` to each resource. `mix ash_gettext.install --apply`
does both; see [Set it up once](set-up-once.md) to write them once for the
whole app. Create, update, destroy and generic actions are translated.

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
`Gettext.with_locale/3`. See [Locales](locales.md).

## Put values in a message

Write `%{name}` in the message and pass the values with `vars`:

```elixir
InvalidAttribute.exception(
  field: :weight,
  message: "must weigh at least %{min} kg",
  vars: [min: 30]
)
```

A message built with `#{...}` cannot be translated. `mix gettext.extract`
warns about each one so you can rewrite it with `%{name}` and `vars`.

## Write your own message

The `message:` is looked up in the catalog as written, so write it as the
plain sentence in your language. Do this for a policy message too. A
message with no catalog entry is left as it was.

## Choose the catalog file

`text_domain` names the `.po` file. It defaults to `"ash"`:

```elixir
gettext do
  backend(MyApp.Gettext)
  text_domain("shipping")
end
```

Messages are now looked up in `priv/gettext/<locale>/LC_MESSAGES/shipping.po`.

## Roll out one domain at a time

`translate_errors? false` leaves a domain's messages exactly as written.
Remove the line when you are ready:

```elixir
gettext do
  backend(MyApp.Gettext)
  translate_errors?(false)
end
```

## Return a coded error

`AshGettext.Error` has a stable `code` the client can branch on and a
translated `message`:

```elixir
{:error,
 AshGettext.Error.exception(
   code: :weight_too_low,
   field: :weight,
   message: "must weigh at least %{min} kg",
   vars: [min: 30]
 )}
```

`code` is required. `field` and `vars` are optional. Return it from any
action but a read. Over JSON:API it renders as:

```json
{
  "code": "weight_too_low",
  "detail": "must weigh at least 30 kg",
  "source": {"pointer": "/data/attributes/weight"},
  "meta": {"min": 30}
}
```

## What is not translated

- A policy's custom message. A direct Ash call shows it. Over JSON:API and
  GraphQL the reader gets the general "You are not allowed to do this"
  sentence, and a Phoenix form shows no error for a policy failure.
- GraphQL's own query checks and "Something went wrong. Error id: ..."
  replies stay in English.
- Errors from a direct `Ash.bulk_destroy` call stay in the source language.
  Over JSON:API and GraphQL they are translated.
- An action with its own `error_handler` is not translated.
- A read action's error is not translated when you call it directly. Use
  `AshGettext.ErrorTranslation.translate/2` where you render it.

An `error_handler` you wrote on a JSON:API or GraphQL domain keeps running.

`Ash.Error.Changes.Required` has no `message`. Its translated sentence is in
`vars[:translation]`. Read it from there when you render errors yourself, for
example in a Phoenix form.
