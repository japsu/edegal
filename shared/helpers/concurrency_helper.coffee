Q = require 'q'

exports.Semaphore = class Semaphore
  constructor: (slots) ->
    @slots = @maxSlots = slots
    @queue = []
    @_finished = Q.defer()
    @finished = @_finished.promise

  pop: ->
    @slots += 1
    next = @queue.shift()

    if next
      @enter.apply this, next
    
    if @slots == @maxSlots
      @_finished.resolve()

  push: (func) ->
    if @slots > 0
      @enter func
    else
      deferred = Q.defer()
      @queue.push [func, deferred]
      deferred.promise

  enter: (func, deferred) ->
    @slots -= 1
    Q.when(func()).then (ret) =>
      deferred.resolve ret if deferred
      @pop()
      ret
    .fail (reason) =>
      deferred.reject reason if deferred
      @pop()
      reason