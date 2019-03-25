package parseSpod.parse;
import haxe.Timer;
import parseSpod.http.Http;
import parseSpod.http.Http.HttpMethod;
import haxe.Json;
import parseSpod.parse.ParseObjectHelper.EntityDesc;
import parseSpod.parse.ParseObjectHelper.EntityDescField;
import promhx.Deferred;
import promhx.Promise;

/**
 * ...
 * @author Thomas Byrne
 */
class ParseIO
{
	static var instances:Map<String, ParseIO> = new Map();
	
	var server:String;
	var token:String;
	var batchDelay:Float;
	var batchQue:Array<ParseRequest> = [];
	var batchTimer:Timer;
	var httpAttempts:Int;

	public inline static function setServer(server:String, batchDelay:Float = 1, httpAttempts:Int = 2) 
	{
		var parseIO = instances.get(server);
		if (parseIO != null){
			parseIO.batchDelay = batchDelay;
			parseIO.httpAttempts = httpAttempts;
		}else {
			instances.set(server, new ParseIO(server, batchDelay, httpAttempts));
		}
	}
	public inline static function get(server:String) : ParseIO 
	{
		return instances.get(server);
	}
	
	static public function setToken(server:String, token:String) 
	{
		var parseIO = instances.get(server);
		parseIO.token = token;
	}
	
	function new(server:String, batchDelay:Float = 1, httpAttempts:Int = 2) 
	{
		this.server = server;
		this.batchDelay = batchDelay;
		this.httpAttempts = httpAttempts;
	}
	
	public function add<T>(method:HttpMethod, url:String, ?data:Dynamic, ?queryOpts:ParseQueryOptions, ?queryVars:Map<String, String>, ?options:RequestOptions, ?file:String, ?contentType:String, ?desc:EntityDesc) : Promise<T>
	{
		if (queryOpts != null){
			if (queryVars == null) queryVars = new Map();
			addQueryOpts(queryVars, queryOpts, desc);
		}
		if (queryVars != null){
			url += encodeQueryVars(queryVars);
		}

		if (batchDelay <= 0 || !canBatch(method, url, data, options) || file!=null){
			return sendSingleRequest(method, url, data, options, file, contentType);
		}else{
			var deferred:Deferred<T> = new Deferred();
			var reqPack:ParseRequestPackage = {method:method, url:url};
			if (data != null) reqPack.data = data;
			batchQue.push({ pack:reqPack, deferred:deferred, options:options });
			startBatchTimer();
			return new Promise(deferred);
		}
	}
	
	function addQueryOpts(query:Map<String, String>, queryOpts:ParseQueryOptions, desc:EntityDesc) 
	{
		if (queryOpts.skip != null){
			query.set("skip", Std.string(queryOpts.skip));
		}
		if (queryOpts.limit != null){
			query.set("limit", Std.string(queryOpts.limit));
		}
		if (queryOpts.order != null){
			query.set("order", queryOpts.order);
		}
		if (queryOpts.include != null){
			query.set("include", queryOpts.include.join(","));
		}
		if (queryOpts.keys != null){
			query.set("keys", queryOpts.keys.join(","));
		}
		if (queryOpts.where != null){
			query.set("where", Json.stringify(encodeQuery(queryOpts.where, desc)));
		}
	}
	
	function encodeQueryVars(query:Map<String, String>) 
	{
		var ret = "";
		for (key in query.keys()){
			if (ret.length > 0) ret += "&";
			ret += key + "=" + query.get(key);
		}
		return (ret.length > 0 ? "?" + ret : "");
	}
	
