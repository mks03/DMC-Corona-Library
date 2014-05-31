--====================================================================--
-- dmc_sockets.atcp
--
--
-- by David McCuskey
-- Documentation: http://docs.davidmccuskey.com/display/docs/dmc_sockets.lua
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



--====================================================================--
-- DMC Corona Library : Async TCP Socket
--====================================================================--


-- Semantic Versioning Specification: http://semver.org/

local VERSION = "0.2.0"



--====================================================================--
-- DMC Corona Library Config
--====================================================================--


--====================================================================--
-- Support Functions

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
-- Configuration

local dmc_lib_data, dmc_lib_info

-- boot dmc_library with boot script or
-- setup basic defaults if it doesn't exist
--
if false == pcall( function() require( "dmc_corona_boot" ) end ) then
	_G.__dmc_corona = {
		dmc_corona={},
	}
end

dmc_lib_data = _G.__dmc_corona
dmc_lib_info = dmc_lib_data.dmc_library



--====================================================================--
-- DMC Library : Async TCP
--====================================================================--


--====================================================================--
-- Configuration


--====================================================================--
-- Imports

local Objects = require 'dmc_objects'
local socket = require 'socket'

local tcp_socket = require 'dmc_sockets.tcp'


--====================================================================--
-- Setup, Constants

-- setup some aliases to make code cleaner
local inheritsFrom = Objects.inheritsFrom

-- local control of development functionality
local LOCAL_DEBUG = false



--====================================================================--
-- Async TCP Socket Class
--====================================================================--


local ATCPSocket = inheritsFrom( tcp_socket )
ATCPSocket.NAME = "Async TCP Socket Class"

--== Class Constants

-- Connection-Status Constants

-- ATCPSocket.NO_SOCKET = 'no_socket'
-- ATCPSocket.NOT_CONNECTED = 'socket_not_connected'
-- ATCPSocket.CONNECTED = 'socket_connected'
-- ATCPSocket.CLOSED = 'socket_closed'

--== Event Constants

-- ATCPSocket.EVENT = 'tcp_socket_event'

-- ATCPSocket.CONNECT = 'connect_event'
-- ATCPSocket.READ = 'read_event'
-- ATCPSocket.WRITE = 'write_event'


--====================================================================--
--== Start: Setup DMC Objects

function ATCPSocket:_init( params )
	-- print( "ATCPSocket:_init" )
	params = params or {}
	self:superCall( "_init", params )
	--==--

	--== Create Properties ==--

	self.__timer_is_active = false
	self._timeout = 2000
	self._active_coroutine = nil
	self._coroutine_queue = {}

	self._read_in_process = false

	-- self._host = nil
	-- self._port = nil
	-- self._buffer = "" -- string
	-- self._status = nil


	--== Object References ==--

	-- self._socket = nil
	-- self._master = params.master

end

--== END: Setup DMC Objects
--====================================================================--


--====================================================================--
--== Public Methods


function ATCPSocket.__getters:timeout( value )
	self._timeout = value
end


function ATCPSocket:connect( host, port, params )
	-- print( 'ATCPSocket:connect', host, port, params )
	params = params or {}
	--==--

	self._host = host
	self._port = port
	self._onConnect = params.onConnect


	if self._status == ATCPSocket.CONNECTED then
		local evt = {}
		evt.type, evt.emsg = self.CONNECT, self.ERR_CONNECTED
		if self._onConnect then self._onConnect( evt ) end
		return
	end

	self:_createSocket( { timeout=0 } )

	local f = function()

		local beg_time = system.getTimer()
		local timeout, time_diff = self._timeout, 0
		local evt = {}

		repeat

			local success, emsg = self._socket:connect( host, port )

			-- print( success, emsg )
			-- messages:
			-- nil	timeout
			-- nil	Operation already in progress
			-- nil	already connected

			if success or emsg == self.ERR_CONNECTED then
				self._status = self.CONNECTED
				evt.type = self.CONNECT
				evt.status = self._status
				evt.emsg = emsg

				self._timer_is_active = false -- do this before calling connect

				if self._onConnect then self._onConnect( evt ) end

			else
				coroutine.yield()

			end

			time_diff = system.getTimer() - beg_time

		until time_diff > timeout or self._status == self.CONNECTED

		if self._status ~= self.CONNECTED then
			self._status = self.NOT_CONNECTED
			evt.type = self.CONNECT
			evt.status = self._status
			evt.emsg = self.ERR_TIMEOUT

			self._timer_is_active = false -- do this before calling connect

			if self._onConnect then self._onConnect( evt ) end
		end

	end

	local co = coroutine.create( f )
	table.insert( self._coroutine_queue, co )

	self._timer_is_active = true

end


