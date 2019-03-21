package parseSpod.parse;
import parseSpod.http.Http;
import parseSpod.parse.ParseIO;
import parseSpod.parse.ParseIO.ParseEntity;
import parseSpod.http.Http.HttpMethod;
import promhx.Deferred;
import promhx.Promise;

/**
 * ...
 * @author Thomas Byrne
 */
class ParseServerHelper
{
	public static function getSession(server:String, token:String, useToken:Bool) : Promise<ParseSession>
	{
		var deferred:Deferred<ParseSession> = new Deferred();
		var promise:Promise<ParseSession> = new Promise(deferred);
		ParseIO.get(server).add(HttpMethod.GET, ParseUrls.getSessionUrl(server), null, null, null, {token:token})
		.then(function(resp:ParseSession){
			if (useToken){
				ParseIO.setToken(server, token);
			}
			deferred.resolve(resp);
			
		})
		.catchError(function(err:String){
			deferred.throwError(err);
			
		});
		return promise;
	}

	public static function signup(server:String, signupOptions:SignupOptions, useToken:Bool) : Promise<ParseSession>
	{
		var deferred:Deferred<ParseSession> = new Deferred();
		var promise:Promise<ParseSession> = new Promise(deferred);
		ParseIO.get(server).add(HttpMethod.POST, ParseUrls.getSignupUrl(server), signupOptions)
		.then(function(resp:ParseSession){
			if (useToken){
				ParseIO.setToken(server, resp.sessionToken);
			}
			deferred.resolve(resp);
			
		})
		.catchError(function(err:String){
			deferred.throwError(err);
			
		});
		return promise;
	}

	public static function signin(server:String, username:String, password:String, useToken:Bool) : Promise<ParseSession>
	{
		var deferred:Deferred<ParseSession> = new Deferred();
		var promise:Promise<ParseSession> = new Promise(deferred);
		ParseIO.get(server).add(HttpMethod.GET, ParseUrls.getSigninUrl(server), null, null, ["username" => username, "password" => password])
		.then(function(resp:ParseSession){
			if (useToken){
				ParseIO.setToken(server, resp.sessionToken);
			}
			deferred.resolve(resp);
			
		})
		.catchError(function(err:String){
			deferred.throwError(err);
			
		});
		return promise;
	}

	public static function loginWithFaceBook(server:String, signupOptions:Dynamic, useToken:Bool, ?installationId:String) : Promise<ParseSession>
	{
		var deferred:Deferred<ParseSession> = new Deferred();
		var promise:Promise<ParseSession> = new Promise(deferred);
		var options = (installationId != null)?{installationId: installationId}:null;

		ParseIO.get(server).add(HttpMethod.POST, ParseUrls.getSignupUrl(server), signupOptions, null, null, installationId)
		.then(function(resp:ParseSession){
			if (useToken){
				ParseIO.setToken(server, resp.sessionToken);
			}
			deferred.resolve(resp);
			
		})
		.catchError(function(err:String){
			deferred.throwError(err);
			
		});
		return promise;
	}

	public static function passwordReset(server:String, email:String) : Promise<Bool>
	{
		var deferred:Deferred<Bool> = new Deferred();
		var promise:Promise<Bool> = new Promise(deferred);
		ParseIO.get(server).add(HttpMethod.POST, ParseUrls.getPasswordResetUrl(server), {email:email})
		.then(function(resp:Dynamic){
			deferred.resolve(true);
			
		})
		.catchError(function(err:String){
			deferred.throwError(err);
			
		});
		return promise;
	}
	
}

typedef SignupOptions =
{
	username:String,
	email:String,
	password:String
}

typedef ParseSession =
{
	> ParseEntity,
	username:String,
	email:String,
	sessionToken:String,
	emailVerified:Bool,
}