	function encodeQuery(where:Map<String, ParseQueryOps>, desc:EntityDesc) : Dynamic
	{
		var obj = {};
		var relatedUsed = false;
		for (field in where.keys()){
			var fieldDesc:EntityDescField<Dynamic> = findFieldDesc(desc.fields, field);
			
			var prop = fieldDesc == null ? field : fieldDesc.remoteName;
			
			switch(where.get(prop)){
				case Eq(value):
					if (fieldDesc != null && fieldDesc.entityDesc != null){
						var childDesc = fieldDesc.entityDesc();
						Reflect.setField(obj, prop, {__type:"Pointer", className:childDesc.remoteName, objectId:value});
					}else{
						Reflect.setField(obj, prop, value);
					}
					
				case LessThan(value):
					Reflect.setField(obj, prop, {"$lt":value});
					
				case LessThanEq(value):
					Reflect.setField(obj, prop, {"$lte":value});
					
				case GreaterThan(value):
					Reflect.setField(obj, prop, {"$gt":value});
					
				case GreaterThanEq(value):
					Reflect.setField(obj, prop, {"$gte":value});
					
				case NotEq(value):
					Reflect.setField(obj, prop, {"$ne":value});
				
				case EqAny(value):
					Reflect.setField(obj, prop, {"$in":value});
					
				case NotEqAny(value):
					Reflect.setField(obj, prop, {"$nin":value});
					
				case All(value):
					Reflect.setField(obj, prop, {"$all":value});
					
				case Contains(value):
					Reflect.setField(obj, prop, value);
				
				case Exists(value):
					if (value == null) value = true;
					Reflect.setField(obj, prop, {"$exists":value});
					
				case Select(where):
					Reflect.setField(obj, prop, {"$select":encodeQuery(where, fieldDesc.entityDesc())});
					
				case DontSelect(where):
					Reflect.setField(obj, prop, {"$dontSelect":encodeQuery(where, fieldDesc.entityDesc())});
					
				case RelatedTo(className, objectId):
					if (relatedUsed){
						throw "Can only use one 'relatedTo' statement per query";
					}
					relatedUsed = true;
					Reflect.setField(obj, "$relatedTo", {object:{__type:"Pointer", className:className, objectId:objectId}, key:prop});
				
				case Regex(ex):
					Reflect.setField(obj, prop, {"$regex":ex});
				
				case Text(ex):
					Reflect.setField(obj, prop, {"$text":ex});
			}
		}
		return obj;
	}
	
	function findFieldDesc(fields:Array<EntityDescField<Dynamic>>, name:String) : EntityDescField<Dynamic> 
	{
		for (field in fields){
			if (field.name == name) return field;
		}
		return null;
	}
	
	function canBatch(method:HttpMethod, url:String, ?data:Dynamic, ?options:RequestOptions) : Bool
	{
		#if sys
		return false;
		#else
		return (method == HttpMethod.PUT || method == HttpMethod.POST || method == HttpMethod.DELETE) && (options == null || options.token == null);
		#end
	}
	
	private function startBatchTimer() 
	{
		if (batchTimer == null){
			batchTimer = new Timer(Std.int(batchDelay) * 1000);
		}
		batchTimer.run = sendBatch;
	}
	
	private function sendBatch() 
	{
		batchTimer.stop();
		batchTimer = null;

		var batchQue = this.batchQue;
		this.batchQue = [];
		
		if (batchQue.length == 1){
			var queItem = batchQue[0];
			_sendSingleRequest(queItem.pack.method, queItem.pack.url, queItem.pack.data, queItem.deferred, queItem.options, null, null);
			return;
		}
		var data:BatchOpData = {requests:[]};
		for (queItem in batchQue){
			var pack:BatchRequest = {method:queItem.pack.method, path:ParseUrls.getPathFromUrl(queItem.pack.url)};
			if (queItem.pack.data != null) pack.body = queItem.pack.data;
			data.requests.push(pack);
		}
		var http = getHttp(HttpMethod.POST, ParseUrls.getBatchUrl(server), data);
		http.then(onBatchSuccess.bind(_, batchQue));
		http.catchError(onBatchFail.bind(_, batchQue));
		http.send();
	}
	
	private function onBatchFail(res:String, batchQue:Array<ParseRequest>) 
	{
		for (item in batchQue){
			item.deferred.throwError(res);
		}
	}
	
	private function onBatchSuccess(res:String, batchQue:Array<ParseRequest>) 
	{
		var res:Array<Dynamic> = Json.parse(res);
		for (i in 0 ... batchQue.length){
			var item = batchQue[i];
			interpretResult(item.deferred, res[i].success);
		}
	}
	