function ATCPSocket:send( data, callback )
	-- print( 'ATCPSocket:send', #data, callback )

	if not callback or type( callback ) ~= 'function' then return end

	local evt = {}

	local bytes, emsg = self._socket:send( data )
	-- print( bytes, emsg )
	evt.error = nil
	evt.emsg = nil

	callback( evt )
end


function ATCPSocket:receive( option, callback )
	-- print( 'ATCPSocket:receive', option, callback )

	if not callback or type( callback ) ~= 'function' then return end

	local buffer = self._buffer

	local evt = {}
	local data

	if type( option ) == 'string' and option == '*a' then
		data = buffer
		self._buffer = ""
		evt.data, evt.emsg = data, nil
		callback( evt )
		return

	elseif type( option ) == 'number' and #buffer >= option then
		data = string.sub( buffer, 1, option )
		self._buffer = string.sub( buffer, option+1 )

		callback( { data=data, emsg=nil } )

	elseif type( option ) == 'string' and option == '*l' then

		-- create coroutine function
		local f = function( not_coroutine )

			local beg_time = system.getTimer()
			local timeout, time_diff = self._timeout, 0

			repeat

				data = self:superCall( "receive", option )

				if not_coroutine then return data end

				if not data then
					coroutine.yield()
				else
					self._read_in_process = false
					evt.data, evt.emsg = data, nil
					callback( evt )
				end

				time_diff = system.getTimer() - beg_time

			until data or time_diff > timeout

			if not data then
				self._read_in_process = false
				evt.data, evt.emsg = nil, self.ERR_TIMEOUT
				callback( evt )
			end

		end

		self._read_in_process = true

		data = f( true )
		if data then
			self._read_in_process = false
			evt.data, evt.emsg = data, nil
			callback( evt )
		else
			local co = coroutine.create( f )
			table.insert( self._coroutine_queue, co )
		end

	end

end


function ATCPSocket:receiveUntilNewline( callback )
	-- print( 'ATCPSocket:receiveUntilNewline' )

	if not callback or type( callback ) ~= 'function' then return end

	local data_list = {}
	local evt = {}

	-- create coroutine function
	local doDataCall = function( not_coroutine )

		local beg_time = system.getTimer()
		local timeout, time_diff = self._timeout, 0

		repeat

			local data = self:superCall( 'receive', '*l' )

			-- data handling
			if data then
				table.insert( data_list, data )

				if data == '' then
					if not_coroutine then
						return true
					else
						self._timer_is_active = false

						evt.data, evt.emsg = data_list, nil
						callback( evt )
					end
				end

			end

			-- control
			if not data then
				if not_coroutine then
					return false
				else
					coroutine.yield()
				end
			end

			time_diff = system.getTimer() - beg_time

		until data == '' or time_diff > timeout

		self._timer_is_active = false

		if data_list[#data_list] ~= '' then
			if #data_list > 0 then
				local str = table.concat( data_list, '\r\n' )
				self:unreceive( str )
			end
			evt.data, evt.emsg = nil, self.ERR_TIMEOUT
			callback( evt )
		end

	end -- doDataCall


	-- run doDataCall, see if we have data now
	-- otherwise put in coroutine loop

	if doDataCall( true ) == true then
		evt.data, evt.emsg = data_list, nil
		callback( evt )

	else
		if #data_list > 0 then
			local str = table.concat( data_list, '\r\n' )
			self:unreceive( str )
		end

		local co = coroutine.create( doDataCall )
		table.insert( self._coroutine_queue, co )

		self._timer_is_active = true

	end

end


--====================================================================--
--== Private Methods

function ATCPSocket.__setters:_timer_is_active( value )
	-- print( 'ATCPSocket.__setters:_timer_is_active', value )

	if self.__timer_is_active == value then return end

	if value then
		Runtime:addEventListener( 'enterFrame', self )
	else
		Runtime:removeEventListener( 'enterFrame', self )
	end

	self.__timer_is_active = value

end


function ATCPSocket:_closeSocketDispatch( evt )
	-- print( 'ATCPSocket:_closeSocketDispatch', evt )
	evt.type = self.CONNECT
	if self._onConnect then self._onConnect( evt ) end
end


function ATCPSocket:_doAfterReadAction()
	-- print( 'ATCPSocket:_doAfterReadAction' )
	if #self._buffer > 0 then
		self:_checkCoroutineQueue()
		if not self._read_in_process then
			-- print(self._buffer)
			self._onConnect( { type=self.READ })
		end

	end
end


function ATCPSocket:_checkCoroutineQueue()
	-- print( 'ATCPSocket:_checkCoroutineQueue' )

	local co = self._active_coroutine

	if not co and #self._coroutine_queue == 0 then return end

	if not co then
		co = table.remove( self._coroutine_queue )
		self._active_coroutine = co
	end

	local status = coroutine.resume( co )
	if coroutine.status( co ) ~= 'dead' then return end

	self._active_coroutine = nil

end


--====================================================================--
--== Event Handlers

function ATCPSocket:_socketsEvent_handler( event )
	-- print( 'ATCPSocket:_socketsEvent_handler', event )
	self:_checkCoroutineQueue()
end


function ATCPSocket:enterFrame( event )
	-- print( 'ATCPSocket:enterFrame', event )
	self:_checkCoroutineQueue()
end




return ATCPSocket
