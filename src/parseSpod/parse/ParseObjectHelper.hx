package parseSpod.parse;

import parseSpod.http.Http;
import parseSpod.parse.ParseIO;
import parseSpod.parse.ParseIO.ParseEntity;
import parseSpod.parse.ParseIO.ParseEntityList;
import parseSpod.parse.ParseIO.ParseQueryOptions;
import parseSpod.http.Http.HttpMethod;
import parseSpod.parse.ParseDate;
import parseSpod.parse.ParseFile;
import parseSpod.parse.ParseObjectHelper.EntityDesc;
import promhx.Deferred;
import promhx.Promise;

/**
 * ...
 * @author Thomas Byrne
 */
class ParseObjectHelper
{
	
	static public function getLoaded(id:String, loadedObjects:Map<String, Bool>) : Bool
	{
		return loadedObjects.exists(id);
	}

	public static inline function get<T>(id:String, local:Map<String, T>, remote:Map<String, T>) : T
	{
		return local.exists(id) ? local.get(id) : remote.get(id);
	}

	public static inline function set<T>(id:String, value:T, local:Map<String, T>, remote:Map<String, T>) : T
	{
		var remoteVal:T = remote.get(id);
		if (value == remoteVal){
			local.remove(id);
		}else{
			local.set(id, value);
		}
		return value;
	}
	
	public static function query<T>(server:String, className:String, desc:EntityDesc, ?options:ParseQueryOptions) : Promise<Array<T>>
	{
		var deferred:Deferred<Array<T>> = new Deferred();
		var promise:Promise<Array<T>> = new Promise(deferred);
		ParseIO.get(server).add(HttpMethod.GET, ParseUrls.getClassUrl(server, className), null, options, null, null, null, null, desc)
		.then(function(resp:ParseEntityList){
			var list:Array<T> = [];
			for (entity in resp.results){
				loadedObj(entity, desc, false, (options==null ? null : options.include));
				list.push(untyped entity.objectId);
			}
			deferred.resolve(list);
			
		})
		.catchError(function(err:String){
			deferred.throwError(err);
			
		});
		return promise;
	}
	
	static private function loadedObj<T>(entity:ParseEntity, desc:EntityDesc, overwriteChanges:Bool, ?include:Array<String>) : T
	{
		var objId = entity.objectId;
		desc.loaded.set(objId, true);
		for (field in desc.fields){
			if (overwriteChanges) field.local.remove(objId);
			switch(field.type){
				case EntityDescFieldType.NORMAL:
					field.remote.set(objId, Reflect.field(entity, field.name));
					
				case EntityDescFieldType.POINTER:
					var pointer = Reflect.field(entity, field.name);
					if (pointer != null){
						var fieldDesc:EntityDesc = field.entityDesc();
						field.remote.set(objId, fieldDesc.coerceData == null ? pointer.objectId : fieldDesc.coerceData(pointer.objectId));
						if (include != null && include.indexOf(field.name) != -1){
							loadedObj(pointer, fieldDesc, overwriteChanges);
						}
					}else{
						field.remote.set(objId, null);
					}
					
				case EntityDescFieldType.FILE:
					var file = Reflect.field(entity, field.name);
					if(file != null) field.remote.set(objId, file.url);
					
				case EntityDescFieldType.RELATION:
					// must be explicitly loaded

				case EntityDescFieldType.DATE:
				trace(Type.typeof(Reflect.field(entity, field.name)), Reflect.field(entity, field.name));
					var date:ParseDate = Reflect.field(entity, field.name);
				trace(Type.typeof(date), date);
					if(date != null) field.remote.set(objId, date);
			}
		}
		return untyped objId;
	}
	