	inline function interpretResult(deferred:Deferred<Dynamic>, res:Dynamic) 
	{
		deferred.resolve(res);
	}
	
	private function sendSingleRequest(method:HttpMethod, url:String, data:Dynamic, options:RequestOptions, file:String, contentType:String) 
	{
		var deferred:Deferred<Dynamic> = new Deferred();
		var promise = new Promise(deferred);
		_sendSingleRequest(method, url, data, deferred, options, file, contentType);
		return promise;
	}
	
	function _sendSingleRequest(method:HttpMethod, url:String, data:Dynamic, deferred:Deferred<Dynamic>, options:RequestOptions, file:String, contentType:String) 
	{
		var http:Http<String>;
		if (file != null){
			http = getFileUploadHttp(method, url, file, contentType, data, options);
		}else{
			http = getHttp(method, url, data, options);
		}
		http.send();
		http.then(function(res:String){
			interpretResult(deferred, Json.parse(res));
			
		}).catchError(function(err:String){
			deferred.throwError(err);
		});
	}
	
	inline private function getHttp(method:HttpMethod, url:String, data:Dynamic, ?options:RequestOptions) : Http<String>
	{
		var http = Http.string(url);
		http.method = method;
		http.attempts = httpAttempts;
		if(data != null)http.data(Json.stringify(data));
		http.setHeader("X-Parse-Application-Id", ParseServers.getAppId(server));
		http.setHeader("X-Parse-REST-API-Key", ParseServers.getRestKey(server));
		http.setHeader("Content-type", "text/plain");
		
		var token:String = ( options==null || options.token==null ? this.token : options.token );
		var installId:String = ( options==null || options.installationId==null ? null : options.installationId );
		if(token != null) http.setHeader("X-Parse-Session-Token", token);
		if(installId != null) http.setHeader("X-Parse-Installation-Id", installId);
		return http;
	}
	
	inline private function getFileUploadHttp(method:HttpMethod, url:String, file:String, contentType:String, ?data:Dynamic, ?options:RequestOptions) : Http<String>
	{
		var http = getHttp(method, url, data, options);
		http.file("d", file, contentType);
		return http;
	}
	
}

typedef RequestOptions =
{
	token:String,
	?installationId:String
}

typedef ParseRequest =
{
	pack:ParseRequestPackage,
	deferred:Deferred<Dynamic>,
	options:RequestOptions
}

typedef BatchOpData =
{
	requests:Array<BatchRequest>
}

typedef ParseRequestPackage =
{
	method:HttpMethod,
	url:String,
	?data:Dynamic
}

typedef BatchRequest =
{
	method:HttpMethod,
	path:String,
	?body:Dynamic
}

typedef BatchResponse = 
{
	results:Array<Dynamic>
}

typedef ParseEntity = 
{
	objectId:String,
	updatedAt:ParseDate,
	createdAt:ParseDate,
}

typedef ParseEntityList =
{
	results:Array<ParseEntity>
}

/*abstract ParseDate(String){
	
}*/

typedef ParseQueryOptions =
{
	?where:Map<String, ParseQueryOps>,
	?order:String,
	?limit:Int,
	?skip:Int,
	?keys:Array<String>,
	?include:Array<String>,
}

enum ParseQueryOps{
	Eq(value:Dynamic);
	NotEq(value:Dynamic);
	
	LessThan(value:Float);
	LessThanEq(value:Float);
	GreaterThan(value:Float);
	GreaterThanEq(value:Float);
	
	EqAny(value:Array<Dynamic>);
	NotEqAny(value:Array<Dynamic>);
	All(value:Array<Dynamic>);
	Contains(value:Dynamic);
	
	Exists(?value:Bool);
	Select(where:Map<String, ParseQueryOps>);
	DontSelect(where:Map<String, ParseQueryOps>);
	RelatedTo(className:String, objectId:String);
	
	Regex(ex:String);
	Text(ex:String);
}