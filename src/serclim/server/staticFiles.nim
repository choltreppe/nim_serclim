import serclim/server

proc serveStaticFiles*(app: var ServerApp, path: string) =
  app.handlers.add(proc(meth: HttpMethod, pathSeq: seq[string], body, queryStr, cookieStr: string): Future[Option[Response]] {.async.} =
    let filePath = pathSeq.join("/")
    if meth == HttpGet and filePath.startsWith(path):
      try:    return some(respTextOk(readFile(filePath)))
      except: discard
    return none(Response)
  )