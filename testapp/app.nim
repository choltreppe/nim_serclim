import serclim

server:
  import htmlgen

client:
  import std/asyncjs
  import std/dom
  import strutils


server:
  
  var app = newServerApp(client_path = "static/client.js")

  func bla: string {. ajax(app, "/blajax"), get(app, "/bla/*") .} =
    "bla"

  proc addit(a,b: int): Future[int] {. async, ajax(app, "/add") .} =
    return a + b

  proc index: Response {. route(app, "/", HttpGet) .} =
    respOk(
      form(
        input(type="text", name="a"),
        input(type="text", name="b"),
        button("calc"),
        p(id="result")
      )
    )

  proc index(uid: int64): Future[string] {. async, route(app, "/user/{uid}", HttpGet), route(app, "/{uid}", HttpGet) .} =
    return h1("hi user" & $uid)

  app.run()


client:
  
  window.addEventListener("load", proc(_: Event) =

    let form = document.forms[0]

    proc calc() {.async.} =
      echo await addit(
        ($form.elements[0].value).parse_int,
        ($form.elements[1].value).parse_int
      )

    form.addEventListener("submit", proc(ev: Event) =
      ev.prevent_default
      discard calc()
    )

  )