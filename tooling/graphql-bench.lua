local _M = {}

local json = require "json"

local function file_exists(file)
  local f = io.open(file, "r")
  if f~=nil then
    local content = f:read("*all")
    io.close(f)
    return content
  else
    error("file not found: " .. file)
  end
end

function _M.init(args)
  -- args[0] is the url
  local queryFile = args[1]
  local operationName = args[2]
  local query = file_exists(queryFile)
  return json.encode({query=query,operationName=operationName})
end

local function get_stat_summary(stat)
  local dist = {}
  for _, p in pairs({ 95, 98, 99 }) do
    dist[tostring(p)] = stat:percentile(p)
  end
  return {
    min=stat.min,
    max=stat.max,
    stdev=stat.stdev,
    mean=stat.mean,
    dist=dist
  }
end

function _M.done(summary, latency, requests)
  io.stderr:write(
    json.encode({
        latency=get_stat_summary(latency),
        summary=summary,
        requests=get_stat_summary(requests)
    })
  )
  io.stderr:write('\n')
end

return _M
