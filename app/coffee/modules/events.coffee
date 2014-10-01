###
# Copyright (C) 2014 Andrey Antukh <niwi@niwi.be>
# Copyright (C) 2014 Jesús Espino Garcia <jespinog@gmail.com>
# Copyright (C) 2014 David Barragán Merino <bameda@dbarragan.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#
# File: modules/events.coffee
###

taiga = @.taiga

module = angular.module("taigaEvents", [])


class EventsService
    constructor: (@win, @log, @config, @auth) ->
        _.bindAll(@)

    initialize: (sessionId) ->
        @.sessionId = sessionId
        @.subscriptions = {}
        @.connected = false
        @.pendingMessages = []

        if @win.WebSocket is undefined
            @log.info "WebSockets not supported on your browser"

    setupConnection: ->
        @.stopExistingConnection()

        wshost = @config.get("eventsHost", "localhost:8888")
        wsscheme = @config.get("eventsScheme", "ws")
        url = "#{wsscheme}://#{wshost}/events"

        @.ws = new @win.WebSocket(url)
        @.ws.addEventListener("open", @.onOpen)
        @.ws.addEventListener("message", @.onMessage)
        @.ws.addEventListener("error", @.onError)
        @.ws.addEventListener("close", @.onClose)

    stopExistingConnection: ->
        if @.ws is undefined
            return

        @.ws.close()
        @.ws.removeEventListener("open", @.onOpen)
        @.ws.removeEventListener("close", @.onClose)
        @.ws.removeEventListener("error", @.onError)
        @.ws.removeEventListener("message", @.onMessage)

        delete @.ws

    serialize: (message) ->
        if _.isObject(message)
            return JSON.stringify(message)
        return message

    sendMessage: (message) ->
        @.pendingMessages.push(message)

        if not @.connected
            return

        messages = _.map(@.serialize, @.pendingMessages)
        @.pendingMessages = []

        for msg in messages
            @.ws.send(msg)

    subscribe: (scope, routingKey, callback) ->
        subscription = {
            scope: scope,
            routingKey: routingKey,
            callback: _.debounce(callback, 500, {"leading": true, "trailing": false})
        }

        message = {
            "cmd": "subscribe",
            "routing_key": routingKey
        }

        @.subscriptions[routingKey] = subscription
        @.sendMessage(message)
        scope.$on("$destroy", => @.unsubscribe(routingKey))

    unsubscribe: (routingKey) ->
        message = {
            "cmd": "unsubscribe",
            "routing_key": routingKey
        }

        @.sendMessage(message)

    onOpen: ->
        @.connected = true

        @log.debug("WebSocket connection opened")
        token = @auth.getToken()

        message = {
            cmd: "auth"
            data: {token: token, sessionId: @.sessionId}
        }

        @.sendMessage(message)

    onMessage: (event) ->
        @.log.debug "WebSocket message received: #{event.data}"

        data = JSON.parse(event.data)
        routingKey = data.routing_key

        if not @.subscriptions[routingKey]?
            return

        subscription = @.subscriptions[routingKey]
        subscription.scope.$apply ->
            subscription.callback(data.data)

    onError: (error) ->
        @log.error("WebSocket error: #{error}")

    onClose: ->
        @log.debug("WebSocket closed.")


class EventsProvider
    setSessionId: (sessionId) ->
        @.sessionId = sessionId

    $get: ($win, $log, $conf, $auth) ->
        service = new EventsService($win, $log, $conf, $auth)
        service.initialize(@.sessionId)
        return service

    @.prototype.$get.$inject = ["$window", "$log", "$tgConfig", "$tgAuth"]

module.provider("$tgEvents", EventsProvider)
