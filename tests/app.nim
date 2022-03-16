import serclim

server:
  import prologue
  import prologue/middlewares/staticfile
  import htmlgen

client:
  import dom
  import strutils


server:
  
  var app = newApp()

  func addit(a,b: int): int {. ajax(app, "/add") .} =
    a + b

  proc index(ctx: Context) {. get(app, "/") .} =
    resp html(
      script(src="/static/client.js"),
      form(
        input(type="text", name="a"),
        input(type="text", name="b"),
        button("calc"),
        p(id="result")
      )
    )

  app.use(staticFileMiddleware("static"))
  app.run()


client:

  window.add_event_listener("load", proc(_: Event) =

    let form = document.forms[0]

    form.add_event_listener("submit", proc(ev: Event) =
      ev.prevent_default
      addit(
        ($form.elements[0].value).parse_int,
        ($form.elements[1].value).parse_int,
        proc(res: int) = echo res
      )
    )

  )