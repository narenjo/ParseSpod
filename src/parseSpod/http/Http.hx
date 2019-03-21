package parseSpod.http;

import haxe.io.Bytes;
import haxe.io.Input;
import parseSpod.fs.FileSystemTools;
import promhx.Deferred;
import promhx.Promise;
import promhx.Stream;

#if sys
import sys.io.File;
import sys.FileSystem;
#end

using Reflect;

/**
 * Http with more control than haxe.Http
 * 
 * @author Thomas Byrne
 */

class Http<T> extends Stream<T>
{
	
	public static function string(?url:String):Http<String>
	{
		return new Http<String>(HttpMethod.GET, url);
	}
	/*public static function binary(?url:String):Http<Bytes>
	{
		return new Http<Bytes>(HttpMethod.GET, url);
	}*/
	
	
	
	@:isVar public var url(default, set):String;
	function set_url(value:String):String{
		// TODO: strip query string into data
		clearHttp();
		return url = value;
	}
	
	public var attempts:Int = 1;
	
	@:isVar public var method(default, set):String;
	function set_method(value:String):String{
		clearHttp();
		return method = value;
	}
	
	function clearHttp() 
	{
		if (_innerhttp != null){
			_innerhttp.onData = null;
			_innerhttp.onError = null;
			_innerhttp.onStatus = null;
			_innerhttp = null;
		}
	}

	var _data:String;
	var _response:Deferred<T>;
	var _contentType:String;
	var _attempted:Int = 0;
	
	var _headers:Map<String, String>;
	
	var _innerhttp:BaseHaxeHttp;
	
	var _fileArgName:String;
	var _filePath:String;
	var _fileContentType:String;

	private function new(method:HttpMethod, ?url:String) 
	{
		_response = new Deferred();
		super(_response);
		this.method = method;
		this.url = url;
	}
	
	
	
	public function get():Http<T>
	{
		method = HttpMethod.GET;
		return this;
	}
	public function put():Http<T>
	{
		method = HttpMethod.PUT;
		return this;
	}
	public function post():Http<T>
	{
		method = HttpMethod.POST;
		return this;
	}
	public function delete():Http<T>
	{
		method = HttpMethod.DELETE;
		return this;
	}
	public function data(data:String):Http<T>
	{
		_data = data;
		return this;
	}
	public function file(argName:String, file:String, contentType:String="application/octet-stream"):Http<T>
	{
		_fileArgName = argName;
		_filePath = file;
		_fileContentType = contentType;
		return this;
	}
	public function setHeader(name:String, value:String):Http<T>
	{
		if (_headers == null) _headers = new Map();
		_headers.set(name, value);
		return this;
	}
	public function removeHeader(name:String):Http<T>
	{
		if (_headers == null) return this;
		clearHttp();
		_headers.remove(name);
		return this;
	}
	
	public function contentType(contentType:String):Http<T>
	{
		_contentType = contentType;
		return this;
	}
	
	public function send() : Http<T>
	{
		try{
			if (_innerhttp == null){
				_innerhttp = new BaseHaxeHttp(url);
				_innerhttp.onData = untyped onData;
				_innerhttp.onError = onError;
				//_innerhttp.onStatus = onStatus;
			}
			
			if (_contentType != null){
				_innerhttp.setHeader("Content-type", _contentType);
			}
			
			if (method == HttpMethod.GET){
				if (_data != null){
					for (field in _data.fields()){
						_innerhttp.setParameter(field, _data.field(field));
					}
				}
				
			}else{
				if(_data != null) _innerhttp.setPostData(_data);
				/*if (method != HttpMethod.POST){
					_innerhttp.setHeader("X-HTTP-Method-Override", method);
				}*/
				_innerhttp.setMethod(method);
			}
			
			if (_filePath != null){
				
				#if sys
					_filePath = FileSystemTools.cleanupNativePath(_filePath);
					var filename:String = FileSystemTools.getName(_filePath);
					var input = File.read(_filePath, true);
					var size:Int = FileSystem.stat(_filePath).size;
					_innerhttp.fileTransfert(_fileArgName, filename, input, size, _fileContentType);
				#else
					//_innerhttp.uploadFile(_fileArgName, _filePath, _fileContentType);
				#end
			}
			
			if(_headers != null){
				for (name in _headers.keys()){
					_innerhttp.setHeader(name, _headers.get(name));
				}
			}
			
			doSend();
			
		}catch (e:Dynamic){
			_response.handleError(e);
		}
		return this;
	}
	
	function doSend() 
	{
		_innerhttp.request(method == HttpMethod.POST);
	}
	
	function onError(err:String) 
	{
		_attempted++;
		if (_attempted >= attempts){
			_attempted = 0;
			if (_innerhttp.responseData != null){
				// Server returned error
				_response.throwError(_innerhttp.responseData);
			}else{
				_response.throwError(err);
			}
		}else{
			doSend();
		}
	}
	
	function onData(res:T) 
	{
		_response.resolve(res);
	}
	
}

@:enum
abstract HttpMethod(String) to String
{
	public var GET = "GET";
	public var POST = "POST";
	public var PUT = "PUT";
	public var DELETE = "DELETE";
	public var HEAD = "HEAD";
	public var OPTIONS = "OPTIONS";
	public var PATCH = "PATCH";
}

/*@:enum
abstract HttpRespType(String) to String
{
	public var TEXT = "TEXT";
	public var BINARY = "BINARY";
}*/