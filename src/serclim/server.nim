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
  static_path: string
  client_path: string
  port: int
  handlers*: seq[proc(meth: HttpMethod, path: seq[string], body: string): Future[Option[Response]] {.async, closure.}]


func newServerApp*(client_path: string, static_path = "static", port = 8080): ServerApp =
  ServerApp(static_path: static_path, client_path: client_path, port: port)


proc run*(app: ServerApp) =
  proc loop {.async.} =
    var server = newAsyncHttpServer()
    proc cb(req: Request) {.async, gcsafe.} =

      let path_rel = req.url.path[1 .. ^1]
      
      if path_rel == app.client_path:
        await req.respond(Http200, readFile(app.client_path))
        return

      if path_rel.startsWith(app.static_path):
        try:
          let content = readFile(path_rel)
          await req.respond(Http200, content)
        except:
          await req.respond(Http404, "Page not found")
        return

      let path = path_rel.split('/')

      for i in 0 ..< app.handlers.len:
        if Some(@res) ?= await app.handlers[i](req.reqMethod, path, req.body):
          await req.respond(
            res.code,
            case res.kind:
              of respOther: res.text
              of respHtml:
                html(
                  head(res.html.head),
                  body(script(src = ("/" & app.client_path)), res.html.body)
                )
            ,
            if res.kind == respHtml:
              newHttpHeaders({"Content-type": "text/html; charset=utf-8"})
            else: newHttpHeaders()
          )
          return

      await req.respond(Http404, "Page not found")

    server.listen(Port(app.port))
    while true:
      if server.shouldAcceptRequest():
        await server.acceptRequest(cb)
      else:
        # too many concurrent connections, `maxFDs` exceeded
        # wait 500ms for FDs to be closed
        await sleepAsync(500)

  waitFor loop()

