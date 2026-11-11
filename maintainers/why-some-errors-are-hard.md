# Why some errors are hard to translate

Most errors are easy: the error holds a sentence, and AshGettext swaps it for
the reader's. A few are not, and the reasons are in Ash and its transports,
not in your app. This page says which ones, why, and what the library does
about each.

"Transport" here means whatever sends an error to the reader: AshJsonApi,
AshGraphql, an AshPhoenix form.

## The short version

| Where the text comes from | Example | Translated | Whose language |
|---|---|---|---|
| The error has a text field | "must weigh at least 30 kg", "is invalid" | In the error, for every transport | The actor's |
| The error has no text field | Ash's own "is required" | Carried in `vars[:translation]`, for Phoenix forms and any transport that passes `vars` on | The actor's |
| The transport writes it | AshJsonApi's "is required" from its body check, "No note record found with ..." | In the reply, per transport | The request's actor's |
| A read action fails | a filter or argument error on a read | In the reply, per transport | The request's actor's |

None of these need setup from you; see
[the request's language](#the-request-s-language).

## Kind 1: the error has a text field

`Ash.Error.Changes.InvalidAttribute` has a `message`. So do most errors a
validation or a change returns, and so does `AshGettext.Error`. A failed
policy has `custom_message`.

AshGettext installs an `error_handler` on every create, update, destroy and
generic action of a resource that uses `AshGettext.Resource`. Ash calls it
with each error and the actor. The handler looks the message up and writes
the translation back into the same field.

The error keeps its type. Every transport reads that field, so every
transport, including one written next year, sends the reader's sentence.
This is the only kind that needs no code per transport.

## Kind 2: the error has no text field

`Ash.Error.Changes.Required` stores the name of the missing field and
nothing else:

```elixir
%Ash.Error.Changes.Required{field: :delivery_date, type: :attribute}
```

There is no sentence in it to replace. Ash builds "attribute delivery_date
is required" from the field name when the error is printed, and each
transport ignores even that and writes its own "is required".

About 60 of Ash's 84 error types are like this. Most report a programming
mistake and never reach a reader. `Required` is the one that does.

### Why not replace the error with one that has a text field

Version 0.1.0 did. It returned its own struct in place of Ash's. Two things
broke:

- Code that matched `%Ash.Error.Changes.Required{}` stopped matching. Elixir
  has no subclasses: a struct is recognised by its one exact name.
- Each transport picks how to show an error by that same name. A struct it
  had never heard of was dropped: AshPhoenix forms showed no error at all.

So the error must stay Ash's own struct.

### What the library does

Every Ash error has a `vars` list for extra values. The handler puts the
translated sentence there and leaves the rest alone:

```elixir
{:error, error} = Ash.create(MyApp.Order, %{}, actor: russian_user)

hd(error.errors)
#=> %Ash.Error.Changes.Required{
#     field: :delivery_date,
#     vars: [translation: "обязательное поле"]
#   }
```

Values your app put in `vars` stay. Every transport passes `vars` on:
AshJsonApi as `meta`, AshGraphql as `vars`, AshPhoenix as the third element
of the form error. AshPhoenix writes "is required" itself and passes the
vars, so a Phoenix form can show this sentence. JSON:API and GraphQL write
their own "is required" and look it up in your catalog in the reader's
language (kind 3); they do not read `vars[:translation]`.

## Kind 3: the transport writes the text

Some text never exists in an Ash error at all.

**AshJsonApi checks the request body before it runs any action.** Post a
record with a required attribute left out and AshJsonApi answers
"is required" from its own schema check. No Ash action ran, no Ash error
was made, and no error handler was called. This is the usual way a reader
meets "is required" over JSON:API.

**AshJsonApi bakes values into some sentences.** A record that is not there
reads "No note record found with `id: 37edd50d-...`". The id changes every
time, so the sentence can never be looked up in a catalog.

**Read actions have no `error_handler` in Ash.** Their errors skip the
handler of kind 1.

Such text can only be translated after the transport wrote it. The rules for
that are in `AshGettext.TransportText` and know nothing about any transport:

1. Look the text up as a msgid, in the reader's language.
2. Look up the written sentence for the error's code (for baked-in values).
3. Otherwise leave the text exactly as it was.

### How it is switched on

You write nothing. A domain with a `gettext` block that also uses
`AshJsonApi.Domain` or `AshGraphql.Domain` gets an `error_handler` in its
`json_api` or `graphql` section. One transformer,
`AshGettext.Domain.Transformers.TranslateReplies`, sets both when your
domain compiles. For JSON:API it is the same as writing this yourself:

```elixir
json_api do
  error_handler {AshGettext.JsonApi, :translate_error, []}
end
```

AshJsonApi then calls this for every error in a reply:

```elixir
# lib/ash_gettext/json_api.ex
def translate_error(%AshJsonApi.Error{} = error, %{domain: domain}) do
  %{
    error
    | detail:
        AshGettext.TransportText.translate(error.detail, domain,
          code: error.code,
          bindings: error.meta
        )
  }
end
```

Only `detail` changes. An `error_handler` you already had runs first, and
what it returns is then translated. `translate_errors? false` leaves the
domain as it was.

### GraphQL

`AshGettext.Graphql` does the same for GraphQL. It translates `message` and
`short_message`, and keeps `code`, `fields` and `path`. AshGraphql hands the
handler the actor directly, so the domain's `locale_resolver` picks the
language.

### The request's language

AshJsonApi calls an error handler with the domain and the resource. It does
not say who the actor is. So the library notes the actor itself: when a
request enters your router, `AshGettext.JsonApi` reads the actor
(`Ash.PlugHelpers.get_actor/1`) from the event `Plug.Router` sends, and the
domain's `locale_resolver` picks that actor's language. There is nothing to
add to your app. With no actor, Gettext's current language is used.

### Phoenix forms

AshPhoenix forms read the error's own text field, so kind 1 is translated
there. For "is required" the form shows the sentence from `vars[:translation]`
(kind 2).

### Another transport

For any other transport, call the same rules from its error hook:

```elixir
AshGettext.TransportText.translate(error.message, domain,
  code: error.code,
  bindings: error.vars,
  actor: context[:actor]
)
```

A transport that tells its hook who the actor is needs nothing more.

## When Ash adds an error

- **In your app, nothing breaks.** An error the library has never seen is
  handled by the rules above: translated if your catalog has its text, sent
  as written if not. Nothing raises.
- **In this library, a test fails.** It reads AshJsonApi's source and fails
  when an update adds a fixed sentence that is not listed for translators.
  It runs in the library's own checks, never in yours.
- **New Ash sentences arrive on the next extract.** `mix gettext.extract`
  reads Ash's own list of sentences, so a sentence added in a later Ash release
  lands in yours the next time you run it.

## Known limits

- A policy's custom message is shown by a direct Ash call. JSON:API and
  GraphQL write their own "forbidden" text, so the reader gets the general
  "You are not allowed to do this" sentence there. Phoenix forms show no
  error for a policy failure: AshPhoenix drops it.
- `validate match(...)` with no `message:` makes a text with the pattern in
  it ("must match ~r/.../"). That cannot be a msgid. Write your own
  `message:`.
- GraphQL checks the document against the schema before Ash runs. Those
  Absinthe errors are not translated. JSON:API's unknown-error reply
  ("Something went wrong. Error id: ...") is not translated either.
- An error type the library has never seen passes through unchanged, on
  every transport.

## What would remove the hard part

Two changes outside this library:

- Ash's errors carry their own text (a `message` on `Required` and the
  like) and the transports read it. Then kind 2 becomes kind 1.
- AshJsonApi passes the actor to its `error_handler`. Then the library
  would not need to note the actor itself.
