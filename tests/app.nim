import serclim

server:
  import std/httpcore
  import htmlgen

client:
  import std/asyncjs
  import std/dom
  import strutils


server:
  
  var app = newServerApp()

  func bla: string {. ajax(app, "/blajax"), route(app, "/bla", HttpGet) .} = "bla"

  func addit(a,b: int): int {. ajax(app, "/add") .} =
    a + b

  proc clientjs: string {. route(app, "/static/client.js", HttpGet) .} =
    readFile("static/client.js")

  proc index: string {. route(app, "/", HttpGet) .} =
    html(
      script(src="/static/client.js"),
      form(
        input(type="text", name="a"),
        input(type="text", name="b"),
        button("calc"),
        p(id="result")
      )
    )

  proc index(uid: int64): string {. route(app, "/user/{uid}", HttpGet), route(app, "/{uid}", HttpGet) .} =
    h1("hi user" & $uid)

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