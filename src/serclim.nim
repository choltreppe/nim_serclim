import jsony
import fusion/matching
export matching
export jsony.toJson, jsony.fromJson

#const serclimClientFile* {.strdefine.} = "client.js"

when defined(js):
  import serclim/client
  export client

else:
  import serclim/server
  export server