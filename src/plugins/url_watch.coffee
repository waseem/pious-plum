UrlFetcher = require '../url_fetcher'
UrlDetector = require '../url_detector'
entities = new(require('html-entities').XmlEntities)

ACCEPTABLE_MIMES = /(text|html|xml)/
TITLE_REGEX = /<title>(.*?)<\/title>/

STATUS_CODES = require("http").STATUS_CODES

bytesToSize = (bytes) -> 
  sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB']
  if (bytes == 0) 
    return 'n/a'
  
  i = parseInt(Math.floor(Math.log(bytes) / Math.log(1024)))
  return Math.round(bytes / Math.pow(1024, i), 2) + ' ' + sizes[[i]]


# There's no way to get the new url's actual protocol without rewriting the follow-redirects module. 
# This function attempts to detect if a redirect happened.
is_redirect = (res, url) ->
  possible_new_url = "#{res.req._headers.host}#{res.req.path}"
  if "#{url.host}#{url.path}" !=  possible_new_url
    possible_new_url

class Plugin 
  constructor: (@bot, @config) -> 
    @__name = "url_watch"
    @__author = "epochwolf"
    @__version = "v0.0.1"
    @__listeners = 
      "message_with_url": [@urlDetails]
    @__commands = {}
    @__autoload = true
    @rate_limiter = new(require('../rate_limiter'))(30 * 60) # 30 minutes

  setup: () =>
    console.log "url_watch plugin loaded"

  teardown:() =>
    console.log "url_watch plugin unloaded"

  urlDetails: (channel, who, message, url) =>
    console.log "I see: #{url.href}"

    unless @rate_limiter.okay "#{url.host}#{url.path}"
      return

    request = new(UrlFetcher)(url).handle (res)=>
      status_code = res.statusCode
      content_type = res.headers['content-type']
      content_type = "#{content_type}".replace(/;.*/, "")
      length = res.headers['content-length']
      data = ""

      # If bot has a handler for the new host, delegate. 
      if new_url = is_redirect res, url
        if redirect_url = UrlDetector.has_url("http://#{new_url}")
          @bot.emit("message_with_url:#{redirect_url.hostname}", channel, who, message, redirect_url)

      res.on 'end', () =>
        display_status = STATUS_CODES["#{status_code}"] || status_code
        title = if "#{content_type}".match ACCEPTABLE_MIMES then "#{data}".match(TITLE_REGEX)

        title_text = if title && title[1]
          "#{title[1]}".replace(/&amp;/, "&")
        else if length
          "#{bytesToSize length} #{content_type}"
        else
          "?? KB #{content_type}"

        title_text = entities.decode title_text

        if new_url 
          title_text += " | #{new_url}"

        if "#{status_code}" != "200" 
          title_text += " (#{display_status})"


        @bot.say channel, "Web | #{title_text}"

      res.on 'data', (d) => 
        data += d
        if data.length > 40000 # We don't want to read all 4.7 gb of an iso if someone is being a dick.
          res.socket.end()

    request.end()
    request.on 'error', (e) =>
        console.error e

module.exports = Plugin
