import serclim

server:
  import htmlgen

client:
  import std/asyncjs
  import std/dom
  import strutils



server:

  var app = newServerApp(client_path = "client.js")

  proc addIndex: Response {. get(app, "/add") .} =
    respOk(
      link(rel="stylesheet", `type`="text/css", href="/static/style.css"),
      form(
        onsubmit="event.preventDefault(); calc(this)",
        input(type="text", name="a"),
        "+",
        input(type="text", name="b"),
        button("calc"),
        p(id="result")
      )
    )

  proc add(a,b: int): int {. ajax(app, "/ajax/add") .} =
    return a + b

  run app


client:

  proc calc(this: FormElement) {.async, exportc.} =
    let res = await add(
      ($this.elements[0].value).parse_int,
      ($this.elements[1].value).parse_int
    )
    document.getElementById("result").innerHTML = res.`$`.cstring

