local Gradient = {}

local RESOLUTION = 16

local function lerp(a, b, t)
    return a + (b - a) * t
end

function Gradient.new(dir, c1, c2)
    dir = dir or "horizontal"

    if dir == "horizontal" then
        dir = true
    elseif dir == "vertical" then
        dir = false
    else
        error("Invalid direction '" .. tostring(dir) .. "' for gradient. Horizontal or vertical expected.")
    end

    local imageData = love.image.newImageData(dir and 1 or RESOLUTION, dir and RESOLUTION or 1)

    for i = 0, RESOLUTION - 1 do
        local perc = i / (RESOLUTION - 1)
        
        imageData:setPixel(
            dir and 0 or i,
            dir and i or 0,
            lerp(c1[1], c2[1], perc),
            lerp(c1[2], c2[2], perc),
            lerp(c1[3], c2[3], perc),
            lerp(c1[4] or 1, c2[4] or 1, perc)
        )
    end

    local result = love.graphics.newImage(imageData)
    result:setFilter("linear", "linear")

    return result
end

return Gradient