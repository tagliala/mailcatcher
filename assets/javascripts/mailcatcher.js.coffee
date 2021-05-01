#= require modernizr
#= require jquery
#= require date
#= require favcount
#= require flexie
#= require keymaster
#= require url

# Add a new jQuery selector expression which does a case-insensitive :contains
jQuery.expr.pseudos.icontains = (a, i, m) ->
  (a.textContent ? a.innerText ? "").toUpperCase().indexOf(m[3].toUpperCase()) >= 0

class MailCatcher
  constructor: ->
    $(document).on "click", ".js-message-row", (e) =>
      e.preventDefault()
      @loadMessage $(e.currentTarget).attr("data-message-id")

    $("#js-search").on "keyup", (e) =>
      query = $.trim $(e.currentTarget).val()
      if query
        @searchMessages query
      else
        @clearSearch()

    $(".js-tab__link").on "click", (e) =>
      e.preventDefault()
      @loadMessageBody @selectedMessage(), $($(e.currentTarget).parent("li")).data("message-format")

    $("#js-message-iframe").on "load", =>
      @decorateMessageBody()

    $("#resizer").on "mousedown", (e) =>
      e.preventDefault()
      events =
        mouseup: (e) =>
          e.preventDefault()
          $(window).off(events)
        mousemove: (e) =>
          e.preventDefault()
          @resizeTo e.clientY
      $(window).on(events)

    @resizeToSaved()

    $("#js-clear").on "click", (e) =>
      e.preventDefault()
      if confirm "You will lose all your received messages.\n\nAre you sure you want to clear all messages?"
        $.ajax
          url: new URL("messages", document.baseURI).toString()
          type: "DELETE"
          success: =>
            @clearMessages()
          error: ->
            alert "Error while clearing all messages."

    $("#js-quit").on "click", (e) =>
      e.preventDefault()
      if confirm "You will lose all your received messages.\n\nAre you sure you want to quit?"
        $.ajax
          type: "DELETE"
          success: ->
            location.replace $("#js-mailcatcher-link").attr("href")
          error: ->
            alert "Error while quitting."

    @favcount = new Favcount($("""link[rel="icon"]""").attr("href"))

    key "up", =>
      if @selectedMessage()
        @loadMessage $(".js-message-row--selected").prevAll(":visible").first().data("message-id")
      else
        @loadMessage $(".js-message-row[data-message-id]").first().data("message-id")
      false

    key "down", =>
      if @selectedMessage()
        @loadMessage $(".js-message-row--selected").nextAll(":visible").data("message-id")
      else
        @loadMessage $(".js-message-row[data-message-id]:first").data("message-id")
      false

    key "⌘+up, ctrl+up", =>
      @loadMessage $(".js-message-row[data-message-id]:visible").first().data("message-id")
      false

    key "⌘+down, ctrl+down", =>
      @loadMessage $(".js-message-row[data-message-id]:visible").first().data("message-id")
      false

    key "left", =>
      @openTab @previousTab()
      false

    key "right", =>
      @openTab @nextTab()
      false

    key "backspace, delete", =>
      id = @selectedMessage()
      if id?
        $.ajax
          url: new URL("messages/#{id}", document.baseURI).toString()
          type: "DELETE"
          success: =>
            @removeMessage(id)

          error: ->
            alert "Error while removing message."
      false

    @refresh()
    @subscribe()

  # Only here because Safari's Date parsing *sucks*
  # We throw away the timezone, but you could use it for something...
  parseDateRegexp: /^(\d{4})[-\/\\](\d{2})[-\/\\](\d{2})(?:\s+|T)(\d{2})[:-](\d{2})[:-](\d{2})(?:([ +-]\d{2}:\d{2}|\s*\S+|Z?))?$/
  parseDate: (date) ->
    if match = @parseDateRegexp.exec(date)
      new Date match[1], match[2] - 1, match[3], match[4], match[5], match[6], 0

  offsetTimeZone: (date) ->
    offset = Date.now().getTimezoneOffset() * 60000 #convert timezone difference to milliseconds
    date.setTime(date.getTime() - offset)
    date

  formatDate: (date) ->
    date &&= @parseDate(date) if typeof(date) == "string"
    date &&= @offsetTimeZone(date)
    date &&= date.toString("dddd, d MMM yyyy h:mm:ss tt")

  messagesCount: ->
    $("#messages tr").length - 1

  updateMessagesCount: ->
    @favcount.set(@messagesCount())
    document.title = 'MailCatcher (' + @messagesCount() + ')'

  tabs: ->
    $(".js-tab")

  getTab: (i) =>
    $(@tabs()[i])

  selectedTab: =>
    @tabs().index($(".js-tab--selected"))

  openTab: (i) =>
    @getTab(i).children("a").click()

  previousTab: (tab)=>
    i = if tab || tab is 0 then tab else @selectedTab() - 1
    i = @tabs().length - 1 if i < 0
    if @getTab(i).is(":visible")
      i
    else
      @previousTab(i - 1)

  nextTab: (tab) =>
    i = if tab then tab else @selectedTab() + 1
    i = 0 if i > @tabs().length - 1
    if @getTab(i).is(":visible")
      i
    else
      @nextTab(i + 1)

  haveMessage: (message) ->
    message = message.id if message.id?
    $(""".js-message-row[data-message-id="#{message}"]""").length > 0

  selectedMessage: ->
    $(".js-message-row--selected").data "message-id"

  searchMessages: (query) ->
    selector = (":icontains('#{token}')" for token in query.split /\s+/).join("")
    $rows = $(".js-message-row")
    $rows.not(selector).hide()
    $rows.filter(selector).show()

  clearSearch: ->
    $("#messages tbody tr").show()

  addMessage: (message) ->
    $("<tr class=\"js-message-row\" />").attr("data-message-id", message.id.toString())
      .append($("<td/>").text(message.sender or "No sender").toggleClass("blank", !message.sender))
      .append($("<td/>").text((message.recipients || []).join(", ") or "No receipients").toggleClass("blank", !message.recipients.length))
      .append($("<td/>").text(message.subject or "No subject").toggleClass("blank", !message.subject))
      .append($("<td/>").text(@formatDate(message.created_at)))
      .prependTo($("#messages tbody"))
    @updateMessagesCount()

  removeMessage: (id) ->
    messageRow = $(""".js-message-row[data-message-id="#{id}"]""")
    isSelected = messageRow.is(".js-tab--selected")
    if isSelected
      switchTo = messageRow.next().data("message-id") || messageRow.prev().data("message-id")
    messageRow.remove()
    if isSelected
      if switchTo
        @loadMessage switchTo
      else
        @unselectMessage()
    @updateMessagesCount()

  clearMessages: ->
    $(".js-message-row").remove()
    @unselectMessage()
    @updateMessagesCount()

  scrollToRow: (row) ->
    relativePosition = row.offset().top - $("#messages").offset().top
    if relativePosition < 0
      $("#messages").scrollTop($("#messages").scrollTop() + relativePosition - 20)
    else
      overflow = relativePosition + row.height() - $("#messages").height()
      if overflow > 0
        $("#messages").scrollTop($("#messages").scrollTop() + overflow + 20)

  unselectMessage: ->
    $(".js-metadata dd").empty()
    $(".js-metadata .attachments").hide()
    $("#js-message-iframe").attr("src", "about:blank")
    null

  loadMessage: (id) ->
    id = id.id if id?.id?
    id ||= $(".js-message-row--selected").attr "data-message-id"

    if id?
      $(".js-message-row:not([data-message-id='#{id}'])").removeClass("js-message-row--selected")
      messageRow = $(".js-message-row[data-message-id='#{id}']")
      messageRow.addClass("js-message-row--selected")
      @scrollToRow(messageRow)

      $.getJSON "messages/#{id}.json", (message) =>
        $("dd.js-metadata__created_at").text(@formatDate message.created_at)
        $("dd.js-metadata__from").text(message.sender)
        $("dd.js-metadata__to").text((message.recipients || []).join(", "))
        $("dd.js-metadata__subject").text(message.subject)
        $(".js-tab").each (i, el) ->
          $el = $(el)
          format = $el.attr("data-message-format")
          if $.inArray(format, message.formats) >= 0
            $el.find("a").attr("href", "messages/#{id}.#{format}")
            $el.show()
          else
            $el.hide()

        if $(".js-tab--selected:not(:visible)").length
          $(".js-tab--selected").removeClass("js-tab--selected")
          $(".js-tab:visible:first").addClass("js-tab--selected")

        if message.attachments.length
          $ul = $("<ul/>").appendTo($("dd.js-metadata__attachments").empty())

          $.each message.attachments, (i, attachment) ->
            $ul.append($("<li>").append($("<a>").attr("href", "messages/#{id}/parts/#{attachment["cid"]}").addClass(attachment["type"].split("/", 1)[0]).addClass(attachment["type"].replace("/", "-")).text(attachment["filename"])))
          $(".js-metadata__attachments").show()
        else
          $(".js-metadata__attachments").hide()

        $("#js-download").attr("href", "messages/#{id}.eml")

        @loadMessageBody()

  loadMessageBody: (id, format) ->
    id ||= @selectedMessage()
    format ||= $(".js-tab--selected").attr("data-message-format")
    format ||= "html"

    $(""".js-tab[data-message-format="#{format}"]:not(.js-tab--selected)""").addClass("js-tab--selected")
    $(""".js-tab:not([data-message-format="#{format}"]).js-tab--selected""").removeClass("js-tab--selected")

    if id?
      $("#js-message-iframe").attr("src", "messages/#{id}.#{format}")

  decorateMessageBody: ->
    format = $(".js-tab--selected").attr("data-message-format")

    switch format
      when "html"
        body = $("#js-message-iframe").contents().find("body")
        $("a", body).attr("target", "_blank")
      when "plain"
        message_iframe = $("#js-message-iframe").contents()
        text = message_iframe.text()
        text = text.replace(/&/g, "&amp;")
        text = text.replace(/</g, "&lt;")
        text = text.replace(/>/g, "&gt;")
        text = text.replace(/\n/g, "<br/>")
        text = text.replace(/((http|ftp|https):\/\/[\w\-_]+(\.[\w\-_]+)+([\w\-\.,@?^=%&amp;:\/~\+#]*[\w\-\@?^=%&amp;\/~\+#])?)/g, """<a href="$1" target="_blank">$1</a>""")
        message_iframe.find("html").html("<html><body>#{text}</html></body>")

  refresh: ->
    $.getJSON "messages", (messages) =>
      $.each messages, (i, message) =>
        unless @haveMessage message
          @addMessage message
      @updateMessagesCount()

  subscribe: ->
    if WebSocket?
      @subscribeWebSocket()
    else
      @subscribePoll()

  subscribeWebSocket: ->
    secure = window.location.protocol is "https:"
    url = new URL("messages", document.baseURI)
    url.protocol = if secure then "wss" else "ws"
    @websocket = new WebSocket(url.toString())
    @websocket.onmessage = (event) =>
      data = JSON.parse(event.data)
      if data.type == "add"
        @addMessage(data.message)
      else if data.type == "remove"
        @removeMessage(data.id)
      else if data.type == "clear"
        @clearMessages()

  subscribePoll: ->
    unless @refreshInterval?
      @refreshInterval = setInterval (=> @refresh()), 1000

  resizeToSavedKey: "mailcatcherSeparatorHeight"

  resizeTo: (height) ->
    $("#messages").css
      height: height - $("#messages").offset().top
    window.localStorage?.setItem(@resizeToSavedKey, height)

  resizeToSaved: ->
    height = parseInt(window.localStorage?.getItem(@resizeToSavedKey))
    unless isNaN height
      @resizeTo height

$ -> window.MailCatcher = new MailCatcher
