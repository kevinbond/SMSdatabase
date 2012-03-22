require 'rubygems' 
require 'net/http' 
require 'json' 


#This is the HTTP request for CouchDB class 
module Couch 

  class Server 
    def initialize(host, port, options = nil) 
      @host = host 
      @port = port 
      @options = options 
    end 

    def delete(uri) 
      request(Net::HTTP::Delete.new(uri)) 
    end 

    def get(uri) 
      request(Net::HTTP::Get.new(uri)) 
    end 

    def put(uri, json) 
      req = Net::HTTP::Put.new(uri) 
      req["content-type"] = "application/json"
      req.body = json 
      request(req) 
    end 

    def request(req) 
      res = Net::HTTP.start(@host, @port) { |http|http.request(req) } 
      unless res.kind_of?(Net::HTTPSuccess) 
        handle_error(req, res) 
      end 
      res 
    end 

    private 

    def handle_error(req, res) 
      e = RuntimeError.new("#{res.code}:#{res.message}\nMETHOD:#{req.method}\nURI:#{req.path}\n#{res.body}") 
      raise e 
    end 
  end 
end

#This is a helper method to get data from  couchDB 
def getCounchDBData 
  url = URI.parse("http://sms.iriscouch.com/_utils") 
  server = Couch::Server.new(url.host, url.port) 
  res = server.get("/sms/currentUsers") 
  json = res.body 
  json = JSON.parse(json) 
end


#This updates the information when people are switching rooms 
def updateCouchDBData(callerID, extra)
  
  json = getCounchDBData 
  url = URI.parse("http://sms.iriscouch.com/_utils") 
  server = Couch::Server.new(url.host, url.port) 
  server.delete("/sms") 
  server.put("/sms", "") 
  sessions = json["people"] 

  i = 1
  not_exit = true
  not_found = true

  while i <= sessions["total"].to_i && not_exit

    if callerID == sessions["users"][i.to_s]["callerID"]

      not_found = false
      not_exit = false
      
      if sessions["users"][i.to_s]["convoNum"].to_i < 4 && sessions["users"][i.to_s]["convoNum"].to_i > 0
        #The number exists, increment the conversation number
        convoNum = sessions["users"][i.to_s]["convoNum"].to_i
        sessions["users"][i.to_s]["convoNum"] = (convoNum + 1).to_s
        
      elsif sessions["users"][i.to_s]["convoNum"].to_i == 4

        #This is the user's important message to save
        convoNum = sessions["users"][i.to_s]["convoNum"].to_i
        sessions["users"][i.to_s]["convoNum"] = (convoNum + 1).to_s
        sessions["users"][i.to_s]["Final Message"] = "#{extra}"
        
      else 
        #User has already gave their opinion, their last message will be always be the same
        convoNum = 5
      end
    end
    i += 1
  end    
  
  if not_found
    #Number does not exists, create it.
    sessions["total"] = (sessions["total"].to_i + 1).to_s
    sessions["users"]["#{sessions["total"]}"] = {"callerID"=>"#{callerID}", "convoNum"=>"1"}
  end  
  
  doc = <<-JSON
  {"type":"SMS Database","people": #{sessions.to_json}}
  JSON
  
  server.put("/sms/currentUsers", doc.strip) 
  return convoNum
end 


messages = ["Hello Tropo developer! Enter 1 if you love Tropo, 2 if you think it's peachy keen or 3 if you think this is the easiest API ever created.",

{"1" => "We love you, too.", 
"2"=>"Only thing peachier is Grandma's cobbler.", 
"3" => "We're totally blushing over here right now.", 
"message"=>"Reply back with scripting or webapi to see a short description of each."},

{"scripting"=>"Tropo Scripting is a simple, yet powerful, synchronous API that lets you build communications applications, hosted on servers in the Tropo cloud.", 
"webapi"=>"The Tropo Web API is a web-service API that lets you build communications applications that run on your servers and drive the Tropo cloud using JSON.",
"message"=>"Reply back with 1 if you want to learn how to sign up, or 2 if you're already signed up."},

{"1"=>"Head over to following URL to sign up: https://www.tropo.com/account/register.jsp ", 
"2"=>"Woo hoo! Awesome having you as a Tropo developer.",
"message"=>"If you have a second, let us know why you chose Tropo."},

"Thank you for your response and interest!",

"Any further questions or comments, shoot em on over to support@tropo.com."
]

if $currentCall
  $status = updateCouchDBData($currentCall.callerID, $currentCall.initialText)
  $reply = $currentCall.initialText
  
  if $status == 4 || $status == 5
    say "#{messages[$status.to_i]}"
  elsif $status == 2
    say "#{messages[$status.to_i][$reply]}"
    say "#{messages[$status.to_i]['message']}"
  else
    say "#{messages[$status.to_i][$reply]} #{messages[$status.to_i]['message']}"
  end
  hangup
else
  
  call($numToDial, {
   :network => "SMS"})
   
  status = updateCouchDBData($numToDial, nil)
  
  say(messages[status.to_i])
  hangup
end