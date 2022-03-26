import serclim

server:
  import htmlgen

client:
  import std/asyncjs
  import std/dom
  import strutils


server:

  var app = newServerApp(clientPath = "client.js")

  func add(a,b: int): int {. ajax(app, "/ajax/add") .} =
    a + b

  proc addGui: Response {. get(app, "/add") .} =
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

  func addUrl(a,b: int): string {. get(app, "/add/{a}/{b}") .} =
    $add(a, b)


  func testDefault(a: string, b = "b", c = "c"): string {.get(app, "/dtestab/{a}/{b}"), get(app, "/dtestac/{a}/{c}").} =
    a & b & c
 
  func bodyParsingTest1(x: Body[int]): string {.get(app, "/testbody").} =
    if x < 0: "negative"
    else: "positive"

  type TestType = enum testA, testB
  func bodyParsingTest2(x: Body[Json[TestType]]): string {.get(app, "/testjson").} =
    case x:
      of testA: "a"
      of testB: "b"


  run app


client:

  proc calc(this: FormElement) {.async, exportc.} =
    let res = await add(
      ($this.elements[0].value).parseInt,
      ($this.elements[1].value).parseInt
    )
    document.getElementById("result").innerHTML = res.`$`.cstring

