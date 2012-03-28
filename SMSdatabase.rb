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

def updateCouchDBData(callerID, extra)
  
  #Call the getCounchDBData method to get the database information
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

      #If the user sent an incorrect reply to an answer, set the convoNum back one and ask
      #the question again
      if extra == "back"
        convoNum = sessions["users"][i.to_s]["convoNum"].to_i - 1
        sessions["users"][i.to_s]["convoNum"] = (convoNum).to_s
      else
        #The number exists, increment the conversation number
        if sessions["users"][i.to_s]["convoNum"].to_i < 3
          convoNum = sessions["users"][i.to_s]["convoNum"].to_i + 1
          sessions["users"][i.to_s]["convoNum"] = (convoNum).to_s
        
          #This is the user's important message to save
        elsif sessions["users"][i.to_s]["convoNum"].to_i == 3
          convoNum = sessions["users"][i.to_s]["convoNum"].to_i + 1
          sessions["users"][i.to_s]["convoNum"] = (convoNum).to_s
          sessions["users"][i.to_s]["Final Message"] = "#{extra}"

          #User has already gave their opinion, their last message will be always be the same        
        else 
          convoNum = 5
        end
      end
    end
    i += 1
  end    

  #Number does not exists, create it.  
  if not_found
    convoNum = 0
    sessions["total"] = (sessions["total"].to_i + 1).to_s
    sessions["users"]["#{sessions["total"]}"] = {"callerID"=>"#{callerID}", "convoNum"=>"0"}
  end  
  
  #Get JSON ready
  doc = <<-JSON
  {"type":"SMS Database","people": #{sessions.to_json}}
  JSON
  
  #send the JSON back to the database
  server.put("/sms/currentUsers", doc.strip) 
  return convoNum
end 


messages = [{"1"=>"Hello Tropo developer!",
"message"=>"Enter 1 if you love Tropo, 2 if you think it's peachy keen or 3 if you think this is the easiest API ever created."},

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
  
  #This variable will correspond to which message should be played
  $status = updateCouchDBData($currentCall.callerID, $currentCall.initialText)
  #This variable will use the users response to give the appropriate answer
  $reply = $currentCall.initialText.downcase
  
  #These two responses only have an answer, not an answer and question
  if $status == 4 || $status == 5
    say "#{messages[$status.to_i]}"
    
  #This status needs to be broken up because of length
  elsif $status == 2
    if messages[$status.to_i][$reply] == nil 
      $newStatus = updateCouchDBData($currentCall.callerID, "back")
      log "new status =========> #{$newStatus}"
      say "Sorry, you have entered a wrong choice. #{messages[$newStatus.to_i]['message']}" 
    else
      say "#{messages[$status.to_i][$reply]}"
      say "#{messages[$status.to_i]['message']}"
    end
    
  #The rest of the questions and answers are short enough to have in one say
  else
    if messages[$status.to_i][$reply] == nil 
      $newStatus = updateCouchDBData($currentCall.callerID, "back") 
      say "Sorry, I didn't understand your choice. #{messages[$newStatus.to_i]['message']}" 
    else
      say "#{messages[$status.to_i][$reply]} #{messages[$status.to_i]['message']}"
    end
  end
  
  #There is no reason to keep the session alive, so we hangup 
  hangup
else
  
  #Grab the $numToDial parameter and initiate the SMS conversation
  call($numToDial, {
   :network => "SMS"})
   
  #This primarily updates the database with the new number. This variable should always be 0
  status = updateCouchDBData($numToDial, nil)
  
  #This gives the initial messsage with a question
  say "#{messages[$status.to_i]['1']} #{messages[$status.to_i]['message']}"
  
  #There is no reason to keep the session alive, so we hangup 
  hangup
end