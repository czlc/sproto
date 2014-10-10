local print = print
local tconcat = table.concat
local tinsert = table.insert
local srep = string.rep
local type = type
local pairs = pairs
local tostring = tostring
local next = next

local function print_r(root)
	local cache = {  [root] = "." }
	local function _dump(t,space,name)
		local temp = {}
		for k,v in pairs(t) do
			local key = tostring(k)
			if cache[v] then
				tinsert(temp,"+" .. key .. " {" .. cache[v].."}")
			elseif type(v) == "table" then
				local new_key = name .. "." .. key
				cache[v] = new_key
				tinsert(temp,"+" .. key .. _dump(v,space .. (next(t,k) and "|" or " " ).. srep(" ",#key),new_key))
			else
				tinsert(temp,"+" .. key .. " [" .. tostring(v).."]")
			end
		end
		return tconcat(temp,"\n"..space)
	end
	print(_dump(root, "",""))
end

local function print_r(root)
	local cache = {  [root] = "." }
	local ret = ""
	
	local function _new_line(level)
		local ret = ""
		ret = ret.."\n"
		for i = 1, level do
			ret = ret.."\t"
		end
		return ret
	end
	
	local function _enter_level(t, level, name)
		local ret = ""
		local _keycache = {}
		for k, v in ipairs(t) do
			ret = ret.._new_line(level + 1)
			if (cache[v]) then
					ret = ret.."["..tostring(k).."]".." = "..cache[v]..","
			elseif (type(v) == "table") then
					local newname = name.."."..k
					cache[v] = newname
					ret = ret.."["..tostring(k).."]".." = ".."{"
					ret = ret.._enter_level(v, level + 1, newname)
					ret = ret.._new_line(level + 1)
					ret = ret.."},"
					
			else
					if (type(v) == "string") then
						ret = ret.."["..tostring(k).."]".." = ".."\""..v.."\""..","
					else
						ret = ret.."["..tostring(k).."]".." = "..tostring(v)..","
					end
			end
			_keycache[k] = true
		end
		
		for k, v in pairs(t) do
			if (not _keycache[k]) then
				ret = ret.._new_line(level + 1)
				if (cache[v]) then
					ret = ret.."[\""..tostring(k).."\"]".." = "..cache[v]..","
				elseif (type(v) == "table") then
					local newname = name.."."..k
					cache[v] = newname
					ret = ret.."[\""..tostring(k).."\"]".." = ".."{"
					ret = ret.._enter_level(v, level + 1, newname)
					ret = ret.._new_line(level + 1)
					ret = ret.."},"
				else
					if (type(v) == "string") then
						ret = ret.."[\""..tostring(k).."\"]".." = ".."\""..v.."\""..","
					else
						ret = ret.."[\""..tostring(k).."\"]".." = "..tostring(v)..","
					end
				end
			end
		end
		return ret
	end
	
	ret = ret .. "{"	
	ret = ret .. _enter_level(root, 0, "")
	ret = ret .. "\n}\n"
	print(ret)
end

return print_r