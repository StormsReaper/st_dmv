STDMV = STDMV or {}

function STDMV.Trim(value)
    return (tostring(value or ''):gsub('^%s*(.-)%s*$', '%1'))
end

function STDMV.NormalizePlate(plate)
    return STDMV.Trim(plate):upper()
end

function STDMV.NormalizeVin(vin)
    return STDMV.Trim(vin):upper()
end

function STDMV.SafeJsonDecode(value, fallback)
    if type(value) == 'table' then return value end
    if not value or value == '' then return fallback or {} end
    local ok, decoded = pcall(json.decode, value)
    return ok and decoded or (fallback or {})
end

function STDMV.SafeJsonEncode(value)
    local ok, encoded = pcall(json.encode, value or {})
    return ok and encoded or '{}'
end

function STDMV.RandomDigits(length)
    local out = ''
    for _ = 1, length do out = out .. tostring(math.random(0, 9)) end
    return out
end

function STDMV.RandomPlate(prefix, length)
    local chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    local out = prefix or ''
    while #out < (length or 6) do
        local i = math.random(1, #chars)
        out = out .. chars:sub(i, i)
    end
    return out:sub(1, length or 6)
end

function STDMV.Now()
    return os.date('%Y-%m-%d %H:%M:%S')
end
