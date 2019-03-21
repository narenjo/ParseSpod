package parseSpod.parse;
import parseSpod.parse.ParseServers;

/**
 * ...
 * @author Thomas Byrne
 */
class ParseUrls
{

	static inline public function getClassUrl(server:String, className:String) 
	{
		if(className == "installations"){
			return return ParseServers.getHost(server) + "/installations";
		}
		return ParseServers.getHost(server) + "/classes/" + className;
	}
	
	static inline public function getObjectUrl(server:String, className:String, objectId:String) 
	{
		return getClassUrl(server, className) + "/" + objectId;
	}
	
	static public function getBatchUrl(server:String) 
	{
		return ParseServers.getHost(server) + "/batch";
	}
	
	static public function getSchemaUrl(server:String) 
	{
		return ParseServers.getHost(server) + "/schema";
	}
	
	static public function getSignupUrl(server:String) 
	{
		return ParseServers.getHost(server) + "/users";
	}
	
	static public function getPasswordResetUrl(server:String) 
	{
		return ParseServers.getHost(server) + "/requestPasswordReset";
	}
	
	static public function getSigninUrl(server:String) 
	{
		return ParseServers.getHost(server) + "/login";
	}
	
	static public function getSessionUrl(server:String) 
	{
		return ParseServers.getHost(server) + "/users/me";
	}
	
	static public function getFilesUrl(server:String, filename:String) 
	{
		return ParseServers.getHost(server) + "/files/" + filename;
	}
	
	static public function getPathFromUrl(url:String)
	{
		var parts = url.split("/");
		parts.splice(0, 3);

        return "/" + parts.join("/");
	}
}