import serclim

server:
  import htmlgen
  import serclim/server/[cookies, staticfiles]

client:
  import std/asyncjs
  import std/dom
  import strutils


server:

  var app = newServerApp()

  app.serveStaticFiles("static")

  proc add(a,b: int  ): int   {. ajax(app) .} = a + b
  proc add(a,b: float): float {. ajax(app) .} = a + b

  proc addGui: Response {. get(app, "/add") .} =
    respOk(
      head = link(rel="stylesheet", `type`="text/css", href="/static/style.css"),
      body =
        form(
          onsubmit="event.preventDefault(); calc(this)",
          input(type="text", name="a"),
          "+",
          input(type="text", name="b"),
          button("calc"),
          p(id="result")
        )
    )

  proc addUrl(a,b: int): string {. get(app, "/add/@a/@b") .} =
    $add(a, b)


  func testDefault(a: string, b = "b", c = "c"): string {.get(app, "/dtestab/@a/@b"), get(app, "/dtestac/@a/@c").} =
    a & b & c
 
  func bodyParsingTest(x: Body[int]): string {.get(app, "/testbody").} =
    if x < 0: "negative"
    else: "positive"


  proc testCookies(cookies: var CookieJar): string {.get(app, "/cookies").} =
    cookies.del("cookieA")
    cookies["cookieB"] = "foo"
    "ok"


  type
    TestEnum = enum teA, teB
    TestObj = object
      case kind: TestEnum
        of teA: a: int
        of teB: b: float
      c: string

  proc testJson(obj: Body[Json[TestObj]]): string {.get(app, "/json").} =
    case obj.kind
      of teA: "a+1=" & $(obj.a + 1) & ", c=" & obj.c
      of teB: "b/2=" & ($(obj.b / 2.0))[0 .. 3] & ", c=" & obj.c


  type FormTest = object
    a: int
    b: float
    c: string
    d: TestEnum

  proc testForm(data: Form[FormTest]): string {.get(app, "/form"), post(app, "/form").} =
    echo data
    "ok"


  run app


client:

  proc calc(this: FormElement) {.async, exportc.} =
    let res =
      try:
        await(add(
          ($this.elements[0].value).parseInt,
          ($this.elements[1].value).parseInt
        )).`$`.cstring
      except:
        await(add(
          ($this.elements[0].value).parseFloat,
          ($this.elements[1].value).parseFloat
        )).`$`.cstring

    document.getElementById("result").innerHTML = res

