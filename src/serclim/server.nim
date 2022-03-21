import std/options
import std/marshal
import std/httpcore
import std/asynchttpserver
import std/asyncdispatch
import std/htmlgen

include server/routing
import server/response

export strutils, options, marshal, asyncdispatch, httpcore
export response


# ignore client. keep server
macro client*(_: untyped): untyped = discard
macro server*(body: untyped): untyped = body


type ServerApp* = object
  client_path: string
  port: int
  handlers*: seq[proc(meth: HttpMethod, path: seq[string], body: string): Future[Option[Response]] {.async, closure.}]


func newServerApp*(client_path: string, port = 8080): ServerApp =
  ServerApp(client_path: client_path, port: port)


proc run*(app: ServerApp) =
  proc loop {.async.} =
    var server = newAsyncHttpServer()
    proc cb(req: Request) {.async, gcsafe.} =
      
      echo req.url.path[1 .. ^1] & "  " & app.client_path
      if req.url.path[1 .. ^1] == app.client_path:
        await req.respond(Http200, readFile(app.client_path), newHttpHeaders())
        return

      let headers = {"Content-type": "text/html; charset=utf-8"}
      let path = req.url.path[1 .. ^1].split('/')

      for i in 0 ..< app.handlers.len:
        if Some(@res) ?= await app.handlers[i](req.reqMethod, path, req.body):
          await req.respond(
            Http200,
            case res.kind:
              of respOther: res.text
              of respHtml:
                html(
                  head(res.html.head),
                  body(script(src = ("/" & app.client_path)), res.html.body)
                )
            ,
            headers.newHttpHeaders()
          )
          return

      await req.respond(Http404, "Page not found", headers.newHttpHeaders())

    server.listen(Port(app.port))
    while true:
      if server.shouldAcceptRequest():
        await server.acceptRequest(cb)
      else:
        # too many concurrent connections, `maxFDs` exceeded
        # wait 500ms for FDs to be closed
        await sleepAsync(500)

  waitFor loop()

