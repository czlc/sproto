local core = require "sproto.core"
local assert = assert

local sproto = {}
local host = {}

local weak_mt = { __mode = "kv" }
local sproto_mt = { __index = sproto }
local sproto_nogc = { __index = sproto }
local host_mt = { __index = host }

function sproto_mt:__gc()
	core.deleteproto(self.__cobj)
end

-- creates a sproto object by a schema string (generates by parser).
function sproto.new(bin)
	local cobj = assert(core.newproto(bin))
	local self = {
		__cobj = cobj,
		__tcache = setmetatable( {} , weak_mt ),	-- 类型
		__pcache = setmetatable( {} , weak_mt ),	-- 协议
	}
	return setmetatable(self, sproto_mt)
end

-- share a sproto object from a sproto c object (generates by sprotocore.newproto).
function sproto.sharenew(cobj)
	local self = {
		__cobj = cobj,
		__tcache = setmetatable( {} , weak_mt ),
		__pcache = setmetatable( {} , weak_mt ),
	}
	return setmetatable(self, sproto_nogc)
end

-- 解析协议包字符串并，将其导入到c结构中，并生成相应的协议组对象(userdata)
-- 挂接mt之后拥有功能：encode,decode,pencode, pdecode
function sproto.parse(ptext)
	local parser = require "sprotoparser"
	local pbin = parser.parse(ptext)
	return sproto.new(pbin)
end

-- 配置好协议处理对象(可以打包request和解包respone)
-- 本方协议，需要peer遵守
-- creates a host object to deliver the rpc message.
function sproto:host( packagename )
	packagename = packagename or  "package"
	local obj = {
		-- self是sproto.new(pbin)出来的sp对象，为了处理对方协议
		__proto = self,
		-- 协议头类型，各个协议都带有它，双方都是基于它
		__package = assert(core.querytype(self.__cobj, packagename), "type package not found"),
		-- 用于匹配reques相应的respond(保存的是respone的类型)
		__session = {},
	}
	return setmetatable(obj, host_mt)	-- host_mt 使其有打包和解包能力
end

-- queries a type object from a sproto object by typename.
-- 返回type 它是lightuserdata类型
local function querytype(self, typename)
	local v = self.__tcache[typename]
	if not v then
		v = assert(core.querytype(self.__cobj, typename), "type not found")
		self.__tcache[typename] = v
	end

	return v
end

-- 是否存在此自定义类型
function sproto:exist_type(typename)
	local v = self.__tcache[typename]
	if not v then
		return core.querytype(self.__cobj, typename) ~= nil
	else
		return true
	end
end

-- encodes a lua table with typename into a binary string
function sproto:encode(typename, tbl)
	local st = querytype(self, typename)
	return core.encode(st, tbl)
end

-- decodes a binary string generated by sproto.encode with typename.
-- If blob is a lightuserdata (C ptr), sz (integer) is needed.
-- sproto:decode(typename, blob [,sz])
function sproto:decode(typename, ...)
	local st = querytype(self, typename)
	return core.decode(st, ...)
end

function sproto:pencode(typename, tbl)
	local st = querytype(self, typename)
	return core.pack(core.encode(st, tbl))
end

function sproto:pdecode(typename, ...)
	local st = querytype(self, typename)
	return core.decode(st, core.unpack(...))
end


-- 查找协议名pname，查找协议详细信息
local function queryproto(self, pname)
	local v = self.__pcache[pname]
	if not v then
		local tag, req, resp = core.protocol(self.__cobj, pname)	-- tag, 请求type，应答type
		assert(tag, pname .. " not found")
		if tonumber(pname) then
			pname, tag = tag, pname
		end
		v = {
			request = req,	-- 请求type(lightuserdata)
			response =resp,	-- 应答type(lightuserdata)
			name = pname,	-- 协议名
			tag = tag,		-- 协议tag
		}
		self.__pcache[pname] = v
		self.__pcache[tag]  = v
	end

	return v
end

-- 是否存在此协议
function sproto:exist_proto(pname)
	local v = self.__pcache[pname]
	if not v then
		return core.protocol(self.__cobj, pname) ~= nil
	else
		return true
	end
end

