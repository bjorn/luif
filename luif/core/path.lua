--
-- Path helper functions, can be used with core.Move and core.PathLayout
--

local Path = {}

-- a squared path with round corners
function Path.roundedSquarePath(x, y, length, radius)
    local circleOffsets = {
        { length - radius,          radius },
        { length - radius, length - radius },
        {          radius, length - radius },
        {          radius,          radius },
    }
    local lineOffsets = {
        { radius,      0 },
        { length, radius },
        { radius, length },
        {      0, radius },
    }

    local circleLength = 2*math.pi*radius
    local rectLength = 4*length - 8*radius
    local circleTime = circleLength / (4*length)
    local rectTime = rectLength / (4*length)
    local straight = (length - 2*radius) / (rectTime)

    assert(rectLength >= 0)

    return function(t)
        t = t + rectTime/8
        t = t > 1 and t - 1 or t

        local slice = math.floor(t*4)
        local section = (t-slice/4)*4

        local circleSection = section > rectTime

        if circleSection then
            t = (section - rectTime) / (1 - rectTime) / 4 + ((slice-1) * .25)
            return x + math.cos(t*2*math.pi) * radius + circleOffsets[slice+1][1],
                   y + math.sin(t*2*math.pi) * radius + circleOffsets[slice+1][2]
        else
            if slice == 2 or slice == 3 then section = rectTime-section end
            local rx = (slice == 0 or slice == 2) and straight * section or 0
            local ry = (slice == 1 or slice == 3) and straight * section or 0
            return rx + x + lineOffsets[slice+1][1], ry + y + lineOffsets[slice+1][2]
        end
    end
end

-- a path following a rectangle
function Path.rectPath(x, y, width, height)
    return function(t)
        local length = (width + height) * 2

        if t * length < width then
            local p = t / (width/length)
            return x + p * width, y + 0
        elseif t * length < width + height then
            local p = (t - (width/length)) / (height/length)
            return x + width, y + p * height
        elseif t * length < 2 * width + height then
            local p = (t - ((width+height)/length)) / (width/length)
            return x + width - (p * width), y + height
        else
            local p = (t - ((2*width+height)/length)) / (height/length)
            return x + 0, y + height - (p * height)
        end
    end
end

-- a simple circular path
function Path.circlePath(x, y, radius, offset)
    return function(t)
        return x + math.cos(t*2*math.pi+offset) * radius,
               y + math.sin(t*2*math.pi+offset) * radius
    end
end

return Path
