--====================================================================--
-- dmc_wamp.lua
--
--
-- by David McCuskey
-- Documentation: http://docs.davidmccuskey.com/display/docs/dmc_wamp.lua
--====================================================================--

--[[

Copyright (C) 2014 David McCuskey. All Rights Reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in the
Software without restriction, including without limitation the rights to use, copy,
modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
and to permit persons to whom the Software is furnished to do so, subject to the
following conditions:

The above copyright notice and this permission notice shall be included in all copies
or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.

--]]

--[[
Wamp support adapted from:
* AutobahnPython (https://github.com/tavendo/AutobahnPython/)
--]]


-- Semantic Versioning Specification: http://semver.org/

local VERSION = "0.1.0"


--====================================================================--
-- Boot Support Methods
--====================================================================--

local Utils = {} -- make copying from dmc_utils easier

function Utils.extend( fromTable, toTable )

	function _extend( fT, tT )

		for k,v in pairs( fT ) do

			if type( fT[ k ] ) == "table" and
				type( tT[ k ] ) == "table" then

				tT[ k ] = _extend( fT[ k ], tT[ k ] )

			elseif type( fT[ k ] ) == "table" then
				tT[ k ] = _extend( fT[ k ], {} )

			else
				tT[ k ] = v
			end
		end

		return tT
	end

	return _extend( fromTable, toTable )
end


--====================================================================--
-- DMC Library Config
--====================================================================--

local dmc_lib_data, dmc_lib_info, dmc_lib_location

-- boot dmc_library with boot script or
-- setup basic defaults if it doesn't exist
--
if false == pcall( function() require( "dmc_library_boot" ) end ) then
	_G.__dmc_library = {
		dmc_library={
			location = ''
		},
		func = {
			find=function( name )
				local loc = ''
				if dmc_lib_data[name] and dmc_lib_data[name].location then
					loc = dmc_lib_data[name].location
				else
					loc = dmc_lib_info.location
				end
				if loc ~= '' and string.sub( loc, -1 ) ~= '.' then
					loc = loc .. '.'
				end
				return loc .. name
			end
		}
	}
end

dmc_lib_data = _G.__dmc_library
dmc_lib_func = dmc_lib_data.func
dmc_lib_info = dmc_lib_data.dmc_library
dmc_lib_location = dmc_lib_info.location



--====================================================================--
-- DMC Library : DMC WAMP
--====================================================================--



--====================================================================--
-- Configuration

dmc_lib_data.dmc_wamp = dmc_lib_data.dmc_wamp or {}

local DMC_WAMP_DEFAULTS = {
	debug_active=false,
}

local dmc_wamp_data = Utils.extend( dmc_lib_data.dmc_wamp, DMC_WAMP_DEFAULTS )


--====================================================================--
-- Imports

local Objects = require( dmc_lib_func.find('dmc_objects') )
local States = require( dmc_lib_func.find('dmc_states') )
local Utils = require( dmc_lib_func.find('dmc_utils') )
local WebSocket = require( dmc_lib_func.find('dmc_websockets') )

local SerializerFactory = require( dmc_lib_func.find('dmc_wamp.serializer') )
local wprotocol = require( dmc_lib_func.find('dmc_wamp.protocol') )

local Error = require( dmc_lib_func.find('dmc_wamp.exception') )


--====================================================================--
-- Setup, Constants

-- setup some aliases to make code cleaner
local inheritsFrom = Objects.inheritsFrom

-- local control of development functionality
local LOCAL_DEBUG = false



--====================================================================--
-- Wamp Class
--====================================================================--

local Wamp = inheritsFrom( WebSocket )
Wamp.NAME = "Wamp Class"


--== Event Constants

Wamp.EVENT = 'wamp_event'

Wamp.ONOPEN = 'onopen'
Wamp.ONCONNECT = 'onconnect'
Wamp.ONDISCONNECT = 'ondisconnect'
-- Wamp.ONCLOSE = 'onclose'


--====================================================================--
--== Start: Setup DMC Objects

function Wamp:_init( params )
	-- print( "Wamp:_init" )
	params = params or {}
	self:superCall( "_init", params )
	--==--

	--== Sanity Check ==--

	if not self.is_intermediate and ( not params.realm ) then
		error( "Wamp: requires parameter 'realm'" )
	end

	--== Create Properties ==--

	self._realm = params.realm
	self._protocols = params.protocols or { 'wamp.2.json' }


	--== Object References ==--

	self._session = nil -- a WAMP session object
	self._serializer = nil -- a WAMP session object

end


-- function Wamp:_initComplete()
-- 	-- print( "Wamp:_initComplete" )
-- 	self:superCall( "_initComplete" )
-- 	--==--

-- end

--== END: Setup DMC Objects
--====================================================================--



--====================================================================--
--== Public Methods

function Wamp.__getters:is_connected()
	-- print( "Wamp.__getters:is_connected" )
	return ( self._session ~= nil )
end


-- @params params table of options:
-- args - array
-- kwargs - table
-- onResult - callback
-- onProgress - callback
-- onError - callback
function Wamp:call( procedure, params )
	-- print( "Wamp:call", procedure )
	params = params or {}
	--==--

	local onError = params.onError

	params.onError = function( event )
		-- print( "Wamp:call, on error")
		if onError then onError( event ) end
	end

	return self._session:call( procedure, params )
end


function Wamp:register( handler, params )
	print( "Wamp:register", handler )
	if params.pkeys or params.disclose_caller then
		params.options = Types.RegisterOptions:new( params )
	end
	return self._session:register( handler, params )
end

function Wamp:yield( topic, callback )
	print( "Wamp:yield", topic )
	-- return self._session:subscribe( topic, callback )
end

function Wamp:unregister( handler, params )
	print( "Wamp:unregister", handler )

	try{
		function()
			self._session:unregister( handler, params )
		end,

		catch{
			function(e)
				print( e, type(e))
				if type(e)=='string' then
					error( e )
				elseif e:isa( Error.ProtocolError ) then
					self:_bailout{
						code=WebSocket.CLOSE_STATUS_CODE_PROTOCOL_ERROR,
						reason="WAMP Protocol Error"
					}
				else
					self:_bailout{
						code=WebSocket.CLOSE_STATUS_CODE_INTERNAL_ERROR,
						reason="WAMP Internal Error ({})"
					}
				end
			end
		}
	}

	-- return self._session:unsubscribe( topic, callback )
end


-- topic
-- callback
function Wamp:subscribe( topic, callback )
	-- print( "Wamp:subscribe", topic )
	return self._session:subscribe( topic, callback )
end

function Wamp:unsubscribe( topic, callback )
	-- print( "Wamp:unsubscribe", topic )
	return self._session:unsubscribe( topic, callback )
end


function Wamp:send( msg )
	-- print( "Wamp:send", msg.TYPE )
	-- params = params or {}
	--==--
	local bytes, is_binary = self._serializer:serialize( msg )

	if LOCAL_DEBUG then print( 'sending', bytes ) end

	self:superCall( 'send', bytes, { type=is_binary } )
end

function Wamp:leave( reason, message )
	-- print( "Wamp:leave" )
	local p = {
		reason=reason,
		log_message=message
	}
	self._session:leave( p )
end

function Wamp:close( reason, message )
	-- print( "Wamp:close" )
	self:_wamp_close( reason, message )
	self:superCall( 'close' )
end


--====================================================================--
--== Private Methods

function Wamp:_wamp_close( message, was_clean )
	-- print( "Wamp:_wamp_close" )
	local had_session = ( self._session ~= nil )

	if self._session then
		self._session:onClose( message, was_clean )
		self._session = nil
	end

	if had_session then
		self:_dispatchEvent( Wamp.ONDISCONNECT )
	end
end


--== Events

-- coming from websockets
function Wamp:_onOpen()
	-- print( "Wamp:_onOpen" )

	-- TODO: match with protocol
	self._serializer = SerializerFactory.create( 'json' )

	self._session = wprotocol.Session:new( { realm=self._realm })
	self._session_f = self:createCallback( self._wampSessionEvent_handler )
	self._session:addEventListener( self._session.EVENT, self._session_f )

	self._session:onOpen( { transport=self } )
end


-- coming from websockets
function Wamp:_onMessage( message )
	-- print( "Wamp:_onMessage", message )

	try{
		function()
			local msg = self._serializer:unserialize( message.data )
			self._session:onMessage( msg, onError )
		end,

		catch{
			function(e)
				print( e, type(e))
				if type(e)=='string' then
					error( e )
				elseif e:isa( Error.ProtocolError ) then
					self:_bailout{
						code=WebSocket.CLOSE_STATUS_CODE_PROTOCOL_ERROR,
						reason="WAMP Protocol Error"
					}
				else
					self:_bailout{
						code=WebSocket.CLOSE_STATUS_CODE_INTERNAL_ERROR,
						reason="WAMP Internal Error ({})"
					}
				end
			end
		}
	}

end

-- coming from websockets
function Wamp:_onClose( message, was_clean )
	-- print( "Wamp:_onClose" )
	self:_wamp_close( reason, message )
end


--====================================================================--
--== Event Handlers

function Wamp:_wampSessionEvent_handler( event )
	-- print( "Wamp:_wampSessionEvent_handler: ", event.type )
	local e_type = event.type
	local session = event.target

	if e_type == session.ONJOIN then
		self:_dispatchEvent( Wamp.ONCONNECT )
	end

end




return Wamp