-- protoname是协议名
function sproto:request_encode(protoname, tbl)
	local p = queryproto(self, protoname)
	local request = p.request
	if request then
		return core.encode(request,tbl) , p.tag
	else
		return "" , p.tag
	end
end

function sproto:response_encode(protoname, tbl)
	local p = queryproto(self, protoname)
	local response = p.response
	if response then
		return core.encode(response,tbl)
	else
		return ""
	end
end

-- 根据类型名protoname，解码...
function sproto:request_decode(protoname, ...)
	local p = queryproto(self, protoname)
	local request = p.request
	if request then
		return core.decode(request,...) , p.name
	else
		return nil, p.name
	end
end

function sproto:response_decode(protoname, ...)
	local p = queryproto(self, protoname)
	local response = p.response
	if response then
		return core.decode(response,...)
	end
end

sproto.pack = core.pack	-- packs a string encoded by sproto.encode to reduce the size.
sproto.unpack = core.unpack	-- unpacks the string packed by sproto.pack.

-- Create a table with default values of typename. Type can be nil , "REQUEST", or "RESPONSE".
function sproto:default(typename, type)
	if type == nil then
		return core.default(querytype(self, typename))
	else
		local p = queryproto(self, typename)
		if type == "REQUEST" then
			if p.request then
				return core.default(p.request)
			end
		elseif type == "RESPONSE" then
			if p.response then
				return core.default(p.response)
			end
		else
			error "Invalid type"
		end
	end
end

local header_tmp = {}

-- 返回一个应答函数
local function gen_response(self, response, session)
	-- 得到一个应答函数，调用该函数并传入应答结构将会得到打包的应答内容
	return function(args, ud)
		header_tmp.type = nil -- type为nil表示是response
		header_tmp.session = session
		header_tmp.ud = ud
		local header = core.encode(self.__package, header_tmp)
		if response then
			local content = core.encode(response, args)
			return core.pack(header .. content)
		else
			return core.pack(header)
		end
	end
end

-- 处理对方发来的request或者response(被动)
-- retuen "REQUEST", 请求类型名，请求内容,
-- return "RESPONSE"
function host:dispatch(...)
	local bin = core.unpack(...)
	header_tmp.type = nil
	header_tmp.session = nil
	header_tmp.ud = nil
	local header, size = core.decode(self.__package, bin, header_tmp) -- 解码协议头
	local content = bin:sub(size + 1)	-- 去掉头，剩下具体内容
	if header.type then	-- type是请求类型tag，若无type表示应答
		-- request
		local proto = queryproto(self.__proto, header.type) -- 根据协议类型header.type得到此type协议具体情况
		local result
		if proto.request then
			result = core.decode(proto.request, content) -- 解码请求协议内容
		end
		if header_tmp.session then	-- 需要应答
			return "REQUEST", proto.name, result, gen_response(self, proto.response, header_tmp.session), header.ud
		else
			return "REQUEST", proto.name, result, nil, header.ud
		end
	else
		-- response
		-- 收到对方应答
		local session = assert(header_tmp.session, "session not found")
		local response = assert(self.__session[session], "Unknown session")
		self.__session[session] = nil
		if response == true then
			return "RESPONSE", session, nil, header.ud
		else
			local result = core.decode(response, content)
			return "RESPONSE", session, result, header.ud
		end
	end
end

-- 关联本方协议sp，用于发送请求(主动)
function host:attach(sp)
	-- 调用打包器，将返回打包好的请求
	-- name是协议名
	-- args是协议table，
	-- session是会话id，如果需要应答则需要这个参数，否则可以设置为nil
	-- ud是一个用户定义字符串可以用于返回error msg，这样就不用在每个协议中增加这么一项
	return function(name, args, session, ud)
		local proto = queryproto(sp, name)	-- 根据对方协议名获得协议类型对象
		header_tmp.type = proto.tag
		header_tmp.session = session
		header_tmp.ud = ud
		local header = core.encode(self.__package, header_tmp)	-- 编码协议头

		-- session保存response的type
		if session then
			self.__session[session] = proto.response or true
		end

		if proto.request then
			local content = core.encode(proto.request, args) -- 编码协议内容
			return core.pack(header ..  content) -- 打包整个协议数据
		else
			return core.pack(header)
		end
	end
end

return sproto