	public static function save<T>(id:String, obj:T, server:String, className:String, desc:EntityDesc, ?fields:Array<String>) : Promise<T>
	{
		var isNew = ParseObjectId.isLocal(id);
		var deferred:Deferred<T> = new Deferred();
		var promise:Promise<T> = new Promise(deferred);
		var changedProps = {};
		var changedFields = [];
		var createdAt:EntityDescField<Dynamic> = null;
		var updatedAt:EntityDescField<Dynamic> = null;
		for (field in desc.fields){
			if (fields != null && fields.indexOf(field.name) == -1) continue;
			
			if (field.local.exists(id)){
				var localValue = field.local.get(id);
				switch(field.type){
					case EntityDescFieldType.NORMAL:
						Reflect.setField(changedProps, field.name, localValue);
						changedFields.push(field);
							
					case EntityDescFieldType.POINTER:
						switch(Type.typeof(localValue)) {
							case Type.ValueType.TClass(c):
								if (Type.getInstanceFields(c).indexOf("objectId") != -1) localValue = Reflect.field(localValue, "objectId");
							default:
								if (Reflect.hasField(localValue, "objectId")) localValue = Reflect.field(localValue, "objectId");
						}
						if (localValue != null) Reflect.setField(changedProps, field.name, { __type: "Pointer", objectId:localValue, className: field.remoteType });
						else Reflect.setField(changedProps, field.name, null);
						changedFields.push(field);
							
					case EntityDescFieldType.FILE:
						var file:ParseFile = untyped localValue;
						if (file == null){
							Reflect.setField(changedProps, field.name, null);
						}else{
							if(file.uploaded){
								Reflect.setField(changedProps, field.name, { __type: "File", name: file.id });
							}else{
								// Can't save unuploaded files
							}
						}
						
					case EntityDescFieldType.RELATION:
						// Can't directly set relations
					case EntityDescFieldType.DATE:
						var date:ParseDate = untyped localValue;
						if(date == null){
							Reflect.setField(changedProps, field.name, null);
						}
						else{
							Reflect.setField(changedProps, field.name, { __type: "Date", iso: date });
						}
						changedFields.push(field);
				}
			}
			if (field.name == "createdAt"){
				createdAt = field;
			}
			if (field.name == "updatedAt"){
				updatedAt = field;
			}
		}
		
		var httpMethod;
		var url:String;
		if (isNew){
			httpMethod = HttpMethod.POST;
			url = ParseUrls.getClassUrl(server, className);
		}else{
			httpMethod = HttpMethod.PUT;
			url = ParseUrls.getObjectUrl(server, className, id);
		}
		ParseIO.get(server).add(httpMethod, url, changedProps)
		.then(function(resp:ParseEntity){
			var origId = id;
			if (isNew){
				id = resp.objectId;
			}
			for (field in changedFields){
				field.remote.set(id, field.local.get(origId));
				field.local.remove(origId);
			}
			if (isNew){
				// Must move relations over to new ID
				for (field in desc.fields){
					switch(field.type){
						case EntityDescFieldType.POINTER | EntityDescFieldType.FILE | EntityDescFieldType.NORMAL | EntityDescFieldType.DATE:
								
						case EntityDescFieldType.RELATION:
							migrateItems(origId, id, field.local);
							migrateItems(origId, id, field.added);
							migrateItems(origId, id, field.removed);
					}
				}
			}
			if (resp.updatedAt != null && updatedAt!=null){
				updatedAt.remote.set(id, resp.updatedAt);
			}
			if (resp.createdAt != null && createdAt!=null){
				createdAt.remote.set(id, resp.createdAt);
			}
			if (Std.is(obj, String)){
				deferred.resolve(untyped id);
			}else{
				// Set objectId?
				deferred.resolve(obj);
			}
		})
		.catchError(function(err:String){
			deferred.throwError(err);
			
		});
		return promise;
	}
	
	static private function migrateItems(origId:String, id:String, map:Map<String, Dynamic>) 
	{
		if (map.exists(origId)){
			var value = map.get(origId);
			map.set(id, value);
			map.remove(origId);
		}
	}
	
	public static inline function load<T>(id:String, obj:T, overwriteChanges:Bool, server:String, className:String, desc:EntityDesc) : Promise<T>
	{
		if (ParseObjectId.isLocal(id)){
			throw "Can't load unsaved object";
		}
		var deferred:Deferred<T> = new Deferred();
		var promise:Promise<T> = new Promise(deferred);
		
		ParseIO.get(server).add(HttpMethod.GET, ParseUrls.getObjectUrl(server, className, id))
		.then(function(resp:ParseEntity){
			loadedObj(resp, desc, overwriteChanges);
			deferred.resolve(obj);
		})
		.catchError(function(err:String){
			deferred.throwError(err);
			
		});
		return promise;
	}
	
	public static function delete<T>(id:String, obj:T, server:String, className:String, desc:EntityDesc) : Promise<T>
	{
		if (ParseObjectId.isLocal(id)){
			throw "Can't delete unsaved object";
		}
		var deferred:Deferred<T> = new Deferred();
		var promise:Promise<T> = new Promise(deferred);
		
		ParseIO.get(server).add(HttpMethod.DELETE, ParseUrls.getObjectUrl(server, className, id))
		.then(function(resp:ParseEntity){
			unload(id, desc);
			deferred.resolve(null);
		})
		.catchError(function(err:String){
			deferred.throwError(err);
			
		});
		return promise;
	}
	
	public static inline function unload(objId:String, desc:EntityDesc) 
	{
		desc.loaded.remove(objId);
		for (field in desc.fields){
			field.remote.remove(objId);
			field.local.remove(objId);
		}
	}
	
	public static inline function toString(id:String, desc:EntityDesc) : String
	{
		if (id == null) return "null";
		var str = "{";
		for (i in 0 ... desc.fields.length){
			var field = desc.fields[i];
			if (i != 0) str += ", ";
			var value = get(id, field.local, field.remote);
			if (Std.is(value, String)) value = '"' + value + '"';
			str += field.name + ":" + value;
		}
		return str + "}";
	}
	
	public static function hasChanges(id:String, desc:EntityDesc, ?fields:Array<String>) : Bool
	{
		for (field in desc.fields){
			if (fields != null && fields.indexOf(field.name) == -1) continue;
			if (field.local.exists(id)){
				return true;
			}
		}
		return false;
	}
	
	static public function revert(id:String, desc:EntityDesc, ?fields:Array<String>) : Bool
	{
		var ret:Bool = false;
		for (field in desc.fields){
			if (fields != null && fields.indexOf(field.name) == -1) continue;
			if (field.local.exists(id)){
				ret = true;
				field.local.remove(id);
			}
		}
		return ret;
	}
}

typedef EntityDesc =
{
	remoteName:String,
	fields:Array<EntityDescField<Dynamic>>,
	loaded:Map<String, Bool>,
	?coerceData:String -> Dynamic,
}

typedef EntityDescField<T> =
{
	name:String,
	remoteName:String,
	local:Map<String, T>,
	remote:Map<String, T>,
	
	?added:Map<String, T>,
	?removed:Map<String, T>,
	
	type:EntityDescFieldType,
	?remoteType:String,
	
	?entityDesc:Void->EntityDesc
}

@:enum
abstract EntityDescFieldType(String){
	public var NORMAL = "normal";
	public var POINTER = "pointer";
	public var RELATION = "relation";
	public var FILE = "file";
	public var DATE = "date";
}