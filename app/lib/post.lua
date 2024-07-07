local https = require("https")
local json = require("lib.dkjson")
local USER_ID, KEY, TOKEN = unpack(require("lib.config"))

local ENDPOINT = "https://us-central1-tts-monster.cloudfunctions.net/generateTTS"

local requests_channel = love.thread.getChannel("requests")
local progress_channel = love.thread.getChannel("progress")

while true do
    local request = requests_channel:demand()
    local text, filename = request.text, request.filename

    progress_channel:push({message = "Starting download..."})

    local request_body = json.encode({
        data = {
            userId = USER_ID,
            key = KEY,
            message = text,
            ai = true,
            details = {
                provider = "streamelements",
                test = false,
                event = "channel-points",
                viewerId = nil
            }
        }
    })

    local code, body = https.request(ENDPOINT, {
        data = request_body,
        method = "POST",
        headers = {
            ["Authorization"] = "Bearer " .. TOKEN,
            ["Content-Type"] = "application/json",
            ["Content-Length"] = string.len(request_body)
        },
    })

    if code ~= 200 or not body then
        progress_channel:push({error = "Received status code " .. code})
        goto continue
    end

    local soundURL = json.decode(body).data.link

    progress_channel:push({message = "Successfully retrieved link!"})

    local code2, body2 = https.request(soundURL, {
        method = "GET"
    })

    if code2 ~= 200 or not body2 then
        progress_channel:push({error = "Received status code " .. code})
    else
        progress_channel:push({message = "Successfully downloaded file!"})

        local res, err = love.filesystem.write(filename, body2)

        if not res then progress_channel:push({error = "Error writing file: " .. err}) break end

        progress_channel:push({finished = filename})
    end

    ::continue::
end